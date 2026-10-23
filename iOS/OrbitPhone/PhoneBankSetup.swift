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
    @State private var entries: [AutoLogActivity.Entry] = []

    private var logged: [Transaction] { all.filter(\.fromBank) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Card and Apple Pay spending never reaches your inbox. Orbit's shortcuts send it here as it happens. iPhone only lets you, not apps, turn on automations, so it takes one minute in the Shortcuts app.")
                        .font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)

                    if !logged.isEmpty {
                        Label("\(logged.count) payment\(logged.count == 1 ? "" : "s") logged this way so far", systemImage: "checkmark.circle.fill")
                            .font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.good)
                    }

                    banksCard

                    guide("Bank text messages", symbol: "message.fill", color: Theme.cyan, steps: [
                        "Tap **Add to Shortcuts** below, choose **Shortcuts** in the share sheet, then **Add Shortcut**.",
                        "In Shortcuts: **Automation** tab › **+** › **Message**.",
                        "Tap **Message Contains**, type **EGP**, tap **Done**. Leave Sender empty.",
                        "Choose **Run Immediately**, tap **Next**, then tap the red **Orbit Bank Message** tile in the top row (swipe the row sideways if you don't see it). That's it.",
                    ], file: "Orbit Bank Message")
                    Text("Bank texts you in Arabic? Add a second Message automation with **جنيه** instead of EGP, running the same shortcut.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)

                    guide("Apple Pay", symbol: "wave.3.right", color: Theme.lime, steps: [
                        "Tap **Add to Shortcuts** below, choose **Shortcuts** in the share sheet, then **Add Shortcut**.",
                        "In Shortcuts: **Automation** tab › **+** › **Wallet**.",
                        "Pick your cards, choose **Run Immediately**, tap **Next**.",
                        "Tap the green **Orbit Card Payment** tile in the top row. That's it.",
                    ], file: "Orbit Card Payment")

                    Button { Platform.open(URL(string: "shortcuts://")!) } label: {
                        Label("Open Shortcuts", systemImage: "square.2.layers.3d").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    activity

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

    private func guide(_ title: String, symbol: String, color: Color, steps: [String], file: String) -> some View {
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
            if let url = Bundle.main.url(forResource: file, withExtension: "shortcut", subdirectory: "Shortcuts") {
                ShareLink(item: url) {
                    Label("Add to Shortcuts", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
    }

    /// What the automations have sent to Orbit, so it's clear whether they fire at all.
    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent activity").font(Theme.display(20))
                Spacer()
                Button { entries = AutoLogActivity.entries } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary)
            }
            Button {
                let text = "\(BankMessages.testPrefix) Your card was charged EGP 25.00 at Cafe"
                var c = URLComponents(string: "shortcuts://run-shortcut")!
                c.queryItems = [.init(name: "name", value: "Orbit Bank Message"), .init(name: "input", value: "text"), .init(name: "text", value: text)]
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "bankSMS.testStarted")
                if let url = c.url { Platform.open(url) }
            } label: {
                Label("Test the bank shortcut", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle())
            Text("Runs Orbit Bank Message with a sample text, then come back here: a “Test worked” line means Shortcuts can reach Orbit. Nothing is saved.")
                .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            if entries.isEmpty {
                Text("Nothing has reached Orbit from Shortcuts yet. Each time an automation runs, it appears here with what Orbit did with it.")
                    .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                Text("Testing? iPhone may not run Message automations for texts you send yourself. Ask someone to text you “Your card was charged EGP 25.00 at Cafe”, or wait for your next bank text.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(entries.prefix(8)) { e in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: e.kind == .sms ? "message.fill" : "wave.3.right").font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26).background(Circle().fill(e.kind == .sms ? Theme.cyan : Theme.lime)).foregroundStyle(Theme.stickerInk)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.result).font(Theme.ui(13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        Text("\(e.date.formatted(.relative(presentation: .named)))\(e.sender.isEmpty ? "" : " · from \(e.sender)")")
                            .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                        if !e.text.isEmpty {
                            Text("“\(e.text)”").font(Theme.ui(11)).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                        } else if !e.result.hasPrefix("Test worked") {
                            Text("No text was passed in. Check the shortcut's Message is set to Shortcut Input › Content.").font(Theme.ui(11)).foregroundStyle(Theme.orange)
                        }
                    }
                }
            }
        }
        .onAppear { entries = AutoLogActivity.entries }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in entries = AutoLogActivity.entries }
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
