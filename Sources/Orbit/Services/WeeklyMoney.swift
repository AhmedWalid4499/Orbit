import Foundation
import SwiftData

/// The last seven days of money next to the seven before, plus subscriptions worth a look.
enum WeeklyMoney {
    struct CategoryChange: Identifiable {
        let name: String
        let spent: Double
        let before: Double
        var id: String { name }
    }

    struct Flag: Identifiable {
        let symbol: String
        let text: String
        var id: String { text }
    }

    struct Report {
        let from: Date
        let spent: Double
        let lastWeek: Double
        let income: Double
        let categories: [CategoryChange]
        let biggest: Transaction?
        let topMerchant: (name: String, total: Double, count: Int)?
        let flags: [Flag]
        /// Change against last week as a share (0.2 = 20% more). nil when last week had nothing.
        var change: Double? { lastWeek > 0 ? spent / lastWeek - 1 : nil }
    }

    static func report(transactions: [Transaction], subscriptions: [Subscription], bills: [Bill] = [], now: Date = .now) -> Report {
        let end = now.startOfDay.adding(days: 1), from = end.adding(days: -7), before = from.adding(days: -7)
        let week = transactions.filter { $0.date >= from && $0.date < end }
        let prior = transactions.filter { $0.date >= before && $0.date < from }
        func spent(_ list: [Transaction]) -> Double { -list.filter(\.isExpense).reduce(0) { $0 + $1.amount } }
        func byCategory(_ list: [Transaction]) -> [String: Double] {
            Dictionary(grouping: list.filter(\.isExpense), by: \.category).mapValues { -$0.reduce(0) { $0 + $1.amount } }
        }
        let now7 = byCategory(week), then7 = byCategory(prior)
        let categories = now7.map { CategoryChange(name: $0.key, spent: $0.value, before: then7[$0.key] ?? 0) }
            .sorted { $0.spent > $1.spent }
        let merchants = Dictionary(grouping: week.filter(\.isExpense)) { $0.title.trimmingCharacters(in: .whitespaces).lowercased() }
            .compactMap { _, list -> (String, Double, Int)? in
                guard let first = list.first else { return nil }
                return (first.title, -list.reduce(0) { $0 + $1.amount }, list.count)
            }
            .filter { $0.2 > 1 }
            .max { $0.1 < $1.1 }
        return Report(from: from, spent: spent(week), lastWeek: spent(prior), income: week.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount },
                      categories: categories, biggest: week.filter(\.isExpense).min { $0.amount < $1.amount },
                      topMerchant: merchants.map { (name: $0.0, total: $0.1, count: $0.2) },
                      flags: flags(subscriptions: subscriptions, bills: bills, transactions: transactions, now: now))
    }

    /// Price rises, trials about to charge, and subscriptions that look forgotten.
    static func flags(subscriptions: [Subscription], bills: [Bill], transactions: [Transaction], now: Date = .now) -> [Flag] {
        var out: [Flag] = []
        for s in subscriptions where s.status != "cancelled" {
            if s.priceWentUp, (s.priceChangedAt ?? .distantPast) > now.adding(days: -60) {
                out.append(Flag(symbol: "arrow.up.circle.fill",
                                text: "\(s.name) went up from \(Fmt.money(s.previousAmount)) to \(Fmt.money(s.amount))."))
            }
            if s.status == "trial", let ends = s.trialEnds, ends > now, ends < now.adding(days: 8) {
                out.append(Flag(symbol: "hourglass", text: "\(s.name) trial turns paid \(when(ends)) (\(Fmt.money(s.amount)))."))
            }
            // No charge for two whole cycles: cancelled somewhere else, or paying for something you don't use.
            if s.status == "active", let last = s.lastCharged, s.cycle.next(after: s.cycle.next(after: last)) < now {
                out.append(Flag(symbol: "questionmark.circle.fill",
                                text: "No \(s.name) charge since \(last.formatted(.dateTime.day().month(.abbreviated))). Still using it, or cancel it here?"))
            }
        }
        for b in bills {
            let c = BillTracker.current(b, transactions: transactions, now: now)
            if case .overdue(let n) = c.status { out.append(Flag(symbol: "exclamationmark.circle.fill", text: "\(b.name) is \(n) day\(n == 1 ? "" : "s") late.")) }
            if case .dueIn(let n) = c.status, n <= 7 {
                out.append(Flag(symbol: "calendar.badge.clock", text: "\(b.name)\(b.amount > 0 ? " (\(Fmt.money(b.amount)))" : "") is due \(n == 0 ? "today" : n == 1 ? "tomorrow" : "in \(n) days")."))
            }
        }
        return out
    }

    /// "today", "tomorrow", "on Monday", "on 3 Nov".
    private static func when(_ d: Date) -> String {
        let r = Fmt.relativeDay(d)
        return r == "Today" || r == "Tomorrow" ? r.lowercased() : "on \(r)"
    }

    /// One line for the Sunday notification.
    static func headline(_ r: Report) -> String {
        guard r.spent > 0 else { return "No spending logged this week." }
        var s = "You spent \(Fmt.money(r.spent)) this week"
        if let c = r.change, abs(c) >= 0.05 { s += ", \(Int(abs(c) * 100))% \(c > 0 ? "more" : "less") than last week" }
        if let top = r.categories.first { s += ". Most went on \(top.name.lowercased())" }
        return s + "."
    }
}
