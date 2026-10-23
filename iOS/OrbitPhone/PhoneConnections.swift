import SwiftUI
import SwiftData

/// Connections on iPhone. Google, GitHub and the API key arrive from your Orbit account, so this shows what's
/// connected rather than the Mac's one-time setup guides.
struct PhoneConnections: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var gh = GitHubStore.shared
    @ObservedObject private var cloud = CloudSync.shared
    @AppStorage("googleCalendarEnabled") private var googleCalendar = true
    @AppStorage("emailExpensesEnabled") private var emailExpenses = true
    @AppStorage("goodreadsUser") private var goodreadsUser = ""
    @State private var user = ""
    @State private var token = ""
    @State private var readingSources = false

    var body: some View {
        List {
            if cloud.vaultState == .waiting {
                Section {
                    Label("Waiting for your Mac to share your sign-ins. Open Orbit on the Mac once (signed in) and they'll appear here.",
                          systemImage: "hourglass").font(Theme.ui(14))
                }
            }

            Section {
                if inbox.accounts.isEmpty {
                    row("envelope.fill", Theme.pink, "Gmail", detail: cloud.isSignedIn
                        ? "Your Gmail accounts come from your Orbit account once they're connected on your Mac."
                        : "Sign in to your Orbit account (Settings › Account & sync) to bring your Gmail accounts here.")
                } else {
                    ForEach(inbox.accounts, id: \.self) { email in
                        HStack(spacing: 12) {
                            icon("envelope.fill", Theme.pink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(email).font(Theme.ui(15, weight: .medium)).lineLimit(1)
                                Label("Connected", systemImage: "checkmark.circle.fill").font(Theme.ui(12)).foregroundStyle(Theme.good)
                            }
                        }
                        .swipeActions { Button("Remove", role: .destructive) { inbox.remove(email) } }
                    }
                    if GoogleAuth.isConfigured {
                        Button { Task { await inbox.addAccount() } } label: {
                            Label(inbox.signingIn ? "Waiting for Google…" : "Add another Gmail account", systemImage: "plus")
                        }
                        .disabled(inbox.signingIn)
                    }
                    Toggle("Show Google Calendar events", isOn: $googleCalendar)
                    Toggle("Add receipts from email to Money", isOn: $emailExpenses)
                }
                if let error = inbox.error { Text(error).font(Theme.ui(12)).foregroundStyle(Theme.critical) }
            } header: {
                Text("Google")
            }

            Section("GitHub") {
                if gh.isConnected {
                    HStack(spacing: 12) {
                        icon("chevron.left.forwardslash.chevron.right", Theme.inverse, ink: Theme.onInverse)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(gh.username)").font(Theme.ui(15, weight: .medium))
                            Text(gh.hasToken ? "Private repos and contributions included" : "Public data only")
                                .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        Button("Disconnect") { gh.disconnect() }.buttonStyle(SoftButtonStyle())
                    }
                } else {
                    TextField("GitHub username", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Access token (optional, for private repos)", text: $token)
                    Button("Connect GitHub") {
                        gh.saveToken(token)
                        gh.username = user.trimmingCharacters(in: .whitespaces)
                        token = ""
                        Task { await gh.refresh() }
                    }
                    .disabled(user.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                appleRow("calendar", Theme.cyan, "Apple Calendar", connected: apple.calendarEnabled && apple.calendarAccess == .granted,
                         denied: apple.calendarAccess == .denied) { Task { await apple.connectCalendar() } } disconnect: { apple.disconnectCalendar() }
                appleRow("checklist", Theme.lime, "Apple Reminders", connected: apple.remindersEnabled && apple.remindersAccess == .granted,
                         denied: apple.remindersAccess == .denied) { Task { await apple.connectReminders() } } disconnect: { apple.disconnectReminders() }
            } header: {
                Text("On this iPhone")
            } footer: {
                Text("iPhone asks for its own permission for these, once.")
            }

            Section("Reading") {
                HStack(spacing: 12) {
                    icon("books.vertical.fill", Theme.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Goodreads").font(Theme.ui(15, weight: .medium))
                        Text(goodreadsUser.isEmpty ? "Not connected" : "Synced from your account")
                            .font(Theme.ui(12)).foregroundStyle(goodreadsUser.isEmpty ? Theme.inkMuted : Theme.good)
                    }
                    Spacer()
                    Button(goodreadsUser.isEmpty ? "Connect" : "Options") { readingSources = true }.buttonStyle(SoftButtonStyle())
                }
                Text("Apple Books and Kindle are imported by Orbit on your Mac, and the books then appear here on their own.").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
            }
        }
        .sheet(isPresented: $readingSources) { ReadingSourcesSheet() }
    }

    private func icon(_ symbol: String, _ color: Color, ink: Color = Theme.stickerInk) -> some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
            .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9).fill(color))
    }

    private func row(_ symbol: String, _ color: Color, _ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon(symbol, color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.ui(15, weight: .medium))
                Text(detail).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func appleRow(_ symbol: String, _ color: Color, _ title: String, connected: Bool, denied: Bool,
                          connect: @escaping () -> Void, disconnect: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            icon(symbol, color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.ui(15, weight: .medium))
                Text(connected ? "Connected" : denied ? "Turned off in iPhone Settings" : "Not connected")
                    .font(Theme.ui(12)).foregroundStyle(connected ? Theme.good : Theme.inkMuted)
            }
            Spacer()
            if connected {
                Button("Disconnect", action: disconnect).buttonStyle(SoftButtonStyle())
            } else if denied {
                Button("Settings") { Platform.open(URL(string: "app-settings:")!) }.buttonStyle(SoftButtonStyle())
            } else {
                Button("Connect", action: connect).buttonStyle(PrimaryButtonStyle()).fixedSize()
            }
        }
    }
}
