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
    @AppStorage(Income.salaryKey) private var salary = 0.0
    @AppStorage(Income.paydayKey) private var payday = 0
    @AppStorage("currencyCode") private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var confirmClear = false

    @EnvironmentObject private var state: AppState

    @State private var placeEditing: SavedPlaceKey?
    @State private var placesVersion = 0

    var body: some View {
    Form {
        TextField("Your name", text: $userName)
        TextField("Monthly budget", value: $monthlyBudget, format: .number)
        TextField("Monthly salary (after tax)", value: $salary, format: .number)
        Picker("Payday", selection: $payday) {
            Text("Not set").tag(0)
            ForEach(1...31, id: \.self) { Text("The \(Income.ordinal($0))").tag($0) }
        }
        .onChange(of: payday) { _, _ in Income.startBudgetOnPayday() }
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
        SavedPlacesSection(editing: $placeEditing, refresh: placesVersion)
        TabsSection(phoneTabs: Platform.isPhone ? [.calendar, .tasks, .money] : [])
        Section {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(Theme.lime))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tour").font(Theme.ui(14, weight: .medium))
                    Text("A quick look at what Joshu can do.").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Button("Take the tour") {
                    // On iPhone, Settings is a sheet: close it first so the tour can cover the screen.
                    state.settingsOpen = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + (Platform.isPhone ? 0.5 : 0)) { state.tourOpen = true }
                }
                .buttonStyle(SoftButtonStyle()).fixedSize()
            }
        }
        Section {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(Theme.critical))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete all data").font(Theme.ui(14, weight: .medium))
                    Text("Removes everything in Joshu, here and in your account.").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Button("Delete…", role: .destructive) { confirmClear = true }
                    .buttonStyle(SoftButtonStyle()).foregroundStyle(Theme.critical).fixedSize()
            }
        }
    }
        .savedPlaceSearch($placeEditing) { placesVersion += 1 }
        .confirmationDialog("Delete everything in Joshu?", isPresented: $confirmClear) {
            Button("Delete all data", role: .destructive) { DataReset.clearAll(context) }
        } message: {
            Text("Tasks, events, habits, transactions, notes, books and bucket list stored in Joshu will be removed, including from your Joshu account if you're signed in. Apple Calendar and Reminders are not touched.")
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
                          symbol: "calendar", brand: .appleCalendar, connected: apple.calendarEnabled && apple.calendarAccess == .granted,
                          denied: apple.calendarAccess == .denied,
                          connect: { Task { await apple.connectCalendar() } },
                          disconnect: apple.disconnectCalendar)
            ConnectionRow(name: "Apple Reminders",
                          detail: "Shows open reminders next to your tasks and completes them both ways.",
                          symbol: "checklist", brand: .appleReminders, connected: apple.remindersEnabled && apple.remindersAccess == .granted,
                          denied: apple.remindersAccess == .denied,
                          connect: { Task { await apple.connectReminders() } },
                          disconnect: apple.disconnectReminders)
        }
        Section {
            GmailSettings()
        } header: {
            HStack(spacing: 6) { BrandLogo(brand: .gmail, size: 14, style: .glyph); BrandLogo(brand: .googleCalendar, size: 14, style: .glyph); Text("Google: Gmail and Calendar") }
        }
        Section {
            if gh.isConnected {
                HStack(spacing: 12) {
                    BrandLogo(brand: .github, size: 28)
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
        } header: {
            HStack(spacing: 6) { BrandLogo(brand: .github, size: 14, style: .glyph); Text("GitHub") }
        }
        Section("Reading") {
            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    BrandLogo(brand: .goodreads, size: 24); BrandLogo(brand: .appleBooks, size: 24); BrandLogo(brand: .kindle, size: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goodreads, Apple Books, Kindle").font(.headline)
                    Text("Sync your shelves and import your libraries.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Connect & import…") { readingSources = true }
            }
        }
        OtherConnections()
        Section("Coming next — need something from you") {
            PlannedRow(name: "Bank accounts", detail: "Each bank and card gets its own page in Money, filled from bank texts, Apple Pay and statements. Live bank links aren't available for Egyptian banks yet.", symbol: "building.columns")
        }
    }
        .sheet(isPresented: $readingSources) { ReadingSourcesSheet() }
    }
}

struct ConnectionRow: View {
    let name: String
    let detail: String
    let symbol: String
    var brand: Brand? = nil
    let connected: Bool
    let denied: Bool
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let brand { BrandLogo(brand: brand, size: 28) } else { Image(systemName: symbol).frame(width: 28) }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(denied ? "Access denied — allow Joshu in System Settings › Privacy & Security." : detail)
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
            Section { ProSettingsRow() }
            #if os(macOS)
            Section {
                if Keychain.apiKey != nil {
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
                Text("Your own Anthropic key (advanced)")
            } footer: {
                Text("Optional: use your own key instead of Joshu's AI. Uses \(ClaudeClient.model); the key stays in your Mac's Keychain, never in a file.")
            }
            #endif

            Section("Your assistant") {
                TextField("Name", text: Binding(get: { UserDefaults.standard.string(forKey: "assistantName") ?? "Joshu" },
                                                set: { UserDefaults.standard.set($0, forKey: "assistantName") }))
                Text("What you call your AI around Joshu: the top-bar button, the journal and the morning brief. It's “Ask” unless you rename it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            MemorySection()
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
                Text("When these are on, Joshu sends Anthropic what it needs: the text you capture, and for the brief today's events, tasks, habits, this month's spending total and yesterday's journal entry. Nothing is sent while no key is saved.")
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
                    BrandLogo(brand: .gmail, size: 28)
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
                Text("Sign in once per account in your browser. Joshu keeps a read-only token in your Keychain and won't ask again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = inbox.error { Text(error).font(.caption).foregroundStyle(Theme.critical) }
            InboxWindowControls()

            if showSetup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("One-time setup (about 5 minutes)").font(.subheadline.weight(.semibold))
                    Text("""
                    1. Open console.cloud.google.com and create a project (e.g. "Joshu").
                    2. APIs & Services › Library › enable "Gmail API".
                    3. OAuth consent screen: User type External, app name Joshu, your email as support contact. Add the scope gmail.readonly. Add both of your Gmail addresses as test users.
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
                Toggle("Build my Google setup into copies of Joshu I share", isOn: Binding(
                    get: { GoogleAuth.isShared }, set: { GoogleAuth.setShared($0) }))
                    .font(.callout)
                Text("People you give Joshu to can then just click “Add Gmail account”, with no Google Cloud setup. They'll see Google's “unverified app” notice, and Google allows up to 100 people.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if GoogleAuth.usingBuiltIn {
                Text("Using the Google connection built into this copy of Joshu.").font(.caption).foregroundStyle(.secondary)
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
    @State private var confirmDelete = false
    @State private var deleteError: String?
    @State private var confirmSignOut = false
    @State private var signingOut = false

    private func signOut(keep: Bool) {
        signingOut = true
        deleteError = nil
        Task {
            do {
                try await cloud.signOut(context: context, keepOnDevice: keep)
                // Settings closes and the welcome page is what's left.
                #if os(macOS)
                NSApp.keyWindow?.close()
                #else
                AppState.current?.settingsOpen = false
                #endif
            } catch { deleteError = error.localizedDescription }
            signingOut = false
        }
    }

    var body: some View {
        Form {
            if !SupabaseConfig.isConfigured {
                Section { Text("Sync isn't set up in this copy of Joshu yet.").foregroundStyle(.secondary) }
            } else if let signedIn = cloud.email {
                Section("Plan") { ProSettingsRow() }
                Section("Joshu account") {
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
                    Button(signingOut ? "Saving to your account…" : "Sign Out…", role: .destructive) { confirmSignOut = true }
                        .disabled(signingOut)
                        .confirmationDialog("Sign out of Joshu?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                            Button("Sign Out and Remove from This Device", role: .destructive) { signOut(keep: false) }
                            Button("Sign Out and Keep a Copy Here") { signOut(keep: true) }
                        } message: {
                            Text(cloud.syncSecrets
                                 ? "Everything is saved to your account first, then removed from this device, with your chats and connected accounts like Gmail. Sign in again and it all comes back. Keep a copy only on a device that's just yours."
                                 : "Everything is saved to your account first, then removed from this device. Key sync is off, so your API keys and connected accounts like Gmail aren't saved: you'd need to add them again. Keep a copy only on a device that's just yours.")
                        }
                    Button("Delete Account…", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete your Joshu account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete Account", role: .destructive) {
                                Task {
                                    do { try await cloud.deleteAccount() }
                                    catch is CancellationError {}
                                    catch { deleteError = error.localizedDescription }
                                }
                            }
                        } message: {
                            Text("This deletes your account and everything synced to it, on all your devices. What's on this device stays until you reset it. A Pro subscription is cancelled in your Apple ID settings, not here.")
                        }
                    if let deleteError { Text(deleteError).font(.caption).foregroundStyle(Theme.orange) }
                }
                KeySyncSection()
                Section {
                    Text("Your tasks, calendar events you made in Joshu, habits, money, notes and journal, books and bucket list sync to your account every couple of minutes. Sign in with the same account on another device to get everything there.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section { AuthPanel().padding(.vertical, 6) }
            }
        }
        .formStyle(.grouped)
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
                    Label("Synced with your Joshu account", systemImage: "lock.shield.fill").foregroundStyle(Theme.good)
                case .waiting:
                    Label("Open Joshu on your Mac once to bring your keys here.", systemImage: "hourglass").font(.caption)
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
    @AppStorage("welcome.speak") private var welcome = true
    @ObservedObject private var wake = WakeListener.shared
    @ObservedObject private var speaker = Speaker.shared
    @AppStorage("voice.natural") private var natural = true
    @AppStorage("voice.openai") private var openAIVoice = "coral"
    @State private var hasOpenAI = NaturalVoice.hasKey
    @State private var openAIKey = ""
    @State private var checking = false
    @State private var voiceStatus: String?

    private var voices: [AVSpeechSynthesisVoice] {
        Speaker.naturalVoices(language: Locale.current.language.languageCode?.identifier ?? "en")
    }
    private var hasPremium: Bool { voices.contains { $0.quality == .premium } }

    var body: some View {
        Section {
            Toggle("Read replies aloud", isOn: $speaks)
            Toggle("Welcome me with the brief out loud when I open Joshu", isOn: $welcome)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Hands-free: answer when I say “Hey \(AssistantName.current)”", isOn: $wake.enabled)
                Text("While Joshu is open it listens for “Hey \(AssistantName.current)”, then answers out loud. Listening happens on this device; only your question goes to \(AssistantName.current). Right after an answer you can just keep talking.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let e = wake.error { Text(e).font(.caption).foregroundStyle(Theme.orange) }
            }
            if hasOpenAI {
                Toggle("Natural voice (OpenAI)", isOn: $natural)
                if natural {
                    Picker("Natural voice", selection: $openAIVoice) {
                        ForEach(NaturalVoice.voices, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                Button("Remove OpenAI key", role: .destructive) { Keychain.delete("openai-key"); hasOpenAI = false }
            } else {
                SecureField("OpenAI API key for a natural voice", text: $openAIKey, prompt: Text("sk-…"))
                HStack {
                    Link("Get a key at platform.openai.com", destination: URL(string: "https://platform.openai.com/api-keys")!).font(.caption)
                    Spacer()
                    Button(checking ? "Checking…" : "Save") {
                        let key = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        checking = true
                        Task {
                            voiceStatus = await NaturalVoice.test(key: key)
                            if voiceStatus == nil { Keychain.write(key, account: "openai-key"); hasOpenAI = true; openAIKey = "" }
                            checking = false
                        }
                    }
                    .disabled(openAIKey.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                }
                if let voiceStatus { Text(voiceStatus).font(.caption).foregroundStyle(Theme.orange) }
            }
            if !(hasOpenAI && natural) {
            Picker("Voice", selection: $voiceID) {
                Text("Most natural (\(Speaker.bestVoice(for: "Hi")?.name ?? "default"))").tag("")
                ForEach(voices, id: \.identifier) { v in
                    Text("\(v.name)\(v.quality == .premium ? " · Premium" : v.quality == .enhanced ? " · Enhanced" : "") (\(v.language))").tag(v.identifier)
                }
            }
            }
            Button(speaker.speaking ? "Stop" : "Preview") {
                if speaker.speaking { speaker.stop() }
                else { speaker.speak("Hey! I had a look at your day. You've got two things this afternoon, so maybe grab lunch early? Let me know if you want me to move anything.") }
            }
        } header: {
            Text("Voice")
        } footer: {
            Text(hasOpenAI && natural ? "Replies are read by OpenAI's voice, the same kind ChatGPT talks with. Each reply costs a fraction of a cent on your OpenAI account; the Apple voice takes over when you're offline." : hasPremium
                 ? "Premium voices sound the most like a person."
                 : "For a much more human voice, download a Premium one (free): \(Platform.isPhone ? "Settings › Accessibility › Spoken Content › Voices › English" : "System Settings › Accessibility › Spoken Content › System voice › Manage Voices"), then pick e.g. Zoe, Ava or Evan (Premium). It shows up here.")
        }
    }
}

/// Settings › General › Tabs: switch off the parts of Orbit you don't use.
struct TabsSection: View {
    @AppStorage("hiddenTabs") private var hiddenRaw = ""
    var phoneTabs: Set<Tab> = []

    var body: some View {
        Section {
            ForEach(Tab.allCases.filter(\.canHide)) { t in
                Toggle(isOn: Binding(get: { !Tab.hidden.contains(t) }, set: { on in
                    var h = Tab.hidden
                    if on { h.remove(t) } else { h.insert(t) }
                    Tab.hidden = h
                    hiddenRaw = UserDefaults.standard.string(forKey: "hiddenTabs") ?? ""
                })) {
                    Label { VStack(alignment: .leading, spacing: 1) { Text(t == .reading ? "Reading" : t.title); Text(t.blurb).font(.caption).foregroundStyle(.secondary) } }
                    icon: { Image(systemName: t.symbol) }
                }
                .disabled(phoneTabs.contains(t))
            }
        } header: {
            Text("Tabs")
        } footer: {
            Text(Platform.isPhone ? "Today, Calendar, Tasks and Money stay in the tab bar; the rest are under More." : "Turn off what you don't use. Nothing is deleted, and you can turn a tab back on any time.")
        }
    }
}

/// How far back the AI reads your inbox, and how often. Needs a Gmail account and an API key.
struct InboxWindowControls: View {
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var ai = AIAssistant.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inbox summary").font(.subheadline.weight(.semibold))
            if !ai.hasKey {
                Label("With Joshu Pro, \(AssistantName.current) summarises your inbox: who's waiting on you, bills, deliveries and alerts.",
                      systemImage: "sparkles").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if inbox.accounts.isEmpty {
                Text("Add a Gmail account above and \(AssistantName.current) summarises it on Today.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Read mail from the last", selection: $inbox.windowHours) {
                ForEach(InboxStore.windowChoices, id: \.hours) { Text($0.label).tag($0.hours) }
            }
            Picker("Check for new mail", selection: $inbox.everyHours) {
                ForEach(InboxStore.everyChoices, id: \.hours) { Text($0.label).tag($0.hours) }
            }
            if ai.hasKey && !inbox.accounts.isEmpty {
                Button(inbox.loading ? "Reading your inbox…" : "Summarise now") { Task { await inbox.refresh() } }.disabled(inbox.loading)
            }
            Text("Only the sender, subject and the first line of each email are sent to Anthropic to write the summary; promotions and social mail are skipped.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .disabled(false)
    }
}
