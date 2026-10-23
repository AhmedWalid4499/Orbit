import Foundation
import SwiftData

/// When each bill is due and whether this month's is paid. A bill counts as paid when it's marked paid by hand, or when an
/// expense whose title has one of its words comes in close to the due date (a bank text, an email receipt, one you typed).
enum BillTracker {
    enum Status: Equatable {
        case paid(Date?)
        case dueIn(Int)
        case overdue(Int)
    }

    struct Cycle {
        let due: Date
        let status: Status
        /// The expense that paid it, when one was found.
        let payment: Transaction?
        var isPaid: Bool { if case .paid = status { return true }; return false }
    }

    static func monthKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// The due date in the month that contains `month`, clamped to the month's last day.
    static func dueDate(_ bill: Bill, in month: Date) -> Date {
        let cal = Calendar.current
        let start = month.startOfMonth
        let days = cal.range(of: .day, in: .month, for: start)?.count ?? 28
        return start.adding(days: min(max(bill.dueDay, 1), days) - 1)
    }

    /// An expense that looks like this bill, from 20 days before the due date to 10 days after.
    static func payment(_ bill: Bill, due: Date, in transactions: [Transaction]) -> Transaction? {
        let words = bill.matchWords
        guard !words.isEmpty else { return nil }
        let from = due.adding(days: -20), to = due.adding(days: 11)
        return transactions.first { t in
            guard t.isExpense, t.date >= from, t.date < to else { return false }
            let title = t.title.lowercased()
            return words.contains { title.contains($0) }
        }
    }

    /// This month's bill if it's still open, else next month's. `keepPaid` keeps showing this month's once it's paid
    /// (for the Bills screen) instead of moving on to next month (for reminders).
    static func current(_ bill: Bill, transactions: [Transaction], now: Date = .now, keepPaid: Bool = false) -> Cycle {
        let today = now.startOfDay
        let thisDue = dueDate(bill, in: today)
        let this = cycle(bill, due: thisDue, transactions: transactions, today: today)
        // A bill added after this month's due day starts next month: it was never late.
        let before = thisDue < bill.createdAt.startOfDay && !this.isPaid
        if before || (this.isPaid && thisDue < today && !keepPaid) {
            let next = Calendar.current.date(byAdding: .month, value: 1, to: today.startOfMonth)!
            return cycle(bill, due: dueDate(bill, in: next), transactions: transactions, today: today)
        }
        return this
    }

    private static func cycle(_ bill: Bill, due: Date, transactions: [Transaction], today: Date) -> Cycle {
        let days = Calendar.current.dateComponents([.day], from: today, to: due).day ?? 0
        if bill.paidMonths.contains(monthKey(due)) { return Cycle(due: due, status: .paid(nil), payment: nil) }
        if let p = payment(bill, due: due, in: transactions) { return Cycle(due: due, status: .paid(p.date), payment: p) }
        return Cycle(due: due, status: days < 0 ? .overdue(-days) : .dueIn(days), payment: nil)
    }

    static func setPaid(_ bill: Bill, due: Date, _ paid: Bool) {
        let key = monthKey(due)
        if paid { if !bill.paidMonths.contains(key) { bill.paidMonths.append(key) } }
        else { bill.paidMonths.removeAll { $0 == key } }
    }

    /// Bills still to pay this month, in your home currency.
    static func leftThisMonth(_ bills: [Bill], transactions: [Transaction]) -> Double {
        bills.reduce(0) { sum, b in
            let c = current(b, transactions: transactions)
            return sum + (!c.isPaid && c.due.startOfMonth == Date.now.startOfMonth ? b.amount : 0)
        }
    }

    static func describe(_ s: Status) -> String {
        switch s {
        case .paid(let d): d.map { let r = Fmt.relativeDay($0); return "Paid \(r == "Today" || r == "Yesterday" ? r.lowercased() : r)" } ?? "Paid"
        case .dueIn(0): "Due today"
        case .dueIn(1): "Due tomorrow"
        case .dueIn(let n): "Due in \(n) days"
        case .overdue(1): "1 day late"
        case .overdue(let n): "\(n) days late"
        }
    }
}
