import SwiftUI
import SwiftData

// MARK: - Quick capture (⌥Space panel)

struct QuickCaptureView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var ai = AIAssistant.shared
    @State private var text = ""
    @State private var saved: String?
    @State private var working = false
    @FocusState private var focused: Bool

    private var parsed: QuickParser.Result { QuickParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if working {
                    ProgressView().controlSize(.small).frame(width: 22)
                } else {
                    Image(systemName: ai.smartCaptureActive ? "sparkles" : "circle.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(Theme.ink).frame(width: 22)
                }
                TextField("Capture anything…  “dentist thu 3pm #health”, “$12 lunch”", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.ui(22))
                    .focused($focused)
                    .disabled(working)
                    .onSubmit(save)
            }
            HStack(spacing: 8) {
                if let saved {
                    Label(saved, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good).lineLimit(2)
                } else if working {
                    Text("Claude is sorting this…").foregroundStyle(Theme.inkSecondary)
                } else if text.isEmpty && ai.smartCaptureActive {
                    Text("Type naturally — Claude sorts it into tasks, events, money and notes. Several at once works too.")
                        .foregroundStyle(Theme.inkMuted)
                } else if text.isEmpty {
                    Text("Task · Event (with a time) · $ expense · +income · note: · journal:")
                        .foregroundStyle(Theme.inkMuted)
                } else {
                    Text("→ \(parsed.summary)")
                    if !parsed.title.isEmpty { Text("“\(parsed.title)”").foregroundStyle(Theme.inkSecondary).lineLimit(1) }
                }
                Spacer()
                Text("↩ save   esc close").foregroundStyle(Theme.inkMuted)
            }
            .font(Theme.ui(13, weight: .medium))
        }
        .padding(22)
        .frame(width: 620)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.canvas))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line))
        .foregroundStyle(Theme.ink)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .captureOpened)) { _ in
            saved = nil
            focused = true
        }
    }

    private func save() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !working else { return }
        guard ai.smartCaptureActive else { return finish([parsed], note: nil) }

        working = true
        Task {
            do {
                let items = try await ai.smartParse(raw)
                finish(items.isEmpty ? [QuickParser.parse(raw)] : items, note: nil)
            } catch {
                // Offline or API trouble: never lose the capture, fall back to the local parser.
                finish([QuickParser.parse(raw)], note: "used offline parser: \(error.localizedDescription)")
            }
            working = false
        }
    }

    private func finish(_ items: [QuickParser.Result], note: String?) {
        let valid = items.filter { !$0.title.isEmpty || $0.amount != nil }
        guard !valid.isEmpty else { return }
        valid.forEach { $0.save(in: context) }
        saved = "Saved — " + valid.map(\.summary).joined(separator: "  |  ") + (note.map { " (\($0))" } ?? "")
        text = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + (note == nil ? 1.2 : 3)) { CapturePanel.shared.hide() }
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @EnvironmentObject private var apple: AppleSync
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \EventItem.start) private var events: [EventItem]
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]

    private var next: CalEntry? {
        let now = Date.now
        let local = events.filter { $0.end > now && $0.start < now.adding(days: 2) }
        return CalEntry.merge(local: local, apple: apple.events(from: now, to: now.adding(days: 2))).first { $0.end > now }
    }

    private var dueToday: [TaskItem] {
        open.filter { ($0.due ?? .distantFuture) < Date.now.startOfDay.adding(days: 1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Theme.display(20))
            if let next {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(next.tint).frame(width: 4, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title).font(Theme.ui(14, weight: .semibold))
                        Text("\(Fmt.relativeDay(next.start)) · \(Fmt.time(next.start))").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                    }
                }
            } else {
                Text("No upcoming events").font(Theme.ui(13)).foregroundStyle(Theme.inkMuted)
            }
            Divider()
            Text("\(dueToday.count) task\(dueToday.count == 1 ? "" : "s") due today").font(Theme.ui(13, weight: .semibold))
            ForEach(dueToday.prefix(5)) { t in
                HStack(spacing: 8) {
                    Circle().fill(t.area.color).frame(width: 8, height: 8)
                    Text(t.title).font(Theme.ui(13)).lineLimit(1)
                }
            }
            Divider()
            HStack {
                Button("Quick capture") { CapturePanel.shared.show() }.buttonStyle(SoftButtonStyle())
                Spacer()
                Button("Open Orbit") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
        .padding(18)
        .frame(width: 300)
    }
}

// MARK: - Search (⌘K)

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @Query private var tasks: [TaskItem]
    @Query private var notes: [Note]
    @Query private var events: [EventItem]
    @Query private var txns: [Transaction]
    @Query private var books: [Book]
    @State private var query = ""
    @FocusState private var focused: Bool

    private struct Hit: Identifiable { let id = UUID(); let title: String; let detail: String; let symbol: String; let tab: Tab }

    private var hits: [Hit] {
        guard query.count >= 2 else { return [] }
        func m(_ s: String) -> Bool { s.localizedCaseInsensitiveContains(query) }
        var r: [Hit] = []
        r += tasks.filter { m($0.title) }.prefix(8).map {
            Hit(title: $0.title, detail: $0.isDone ? "Completed task" : "Task · \($0.area.title)", symbol: "checkmark.circle", tab: .tasks)
        }
        r += events.filter { m($0.title) }.prefix(6).map {
            Hit(title: $0.title, detail: "Event · \($0.start.formatted(date: .abbreviated, time: .shortened))", symbol: "calendar", tab: .calendar)
        }
        r += notes.filter { m($0.title) || m($0.body) }.prefix(6).map {
            Hit(title: $0.title.isEmpty ? "Untitled" : $0.title, detail: $0.isJournal ? "Journal" : "Note", symbol: "doc.text", tab: .notes)
        }
        r += txns.filter { m($0.title) }.prefix(6).map {
            Hit(title: $0.title, detail: "\(Fmt.money($0.amount, signed: true)) · \($0.date.formatted(date: .abbreviated, time: .omitted))",
                symbol: "creditcard", tab: .money)
        }
        r += books.filter { m($0.title) || m($0.author) }.prefix(6).map {
            Hit(title: $0.title, detail: "Book · \($0.author) · \($0.status.title)", symbol: "book", tab: .reading)
        }
        return r
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(Theme.inkMuted)
                TextField("Search tasks, events, notes, money…", text: $query)
                    .textFieldStyle(.plain).font(Theme.ui(20)).focused($focused)
                    .onSubmit { if let first = hits.first { go(first.tab) } }
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(spacing: 4) {
                    if query.count >= 2 && hits.isEmpty { EmptyHint(symbol: "questionmark", text: "No matches").padding() }
                    ForEach(hits) { hit in
                        Button { go(hit.tab) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: hit.symbol).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title).font(Theme.ui(14, weight: .medium))
                                    Text(hit.detail).font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .frame(height: 360)
        }
        .frame(width: 620)
        .onAppear { focused = true }
        .onExitCommand { dismiss() }
    }

    private func go(_ tab: Tab) {
        state.tab = tab
        dismiss()
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @AppStorage("userName") private var userName = NSFullUserName()
    @AppStorage("monthlyBudget") private var monthlyBudget = 2000.0
    @AppStorage("currencyCode") private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var confirmClear = false
    @State private var readingSources = false
    @ObservedObject private var gh = GitHubStore.shared

    var body: some View {
        TabView {
            Form {
                TextField("Your name", text: $userName)
                TextField("Monthly budget", value: $monthlyBudget, format: .number)
                Picker("Currency", selection: $currency) {
                    ForEach(["USD", "EUR", "GBP", "EGP", "AED", "SAR", "JPY", "CAD", "AUD", "INR"], id: \.self) { Text($0) }
                }
                Section("Updates") { UpdatePanel() }
                LabeledContent("Quick capture", value: "⌥Space (anywhere)")
                LabeledContent("Search", value: "⌘K")
                Section {
                    Button("Delete all data…", role: .destructive) { confirmClear = true }
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Built in — works now") {
                    ConnectionRow(name: "Apple Calendar",
                                  detail: "Shows every calendar on this Mac — iCloud, Google, Outlook, Exchange.",
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
                Section("Gmail") { GmailSettings() }
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
                    PlannedRow(name: "Bank accounts", detail: "Auto-import spending. Plaid account, or CSV import from your bank.", symbol: "building.columns")
                    PlannedRow(name: "Apple Health", detail: "Sleep, steps, workouts. Needs an iPhone companion app.", symbol: "heart")
                }
            }
            .tabItem { Label("Connections", systemImage: "link") }

            AISettings()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 640)
        .sheet(isPresented: $readingSources) { ReadingSourcesSheet() }
        .confirmationDialog("Delete everything in Orbit?", isPresented: $confirmClear) {
            Button("Delete all data", role: .destructive) { DataReset.clearAll(context) }
        } message: {
            Text("Tasks, events, habits, transactions, notes and books stored in Orbit will be removed. Apple Calendar and Reminders are not touched.")
        }
    }
}

private struct ConnectionRow: View {
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
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            } else {
                Button("Connect", action: connect).buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct PlannedRow: View {
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

private struct AISettings: View {
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
                Text("Uses \(ClaudeClient.model). The key is stored in your macOS Keychain, never in a file.")
            }

            Section("Features") {
                Toggle(isOn: $ai.smartCaptureEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart capture")
                        Text("⌥Space text is sorted by Claude, and one line can hold several items. Falls back to the offline parser if the API is unreachable.")
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

private struct GmailSettings: View {
    @ObservedObject private var inbox = InboxStore.shared
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
            Text("Inbox summaries send the sender, subject and a short preview of the last two days of mail (no promotions or social) to Anthropic.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
