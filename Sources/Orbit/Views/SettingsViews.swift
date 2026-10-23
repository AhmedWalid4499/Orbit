import SwiftUI
import AVFoundation
import SwiftData

// MARK: - Settings

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ConnectionsSettings()
                .tabItem { Label("Connections", systemImage: "link") }
            AISettings()
                .tabItem { Label("AI", systemImage: "sparkles") }
            AccountSettings()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 640)
    }
}

/// Name, budget, currency, weather city; delete everything.
struct GeneralSettings: View {
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = Platform.fullUserName
    @AppStorage("monthlyBudget") private var monthlyBudget = 2000.0
    @AppStorage("currencyCode") private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var confirmClear = false

    var body: some View {
    Form {
        TextField("Your name", text: $userName)
        TextField("Monthly budget", value: $monthlyBudget, format: .number)
        Picker("Currency", selection: $currency) {
            ForEach(["USD", "EUR", "GBP", "EGP", "AED", "SAR", "JPY", "CAD", "AUD", "INR"], id: \.self) { Text($0) }
        }
        TextField("Weather city", text: Binding(get: { UserDefaults.standard.string(forKey: "weatherCity") ?? "" },
                                                set: { UserDefaults.standard.set($0, forKey: "weatherCity"); Task { await WeatherStore.shared.refresh() } }),
                  prompt: Text(WeatherStore.defaultCity))
        #if os(macOS)
        Section("Updates") { UpdatePanel() }
        LabeledContent("Quick capture", value: "⌥Space (anywhere)")
        LabeledContent("Search", value: "⌘K")
        #endif
        Section {
            Button("Delete all data…", role: .destructive) { confirmClear = true }
        }
    }
        .confirmationDialog("Delete everything in Orbit?", isPresented: $confirmClear) {
            Button("Delete all data", role: .destructive) { DataReset.clearAll(context) }
        } message: {
            Text("Tasks, events, habits, transactions, notes, books and bucket list stored in Orbit will be removed, including from your Orbit account if you're signed in. Apple Calendar and Reminders are not touched.")
        }
    }
}

/// Apple Calendar and Reminders, Google, GitHub, reading sources.
struct ConnectionsSettings: View {
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var gh = GitHubStore.shared
    @State private var readingSources = false

    var body: some View {
    Form {
        Section("Built in — works now") {
            ConnectionRow(name: "Apple Calendar",
                          detail: "Shows every calendar on this \(Platform.isPhone ? "iPhone" : "Mac") — iCloud, Google, Outlook, Exchange.",
                          symbol: "calendar", connected: apple.calendarEnabled && apple.calendarAccess == .granted,
                          denied: apple.calendarAccess == .denied,
                          connect: { Task { await apple.connectCalendar() } },
                          disconnect: apple.disconnectCalendar)
            ConnectionRow(name: "Apple Reminders",
                          detail: "Shows open reminders next to your tasks and completes them both ways.",
                          symbol: "checklist", connected: apple.remindersEnabled && apple.remindersAccess == .granted,
                          denied: apple.remindersAccess == .denied,
                          connect: { Task { await apple.connectReminders() } },
                          disconnect: apple.disconnectReminders)
        }
        Section("Google: Gmail and Calendar") { GmailSettings() }
        Section("GitHub") {
            if gh.isConnected {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(gh.username)").font(.headline)
                        Text(gh.hasToken ? "Token saved — private repos and contributions included." : "Public data only. Add a token on the GitHub tab for private repos.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disconnect") { gh.disconnect() }
                }
            } else {
                GitHubConnectCard()
            }
        }
        Section("Reading") {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical").frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goodreads, Apple Books, Kindle").font(.headline)
                    Text("Sync your shelves and import your libraries.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Connect & import…") { readingSources = true }
            }
        }
        Section("Coming next — need something from you") {
            PlannedRow(name: "Bank accounts", detail: "Automatic bank sync is coming. For now, use Money › Import statement with your bank’s CSV or PDF.", symbol: "building.columns")
            PlannedRow(name: "Apple Health", detail: "Sleep, steps, workouts. Needs an iPhone companion app.", symbol: "heart")
        }
    }
        .sheet(isPresented: $readingSources) { ReadingSourcesSheet() }
    }
}

struct ConnectionRow: View {
    let name: String
    let detail: String
    let symbol: String
    let connected: Bool
    let denied: Bool
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(denied ? "Access denied — allow Orbit in System Settings › Privacy & Security." : detail)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if connected {
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good).font(.caption)
                Button("Disconnect", action: disconnect)
            } else if denied {
                Button("Open Settings") {
                    Platform.open(URL(string: Platform.isPhone ? "app-settings:" : "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            } else {
                Button("Connect", action: connect).buttonStyle(.borderedProminent)
            }
        }
    }
}

struct PlannedRow: View {
    let name: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Planned").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AISettings: View {
    @ObservedObject private var ai = AIAssistant.shared
    @State private var keyField = ""
    @State private var status: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                if ai.hasKey {
                    LabeledContent("Anthropic API key") {
                        Label("Saved in Keychain", systemImage: "lock.fill").foregroundStyle(Theme.good)
                    }
                    HStack {
                        Button(testing ? "Testing…" : "Test connection") {
                            testing = true
                            Task { status = await ai.testConnection(); testing = false }
                        }
                        .disabled(testing)
                        Spacer()
                        Button("Remove key", role: .destructive) { ai.removeKey(); status = nil }
                    }
                } else {
                    SecureField("Anthropic API key", text: $keyField, prompt: Text("sk-ant-…"))
                    HStack {
                        Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                            .font(.caption)
                        Spacer()
                        Button("Save") {
                            status = ai.setKey(keyField) ? nil : "Couldn't save to Keychain."
                            keyField = ""
                            if ai.hasKey {
                                testing = true
                                Task { status = await ai.testConnection(); testing = false }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Claude")
            } footer: {
                Text("Uses \(ClaudeClient.model). The key is stored in your \(Platform.isPhone ? "iPhone's" : "Mac's") Keychain, never in a file.")
            }

            Section("Your assistant") {
                TextField("Name", text: Binding(get: { UserDefaults.standard.string(forKey: "assistantName") ?? "Ask" },
                                                set: { UserDefaults.standard.set($0, forKey: "assistantName") }))
                Text("What you call your AI around Orbit: the top-bar button, the journal and the morning brief. It's “Ask” unless you rename it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VoiceSection()
            Section("Features") {
                Toggle(isOn: $ai.smartCaptureEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart capture")
                        Text("\(Platform.isPhone ? "Quick add" : "⌥Space") text is sorted by \(AssistantName.current), and one line can hold several items. Falls back to the offline parser if the API is unreachable.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $ai.morningBriefEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Morning brief")
                        Text("Once a day on the Today screen. Refresh any time.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Privacy") {
                Text("When these are on, Orbit sends Anthropic what it needs: the text you capture, and for the brief today's events, tasks, habits, this month's spending total and yesterday's journal entry. Nothing is sent while no key is saved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct GmailSettings: View {
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var google = GoogleCalendarStore.shared
    @State private var clientID = GoogleAuth.clientID
    @State private var clientSecret = ""
    @State private var showSetup = !GoogleAuth.isConfigured

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(inbox.accounts, id: \.self) { email in
                HStack {
                    Image(systemName: "envelope.fill").frame(width: 28)
                    Text(email).font(.headline)
                    Label("Connected", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.good)
                    Spacer()
                    Button("Remove") { inbox.remove(email) }
                }
            }
            if GoogleAuth.isConfigured {
                HStack {
                    Button(inbox.signingIn ? "Waiting for Google…" : "Add Gmail account…") { Task { await inbox.addAccount() } }
                        .buttonStyle(.borderedProminent).disabled(inbox.signingIn)
                    Spacer()
                    Button(showSetup ? "Hide setup" : "Google client settings") { showSetup.toggle() }
                }
                Text("Sign in once per account in your browser. Orbit keeps a read-only token in your Keychain and won't ask again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = inbox.error { Text(error).font(.caption).foregroundStyle(Theme.critical) }

            if showSetup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("One-time setup (about 5 minutes)").font(.subheadline.weight(.semibold))
                    Text("""
                    1. Open console.cloud.google.com and create a project (e.g. "Orbit").
                    2. APIs & Services › Library › enable "Gmail API".
                    3. OAuth consent screen: User type External, app name Orbit, your email as support contact. Add the scope gmail.readonly. Add both of your Gmail addresses as test users.
                    4. Then click "Publish app" (In production). For your own use, verification isn't needed: Google shows an "unverified app" screen you can continue past. This stops Google from expiring the sign-in every 7 days.
                    5. Credentials › Create credentials › OAuth client ID › Application type "Desktop app".
                    6. Paste the client ID and client secret here.
                    """).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Link("Open Google Cloud Console", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!).font(.caption)
                    TextField("Client ID", text: $clientID)
                    SecureField(GoogleAuth.isConfigured ? "Client secret (saved)" : "Client secret", text: $clientSecret)
                    HStack {
                        Spacer()
                        Button("Save") {
                            GoogleAuth.clientID = clientID
                            if !clientSecret.isEmpty { GoogleAuth.clientSecret = clientSecret }
                            clientSecret = ""
                            showSetup = !GoogleAuth.isConfigured
                        }
                        .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || (clientSecret.isEmpty && !GoogleAuth.isConfigured))
                    }
                }
                .padding(.top, 4)
            }
            Toggle("Show Google Calendar events", isOn: Binding(
                get: { GoogleCalendarStore.shared.enabled },
                set: { GoogleCalendarStore.shared.enabled = $0; Task { await GoogleCalendarStore.shared.refresh() } }))
                .font(.callout)
            if !GoogleCalendarStore.shared.needsConsent.isEmpty {
                ForEach(GoogleCalendarStore.shared.needsConsent.sorted(), id: \.self) { acct in
                    HStack {
                        Text("\(acct) needs to allow Calendar once.").font(.caption)
                        Spacer()
                        Button("Allow Calendar") { Task { await GoogleCalendarStore.shared.reconnect(acct) } }
                    }
                }
            }
            if GoogleCalendarStore.shared.apiDisabled {
                HStack {
                    Text("Turn on the Google Calendar API in your Google Cloud project.").font(.caption)
                    Spacer()
                    Button("Enable") { Platform.open(GoogleCalendarStore.enableAPIURL) }
                }
            }
            if !GoogleAuth.usingBuiltIn && GoogleAuth.isConfigured {
                Toggle("Build my Google setup into copies of Orbit I share", isOn: Binding(
                    get: { GoogleAuth.isShared }, set: { GoogleAuth.setShared($0) }))
                    .font(.callout)
                Text("People you give Orbit to can then just click “Add Gmail account”, with no Google Cloud setup. They'll see Google's “unverified app” notice, and Google allows up to 100 people.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if GoogleAuth.usingBuiltIn {
                Text("Using the Google connection built into this copy of Orbit.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Add payments and receipts from email to Money", isOn: Binding(
                get: { EmailExpenses.shared.enabled }, set: { EmailExpenses.shared.enabled = $0 }))
                .font(.callout)
            Text("Inbox summaries send the sender, subject and a short preview of the last two days of mail (no promotions or social) to Anthropic. Expense import also sends the text of emails that look like receipts or payments.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Account & sync

struct AccountSettings: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSync.shared
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @State private var working = false
    @State private var message: String?

    var body: some View {
        Form {
            if !SupabaseConfig.isConfigured {
                Section { Text("Sync isn't set up in this copy of Orbit yet.").foregroundStyle(.secondary) }
            } else if let signedIn = cloud.email {
                Section("Orbit account") {
                    LabeledContent("Signed in as", value: signedIn)
                    HStack {
                        if cloud.syncing { ProgressView().controlSize(.small) }
                        Text(cloud.status ?? "Not synced yet").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Sync Now") { Task { await cloud.sync(context: context) } }.disabled(cloud.syncing)
                    }
                    if let last = cloud.lastSync {
                        Text("Last synced \(last.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Sign Out", role: .destructive) { cloud.signOut() }
                }
                KeySyncSection()
                Section {
                    Text("Your tasks, calendar events you made in Orbit, habits, money, notes and journal, books and bucket list sync to your account every couple of minutes. Sign in with the same account on another device to get everything there.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Button { google() } label: {
                        HStack {
                            Image(systemName: "g.circle.fill").font(.title2)
                            Text("Continue with Google").fontWeight(.semibold)
                            Spacer()
                            if working { ProgressView().controlSize(.small) }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(working)
                    Text("Use the same Google account on your Mac, your Windows PC and anywhere else Orbit runs, and you're always in the same Orbit account.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(creating ? "Or create an account with email" : "Or sign in with email") {
                    TextField("Email", text: $email).textContentType(.username)
                    SecureField("Password", text: $password).textContentType(creating ? .newPassword : .password)
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button(creating ? "I already have an account" : "Create an account") { creating.toggle(); message = nil }
                            .buttonStyle(.orbitLink)
                        Spacer()
                        if working { ProgressView().controlSize(.small) }
                        Button(creating ? "Create Account" : "Sign In", action: submit)
                            .buttonStyle(.borderedProminent)
                            .disabled(working || !email.contains("@") || password.count < 6)
                            .keyboardShortcut(.defaultAction)
                    }
                    if !creating {
                        Button("Forgot password?") {
                            Task {
                                do { try await CloudAuth.resetPassword(email: email); message = "Check \(email) for a link to reset your password." }
                                catch { message = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.orbitLink).font(.caption).disabled(!email.contains("@"))
                    }
                }
                Section {
                    Text("An Orbit account keeps your data in sync between your Macs and backs it up online. Each person only ever sees their own data. Passwords need at least 6 characters.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func google() {
        working = true
        message = nil
        Task {
            defer { working = false }
            do { try await cloud.signInWithGoogle(context: context) }
            catch is CancellationError {}
            catch { message = error.localizedDescription }
        }
    }

    private func submit() {
        working = true
        message = nil
        let e = email.trimmingCharacters(in: .whitespaces)
        Task {
            defer { working = false }
            do {
                if creating {
                    switch try await cloud.signUp(email: e, password: password, context: context) {
                    case .signedIn: password = ""
                    case .checkEmail:
                        message = "Almost done: open the email Supabase sent to \(e), confirm it, then come back and sign in."
                        creating = false
                    }
                } else {
                    try await cloud.signIn(email: e, password: password, context: context)
                    password = ""
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// Sync API keys and connections between devices, end-to-end encrypted with a passphrase.
struct KeySyncSection: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var cloud = CloudSync.shared

    var body: some View {
        Section("API keys and connections") {
            Toggle("Bring them to my other devices", isOn: Binding(
                get: { cloud.syncSecrets },
                set: { on in if on { cloud.syncSecrets = true; Task { await cloud.sync(context: context) } } else { cloud.turnOffKeySync() } }))
            if cloud.syncSecrets {
                switch cloud.vaultState {
                case .on:
                    Label("Synced with your Orbit account", systemImage: "lock.shield.fill").foregroundStyle(Theme.good)
                case .waiting:
                    Label("Open Orbit on your Mac once to bring your keys here.", systemImage: "hourglass").font(.caption)
                case .error(let e):
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange).font(.caption)
                case .off:
                    Text("Sign in to sync them.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Your Anthropic key, GitHub token, Google sign-ins for Gmail and Calendar, and their settings arrive on every device you sign in to, with nothing to type. They're stored encrypted in your account.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Settings › AI › Voice: which voice reads replies aloud, with a preview.
struct VoiceSection: View {
    @AppStorage("assistantSpeaks") private var speaks = false
    @AppStorage("assistantVoice") private var voiceID = ""
    @ObservedObject private var speaker = Speaker.shared

    private var voices: [AVSpeechSynthesisVoice] {
        Speaker.naturalVoices(language: Locale.current.language.languageCode?.identifier ?? "en")
    }
    private var hasPremium: Bool { voices.contains { $0.quality == .premium } }

    var body: some View {
        Section {
            Toggle("Read replies aloud", isOn: $speaks)
            Picker("Voice", selection: $voiceID) {
                Text("Most natural (\(Speaker.bestVoice(for: "Hi")?.name ?? "default"))").tag("")
                ForEach(voices, id: \.identifier) { v in
                    Text("\(v.name)\(v.quality == .premium ? " · Premium" : v.quality == .enhanced ? " · Enhanced" : "") (\(v.language))").tag(v.identifier)
                }
            }
            Button(speaker.speaking ? "Stop" : "Preview") {
                if speaker.speaking { speaker.stop() }
                else { speaker.speak("Hey! I had a look at your day. You've got two things this afternoon, so maybe grab lunch early? Let me know if you want me to move anything.") }
            }
        } header: {
            Text("Voice")
        } footer: {
            Text(hasPremium
                 ? "Premium voices sound the most like a person."
                 : "For a much more human voice, download a Premium one (free): \(Platform.isPhone ? "Settings › Accessibility › Spoken Content › Voices › English" : "System Settings › Accessibility › Spoken Content › System voice › Manage Voices"), then pick e.g. Zoe, Ava or Evan (Premium). It shows up here.")
        }
    }
}
