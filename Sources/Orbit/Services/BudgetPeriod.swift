import Foundation
import SwiftUI

/// The stretch of time the monthly budget covers. Calendar months unless you start a new month yourself
/// (Money › Start new month, e.g. on payday the 25th): then each budget month runs from that day to the same day
/// next month, and rolls on by itself until you start a new one again. Spending before the start doesn't count.
enum BudgetPeriod {
    static let key = "budget.periodStart"

    /// The day you last started a new month, or nil for calendar months.
    static var anchor: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: key)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let newValue { UserDefaults.standard.set(newValue.startOfDay.timeIntervalSince1970, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    static var isCustom: Bool { anchor != nil }

    /// The budget month that contains `date`.
    static func period(containing date: Date = .now) -> DateInterval {
        let cal = Calendar.current
        guard let anchor else {
            let start = date.startOfMonth
            return DateInterval(start: start, end: cal.date(byAdding: .month, value: 1, to: start)!)
        }
        // Step whole months from the anchor (forwards or backwards) until the period holds `date`.
        var n = cal.dateComponents([.month], from: anchor, to: date).month ?? 0
        var start = cal.date(byAdding: .month, value: n, to: anchor)!
        if start > date { n -= 1; start = cal.date(byAdding: .month, value: n, to: anchor)! }
        var end = cal.date(byAdding: .month, value: n + 1, to: anchor)!
        if end <= date { start = end; end = cal.date(byAdding: .month, value: n + 2, to: anchor)! }
        return DateInterval(start: start, end: end)
    }

    static var current: DateInterval { period(containing: .now) }

    /// The period before or after `p`.
    static func shifted(_ p: DateInterval, by months: Int) -> DateInterval {
        period(containing: Calendar.current.date(byAdding: .month, value: months, to: p.start)!.addingTimeInterval(3600))
    }

    /// Starts a new budget month today.
    static func startNew(_ day: Date = .now) { anchor = day }

    /// "October 2026", or "25 Oct – 24 Nov" for a month that starts on payday.
    static func title(_ p: DateInterval) -> String {
        guard isCustom else { return p.start.formatted(.dateTime.month(.wide).year()) }
        let last = p.end.adding(days: -1)
        return "\(p.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// Spending in the current budget month.
    static func spent(_ txns: [Transaction], in p: DateInterval = current) -> Double {
        -txns.filter { $0.isExpense && $0.date >= p.start && $0.date < p.end }.reduce(0) { $0 + $1.amount }
    }

    /// Days gone and days in the budget month, for pace ("day 12 of 30").
    static func day(of p: DateInterval = current, now: Date = .now) -> (day: Int, of: Int) {
        let cal = Calendar.current
        let total = cal.dateComponents([.day], from: p.start, to: p.end).day ?? 30
        let d = (cal.dateComponents([.day], from: p.start, to: now.startOfDay).day ?? 0) + 1
        return (min(max(d, 1), total), total)
    }
}

extension View {
    /// Money › New month: confirm, then start the budget month today (or go back to calendar months).
    func newBudgetMonthDialog(_ shown: Binding<Bool>, onChange: @escaping () -> Void) -> some View {
        let next = Calendar.current.date(byAdding: .month, value: 1, to: Date.now.startOfDay)!.adding(days: -1)
        return confirmationDialog("Start a new budget month today?", isPresented: shown, titleVisibility: .visible) {
            Button("Start new month") { BudgetPeriod.startNew(); onChange() }
            if BudgetPeriod.isCustom {
                Button("Go back to calendar months") { BudgetPeriod.anchor = nil; onChange() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your budget will run from today to \(next.formatted(.dateTime.day().month(.wide))), then month to month from this day. Spending before today won't count. Handy on payday.")
        }
    }
}
