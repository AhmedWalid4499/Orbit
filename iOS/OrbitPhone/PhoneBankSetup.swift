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
    @State private var chosen = EgyptBanks.chosen
    @State private var extra = EgyptBanks.extraSenders
    @State private var ignored = EgyptBanks.lastIgnored
    @State private var picking = false

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

                    banksCard

                    guide("Bank text messages", symbol: "message.fill", color: Theme.cyan, steps: [
                        "Open **Shortcuts** › **Automation** › **+** › **Message**.",
                        "Tap **Message Contains**, type **EGP**, and leave **Sender** empty. Choose **Run Immediately**, then **Next**.",
                        "Tap **New Blank Automation** › **Add Action**, search **Orbit** and pick **Log Bank Message**.",
                        "Tap **Message** › **Shortcut Input**, then tap it and choose **Content**. Tap **Sender** › **Shortcut Input**, then choose **Sender**.",
                        "Tap **Done**. Orbit keeps texts from the banks you picked above and ignores the rest. Codes, declined payments and balance updates are always ignored.",
                    ])
                    Text("Bank texts you in Arabic? Make the same automation once more with **جنيه** instead of EGP.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)

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

    /// Step one for bank texts: which banks are yours.
    private var banksCard: some View {
        let names = EgyptBanks.all.filter { chosen.contains($0.id) }.map(\.name) + extra
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "building.columns.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                    .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9).fill(Theme.peach))
                Text("Your banks").font(Theme.display(20))
                Spacer()
                Button(names.isEmpty ? "Choose" : "Edit") { picking = true }.buttonStyle(SoftButtonStyle())
            }
            if names.isEmpty {
                Text("Pick the banks and wallets that text you, so Orbit only reads their messages.")
                    .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(names, id: \.self) { n in
                        Text(n).font(Theme.ui(12, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Theme.canvas))
                    }
                }
            }
            if let ignored {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Skipped a payment text from **\(ignored.sender)**: “\(ignored.text)”").font(Theme.ui(12))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("That's my bank, log its texts") {
                        EgyptBanks.addSender(ignored.sender)
                        extra = EgyptBanks.extraSenders
                        self.ignored = nil
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.blush))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        .sheet(isPresented: $picking) { BankPicker(chosen: $chosen, extra: $extra) }
        .onChange(of: chosen) { _, v in EgyptBanks.chosen = v }
        .onChange(of: extra) { _, v in EgyptBanks.extraSenders = v }
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

/// Pick your banks and wallets; their usual text senders come with them.
private struct BankPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var chosen: Set<String>
    @Binding var extra: [String]
    @State private var query = ""
    @State private var newSender = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(EgyptBanks.all.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { bank in
                        Button {
                            if chosen.contains(bank.id) { chosen.remove(bank.id) } else { chosen.insert(bank.id) }
                        } label: {
                            HStack {
                                Text(bank.name).foregroundStyle(Theme.ink)
                                Spacer()
                                if chosen.contains(bank.id) { Image(systemName: "checkmark").foregroundStyle(Theme.good).fontWeight(.semibold) }
                            }
                        }
                    }
                }
                Section {
                    ForEach(extra, id: \.self) { Text($0) }.onDelete { extra.remove(atOffsets: $0) }
                    HStack {
                        TextField("Sender name, e.g. CIB", text: $newSender).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Add") {
                            let s = newSender.trimmingCharacters(in: .whitespaces)
                            if !s.isEmpty, !extra.contains(s) { extra.append(s) }
                            newSender = ""
                        }
                        .disabled(newSender.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Other senders")
                } footer: {
                    Text("If your bank's texts arrive under a different name, add it exactly as it appears in Messages.")
                }
            }
            .searchable(text: $query, prompt: "Search banks")
            .navigationTitle("Your banks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
