import SwiftUI
import SwiftData

/// Money › Budgets & rules: a budget per category (alerts at 80% and 100%) and the merchant categories Orbit learned.
struct MoneyRulesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var all: [Transaction]
    @AppStorage("monthlyBudget") private var monthlyBudget = 2000.0
    @State private var budgets = SpendingAlerts.budgets
    @State private var rules = MerchantRules.all
    @State private var budgetAlerts = SpendingAlerts.budgetAlerts
    @State private var bigCharges = SpendingAlerts.bigChargeAlerts

    private var monthSpend: [String: Double] {
        let start = Date.now.startOfMonth
        return Dictionary(grouping: all.filter { $0.isExpense && $0.date >= start }, by: \.category).mapValues { -$0.reduce(0) { $0 + $1.amount } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Budgets & rules").font(Theme.display(28))
                    Spacer()
                    Button("Done") { save(); dismiss() }.buttonStyle(PrimaryButtonStyle()).fixedSize().keyboardShortcut(.defaultAction)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Alerts").font(Theme.display(20))
                    Toggle("Tell me when spending reaches 80% and 100% of a budget", isOn: $budgetAlerts).font(Theme.ui(14))
                    Toggle("Tell me about unusually large charges", isOn: $bigCharges).font(Theme.ui(14))
                }
                .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Budgets this month").font(Theme.display(20))
                    budgetRow("Everything", spent: monthSpend.values.reduce(0, +), value: $monthlyBudget)
                    ForEach(MoneyCategory.all.filter { $0 != "Income" }, id: \.self) { c in
                        budgetRow(c, spent: monthSpend[c] ?? 0, value: Binding(get: { budgets[c] ?? 0 }, set: { budgets[c] = $0 }))
                    }
                    Text("Leave a category at 0 for no limit.").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                }
                .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Learned from you").font(Theme.display(20))
                    if rules.isEmpty {
                        Text("Change an expense's category (\(Platform.isPhone ? "long-press it" : "right-click it") › Category) and Orbit files that shop the same way from then on, including email, bank texts and receipts.")
                            .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(rules.keys.sorted(), id: \.self) { merchant in
                        HStack {
                            Text(merchant.capitalized).font(Theme.ui(14, weight: .medium))
                            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
                            Menu(rules[merchant] ?? "") {
                                ForEach(MoneyCategory.all.filter { $0 != "Income" }, id: \.self) { c in Button(c) { rules[merchant] = c } }
                            }
                            .fixedSize()
                            Spacer()
                            Button { rules[merchant] = nil } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(Theme.inkMuted).help("Forget this rule")
                        }
                    }
                }
                .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
            }
            .padding(Platform.isPhone ? 20 : 28)
        }
        .scrollIndicators(.never)
        .background(Theme.canvas)
        .sheetFrame(width: 560, height: 720)
        .onDisappear(perform: save)
    }

    private func budgetRow(_ name: String, spent: Double, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(Theme.ui(14, weight: .medium))
                Spacer()
                Text("\(Fmt.money(spent)) of").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                TextField("0", value: value, format: .number).textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing).frame(width: 80)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.canvas))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
            if value.wrappedValue > 0 {
                let p = min(1, spent / value.wrappedValue)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.canvas)
                        Capsule().fill(p >= 1 ? Theme.critical : p >= 0.8 ? Theme.orange : Theme.lime).frame(width: g.size.width * p)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private func save() {
        SpendingAlerts.budgets = budgets
        MerchantRules.all = rules
        UserDefaults.standard.set(budgetAlerts, forKey: "notify.budgets")
        UserDefaults.standard.set(bigCharges, forKey: "notify.bigCharges")
        SpendingAlerts.check(context: context)
    }
}
