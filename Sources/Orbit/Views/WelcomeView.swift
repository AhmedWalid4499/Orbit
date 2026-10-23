import SwiftUI

/// First launch on a new Mac: a few quick settings so Orbit feels like yours.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var ai = AIAssistant.shared

    @AppStorage("userName") private var userName = NSFullUserName()
    @AppStorage("assistantName") private var assistantName = "Ask"
    @AppStorage("currencyCode") private var currency = Locale.current.currency?.identifier ?? "USD"
    @AppStorage("weatherCity") private var city = ""
    @AppStorage("onboarded") private var onboarded = false
    @State private var apiKey = ""
    @ObservedObject private var cloud = CloudSync.shared
    @AppStorage("hiddenTabs") private var hiddenRaw = ""
    private var hiddenSet: Set<Tab> { Set(hiddenRaw.split(separator: ",").compactMap { Tab(rawValue: String($0)) }) }
    @State private var accountStep = SupabaseConfig.isConfigured && CloudSync.shared.email == nil

    var body: some View {
        if accountStep { accountPage } else { settingsPage }
    }

    /// Step 1: sign in or create an account (skippable).
    private var accountPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                OrbitMark(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Orbit").font(Theme.display(30))
                    Text("Create an account to keep everything in sync and backed up.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                }
            }
            AuthPanel()
            HStack {
                Spacer()
                Button("Skip for now") { withAnimation { accountStep = false } }.buttonStyle(.orbitLink).font(Theme.ui(13))
            }
        }
        .padding(30)
        .sheetFrame(width: 480)
        .interactiveDismissDisabled()
        .onChange(of: cloud.email) { _, e in if e != nil { withAnimation { accountStep = false } } }
    }

    /// Step 2: a few quick settings.
    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                OrbitMark(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Orbit").font(Theme.display(30))
                    Text("Your day, plans, money, reading and dreams in one place.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Your name").foregroundStyle(Theme.inkSecondary)
                    TextField("Name", text: $userName).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Call your AI").foregroundStyle(Theme.inkSecondary)
                    TextField("Ask", text: $assistantName).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Currency").foregroundStyle(Theme.inkSecondary)
                    Picker("", selection: $currency) {
                        ForEach(["USD", "EUR", "GBP", "EGP", "AED", "SAR", "KWD", "QAR", "JPY", "CAD", "AUD", "INR"], id: \.self) { Text($0) }
                    }
                    .labelsHidden().frame(width: 120)
                }
                GridRow {
                    Text("Weather city").foregroundStyle(Theme.inkSecondary)
                    TextField(WeatherStore.defaultCity, text: $city).textFieldStyle(.roundedBorder)
                }
            }
            .font(Theme.ui(13))

            VStack(alignment: .leading, spacing: 10) {
                Text("Connect (you can do this later in Settings)").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                row("calendar", "Apple Calendar & Reminders", done: apple.calendarEnabled) {
                    Task { await apple.connectCalendar(); await apple.connectReminders() }
                }
                if GoogleAuth.isConfigured {
                    row("envelope.fill", inbox.accounts.isEmpty ? "Gmail & Google Calendar" : "Google: \(inbox.accounts.joined(separator: ", "))",
                        done: !inbox.accounts.isEmpty) {
                        Task { await inbox.addAccount() }
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").frame(width: 24)
                    if ai.hasKey {
                        Text("\(assistantName.isEmpty ? "Ask" : assistantName) is ready").font(Theme.ui(13, weight: .medium))
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                    } else {
                        SecureField("Anthropic API key for \(assistantName.isEmpty ? "Ask" : assistantName) (optional)", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Link("Get a key", destination: URL(string: "https://console.anthropic.com/settings/keys")!).font(Theme.ui(12))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What will you use? (change it any time in Settings › General)").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                FlowLayout(spacing: 6) {
                    ForEach(Tab.allCases.filter(\.canHide)) { t in
                        let on = !hiddenSet.contains(t)
                        Label(t == .reading ? "Reading" : t.title, systemImage: t.symbol).font(Theme.ui(12, weight: .medium))
                            .foregroundStyle(on ? Theme.onInverse : Theme.inkSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(on ? Theme.inverse : Theme.card))
                            .onTapGesture {
                                var h = Tab.hidden
                                if on { h.insert(t) } else { h.remove(t) }
                                Tab.hidden = h
                                hiddenRaw = UserDefaults.standard.string(forKey: "hiddenTabs") ?? ""
                            }
                    }
                }
            }

            HStack {
                if let e = cloud.email {
                    Label("Signed in as \(e)", systemImage: "checkmark.circle.fill").font(Theme.ui(11)).foregroundStyle(Theme.good)
                } else if SupabaseConfig.isConfigured {
                    Button("Sign in or create an account") { withAnimation { accountStep = true } }.buttonStyle(.orbitLink).font(Theme.ui(12))
                }
                Spacer()
                Button("Get started") {
                    if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty { _ = ai.setKey(apiKey) }
                    onboarded = true
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle()).frame(width: 160)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .sheetFrame(width: 560)
        .interactiveDismissDisabled()
    }

    private func row(_ symbol: String, _ title: String, done: Bool, connect: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 24)
            Text(title).font(Theme.ui(13, weight: .medium)).lineLimit(1)
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            } else {
                Button("Connect", action: connect)
            }
        }
    }
}
