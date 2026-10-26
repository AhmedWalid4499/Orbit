import SwiftUI
import SwiftData

/// Money › Bills: rent, internet, phone… each with its due day, a reminder a few days before, and paid or not this month.
struct BillsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bill.dueDay) private var bills: [Bill]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var editing: Bill?
    @State private var adding = false

    private var cycles: [(Bill, BillTracker.Cycle)] {
        bills.map { ($0, BillTracker.current($0, transactions: transactions, keepPaid: true)) }.sorted { a, b in
            if a.1.isPaid != b.1.isPaid { return !a.1.isPaid }
            return a.1.due < b.1.due
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bills").font(Theme.display(24))
                    let left = BillTracker.leftThisMonth(bills, transactions: transactions)
                    Text(bills.isEmpty ? "Add the bills you pay every month. Joshu reminds you before each one."
                         : left > 0 ? "\(Fmt.money(left)) still to pay this month" : "All paid this month")
                        .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Button { adding = true } label: { Label("Add bill", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
            }
            if bills.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        EmptyHint(symbol: "doc.text", text: "No bills yet.")
                        Text("When a bank text or receipt with the bill's name comes in near the due date, Joshu marks it paid for you.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            ForEach(["Rent", "Internet", "Phone", "Electricity"], id: \.self) { n in
                                Button(n) { let b = Bill(name: n, dueDay: 1); context.insert(b); editing = b }.buttonStyle(SoftButtonStyle())
                            }
                        }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(cycles, id: \.0.persistentModelID) { bill, cycle in
                    BillRow(bill: bill, cycle: cycle) { editing = bill }
                }
            }
        }
        .sheet(isPresented: $adding) { BillEditor(bill: nil) }
        .sheet(item: $editing) { BillEditor(bill: $0) }
    }
}

struct BillRow: View {
    @Environment(\.modelContext) private var context
    let bill: Bill
    let cycle: BillTracker.Cycle
    /// Opens the editor. Only the date and name area does this, so Mark paid always gets its own tap.
    var onEdit: () -> Void = {}
    @State private var askingAmount = false
    @State private var amountText = ""

    private var tint: Color {
        switch cycle.status {
        case .paid: Theme.mint
        case .overdue: Theme.peach
        case .dueIn(let n): n <= bill.remindDays ? Theme.sand : Theme.card
        }
    }

    var body: some View {
        let sticker = tint != Theme.card
        HStack(alignment: .top, spacing: 12) {
            Button(action: onEdit) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Text(cycle.due.formatted(.dateTime.month(.abbreviated))).font(Theme.ui(10, weight: .semibold)).textCase(.uppercase)
                        Text(cycle.due.formatted(.dateTime.day())).font(Theme.display(20))
                    }
                    .frame(width: 44, height: 48)
                    .background(RoundedRectangle(cornerRadius: 10).fill(sticker ? Color.white.opacity(0.55) : Theme.canvas))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bill.name).font(Theme.ui(15, weight: .semibold)).lineLimit(1)
                        Text(BillTracker.describe(cycle.status)).font(Theme.ui(12, weight: .medium))
                        if let p = cycle.payment {
                            Text("Matched “\(p.title)” \(Fmt.money(p.amount))").font(Theme.ui(11)).lineLimit(1).opacity(0.7)
                        }
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .trailing, spacing: 8) {
                if bill.amount > 0 { Text(Fmt.money(bill.amount)).font(Theme.ui(14, weight: .semibold)) }
                if !cycle.isPaid || cycle.payment == nil {
                    Button(cycle.isPaid ? "Undo" : "Mark paid") {
                        // A bill whose amount varies asks how much it was, so the right amount comes off Left to spend.
                        if !cycle.isPaid && bill.amount <= 0 { amountText = ""; askingAmount = true }
                        else { BillTracker.setPaid(bill, due: cycle.due, !cycle.isPaid, context: context) }
                    }
                        .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(sticker ? Color.white.opacity(0.6) : Theme.canvas))
                }
            }
        }
        .foregroundStyle(sticker ? Theme.stickerInk : Theme.ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint))
        .alert("How much was \(bill.name)?", isPresented: $askingAmount) {
            TextField("Amount", text: $amountText)
            Button("Mark paid") {
                let value = Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0
                BillTracker.setPaid(bill, due: cycle.due, true, amount: value, context: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's logged as an expense and comes off what's left to spend.")
        }
    }
}

struct BillEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let bill: Bill?

    @State private var name = ""
    @State private var amount = ""
    @State private var dueDay = 1
    @State private var remindDays = 3
    @State private var match = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(bill == nil ? "New bill" : "Edit bill").font(Theme.display(26))
            Form {
                TextField("Name", text: $name, prompt: Text("Rent, Internet, Vodafone…"))
                TextField("Usual amount", text: $amount, prompt: Text("0 if it changes"))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Picker("Due on day", selection: $dueDay) { ForEach(1...31, id: \.self) { Text("\($0)").tag($0) } }
                Picker("Remind me", selection: $remindDays) {
                    Text("On the day").tag(0); Text("1 day before").tag(1); Text("3 days before").tag(3); Text("A week before").tag(7)
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Bank text words", text: $match, prompt: Text(name.isEmpty ? "e.g. vodafone, we" : name.lowercased()))
                    Text("When an expense with one of these words comes in near the due date, the bill is marked paid. Separate words with commas.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                if let bill {
                    Button("Delete", role: .destructive) { context.delete(bill); dismiss() }.buttonStyle(SoftButtonStyle())
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).fixedSize()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Platform.isPhone ? 20 : 24)
        .sheetFrame(width: 460, height: 540)
        .onAppear {
            guard let bill else { return }
            name = bill.name; amount = bill.amount > 0 ? String(format: "%g", bill.amount) : ""
            dueDay = bill.dueDay; remindDays = bill.remindDays; match = bill.match
        }
    }

    private func save() {
        let b = bill ?? { let b = Bill(name: ""); context.insert(b); return b }()
        b.name = name.trimmingCharacters(in: .whitespaces)
        b.amount = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
        b.dueDay = dueDay; b.remindDays = remindDays; b.match = match.trimmingCharacters(in: .whitespaces)
        try? context.save()
        dismiss()
    }
}

/// Money › Overview: the last seven days next to the week before, and subscriptions or bills that need a look.
struct WeeklyMoneyCard: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var subscriptions: [Subscription]
    @Query private var bills: [Bill]

    var body: some View {
        let r = WeeklyMoney.report(transactions: transactions, subscriptions: subscriptions, bills: bills)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Your week in money", systemImage: "calendar").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Text("\(r.from.formatted(.dateTime.day().month(.abbreviated))) – today").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                }
                AdaptiveStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Fmt.money(r.spent)).font(Theme.display(30))
                        if let c = r.change, abs(c) >= 0.01 {
                            Label("\(Int(abs(c) * 100))% \(c > 0 ? "more" : "less") than last week", systemImage: c > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(Theme.ui(12, weight: .semibold)).foregroundStyle(c > 0 ? Theme.critical : Theme.good)
                        } else {
                            Text(r.lastWeek > 0 ? "About the same as last week" : "Spent in the last 7 days").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .frame(minWidth: 180, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(r.categories.prefix(3)) { c in
                            HStack(spacing: 8) {
                                Text(c.name).font(Theme.ui(13, weight: .medium))
                                Spacer()
                                Text(Fmt.money(c.spent)).font(Theme.ui(13, weight: .semibold))
                                if c.before > 0 {
                                    let d = c.spent / c.before - 1
                                    Text("\(d >= 0 ? "+" : "−")\(Int(abs(d) * 100))%").font(Theme.ui(11, weight: .medium))
                                        .foregroundStyle(d > 0.05 ? Theme.critical : d < -0.05 ? Theme.good : Theme.inkMuted).frame(width: 44, alignment: .trailing)
                                } else {
                                    Text("new").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).frame(width: 44, alignment: .trailing)
                                }
                            }
                        }
                        if let b = r.biggest {
                            Text("Biggest: \(b.title) \(Fmt.money(-b.amount))\(r.topMerchant.map { " · Most often: \($0.name) ×\($0.count)" } ?? "")")
                                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                        }
                        if r.categories.isEmpty { EmptyHint(symbol: "tray", text: "Nothing spent this week.") }
                    }
                    .frame(maxWidth: 420)
                    Spacer(minLength: 0)
                }
                if !r.flags.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(r.flags.prefix(5)) { f in
                            Label(f.text, systemImage: f.symbol).font(Theme.ui(12)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
