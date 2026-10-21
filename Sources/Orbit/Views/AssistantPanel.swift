import SwiftUI
import SwiftData

/// Slide-over chat with Claude that can create things in Orbit. Opens from the ✦ button or ⌘J.
struct AssistantPanel: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @EnvironmentObject private var state: AppState
    @ObservedObject private var store = AssistantStore.shared
    @ObservedObject private var ai = AIAssistant.shared

    @State private var draft = ""
    @FocusState private var focused: Bool

    private let suggestions = [
        "I can't seem to read every day. Can you help?",
        "Recommend books about Japanese culture",
        "Plan my week around what's on my calendar",
        "How can I spend less on food this month?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            if !ai.hasKey {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles").font(.system(size: 30))
                    Text("Add your Anthropic API key to chat with Claude.").font(Theme.ui(13)).multilineTextAlignment(.center)
                    SettingsLink { Text("Open Settings") }.buttonStyle(SoftButtonStyle())
                    Spacer()
                }
                .foregroundStyle(Theme.inkSecondary)
                .padding(24)
            } else {
                messages
                composer
            }
        }
        .frame(width: 440)
        .frame(maxHeight: .infinity)
        .background(Theme.canvas)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
        .shadow(color: .black.opacity(0.12), radius: 24, x: -8)
        .onAppear { focused = true; sendSeed() }
        .onChange(of: state.assistantSeed) { sendSeed() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.stickerInk)
                .frame(width: 32, height: 32).background(Circle().fill(Theme.lime))
            VStack(alignment: .leading, spacing: 1) {
                Text("Ask Claude").font(Theme.display(20))
                Text("Talks things through and sets things up for you").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Button { store.newChat() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.plain).help("New chat").disabled(store.busy)
            Button { withAnimation(.spring(response: 0.35)) { state.assistantOpen = false } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Close (Esc)").keyboardShortcut(.cancelAction)
        }
        .font(.system(size: 14, weight: .semibold))
        .padding(16)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.items.isEmpty && !store.busy {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What's on your mind?").font(Theme.display(22))
                            Text("Ask for advice, or just say what you want: Claude can add habits, tasks, events, notes, expenses and books for you.")
                                .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                            ForEach(suggestions, id: \.self) { s in
                                Button { send(s) } label: {
                                    Text(s).font(Theme.ui(13)).multilineTextAlignment(.leading)
                                        .padding(.horizontal, 12).padding(.vertical, 9)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }
                    ForEach(store.items) { item in
                        row(item).id(item.id)
                    }
                    if store.busy {
                        if store.revealed.isEmpty {
                            HStack { Thinking(); Spacer() }.id("live")
                        } else {
                            AssistantText(text: store.revealed).id("live")
                        }
                    }
                    if let e = store.error {
                        Label(e, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(12)).foregroundStyle(Theme.orange)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.never)
            .onChange(of: store.items.count) { withAnimation { proxy.scrollTo(store.items.last?.id, anchor: .bottom) } }
            .onChange(of: store.revealed) { proxy.scrollTo("live", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func row(_ item: ChatItem) -> some View {
        switch item.role {
        case .user:
            HStack {
                Spacer(minLength: 50)
                Text(item.text).font(Theme.ui(14)).textSelection(.enabled)
                    .foregroundStyle(Theme.onInverse)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.inverse))
            }
        case .assistant:
            AssistantText(text: item.text)
        case .action:
            HStack(spacing: 10) {
                Image(systemName: item.undone ? "arrow.uturn.backward" : item.symbol)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.stickerInk)
                    .frame(width: 26, height: 26).background(Circle().fill(item.undone ? Theme.line : Theme.lime))
                Text(item.text).font(Theme.ui(12, weight: .medium)).strikethrough(item.undone).lineLimit(3)
                    .foregroundStyle(item.undone ? Theme.inkMuted : Theme.ink)
                Spacer(minLength: 4)
                if item.undo != nil && !item.undone {
                    Button("Undo") { store.undo(item, context: context) }
                        .buttonStyle(.plain).font(Theme.ui(11, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message Claude…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(Theme.ui(14)).lineLimit(1...6)
                .focused($focused)
                .onSubmit { send(draft) }
            Button { send(draft) } label: {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.onInverse)
                    .frame(width: 30, height: 30).background(Circle().fill(Theme.inverse))
            }
            .buttonStyle(.plain)
            .disabled(store.busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .padding(14)
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !store.busy else { return }
        draft = ""
        Task { await store.send(t, context: context, apple: apple) }
    }

    private func sendSeed() {
        guard let seed = state.assistantSeed else { return }
        state.assistantSeed = nil
        send(seed)
    }
}

/// Assistant text with light markdown (bold, italics, links) and calm line spacing.
private struct AssistantText: View {
    let text: String

    var body: some View {
        let attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        HStack {
            Text(attributed).font(Theme.ui(14)).lineSpacing(3).textSelection(.enabled)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 30)
        }
    }
}

private struct Thinking: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(Theme.inkMuted).frame(width: 7, height: 7)
                    .opacity(on ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: on)
            }
        }
        .padding(.vertical, 8)
        .onAppear { on = true }
    }
}
