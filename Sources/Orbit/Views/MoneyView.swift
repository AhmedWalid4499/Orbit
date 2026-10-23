import SwiftUI
import SwiftData
import Charts

struct MoneyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var all: [Transaction]
    @AppStorage("monthlyBudget") private var monthlyBudget = 2000.0

    @State private var month = Date.now.startOfMonth
    @State private var adding = false
    @State private var hoveredDay: Date?
    /// overview, calendar or subscriptions
    @AppStorage("moneyTab") private var mode = "overview"
    @State private var pickingStatement = false
    @State private var pickingReceipt = false
    @State private var receipt: ReceiptPhoto?
    @State private var rulesOpen = false
    @State private var statement: StatementFile?

    private var monthEnd: Date { Calendar.current.date(byAdding: .month, value: 1, to: month)! }
    private var txns: [Transaction] { all.filter { $0.date >= month && $0.date < monthEnd } }
    private var spent: Double { -txns.filter(\.isExpense).reduce(0) { $0 + $1.amount } }
    private var income: Double { txns.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount } }

    private struct DayTotal: Identifiable { let day: Date; let total: Double; var id: Date { day } }

    private var daily: [DayTotal] {
        let days = Calendar.current.range(of: .day, in: .month, for: month)!.count
        let grouped = Dictionary(grouping: txns.filter(\.isExpense)) { $0.date.startOfDay }
        return (0..<days).map { i in
            let d = month.adding(days: i)
            return DayTotal(day: d, total: -(grouped[d]?.reduce(0) { $0 + $1.amount } ?? 0))
        }
    }

    private var byCategory: [(String, Double)] {
        Dictionary(grouping: txns.filter(\.isExpense), by: \.category)
            .map { ($0.key, -$0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
    }

    private var recurring: [Transaction] {
        // Latest instance of each recurring item, across all months.
        var seen = Set<String>()
        return all.filter { $0.isRecurring && seen.insert($0.title).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                HStack(spacing: 20) {
                    BalanceCard(title: "Left to spend", value: monthlyBudget - spent,
                                caption: "of \(Fmt.money(monthlyBudget)) budget",
                                fill: LinearGradient(colors: [Theme.lime, Theme.mint], startPoint: .topLeading, endPoint: .bottomTrailing),
                                symbol: "target")
                    BalanceCard(title: "Spent", value: spent, caption: "\(txns.filter(\.isExpense).count) expenses",
                                fill: LinearGradient(colors: [Theme.orange, Theme.peach], startPoint: .topLeading, endPoint: .bottomTrailing),
                                symbol: "arrow.up.right")
                    BalanceCard(title: "Income", value: income, caption: "Net \(Fmt.money(income - spent, signed: true))",
                                fill: LinearGradient(colors: [Theme.cyan, Theme.purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                                symbol: "arrow.down.left")
                }
                if mode == "calendar" {
                    MoneyCalendar(month: month, transactions: all)
                } else if mode == "subscriptions" {
                    SubscriptionsView()
                } else if mode == "bills" {
                    BillsView()
                } else {
                    WeeklyMoneyCard()
                    MoneyCoachCard()
                    HStack(alignment: .top, spacing: 20) {
                        chartCard
                        categoryCard.frame(width: 340)
                    }
                    HStack(alignment: .top, spacing: 20) {
                        transactionsCard
                        recurringCard.frame(width: 340)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .sheet(isPresented: $adding) { NewTransactionSheet() }
        .fileImporter(isPresented: $pickingStatement, allowedContentTypes: [.commaSeparatedText, .plainText, .pdf, .text]) { result in
            if case .success(let url) = result { statement = StatementFile(url: url) }
        }
        .sheet(item: $statement) { StatementImportSheet(url: $0.url) }
        .sheet(item: $receipt) { ReceiptScanSheet(photo: $0) }
        .sheet(isPresented: $rulesOpen) { MoneyRulesSheet() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(month.formatted(.dateTime.month(.wide).year())).font(Theme.display(38)).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 2) {
                ForEach([("Overview", "overview"), ("Calendar", "calendar"), ("Bills", "bills"), ("Subscriptions", "subscriptions")], id: \.1) { label, key in
                    Button(label) { withAnimation(.snappy) { mode = key } }
                        .buttonStyle(.plain)
                        .font(Theme.ui(13, weight: .semibold)).lineLimit(1).fixedSize()
                        .foregroundStyle(mode == key ? Theme.onInverse : Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(mode == key ? Theme.inverse : .clear))
                }
            }
            .padding(3)
            .background(Capsule().fill(Theme.card))
            .padding(.leading, 8)
            Spacer()
            EmailExpensesChip()
            Button { pickingReceipt = true } label: { Label("Receipt", systemImage: "doc.viewfinder") }
                .buttonStyle(SoftButtonStyle()).help("Add an expense from a photo of a receipt")
                .fileImporter(isPresented: $pickingReceipt, allowedContentTypes: [.image]) { result in
                    guard case .success(let url) = result else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let img = PlatformImage.load(url) { receipt = ReceiptPhoto(image: img) }
                }
            Button { rulesOpen = true } label: { Label("Budgets", systemImage: "slider.horizontal.3") }
                .buttonStyle(SoftButtonStyle()).help("Budgets per category, spending alerts and learned merchant categories")
            Button { pickingStatement = true } label: { Label("Import", systemImage: "doc.text.magnifyingglass") }
                .buttonStyle(SoftButtonStyle()).help("Add transactions from your bank's CSV or PDF statement")
            Button { adding = true } label: { Label("Add transaction", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
            CircleIconButton(symbol: "arrow.left", filled: true, size: 46) {
                month = Calendar.current.date(byAdding: .month, value: -1, to: month)!
            }
            CircleIconButton(symbol: "arrow.right", filled: true, size: 46) {
                month = Calendar.current.date(byAdding: .month, value: 1, to: month)!
            }
        }
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Daily spending").font(Theme.display(22))
                    Spacer()
                    if let d = hoveredDay, let t = daily.first(where: { $0.day == d }) {
                        Text("\(d.formatted(.dateTime.weekday().day().month())) · \(Fmt.money(t.total))")
                            .font(Theme.ui(13, weight: .medium))
                    } else {
                        Text("Hover a bar for details").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                    }
                }
                Chart(daily) { item in
                    BarMark(x: .value("Day", item.day, unit: .day),
                            y: .value("Spent", item.total), width: .ratio(0.6))
                        .foregroundStyle(hoveredDay == nil || hoveredDay == item.day ? Theme.ink : Theme.inkMuted.opacity(0.5))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                }
                .chartXSelection(value: $hoveredDay)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.money(d)) } }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var categoryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("By category").font(Theme.display(22))
                if byCategory.isEmpty { EmptyHint(symbol: "chart.bar", text: "No spending yet.") }
                let maxV = byCategory.first?.1 ?? 1
                ForEach(byCategory, id: \.0) { cat, value in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(cat).font(Theme.ui(13, weight: .medium))
                            Spacer()
                            Text(Fmt.money(value)).font(Theme.ui(13, weight: .semibold))
                            Text("\(Int((value / max(spent, 1) * 100).rounded()))%")
                                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).frame(width: 34, alignment: .trailing)
                        }
                        GeometryReader { g in
                            Capsule().fill(Theme.ink).frame(width: max(4, g.size.width * value / maxV))
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }

    private var transactionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Transactions").font(Theme.display(22))
                if txns.isEmpty { EmptyHint(symbol: "creditcard", text: "No transactions this month. Try ⌥Space → “$12 lunch”.") }
                let groups = Dictionary(grouping: txns) { $0.date.startOfDay }
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    Text(Fmt.relativeDay(day)).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted).padding(.top, 6)
                    ForEach(groups[day]!) { TxnRow(txn: $0) }
                }
            }
        }
    }

    private var recurringCard: some View {
        Card(fill: Theme.blush) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recurring").font(Theme.display(22))
                Text("Subscriptions and bills that repeat monthly.").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                if recurring.isEmpty { EmptyHint(symbol: "repeat", text: "Mark a transaction as recurring to track it.") }
                ForEach(recurring) { t in
                    let next = Calendar.current.date(byAdding: .month, value: 1, to: t.date)!
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).font(Theme.ui(14, weight: .medium))
                            Text("Next ~ \(next.formatted(.dateTime.day().month()))").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer()
                        Text(Fmt.money(t.amount, signed: true)).font(Theme.ui(14, weight: .semibold))
                            .foregroundStyle(t.isExpense ? Theme.ink : Theme.good)
                    }
                }
                let monthly = recurring.filter(\.isExpense).reduce(0) { $0 - $1.amount }
                Divider()
                HStack {
                    Text("Fixed costs / month").font(Theme.ui(13))
                    Spacer()
                    Text(Fmt.money(monthly)).font(Theme.ui(14, weight: .bold))
                }
            }
        }
    }
}

struct BalanceCard: View {
    let title: String
    let value: Double
    let caption: String
    let fill: LinearGradient
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(Theme.ui(14, weight: .semibold))
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.5)))
            }
            Text(Fmt.money(value)).font(Theme.display(40)).minimumScaleFactor(0.6).lineLimit(1)
            Text(caption).font(Theme.ui(12, weight: .medium)).opacity(0.75)
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(fill))
    }
}

struct TxnRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var txn: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.stickerInk)
                .frame(width: 34, height: 34)
                .background(Circle().fill(txn.isExpense ? Theme.peach : Theme.mint))
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.title).font(Theme.ui(14, weight: .medium))
                HStack(spacing: 6) {
                    if txn.fromEmail { Image(systemName: "envelope.fill").help("Added from \(txn.source.dropFirst(6))") }
                    if txn.fromBank { Image(systemName: txn.source == "sms" ? "message.fill" : "wave.3.right").help(txn.source == "sms" ? "Added from a bank message" : "Added from Apple Pay") }
                    if txn.source == "receipt" { Image(systemName: "doc.viewfinder").help("Added from a receipt photo") }
                    Text(txn.category)
                    if !txn.originalCurrency.isEmpty {
                        Text("· \(txn.originalAmount.formatted(.number.precision(.fractionLength(0...2)))) \(txn.originalCurrency)")
                    }
                    if txn.isRecurring { Image(systemName: "repeat") }
                }
                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Text(Fmt.money(txn.amount, signed: true))
                .font(Theme.ui(14, weight: .semibold))
                .foregroundStyle(txn.isExpense ? Theme.ink : Theme.good)
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
        .contextMenu {
            Toggle("Recurring", isOn: $txn.isRecurring)
            Menu("Category") {
                ForEach(MoneyCategory.all, id: \.self) { c in Button(c) { MerchantRules.learn(txn, category: c, context: context) } }
            }
            Divider()
            if txn.fromEmail {
                Button("Not an expense") { EmailExpenses.shared.reject(txn, context: context) }
                if let link = URL(string: "https://mail.google.com/mail/u/?authuser=\(txn.source.dropFirst(6))#all/\(txn.sourceID)") {
                    Link("Open email", destination: link)
                }
            }
            Button("Delete", role: .destructive) { context.delete(txn) }
        }
    }

    private var icon: String {
        switch txn.category {
        case "Food": "fork.knife"
        case "Transport": "car.fill"
        case "Bills": "bolt.fill"
        case "Shopping": "bag.fill"
        case "Health": "cross.case.fill"
        case "Fun": "theatermasks.fill"
        case "Subscriptions": "repeat"
        case "Income": "arrow.down.left"
        default: "circle.grid.2x2.fill"
        }
    }
}

struct NewTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var amount = ""
    @State private var isIncome = false
    @State private var category = "Food"
    @State private var date = Date.now
    @State private var recurring = false
    @State private var pickedCategory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New transaction").font(Theme.display(28))
            Picker("", selection: $isIncome) { Text("Expense").tag(false); Text("Income").tag(true) }
                .pickerStyle(.segmented).labelsHidden()
            field("What", text: $title, prompt: "Groceries")
                .onChange(of: title) { _, t in
                    if !pickedCategory { let g = QuickParser.guessCategory(t); category = g == "Income" || g == "General" && t.isEmpty ? "Food" : g }
                }
            field("Amount", text: $amount, prompt: "0.00")
            HStack {
                Picker("Category", selection: Binding(get: { category }, set: { category = $0; pickedCategory = true })) {
                    ForEach(MoneyCategory.all, id: \.self) { Text($0) }
                }
                DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
            }
            Toggle("Repeats monthly", isOn: $recurring)
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Spacer()
                Button("Add") {
                    let v = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
                    let t = Transaction(title: title, amount: isIncome ? v : -v,
                                        category: isIncome ? "Income" : category, date: date, isRecurring: recurring)
                    context.insert(t)
                    // Picking a different category than Orbit suggested teaches it this merchant.
                    if !isIncome, pickedCategory, category != QuickParser.guessCategory(title) { MerchantRules.learn(t, category: category, context: context) }
                    t.category = isIncome ? "Income" : category
                    SpendingAlerts.check(context: context)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle()).frame(width: 120)
                .disabled(title.isEmpty || Double(amount.replacingOccurrences(of: ",", with: ".")) == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(Theme.ui(13))
        .padding(28)
        .sheetFrame(width: 420)
        .onChange(of: title) { _, t in if !isIncome { category = ["General", "Income"].contains(QuickParser.guessCategory(t)) ? category : QuickParser.guessCategory(t) } }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).foregroundStyle(Theme.inkSecondary)
            TextField(prompt, text: text).textFieldStyle(.plain).font(Theme.ui(16))
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        }
    }
}

/// Status of receipts imported from Gmail, with a manual sync.
struct EmailExpensesChip: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var importer = EmailExpenses.shared
    @ObservedObject private var inbox = InboxStore.shared
    @State private var showing = false

    var body: some View {
        if inbox.isConnected && importer.enabled {
            Button { showing = true } label: {
                HStack(spacing: 6) {
                    if importer.running { ProgressView().controlSize(.mini) } else { Image(systemName: "envelope.badge") }
                    Text(importer.running ? "Reading receipts…" : "From email")
                }
                .font(Theme.ui(13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Theme.card))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Expenses from email").font(Theme.display(20))
                    Text("\(AssistantName.current) checks both inboxes every few hours: anything under a payments, receipts, bank or orders label, plus receipts, invoices and card-charge emails anywhere. Paid amounts are added here (converted to \(Fmt.currencyCode)); bills still due become tasks.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    if let s = importer.status { Text(s).font(Theme.ui(12, weight: .medium)) }
                    if importer.lastSync > 0 {
                        Text("Last checked \(Date(timeIntervalSince1970: importer.lastSync).formatted(.relative(presentation: .named)))")
                            .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                    }
                    Text("Wrong one? Right-click it › Not an expense, and it won't come back.")
                        .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                    Button(importer.running ? "Checking…" : "Check now") { Task { await importer.sync(context: context) } }
                        .buttonStyle(PrimaryButtonStyle()).disabled(importer.running)
                }
                .padding(20)
                .frame(width: 340)
            }
        }
    }
}

/// A picked statement file, for `.sheet(item:)`.
struct StatementFile: Identifiable {
    let url: URL
    var id: URL { url }
}
