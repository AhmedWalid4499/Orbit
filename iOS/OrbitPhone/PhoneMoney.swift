import SwiftUI
import SwiftData
import Charts
import PhotosUI

/// Money on iPhone: the month at a glance, then Overview, Calendar or Subscriptions, like the Mac.
struct PhoneMoney: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var all: [Transaction]
    @AppStorage("monthlyBudget") private var monthlyBudget = 2000.0
    @AppStorage("moneyTab") private var mode = "overview"

    @State private var period = BudgetPeriod.current
    @State private var confirmNewMonth = false
    private var month: Date { period.start }
    @State private var adding = false
    @State private var pickingStatement = false
    @State private var statement: StatementFile?
    @State private var bankSetup = false
    @State private var camera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var receiptMenu = false
    @State private var receipt: ReceiptPhoto?
    @State private var rulesOpen = false

    private var monthEnd: Date { period.end }
    private var txns: [Transaction] { all.filter { $0.date >= month && $0.date < monthEnd } }
    private var spent: Double { -txns.filter(\.isExpense).reduce(0) { $0 + $1.amount } }
    private var income: Double { txns.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(BudgetPeriod.title(period)).font(Theme.display(22))
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain).font(.system(size: 16, weight: .semibold))

                BalanceCard(title: "Left to spend", value: monthlyBudget - spent, caption: "of \(Fmt.money(monthlyBudget)) budget\(BudgetPeriod.isCustom ? " · since \(period.start.formatted(.dateTime.day().month(.abbreviated)))" : "")",
                            fill: LinearGradient(colors: [Theme.lime, Theme.mint], startPoint: .topLeading, endPoint: .bottomTrailing), symbol: "target")
                HStack(spacing: 12) {
                    mini("Spent", Fmt.money(spent), "\(txns.filter(\.isExpense).count) expenses", Theme.peach)
                    mini("Income", Fmt.money(income), "Net \(Fmt.money(income - spent, signed: true))", Theme.cyan)
                }

                Picker("", selection: $mode) {
                    Text("Overview").tag("overview"); Text("Calendar").tag("calendar"); Text("Bills").tag("bills"); Text("Subs").tag("subscriptions")
                }
                .pickerStyle(.segmented)

                if mode == "calendar" {
                    MoneyCalendar(month: period.start.adding(days: 14), transactions: all)
                } else if mode == "subscriptions" {
                    SubscriptionsView()
                } else if mode == "bills" {
                    BillsView()
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            Button { adding = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
                            Button { receiptMenu = true } label: { Label("Receipt", systemImage: "doc.viewfinder") }.buttonStyle(SoftButtonStyle())
                            Button { rulesOpen = true } label: { Label("Budgets", systemImage: "slider.horizontal.3") }.buttonStyle(SoftButtonStyle())
                            Button { confirmNewMonth = true } label: { Label("New month", systemImage: "arrow.counterclockwise") }.buttonStyle(SoftButtonStyle())
                            Button { pickingStatement = true } label: { Label("Statement", systemImage: "doc.text.magnifyingglass") }
                                .buttonStyle(SoftButtonStyle())
                        }
                    }
                    .scrollIndicators(.never)
                    AccountsStrip(period: period)
                    autoLogCard
                    WeeklyMoneyCard()
                    MoneyCoachCard()
                    chart
                    categories
                    transactions
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .sheet(isPresented: $adding) { NewTransactionSheet().presentationDetents([.large]) }
        .fileImporter(isPresented: $pickingStatement, allowedContentTypes: [.commaSeparatedText, .plainText, .pdf, .text]) { result in
            if case .success(let url) = result { statement = StatementFile(url: url) }
        }
        .sheet(item: $statement) { StatementImportSheet(url: $0.url) }
        .sheet(isPresented: $bankSetup) { PhoneBankSetup() }
        .sheet(isPresented: $rulesOpen) { MoneyRulesSheet() }
        .sheet(item: $receipt) { ReceiptScanSheet(photo: $0) }
        .confirmationDialog("Add a receipt", isPresented: $receiptMenu) {
            Button("Take photo") { camera = true }
            Button("Choose from Photos") { choosingPhoto = true }
        }
        .fullScreenCover(isPresented: $camera) { CameraPicker { receipt = ReceiptPhoto(image: $0) }.ignoresSafeArea() }
        .photosPicker(isPresented: $choosingPhoto, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) { receipt = ReceiptPhoto(image: img) }
                libraryItem = nil
            }
        }
        .newBudgetMonthDialog($confirmNewMonth) { period = BudgetPeriod.current }
        .phoneChrome("Money")
    }

    /// Card and Apple Pay spending, via Shortcuts automations.
    private var autoLogCard: some View {
        let count = all.filter(\.fromBank).count
        return Button { bankSetup = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "wave.3.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                    .frame(width: 38, height: 38).background(Circle().fill(Theme.lime))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-log card payments").font(Theme.ui(15, weight: .semibold))
                    Text(count == 0 ? "Apple Pay and bank texts, straight into Money" : "\(count) logged from Apple Pay and bank texts")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        }
        .buttonStyle(.plain)
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) { period = BudgetPeriod.shifted(period, by: n) }
    }

    private func mini(_ title: String, _ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.ui(13, weight: .semibold))
            Text(value).font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.5)
            Text(caption).font(Theme.ui(11, weight: .medium)).opacity(0.75).lineLimit(1)
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(color))
    }

    private var chart: some View {
        let days = Calendar.current.dateComponents([.day], from: period.start, to: period.end).day ?? 30
        let grouped = Dictionary(grouping: txns.filter(\.isExpense)) { $0.date.startOfDay }
        let points = (0..<days).map { i -> (Date, Double) in
            let d = month.adding(days: i)
            return (d, -(grouped[d]?.reduce(0) { $0 + $1.amount } ?? 0))
        }
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily spending").font(Theme.display(20))
                Chart(points, id: \.0) { p in
                    BarMark(x: .value("Day", p.0, unit: .day), y: .value("Spent", p.1))
                        .foregroundStyle(p.0.isToday ? Theme.orange : Theme.ink.opacity(0.75)).cornerRadius(3)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 150)
            }
        }
    }

    private var categories: some View {
        let byCategory = Dictionary(grouping: txns.filter(\.isExpense), by: \.category)
            .map { ($0.key, -$0.value.reduce(0) { $0 + $1.amount }) }.sorted { $0.1 > $1.1 }
        return Group {
            if !byCategory.isEmpty {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("By category").font(Theme.display(20))
                        ForEach(byCategory, id: \.0) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(c.0).font(Theme.ui(14, weight: .medium))
                                    Spacer()
                                    Text(Fmt.money(c.1)).font(Theme.ui(14, weight: .semibold))
                                }
                                ProgressView(value: spent > 0 ? c.1 / spent : 0).tint(Theme.ink)
                            }
                        }
                    }
                }
            }
        }
    }

    private var transactions: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transactions").font(Theme.display(20))
                if txns.isEmpty { EmptyHint(symbol: "creditcard", text: "No transactions this month. Try + → “$12 lunch”.") }
                let groups = Dictionary(grouping: txns) { $0.date.startOfDay }
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    Text(Fmt.relativeDay(day)).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted).padding(.top, 4)
                    ForEach(groups[day]!) { TxnRow(txn: $0) }
                }
            }
        }
    }
}
