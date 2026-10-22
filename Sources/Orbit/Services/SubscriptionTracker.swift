import Foundation
import SwiftData

/// Finds subscriptions in your transactions (repeating charges from the same merchant), keeps their
/// next renewal date current, and notices when a price goes up. Trials come in from email (EmailExpenses).
@MainActor
enum SubscriptionTracker {
    /// "Netflix.com 12/10" and "NETFLIX" → "netflix"
    static func key(_ name: String) -> String {
        let words = name.lowercased()
            .replacingOccurrences(of: #"\.(com|net|org|io|co)\b"#, with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.letters.inverted).filter { $0.count > 1 }
        let noise: Set<String> = ["subscription", "payment", "renewal", "monthly", "annual", "plan", "premium", "inc", "ltd", "llc", "the"]
        let kept = words.filter { !noise.contains($0) }
        return (kept.isEmpty ? words : kept).prefix(2).joined(separator: " ")
    }

    /// Subscriptions you removed; detection won't bring them back.
    static var dismissed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "subscriptionsDismissed") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "subscriptionsDismissed") }
    }

    static func remove(_ s: Subscription, context: ModelContext) {
        dismissed = dismissed.union([key(s.name)])
        context.delete(s)
        try? context.save()
    }

    /// Looks through the last 13 months of expenses. Returns how many new subscriptions were found.
    @discardableResult
    static func detect(context: ModelContext) -> Int {
        let since = Date.now.adding(days: -400)
        let txns = ((try? context.fetch(FetchDescriptor<Transaction>())) ?? []).filter { $0.isExpense && $0.date >= since }
        var subs = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        let skip = dismissed
        var added = 0

        for (k, group) in Dictionary(grouping: txns, by: { key($0.title) }) where !k.isEmpty && !skip.contains(k) {
            let charges = group.sorted { $0.date < $1.date }
            guard let latest = charges.last else { continue }
            let flagged = charges.contains { $0.isRecurring || $0.category == "Subscriptions" }
            let gaps = zip(charges, charges.dropFirst()).map { $1.date.timeIntervalSince($0.date) / 86400 }.sorted()
            let cycle: BillingCycle?
            if let median = gaps.isEmpty ? nil : gaps[gaps.count / 2] {
                switch median {
                case 5...9: cycle = .weekly
                case 25...35: cycle = .monthly
                case 80...100: cycle = .quarterly
                case 350...380: cycle = .yearly
                default: cycle = flagged ? .monthly : nil
                }
            } else {
                cycle = flagged ? .monthly : nil
            }
            guard let cycle else { continue }
            // Repeating charges should cost roughly the same each time.
            if charges.count >= 2 {
                let a = abs(latest.amount), b = abs(charges[charges.count - 2].amount)
                guard a > 0, b > 0, a / b < 2, b / a < 2 else { continue }
            }
            let amount = abs(latest.amount)

            if let s = subs.first(where: { key($0.name) == k }) {
                guard s.status != "cancelled" else { continue }
                if (s.lastCharged ?? .distantPast) < latest.date.startOfDay {
                    if s.amount > 0, abs(amount - s.amount) / s.amount > 0.01 {
                        s.previousAmount = s.amount
                        s.priceChangedAt = latest.date
                    }
                    s.amount = amount
                    s.lastCharged = latest.date
                    if s.status == "trial", let ends = s.trialEnds, latest.date >= ends.startOfDay { s.status = "active" }
                }
                if s.source == "detected" { s.cycle = cycle }
                s.nextDate = upcoming(after: s.lastCharged ?? latest.date, cycle: s.cycle)
            } else {
                let s = Subscription(name: latest.title, amount: amount, cycle: cycle)
                s.source = "detected"
                s.category = latest.category
                s.lastCharged = latest.date
                s.nextDate = upcoming(after: latest.date, cycle: cycle)
                if !latest.originalCurrency.isEmpty { s.originalAmount = latest.originalAmount; s.originalCurrency = latest.originalCurrency }
                context.insert(s)
                subs.append(s)
                added += 1
            }
        }
        try? context.save()
        return added
    }

    /// From an email: a free trial that will start charging on `ends`.
    static func recordTrial(name: String, amount: Double, originalAmount: Double, currency: String, cycle: BillingCycle,
                            ends: Date?, context: ModelContext) {
        let k = key(name)
        let subs = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        let s = subs.first { key($0.name) == k } ?? {
            let s = Subscription(name: name, amount: amount, cycle: cycle)
            s.source = "email"
            context.insert(s)
            return s
        }()
        if s.status != "active" { s.status = "trial" }
        s.trialEnds = ends
        s.nextDate = ends
        if amount > 0 { s.amount = amount }
        if currency != Fmt.currencyCode, originalAmount > 0 { s.originalAmount = originalAmount; s.originalCurrency = currency }
    }

    private static func upcoming(after date: Date, cycle: BillingCycle) -> Date {
        var next = cycle.next(after: date)
        while next < Date.now.startOfDay { next = cycle.next(after: next) }
        return next.startOfDay
    }

    static func monthlyTotal(_ subs: [Subscription]) -> Double { subs.reduce(0) { $0 + $1.monthlyCost } }
}
