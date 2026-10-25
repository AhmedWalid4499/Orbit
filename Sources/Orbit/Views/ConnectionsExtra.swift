import SwiftUI

/// Every other connection with its own Disconnect: reading sources and the AI keys (Mac and iPhone settings).
struct OtherConnections: View {
    @ObservedObject private var reading = ReadingSync.shared
    @ObservedObject private var ai = AIAssistant.shared
    @State private var openAIConnected = !(Keychain.read("openai-key") ?? "").isEmpty
    @State private var confirm: String?

    var body: some View {
        Section("YouTube") { YouTubeConnectionRow() }
        Section {
            row("Goodreads", "books.vertical.fill", reading.goodreadsUser.isEmpty ? nil : "Shelves sync from your profile") {
                reading.goodreadsUser = ""
            }
            if !Platform.isPhone {
                row("Apple Books", "book.fill", reading.appleBooksLinked ? "Library on this Mac syncs daily" : nil) { reading.appleBooksLinked = false }
                row("Kindle", "flame.fill", reading.kindleLinked ? "Kindle app library syncs daily" : nil) { reading.kindleLinked = false }
            }
        } header: {
            Text("Reading sources")
        } footer: {
            Text("Disconnecting stops future syncs. Books already in your library stay.")
        }
        Section {
            row("Claude (Anthropic API key)", "sparkles", ai.hasKey ? "Powers the assistant, brief and smart features" : nil) { ai.removeKey() }
            row("OpenAI voice", "waveform", openAIConnected ? "Natural voice for spoken replies" : nil) {
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
    private func row(_ name: String, _ symbol: String, _ detail: String?, disconnect: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(detail ?? "Not connected").font(.caption).foregroundStyle(detail == nil ? Theme.inkMuted : Theme.good)
            }
            Spacer()
            if detail != nil {
                Button("Disconnect", role: .destructive) { confirm = name }
                    .confirmationDialog("Disconnect \(name)?", isPresented: Binding(get: { confirm == name }, set: { if !$0 { confirm = nil } })) {
                        Button("Disconnect", role: .destructive) { disconnect(); confirm = nil }
                    }
            }
        }
    }
}
