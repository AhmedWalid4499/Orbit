import SwiftUI
import SwiftData

/// Every recurring charge in one place: what it costs per month and year, what renews next,
/// trials about to start charging, and price increases.
struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var state: AppState
    @Query(sort: \Subscription.name) private var subs: [Subscription]
    @State private var editing: Subscription?
    @State private var adding = false
    @State private var showCancelled = false

    private var active: [Subscription] { subs.filter { $0.status != "cancelled" }.sorted { ($0.nextDate ?? .distantFuture) < ($1.nextDate ?? .distantFuture) } }
    private var trialsEnding: [Subscription] {
        subs.filter { $0.status == "trial" && ($0.trialEnds ?? .distantFuture) < Date.now.adding(days: 14) }
    }
    private var increases: [Subscription] {
        subs.filter { $0.status != "cancelled" && $0.priceWentUp && ($0.priceChangedAt ?? .distantPast) > Date.now.adding(days: -60) }
    }

    var body: some View {
        let monthly = SubscriptionTracker.monthlyTotal(active)
        VStack(alignment: .leading, spacing: 18) {
            AdaptiveStack(grid: true) {
                tile(Fmt.money(monthly), "Per month", Theme.lime)
                tile(Fmt.money(monthly * 12), "Per year", Theme.orange)
                tile("\(active.filter { $0.status == "active" }.count)", "Active", Theme.cyan)
                tile("\(subs.filter { $0.status == "trial" }.count)", "Free trials", Theme.pink)
            }

            if !trialsEnding.isEmpty || !increases.isEmpty {
                Card(fill: Theme.blush) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Needs your attention").font(Theme.display(20))
                        ForEach(trialsEnding) { s in
                            attention("hourglass", "\(s.name) trial ends \(Fmt.relativeDay(s.trialEnds ?? .now)) — then \(Fmt.money(s.amount)) \(s.cycle.title.lowercased())", s)
                        }
                        ForEach(increases) { s in
                            attention("arrow.up.right", "\(s.name) went up from \(Fmt.money(s.previousAmount)) to \(Fmt.money(s.amount))", s)
                        }
                    }
                }
            }

            PageHeader(title: "Subscriptions") {
                Button { SubscriptionTracker.detect(context: context) } label: { Label("Find in my transactions", systemImage: "sparkle.magnifyingglass") }
                    .buttonStyle(SoftButtonStyle())
                Button { state.openAssistant(with: "Look at my subscriptions and tell me which ones I could cancel or downgrade to save money.") } label: {
                    Label { Text("Which can I cut?") } icon: { AssistantAvatar(size: 18) }
                }
                .buttonStyle(SoftButtonStyle())
                Button { adding = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
            }
            if active.isEmpty {
                EmptyHint(symbol: "repeat", text: "No subscriptions yet. Joshu finds them in your transactions and email receipts, or add one yourself.")
            }
            VStack(spacing: 8) { ForEach(active) { row($0) } }

            let cancelled = subs.filter { $0.status == "cancelled" }
            if !cancelled.isEmpty {
                DisclosureGroup("Cancelled (\(cancelled.count))", isExpanded: $showCancelled) {
                    VStack(spacing: 8) { ForEach(cancelled) { row($0) } }.padding(.top, 8)
                }
                .font(Theme.ui(13, weight: .semibold))
            }
        }
        .sheet(item: $editing) { SubscriptionEditor(sub: $0) }
        .sheet(isPresented: $adding) { SubscriptionEditor(sub: nil) }
        .task { SubscriptionTracker.detect(context: context) }
    }

    private func row(_ s: Subscription) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.status == "trial" ? "hourglass" : "repeat")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                .frame(width: 34, height: 34).background(Circle().fill(s.status == "trial" ? Theme.pink : Theme.peach))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.name).font(Theme.ui(14, weight: .semibold))
                    if s.status == "trial" { badge("Trial", Theme.pink) }
                    if s.priceWentUp { badge("Price up", Theme.orange) }
                    if s.source == "detected" || s.source == "email" { badge(s.source == "email" ? "From email" : "Found", Theme.card) }
                }
                Text([s.cycle.title, s.nextDate.map { s.status == "cancelled" ? "" : "next \(Fmt.relativeDay($0))" } ?? "",
                      s.originalCurrency.isEmpty ? "" : "\(s.originalAmount.formatted(.number.precision(.fractionLength(0...2)))) \(s.originalCurrency)"]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.money(s.amount)).font(Theme.ui(14, weight: .semibold)).strikethrough(s.status == "cancelled")
                if s.cycle != .monthly && s.status != "cancelled" {
                    Text("\(Fmt.money(s.monthlyCost))/mo").font(Theme.ui(10)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .opacity(s.status == "cancelled" ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editing = s }
        .contextMenu {
            if s.status != "cancelled" { Button("Mark as cancelled") { s.status = "cancelled" } }
            else { Button("Mark as active") { s.status = "active" } }
            Divider()
            Button("Remove (and stop detecting it)", role: .destructive) { SubscriptionTracker.remove(s, context: context) }
        }
    }

    private func attention(_ symbol: String, _ text: String, _ s: Subscription) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(Theme.orange)
            Text(text).font(Theme.ui(13))
            Spacer()
            Button("Cancelled it") { s.status = "cancelled" }.buttonStyle(.plain).font(Theme.ui(12, weight: .semibold))
            Button("Keep") { s.status = "active"; s.previousAmount = 0 }.buttonStyle(.plain).font(Theme.ui(12, weight: .semibold))
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(Theme.ui(10, weight: .semibold)).foregroundStyle(Theme.stickerInk)
            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(color))
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(Theme.ui(12, weight: .semibold)).opacity(0.8)
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(color))
    }
}

struct SubscriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let sub: Subscription?

    @State private var name = ""
    @State private var amount = ""
    @State private var cycle: BillingCycle = .monthly
    @State private var status = "active"
    @State private var hasNext = true
    @State private var next = Date.now.adding(days: 30)
    @State private var trialEnds = Date.now.adding(days: 7)
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sub == nil ? "New subscription" : sub!.name).font(Theme.display(26))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow { Text("Name").foregroundStyle(Theme.inkSecondary); TextField("Netflix", text: $name).textFieldStyle(.roundedBorder) }
                GridRow {
                    Text("Price").foregroundStyle(Theme.inkSecondary)
                    HStack {
                        TextField("0", text: $amount).textFieldStyle(.roundedBorder).frame(width: 110)
                        Text(Fmt.currencyCode).foregroundStyle(Theme.inkMuted)
                        Picker("", selection: $cycle) { ForEach(BillingCycle.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 120)
                    }
                }
                GridRow {
                    Text("Status").foregroundStyle(Theme.inkSecondary)
                    Picker("", selection: $status) { Text("Active").tag("active"); Text("Free trial").tag("trial"); Text("Cancelled").tag("cancelled") }
                        .pickerStyle(.segmented).labelsHidden()
                }
                if status == "trial" {
                    GridRow { Text("Trial ends").foregroundStyle(Theme.inkSecondary); DatePicker("", selection: $trialEnds, displayedComponents: .date).labelsHidden() }
                } else if status == "active" {
                    GridRow {
                        Text("Renews").foregroundStyle(Theme.inkSecondary)
                        HStack { Toggle("", isOn: $hasNext).labelsHidden(); if hasNext { DatePicker("", selection: $next, displayedComponents: .date).labelsHidden() } }
                    }
                }
                GridRow { Text("Notes").foregroundStyle(Theme.inkSecondary); TextField("Shared with…, cancel by…", text: $notes).textFieldStyle(.roundedBorder) }
            }
            .font(Theme.ui(13))
            HStack {
                if let sub { Button("Remove", role: .destructive) { SubscriptionTracker.remove(sub, context: context); dismiss() }.buttonStyle(SoftButtonStyle()) }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).frame(width: 110).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(26).sheetFrame(width: 480)
        .onAppear {
            guard let s = sub else { return }
            name = s.name; amount = s.amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)); cycle = s.cycle
            status = s.status; notes = s.notes
            if let n = s.nextDate { next = n } else { hasNext = false }
            if let t = s.trialEnds { trialEnds = t }
        }
    }

    private func save() {
        let s = sub ?? { let s = Subscription(name: name, amount: 0); context.insert(s); return s }()
        s.name = name.trimmingCharacters(in: .whitespaces)
        s.amount = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? s.amount
        s.cycle = cycle
        s.status = status
        s.notes = notes
        s.trialEnds = status == "trial" ? trialEnds.startOfDay : nil
        s.nextDate = status == "trial" ? trialEnds.startOfDay : (status == "active" && hasNext ? next.startOfDay : nil)
        try? context.save()
        dismiss()
    }
}
