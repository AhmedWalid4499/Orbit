import SwiftUI
import SwiftData

/// Money › Auto-log card payments: how to set up the two Shortcuts automations, and a box to try a bank message.
struct PhoneBankSetup: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var all: [Transaction]
    @State private var sample = ""
    @State private var preview: BankMessages.Parsed?
    @State private var checked = false
    @State private var busy = false
    @State private var result: String?

    private var logged: [Transaction] { all.filter(\.fromBank) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Card and Apple Pay spending never reaches your inbox. Two automations in the Shortcuts app send it to Orbit as it happens: iPhone doesn't let apps read your messages themselves, so you choose exactly which ones Orbit sees.")
                        .font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)

                    if !logged.isEmpty {
                        Label("\(logged.count) payment\(logged.count == 1 ? "" : "s") logged this way so far", systemImage: "checkmark.circle.fill")
                            .font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.good)
                    }

                    guide("Apple Pay", symbol: "wave.3.right", color: Theme.lime, steps: [
                        "Open **Shortcuts** › **Automation** › **+** › **Wallet**.",
                        "Pick your cards, choose **Run Immediately**, then **Next**.",
                        "Tap **New Blank Automation** › **Add Action**, search **Orbit** and pick **Log Card Payment**.",
                        "Tap **Amount** › **Shortcut Input**, then tap the blue Shortcut Input and choose **Amount**. Do the same for **Merchant** (Merchant) and **Card** (Card).",
                        "Tap **Done**. Every Apple Pay tap now lands in Money.",
                    ])

                    guide("Bank text messages", symbol: "message.fill", color: Theme.cyan, steps: [
                        "Open **Shortcuts** › **Automation** › **+** › **Message**.",
                        "Under **Sender**, choose your bank (save its SMS sender as a contact first), or use **Message Contains** with a word your bank always uses, like **EGP** or **debited**.",
                        "Choose **Run Immediately**, then **Next** › **New Blank Automation**.",
                        "**Add Action**, search **Orbit**, pick **Log Bank Message**.",
                        "Tap **Message** › **Shortcut Input**, then tap it and choose **Content**. Tap **Done**.",
                        "Repeat for each bank. Purchases, transfers, ATM withdrawals and money in are logged; codes, declined payments and balance updates are ignored.",
                    ])

                    Button { Platform.open(URL(string: "shortcuts://")!) } label: {
                        Label("Open Shortcuts", systemImage: "square.2.layers.3d").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    tryIt

                    Text("A Wallet tap and the bank's text for the same purchase are logged once. Wrong one? Delete it from Money like any other expense.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                }
                .padding(20)
            }
            .navigationTitle("Auto-log card payments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func guide(_ title: String, symbol: String, color: Color, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                    .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9).fill(color))
                Text(title).font(Theme.display(20))
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(Theme.ui(12, weight: .bold)).frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.canvas))
                    Text(.init(step)).font(Theme.ui(14)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try a message").font(Theme.display(20))
            Text("Paste a text from your bank to see what Orbit reads.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
            TextField("e.g. Your card ending 1234 was charged EGP 350.00 at CARREFOUR MAADI", text: $sample, axis: .vertical)
                .font(Theme.ui(14)).lineLimit(2...6)
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                .onChange(of: sample) { checked = false; preview = nil; result = nil }
            HStack {
                Button(busy ? "Reading…" : "Check") {
                    busy = true
                    Task { preview = await BankMessages.read(sample); checked = true; busy = false }
                }
                .buttonStyle(SoftButtonStyle()).disabled(busy || sample.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if let p = preview, p.kind != .notPayment, p.amount > 0, result == nil {
                    Button("Log it") {
                        Task { result = await BankMessages.log(message: sample, context: context) }
                    }
                    .buttonStyle(PrimaryButtonStyle()).fixedSize()
                }
            }
            if checked {
                if let p = preview, p.kind != .notPayment, p.amount > 0 {
                    let what = p.kind == .expense ? "Spent" : p.kind == .refund ? "Refund" : "Money in"
                    let currency = p.currency.isEmpty ? Fmt.currencyCode : p.currency
                    Label("\(what): \(p.amount.formatted(.number.precision(.fractionLength(0...2)))) \(currency)\(p.merchant.isEmpty ? "" : " · \(p.merchant)") · \(p.category)",
                          systemImage: "checkmark.circle.fill")
                        .font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.good)
                } else {
                    Label("Not a payment, so it would be ignored.", systemImage: "minus.circle").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                }
            }
            if let result { Text(result).font(Theme.ui(13, weight: .medium)) }
        }
    }
}
