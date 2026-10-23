import SwiftUI
import SwiftData

/// A payment that is (or was) due on a day: a bill task, or the next charge of a recurring transaction.
struct DuePayment: Identifiable {
    enum Kind { case bill, recurring }
    let id: String
    let date: Date
    let title: String
    let amount: Double?
    let kind: Kind
    let paid: Bool
}

enum DuePayments {
    /// Bills from Tasks (Money area, with a due date) and projected recurring charges between `start` and `end`.
    static func between(_ start: Date, _ end: Date, tasks: [TaskItem], transactions: [Transaction]) -> [DuePayment] {
        var out: [DuePayment] = []
        for t in tasks where t.area == .money && t.due != nil {
            guard let due = t.due, due >= start, due < end else { continue }
            out.append(DuePayment(id: "task-\(t.persistentModelID.hashValue)", date: due, title: t.title.replacingOccurrences(of: "Pay ", with: ""),
                                  amount: nil, kind: .bill, paid: t.isDone))
        }
        // Latest charge of each recurring item, projected forward month by month.
        var latest: [String: Transaction] = [:]
        for txn in transactions where txn.isRecurring && txn.isExpense {
            let key = txn.title.lowercased()
            if let prev = latest[key], prev.date >= txn.date { continue }
            latest[key] = txn
        }
        for txn in latest.values {
            var next = Calendar.current.date(byAdding: .month, value: 1, to: txn.date)!
            while next < end {
                if next >= start {
                    let alreadyPaid = transactions.contains {
                        $0.title.lowercased() == txn.title.lowercased() && Calendar.current.isDate($0.date, equalTo: next, toGranularity: .month)
                    }
                    out.append(DuePayment(id: "rec-\(txn.title)-\(next.timeIntervalSince1970)", date: next.startOfDay, title: txn.title,
                                          amount: -txn.amount, kind: .recurring, paid: alreadyPaid))
                }
                next = Calendar.current.date(byAdding: .month, value: 1, to: next)!
            }
        }
        return out.sorted { $0.date < $1.date }
    }
}

struct MoneyCalendar: View {
    let month: Date
    let transactions: [Transaction]
    @Query(filter: #Predicate<TaskItem> { $0.areaRaw == "money" }) private var moneyTasks: [TaskItem]
    @State private var selected: Date?

    private var gridDays: [Date] { (0..<42).map { month.startOfMonth.startOfWeek.adding(days: $0) } }

    var body: some View {
        let due = DuePayments.between(gridDays.first!, gridDays.last!.adding(days: 1), tasks: moneyTasks, transactions: transactions)
        let spentByDay = Dictionary(grouping: transactions.filter(\.isExpense)) { $0.date.startOfDay }
            .mapValues { -$0.reduce(0) { $0 + $1.amount } }
        let upcoming = DuePayments.between(Date.now.startOfDay, Date.now.startOfDay.adding(days: 31), tasks: moneyTasks, transactions: transactions)
            .filter { !$0.paid }

        let grid = VStack(spacing: compact ? 4 : 6) {
            HStack(spacing: compact ? 4 : 6) {
                ForEach(gridDays.prefix(7), id: \.self) { d in
                    Text(d.formatted(.dateTime.weekday(compact ? .narrow : .abbreviated))).font(Theme.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: compact ? 4 : 6), count: 7), spacing: compact ? 4 : 6) {
                ForEach(gridDays, id: \.self) { day in
                    MoneyDayCell(day: day,
                                 inMonth: Calendar.current.isDate(day, equalTo: month, toGranularity: .month),
                                 spent: spentByDay[day] ?? 0,
                                 due: due.filter { $0.date.isSameDay(as: day) },
                                 selected: selected == day,
                                 compact: compact)
                        .onTapGesture { selected = selected == day ? nil : day }
                }
            }
            legend
        }
        let side = VStack(alignment: .leading, spacing: 14) {
            if let selected { dayDetail(selected, due: due.filter { $0.date.isSameDay(as: selected) }) }
            upcomingCard(upcoming)
        }

        // A phone stacks the month and the details; a Mac puts them side by side.
        if compact {
            VStack(alignment: .leading, spacing: 16) { grid; side }
        } else {
            HStack(alignment: .top, spacing: 20) {
                grid.frame(maxWidth: .infinity)
                side.frame(width: 340)
            }
        }
    }

    private var compact: Bool { Platform.isPhone }

    private var legend: some View {
        FlowLayout(spacing: 16) {
            Label { Text("Due") } icon: { Circle().fill(Theme.orange).frame(width: 8, height: 8) }
            Label { Text("Paid") } icon: { Circle().fill(Theme.good).frame(width: 8, height: 8) }
            Label { Text("Spent that day") } icon: { Image(systemName: "creditcard") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(Theme.ui(11)).foregroundStyle(Theme.inkSecondary)
        .padding(.top, 4)
    }

    private func upcomingCard(_ items: [DuePayment]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Due in the next 30 days").font(Theme.display(20))
                let total = items.compactMap(\.amount).reduce(0, +)
                if total > 0 { Text("About \(Fmt.money(total)) in known amounts").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary) }
                if items.isEmpty {
                    EmptyHint(symbol: "checkmark.seal", text: "Nothing due. Bills from email and recurring payments show up here.")
                }
                ForEach(items) { DueRow(item: $0) }
            }
        }
    }

    private func dayDetail(_ day: Date, due: [DuePayment]) -> some View {
        let spent = transactions.filter { $0.isExpense && $0.date.isSameDay(as: day) }
        return Card(fill: Theme.blush) {
            VStack(alignment: .leading, spacing: 8) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month())).font(Theme.display(20))
                if due.isEmpty && spent.isEmpty { EmptyHint(symbol: "calendar", text: "Nothing on this day.") }
                ForEach(due) { DueRow(item: $0) }
                ForEach(spent) { t in
                    HStack {
                        Text(t.title).font(Theme.ui(13))
                        Spacer()
                        Text(Fmt.money(t.amount, signed: true)).font(Theme.ui(13, weight: .semibold))
                    }
                }
            }
        }
    }
}

struct DueRow: View {
    let item: DuePayment

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(item.paid ? Theme.good : Theme.orange).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(Theme.ui(13, weight: .medium)).lineLimit(1)
                Text("\(Fmt.relativeDay(item.date)) · \(item.kind == .bill ? "Bill" : "Recurring")\(item.paid ? " · paid" : "")")
                    .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            if let a = item.amount { Text(Fmt.money(a)).font(Theme.ui(13, weight: .semibold)) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.canvas))
    }
}

struct MoneyDayCell: View {
    let day: Date
    let inMonth: Bool
    let spent: Double
    let due: [DuePayment]
    let selected: Bool
    var compact = false
    @State private var hovering = false

    var body: some View {
        if compact { phoneCell } else { macCell }
    }

    /// Phone: the day, a dot per payment due, and what was spent, short.
    private var phoneCell: some View {
        VStack(spacing: 3) {
            Text(day.formatted(.dateTime.day()))
                .font(Theme.ui(14, weight: day.isToday ? .bold : .medium))
                .frame(width: 24, height: 24)
                .background(Circle().fill(day.isToday ? Theme.lime : .clear))
                .foregroundStyle(day.isToday ? Theme.stickerInk : Theme.ink)
            HStack(spacing: 2) {
                ForEach(due.prefix(3)) { d in Circle().fill(d.paid ? Theme.good : Theme.orange).frame(width: 5, height: 5) }
            }
            .frame(height: 5)
            Text(spent > 0 ? Self.short(spent) : " ").font(Theme.ui(9, weight: .medium)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.ink, lineWidth: selected ? 1.5 : 0))
        .opacity(inMonth ? 1 : 0.35)
        .contentShape(Rectangle())
    }

    /// 1,250 → "1.3k", without the currency, to fit a phone cell.
    static func short(_ v: Double) -> String {
        v >= 1000 ? String(format: v >= 10000 ? "%.0fk" : "%.1fk", v / 1000) : String(format: "%.0f", v)
    }

    private var macCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.formatted(.dateTime.day()))
                .font(Theme.display(15, weight: day.isToday ? .bold : .medium))
                .padding(.horizontal, 6)
                .background(Capsule().fill(day.isToday ? Theme.lime : .clear))
                .foregroundStyle(day.isToday ? Theme.stickerInk : Theme.ink)
            ForEach(due.prefix(2)) { d in
                Text(d.title)
                    .font(Theme.ui(10, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(Theme.stickerInk)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 5).fill(d.paid ? Theme.mint : Theme.orange))
            }
            if due.count > 2 { Text("+\(due.count - 2)").font(Theme.ui(10, weight: .semibold)).foregroundStyle(Theme.inkMuted) }
            Spacer(minLength: 0)
            if spent > 0 {
                Text(Fmt.money(spent)).font(Theme.ui(10, weight: .medium)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Theme.cardHover : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.ink, lineWidth: selected ? 1.5 : 0))
        .opacity(inMonth ? 1 : 0.4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
