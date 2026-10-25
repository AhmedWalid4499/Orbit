import SwiftUI

/// Every other connection with its own Disconnect: reading sources and the AI keys (Mac and iPhone settings).
struct OtherConnections: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var reading = ReadingSync.shared
    @ObservedObject private var ai = AIAssistant.shared
    @State private var openAIConnected = !(Keychain.read("openai-key") ?? "").isEmpty
    @State private var confirm: String?

    var body: some View {
        Section("YouTube") { YouTubeConnectionRow() }
        Section("LinkedIn") { LinkedInConnectionRow() }
        Section {
            row("Goodreads", .goodreads, reading.goodreadsUser.isEmpty ? nil : "Shelves sync from your profile") {
                reading.goodreadsUser = ""
            }
            if !Platform.isPhone {
                row("Apple Books", .appleBooks, reading.appleBooksLinked ? "Library on this Mac syncs daily" : nil) { reading.disconnect("apple", context: context) }
                row("Kindle", .kindle, reading.kindleLinked ? "Kindle app library syncs daily" : nil) { reading.disconnect("kindle", context: context) }
            }
        } header: {
            Text("Reading sources")
        } footer: {
            Text("Disconnecting Apple Books or Kindle stops the sync and removes the books that came only from it. Goodreads books stay.")
        }
        Section {
            row("Claude (Anthropic API key)", .claude, ai.hasKey ? "Powers the assistant, brief and smart features" : nil) { ai.removeKey() }
            row("OpenAI voice", .openai, openAIConnected ? "Natural voice for spoken replies" : nil) {
                Keychain.delete("openai-key")
                openAIConnected = false
            }
        } header: {
            Text("AI")
        } footer: {
            Text("Removing a key deletes it from this device's Keychain. Add it again in Settings › AI.")
        }
    }

    /// A connection with a Disconnect button while it's on (`detail` nil means not connected).
    private func row(_ name: String, _ brand: Brand, _ detail: String?, disconnect: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            BrandLogo(brand: brand, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(detail ?? "Not connected").font(.caption).foregroundStyle(detail == nil ? Theme.inkMuted : Theme.good)
            }
            Spacer()
            if detail != nil {
                Button("Disconnect", role: .destructive) { confirm = name }
                    .confirmationDialog("Disconnect \(name)?", isPresented: Binding(get: { confirm == name }, set: { if !$0 { confirm = nil } }),
                                        titleVisibility: .visible) {
                        Button("Disconnect", role: .destructive) { disconnect(); confirm = nil }
                    }
            }
        }
    }
}
