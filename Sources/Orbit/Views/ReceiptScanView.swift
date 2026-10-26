import SwiftUI
import SwiftData

/// A picked or photographed receipt, for `.sheet(item:)`.
struct ReceiptPhoto: Identifiable {
    let id = UUID()
    let image: PlatformImage
}

/// Shows the receipt, reads it, and lets you check the shop, total, category and date before adding the expense.
struct ReceiptScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let photo: ReceiptPhoto

    @State private var reading = true
    @State private var error: String?
    @State private var merchant = ""
    @State private var amount = ""
    @State private var currency = ""
    @State private var category = "General"
    @State private var suggested = "General"
    @State private var date = Date.now
    @State private var items: [String] = []
    @State private var usedAI = false
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Receipt").font(Theme.display(28))
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                }
                photo.image.swiftUI.resizable().scaledToFit()
                    .frame(maxHeight: Platform.isPhone ? 260 : 300)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: .infinity)
                if reading {
                    HStack(spacing: 10) { ProgressView(); Text("Reading the receipt…").font(Theme.ui(14)) }
                } else {
                    if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(13)).foregroundStyle(Theme.orange) }
                    form
                }
            }
            .padding(Platform.isPhone ? 20 : 28)
        }
        .scrollIndicators(.never)
        .background(Theme.canvas)
        .sheetFrame(width: 480, height: 720)
        .task { await read() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Shop") { TextField("Shop", text: $merchant).textFieldStyle(.plain).multilineTextAlignment(.trailing) }
            field("Total") {
                HStack(spacing: 6) {
                    TextField("0.00", text: $amount).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(currency.isEmpty ? Fmt.currencyCode : currency).foregroundStyle(Theme.inkSecondary)
                }
            }
            field("Category") {
                Picker("", selection: $category) { ForEach(MoneyCategory.all.filter { $0 != "Income" }, id: \.self) { Text($0) } }.labelsHidden()
            }
            field("Date") { DatePicker("", selection: $date, displayedComponents: .date).labelsHidden() }
            if !items.isEmpty {
                Text(items.joined(separator: " · ")).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
            }
            if !usedAI {
                Text(ClaudeClient() == nil ? "Read on this device. Joshu Pro reads crumpled or Arabic receipts better."
                                           : "Read on this device. Check the total before adding.")
                    .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
            }
            if currency != "" && currency != Fmt.currencyCode {
                Text("Converted to \(Fmt.currencyCode) at today's rate when you add it.").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
            }
            Button(action: save) {
                Label(saving ? "Adding…" : "Add expense", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(saving || value == nil || merchant.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var value: Double? {
        Double(amount.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }).flatMap { $0 > 0 ? $0 : nil }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary)
            Spacer()
            content().font(Theme.ui(15, weight: .medium))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }

    private func read() async {
        do {
            let r = try await ReceiptScanner.read(photo.image)
            merchant = r.merchant
            amount = r.total > 0 ? r.total.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) : ""
            currency = r.currency
            category = r.category; suggested = r.category
            if let d = r.date { date = d }
            items = r.items
            usedAI = r.usedAI
            if r.total <= 0 { error = "Couldn't find the total. Type it in." }
        } catch {
            self.error = error.localizedDescription
        }
        reading = false
    }

    private func save() {
        guard let v = value else { return }
        saving = true
        Task {
            let code = currency.isEmpty ? Fmt.currencyCode : currency
            let converted = await Currency.convert(v, from: code, to: Fmt.currencyCode)
            let name = merchant.trimmingCharacters(in: .whitespaces)
            let t = Transaction(title: converted == nil && code != Fmt.currencyCode ? "\(name) (\(code))" : name,
                                amount: -(converted ?? v), category: category, date: date.startOfDay.adding(minutes: 12 * 60))
            t.source = "receipt"
            if code != Fmt.currencyCode { t.originalAmount = v; t.originalCurrency = code }
            context.insert(t)
            if category != suggested { MerchantRules.learn(t, category: category, context: context) }
            t.category = category
            try? context.save()
            SpendingAlerts.check(context: context)
            dismiss()
        }
    }
}
