import SwiftUI
import SwiftData
import Charts

/// Bank cards along the top of Money, one per account Orbit has seen in bank texts and Apple Pay (or you added).
/// Each opens its own page: balance, spending by month, categories and transactions.
struct AccountsStrip: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BankAccount.createdAt) private var accounts: [BankAccount]
    @Query(sort: \Transaction.date, order: .reverse) private var all: [Transaction]
    let period: DateInterval
    @State private var open: BankAccount?
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your banks").font(Theme.display(22))
                Spacer()
                Button { adding = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
            }
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(accounts) { a in
                        Button { open = a } label: {
                            AccountCardView(account: a, spent: Accounts.totals(a, all, in: period).spent)
                        }
                        .buttonStyle(.plain)
                    }
                    if accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "creditcard.and.123").font(.system(size: 22, weight: .semibold))
                            Text("Each bank and card gets its own page here.").font(Theme.ui(14, weight: .semibold))
                            Text("They appear by themselves from your bank texts and Apple Pay, with the balance your bank last texted. You can also add one.")
                                .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(width: 300, height: 180, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
        }
        .sheet(item: $open) { AccountPage(account: $0) }
        .sheet(isPresented: $adding) { AccountEditor(account: nil) }
    }
}

/// A bank card, like the ones in a banking app.
struct AccountCardView: View {
    let account: BankAccount
    var spent: Double = 0
    var wide = false

    static func gradient(_ i: Int) -> LinearGradient {
        let pairs: [(UInt32, UInt32)] = [(0x7B5CF5, 0x4338CA), (0xE6FF1F, 0x8EEDBF), (0x27D3F6, 0x7B5CF5),
                                         (0xEDAA2F, 0xF7C2EC), (0xF472B6, 0x7C3AED), (0x2A2A30, 0x0E0E10)]
        let p = pairs[((i % pairs.count) + pairs.count) % pairs.count]
        return LinearGradient(colors: [Color(hex: p.0), Color(hex: p.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func ink(_ i: Int) -> Color { [1, 3].contains(((i % 6) + 6) % 6) ? Theme.stickerInk : .white }

    private var symbol: String {
        switch account.kind {
        case "account": "building.columns.fill"
        case "wallet": "iphone.gen3"
        case "cash": "banknote.fill"
        default: "creditcard.fill"
        }
    }

    var body: some View {
        let ink = Self.ink(account.colorIndex)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(account.name).font(.system(size: 18, weight: .bold)).lineLimit(1)
                Spacer()
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).opacity(0.85)
            }
            Spacer(minLength: 8)
            Text(account.last4.isEmpty ? " " : "••••  ••••  ••••  \(account.last4)").font(.system(size: 15, weight: .medium, design: .monospaced)).opacity(0.85)
            Spacer(minLength: 8)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.balanceAt != nil ? (account.kind == "card" ? "Available" : "Balance") : "Spent this month")
                        .font(.system(size: 11, weight: .semibold)).opacity(0.75)
                    Text(Fmt.money(account.balanceAt != nil ? account.balance : spent)).font(.system(size: wide ? 30 : 24, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer()
                if let at = account.balanceAt {
                    Text(at.formatted(.relative(presentation: .named))).font(.system(size: 10, weight: .medium)).opacity(0.7)
                } else {
                    HStack(spacing: -8) {
                        Circle().fill(Color.white.opacity(0.55)).frame(width: 24, height: 24)
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 24, height: 24)
                    }
                }
            }
        }
        .foregroundStyle(ink)
        .padding(18)
        .frame(width: wide ? nil : 300, height: wide ? 200 : 180)
        .frame(maxWidth: wide ? .infinity : nil)
        .background {
            ZStack {
                Self.gradient(account.colorIndex)
                // A soft sheen, like a real card.
                Circle().fill(Color.white.opacity(0.12)).frame(width: 220).offset(x: 120, y: -70)
                Circle().fill(Color.white.opacity(0.07)).frame(width: 180).offset(x: -110, y: 90)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
    }
}

/// One account's page: its card, this budget month, six months of spending, categories and every transaction.
struct AccountPage: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var account: BankAccount
    @Query(sort: \Transaction.date, order: .reverse) private var all: [Transaction]
    @State private var editing = false

    private var mine: [Transaction] { all.filter { $0.account == account.uuid } }
    private var period: DateInterval { BudgetPeriod.current }

    private struct Month: Identifiable { let id: Int; let label: String; let spent: Double }
    private var months: [Month] {
        (0..<6).reversed().map { back in
            let p = BudgetPeriod.shifted(period, by: -back)
            return Month(id: back, label: p.start.formatted(.dateTime.month(.abbreviated)), spent: Accounts.totals(account, all, in: p).spent)
        }
    }

    private var categories: [(String, Double)] {
        let spent = mine.filter { $0.isExpense && $0.date >= period.start && $0.date < period.end }
        return Dictionary(grouping: spent, by: \.category).map { ($0.key, -$0.value.reduce(0) { $0 + $1.amount }) }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        let t = Accounts.totals(account, all, in: period)
        VStack(spacing: 0) {
            HStack {
                Text(account.title).font(Theme.display(26)).lineLimit(1)
                Spacer()
                Button("Edit") { editing = true }.buttonStyle(SoftButtonStyle())
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).fixedSize()
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AccountCardView(account: account, spent: t.spent, wide: true)
                    HStack(spacing: 12) {
                        tile("Spent", Fmt.money(t.spent), "this budget month", Theme.peach)
                        tile("Money in", Fmt.money(t.income), "this budget month", Theme.mint)
                        tile("Payments", "\(mine.filter { $0.date >= period.start }.count)", "this budget month", Theme.cyan)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Spending by month").font(Theme.ui(15, weight: .semibold))
                        Chart(months) { m in
                            BarMark(x: .value("Month", m.label), y: .value("Spent", m.spent))
                                .foregroundStyle(AccountCardView.gradient(account.colorIndex)).cornerRadius(6)
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 170)
                    }
                    .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
                    if !categories.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Breakdown").font(Theme.ui(15, weight: .semibold))
                            let total = max(1, categories.reduce(0) { $0 + $1.1 })
                            ScrollView(.horizontal) {
                                HStack(spacing: 14) {
                                    ForEach(categories.prefix(6), id: \.0) { c in
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle().stroke(Theme.line, lineWidth: 5)
                                                Circle().trim(from: 0, to: c.1 / total).stroke(AccountCardView.gradient(account.colorIndex), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                                    .rotationEffect(.degrees(-90))
                                                Text("\(Int((c.1 / total * 100).rounded()))%").font(Theme.ui(12, weight: .bold))
                                            }
                                            .frame(width: 58, height: 58)
                                            Text(c.0).font(Theme.ui(11, weight: .medium)).lineLimit(1)
                                            Text(Fmt.money(c.1)).font(Theme.ui(10)).foregroundStyle(Theme.inkMuted)
                                        }
                                        .frame(width: 76)
                                    }
                                }
                            }
                            .scrollIndicators(.never)
                        }
                        .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transactions").font(Theme.ui(15, weight: .semibold))
                        if mine.isEmpty {
                            Text("Payments from this \(account.kind == "account" ? "account" : "card") show up here.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                        }
                        ForEach(mine.prefix(80)) { tx in
                            HStack(spacing: 12) {
                                Text(String(tx.title.prefix(1)).uppercased()).font(Theme.ui(14, weight: .bold)).foregroundStyle(AccountCardView.ink(account.colorIndex))
                                    .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 10).fill(AccountCardView.gradient(account.colorIndex)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tx.title).font(Theme.ui(14, weight: .semibold)).lineLimit(1)
                                    Text("\(tx.category) · \(tx.date.formatted(.dateTime.day().month(.abbreviated)))").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                                Text(Fmt.money(tx.amount, signed: true)).font(Theme.ui(14, weight: .semibold))
                                    .foregroundStyle(tx.isExpense ? Theme.critical : Theme.good)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        }
        .background(Theme.canvas)
        .sheetFrame(width: 720, height: 760)
        .sheet(isPresented: $editing) { AccountEditor(account: account) }
    }

    private func tile(_ title: String, _ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.ui(12, weight: .semibold))
            Text(value).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.5)
            Text(caption).font(Theme.ui(10, weight: .medium)).opacity(0.7)
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(color))
    }
}

/// Add or change an account: name, last 4 digits, kind, colour and (optionally) its balance.
struct AccountEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let account: BankAccount?
    @State private var name = ""
    @State private var last4 = ""
    @State private var kind = "card"
    @State private var colorIndex = 0
    @State private var balance = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(account == nil ? "Add a bank or card" : "Edit \(account!.title)").font(Theme.display(24))
            AccountCardView(account: preview, wide: true)
            TextField("Bank or wallet, e.g. CIB", text: $name).textFieldStyle(.roundedBorder)
            TextField("Last 4 digits (optional)", text: $last4).textFieldStyle(.roundedBorder)
                .onChange(of: last4) { _, v in last4 = String(v.filter(\.isNumber).prefix(4)) }
            Picker("Type", selection: $kind) {
                Text("Card").tag("card"); Text("Account").tag("account"); Text("Wallet").tag("wallet"); Text("Cash").tag("cash")
            }
            .pickerStyle(.segmented)
            HStack(spacing: 10) {
                ForEach(0..<Accounts.palettes, id: \.self) { i in
                    Circle().fill(AccountCardView.gradient(i)).frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: colorIndex == i ? 2.5 : 0))
                        .onTapGesture { colorIndex = i }
                }
            }
            TextField("Balance now (optional; bank texts keep it up to date)", text: $balance).textFieldStyle(.roundedBorder)
            HStack {
                if account != nil {
                    Button("Delete", role: .destructive) { confirmDelete = true }.buttonStyle(SoftButtonStyle())
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).fixedSize()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .font(Theme.ui(14))
        .padding(24)
        .sheetFrame(width: 460, height: nil)
        .onAppear {
            guard let a = account else { return }
            name = a.name; last4 = a.last4; kind = a.kind; colorIndex = a.colorIndex
            if a.balanceAt != nil { balance = a.balance.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
        }
        .confirmationDialog("Delete \(account?.title ?? "this account")?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let a = account {
                    let id = a.uuid
                    for t in (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.account == id }))) ?? [] { t.account = "" }
                    context.delete(a)
                    try? context.save()
                }
                dismiss()
            }
        } message: { Text("Its transactions stay in Money; they just won't be linked to this card any more.") }
    }

    private var preview: BankAccount {
        let a = BankAccount(name: name.isEmpty ? "Bank" : name, last4: last4, kind: kind)
        a.colorIndex = colorIndex
        if let v = Double(balance.replacingOccurrences(of: ",", with: "")) { a.balance = v; a.balanceAt = .now }
        return a
    }

    private func save() {
        let a = account ?? {
            let a = BankAccount(name: "")
            a.uuid = UUID().uuidString.lowercased()
            context.insert(a)
            return a
        }()
        a.name = name.trimmingCharacters(in: .whitespaces); a.last4 = last4; a.kind = kind; a.colorIndex = colorIndex
        if let v = Double(balance.replacingOccurrences(of: ",", with: "")) {
            if a.balanceAt == nil || abs(a.balance - v) > 0.001 { a.balance = v; a.balanceAt = .now }
        } else if balance.isEmpty { a.balanceAt = nil; a.balance = 0 }
        try? context.save()
        dismiss()
    }
}
