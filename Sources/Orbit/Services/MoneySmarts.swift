import Foundation
import SwiftData
import UserNotifications

// MARK: - Merchant rules

/// Categories Orbit learned from your corrections: change Talabat to Food once and every Talabat expense after that
/// (from email, bank texts, Apple Pay, receipts or statements) is filed under Food. Synced as the "merchantRules" setting.
enum MerchantRules {
    private static let key = "merchantRules"

    static var all: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// "TALABAT EGYPT*1234 (USD)" → "talabat egypt". Digits, card refs and currency notes don't change the merchant.
    static func merchantKey(_ title: String) -> String {
        var t = title.lowercased()
        if let r = t.range(of: #"\s*\([a-z]{3}\)$"#, options: .regularExpression) { t.removeSubrange(r) }
        let words = t.components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(.init(charactersIn: "&'")))
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) && !["the", "www", "com", "eg", "egp", "llc", "ltd", "co", "inc", "pos"].contains($0) }
        return words.prefix(2).joined(separator: " ")
    }

    static func category(for title: String) -> String? {
        let k = merchantKey(title)
        guard !k.isEmpty else { return nil }
        let rules = all
        if let c = rules[k] { return c }
        return rules.first { sameMerchant(k, $0.key) }?.value
    }

    /// "talabat" also matches "talabat mart" and "talabat egypt", and the other way round.
    static func sameMerchant(_ a: String, _ b: String) -> Bool {
        !a.isEmpty && !b.isEmpty && (a == b || a.hasPrefix(b + " ") || b.hasPrefix(a + " "))
    }

    /// Remembers the category for this merchant and re-files its other expenses. Returns how many others changed.
    @MainActor @discardableResult
    static func learn(_ txn: Transaction, category: String, context: ModelContext) -> Int {
        txn.category = category
        let k = merchantKey(txn.title)
        guard !k.isEmpty, category != "Income", txn.isExpense else { return 0 }
        var rules = all
        rules[k] = category
        all = rules
        let others = ((try? context.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter { $0 !== txn && $0.isExpense && $0.category != category && sameMerchant(merchantKey($0.title), k) }
        for t in others { t.category = category }
        try? context.save()
        return others.count
    }

    static func forget(_ merchant: String) {
        var rules = all
        rules[merchant] = nil
        all = rules
    }
}

// MARK: - Spending alerts

/// Notifications when a category (or the whole month) reaches 80% / 100% of its budget, and for a charge far bigger
/// than you usually spend there. Each alert is sent once; the sent list syncs so the Mac and iPhone don't both nag.
@MainActor
enum SpendingAlerts {
    static var budgets: [String: Double] {
        get { (UserDefaults.standard.dictionary(forKey: "categoryBudgets") as? [String: Double] ?? [:]).filter { $0.value > 0 } }
        set { UserDefaults.standard.set(newValue.filter { $0.value > 0 }, forKey: "categoryBudgets") }
    }
    static var budgetAlerts: Bool { UserDefaults.standard.object(forKey: "notify.budgets") as? Bool ?? true }
    static var bigChargeAlerts: Bool { UserDefaults.standard.object(forKey: "notify.bigCharges") as? Bool ?? true }

    private static var sent: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "spendAlerts.sent") ?? []) }
        set { UserDefaults.standard.set(Array(newValue.sorted().suffix(300)), forKey: "spendAlerts.sent") }
    }

    struct Alert: Equatable { let id: String; let title: String; let body: String }

    /// Looks at this month's spending and posts any alerts that are due.
    static func check(context: ModelContext) {
        guard !Snapshot.isActive else { return }
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let due = alerts(all, now: .now).filter { !sent.contains($0.id) }
        guard !due.isEmpty else { return }
        sent.formUnion(due.map(\.id))
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .authorized else { return }
            for a in due.prefix(3) {
                let c = UNMutableNotificationContent()
                c.title = a.title
                c.body = a.body
                c.sound = .default
                c.userInfo = ["route": "money"]
                c.threadIdentifier = "money"
                try? await center.add(UNNotificationRequest(identifier: "orbit.spend." + a.id, content: c, trigger: nil))
            }
        }
    }

    /// What should be said about these transactions right now (pure, so it can be tested).
    static func alerts(_ all: [Transaction], now: Date) -> [Alert] {
        let month = now.startOfMonth
        let monthKey = DayKey.key(month).prefix(7)
        let spentThisMonth = all.filter { $0.isExpense && $0.date >= month && $0.date <= now.adding(days: 1) }
        var out: [Alert] = []

        if budgetAlerts {
            var limits = budgets.map { name, limit in
                (name: name, limit: limit, spent: -spentThisMonth.filter { $0.category == name }.reduce(0) { $0 + $1.amount })
            }
            let monthly = UserDefaults.standard.object(forKey: "monthlyBudget") as? Double ?? 2000
            if monthly > 0 { limits.append((name: "", limit: monthly, spent: -spentThisMonth.reduce(0) { $0 + $1.amount })) }
            for l in limits where l.spent >= l.limit * 0.8 {
                let over = l.spent >= l.limit
                let what = l.name.isEmpty ? "your monthly budget" : "your \(l.name) budget"
                let left = Fmt.money(max(0, l.limit - l.spent))
                out.append(Alert(id: "\(monthKey)|\(l.name.isEmpty ? "month" : l.name)|\(over ? 100 : 80)",
                                 title: over ? "Over \(what)" : "\(Int(l.spent / l.limit * 100))% of \(what) used",
                                 body: over ? "\(Fmt.money(l.spent)) spent of \(Fmt.money(l.limit)) this month."
                                            : "\(Fmt.money(l.spent)) of \(Fmt.money(l.limit)) spent, \(left) left this month."))
            }
            // Only the strongest alert per budget.
            out = out.filter { a in !(a.id.hasSuffix("|80") && out.contains { $0.id == a.id.dropLast(2) + "100" }) }
        }

        if bigChargeAlerts {
            let history = all.filter { $0.isExpense && $0.date >= now.adding(days: -120) }
            let monthly = UserDefaults.standard.object(forKey: "monthlyBudget") as? Double ?? 2000
            for t in all where t.isExpense && t.date >= now.adding(days: -2) && t.date <= now.adding(days: 1) && !t.isRecurring {
                let same = history.filter { $0 !== t && $0.category == t.category }.map { -$0.amount }
                let pool = same.count >= 5 ? same : history.filter { $0 !== t }.map { -$0.amount }
                guard pool.count >= 5 else { continue }
                let typical = pool.sorted()[pool.count / 2]
                let value = -t.amount
                guard value >= max(typical * 3, monthly * 0.1) else { continue }
                out.append(Alert(id: "big|\(t.uuid.isEmpty ? "\(t.title)\(t.date.timeIntervalSince1970)" : t.uuid)",
                                 title: "Big charge: \(Fmt.money(value)) at \(t.title)",
                                 body: "About \(Int((value / max(typical, 1)).rounded()))× what you usually spend\(same.count >= 5 ? " on \(t.category)" : ""). Not you? Check with your bank."))
            }
        }
        return out
    }
}

/// Test hook: `ORBIT_SMARTS_TEST=1` checks merchant rules, spending alerts, receipt reading and map links on demo data,
/// prints the results and quits. Nothing touches your real data.
@MainActor
enum SmartsTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["ORBIT_SMARTS_TEST"] != nil else { return }
        Task {
            let container = Snapshot.demoContainer()
            let ctx = container.mainContext
            let savedRules = MerchantRules.all, savedBudgets = SpendingAlerts.budgets
            MerchantRules.all = [:]
            print("KEY     \(MerchantRules.merchantKey("TALABAT EGYPT*1234 (USD)")) | \(MerchantRules.merchantKey("Talabat"))")
            let a = Transaction(title: "Talabat", amount: -220, category: "General"); ctx.insert(a)
            let b = Transaction(title: "TALABAT EGYPT 99", amount: -150, category: "General"); ctx.insert(b)
            let others = MerchantRules.learn(a, category: "Food", context: ctx)
            let c = Transaction(title: "Talabat Mart", amount: -90, category: "Shopping")
            print("RULES   learned=\(MerchantRules.all) others=\(others) b=\(b.category) new=\(c.category) guess=\(QuickParser.guessCategory("talabat order"))")

            SpendingAlerts.budgets = ["Food": 1000]
            let all = (try? ctx.fetch(FetchDescriptor<Transaction>())) ?? []
            let big = Transaction(title: "Gucci", amount: -25000, category: "Shopping"); ctx.insert(big)
            for a in SpendingAlerts.alerts(all + [big], now: .now) { print("ALERT   \(a.id) :: \(a.title) :: \(a.body)") }

            let receipt = "CARREFOUR MAADI\nCity Centre Maadi\n23/10/2026 14:02\nMilk 2x 45.00\nBread 15.00\nSUBTOTAL 105.00\nVAT 14% 14.70\nTOTAL EGP 119.70\nVISA ****1234"
            let r = ReceiptScanner.offline(receipt)
            print("RECEIPT \(r.merchant) | \(r.total) \(r.currency) | \(r.date.map { DayKey.key($0) } ?? "-") | \(r.category)")

            for q in ["food", "coffee", "sushi"] {
                print("NEARBY  \(q):\n" + (await NearbyFinder.shared.lookup(q, radius: 1500, context: ctx)).text.split(separator: "\n").prefix(5).joined(separator: "\n"))
            }
            print("AROUND  " + (await NearbyFinder.shared.lookup("coffee", near: "Egyptian Museum Cairo", radius: 1000, context: ctx)).text.split(separator: "\n").prefix(5).joined(separator: "\n"))
            SavedPlaces.set("home", .init(name: "Home", address: "Zamalek", lat: 30.0611, lon: 31.2194))
            let rt = TaskItem(title: "Call mom"); rt.placeName = "Home"; rt.placeLat = 30.0611; rt.placeLon = 31.2194; rt.remindAt = .now.addingTimeInterval(3600)
            let req = SmartReminders.requests(tasks: [rt], prefix: "orbit.")
            let near = await SmartReminders.resolve("pharmacy")
            print("REMIND  timed=\(req.timed.count) places=\(req.places.count) home=\(await SmartReminders.resolve("home")?.name ?? "nil") pharmacy=\(near.map { "\($0.name) \($0.lat),\($0.lon)" } ?? "nil")")
            SavedPlaces.set("home", nil)
            print("WEATHER " + (await WeatherStore.shared.forecastText(latitude: 30.06, longitude: 31.22, place: "Cairo") ?? "nil").split(separator: "\n").prefix(7).joined(separator: "\n"))
            print("SENT    \(Speaker.sentences("Hey! Your day looks calm. Two things left: • Gym at 7 • Call mom. Want me to move one?"))")
            print("VOICE   \(Speaker.bestVoice(for: "Hi").map { "\($0.name) \($0.quality.rawValue) \($0.language)" } ?? "-")")
            for link in ["https://www.google.com/maps/place/Zooba/@30.0612,31.2195,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d30.0613!4d31.2196",
                         "https://maps.apple.com/?q=Egyptian%20Museum&ll=30.0478,31.2336", "Zooba Zamalek Cairo", "Cairo Festival City Mall"] {
                let f = await PlaceLookup.resolve(link)
                print("PLACE   \(link.prefix(40)) -> \(f.map { "\($0.name) | \($0.category.rawValue) | \($0.address) | \($0.coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "-")" } ?? "nil")")
            }
            MerchantRules.all = savedRules; SpendingAlerts.budgets = savedBudgets   // exit() skips the defer
            fflush(stdout)
            withExtendedLifetime(container) { exit(0) }
        }
    }
}
