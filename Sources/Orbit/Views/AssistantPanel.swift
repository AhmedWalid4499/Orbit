import SwiftUI
import SwiftData
import MapKit

/// Slide-over chat with Claude that can create things in Orbit. Opens from the ✦ button or ⌘J.
struct AssistantPanel: View {
    /// Shown as its own tab (the AI tab) instead of sliding over the window.
    var embedded = false
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @EnvironmentObject private var state: AppState
    @ObservedObject private var store = AssistantStore.shared
    @ObservedObject private var ai = AIAssistant.shared

    @AppStorage("assistantName") private var assistantName = "Joshu"
    @AppStorage("assistantSpeaks") private var speaks = false
    @ObservedObject private var dictation = Dictation.shared
    @ObservedObject private var speaker = Speaker.shared
    @ObservedObject private var wake = WakeListener.shared
    @State private var draft = ""
    @State private var attachments: [ChatAttachment] = []
    @State private var picking = false
    @State private var dropping = false
    @State private var fileError: String?
    /// The last message was spoken, so keep the conversation going by voice.
    @State private var voiceTurn = false
    /// The chat is showing (the AI tab can be left while a reply is read out).
    @State private var onScreen = false
    @FocusState private var focused: Bool

    private let suggestions: [(String, String, Color)] = [
        ("I'm hungry, what's good near me?", "fork.knife", Theme.peach),
        ("Plan my week around my calendar", "calendar", Theme.cyan),
        ("How can I spend less on food this month?", "banknote.fill", Theme.mint),
        ("Recommend books about Japanese culture", "books.vertical.fill", Theme.lavender),
        ("What should I wear today?", "cloud.sun.fill", Theme.sand),
        ("I can't seem to read every day. Help?", "heart.fill", Theme.pink),
    ]

    private var firstName: String { Platform.userName.split(separator: " ").first.map(String.init) ?? "" }
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        let part = h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        return firstName.isEmpty ? "\(part)!" : "\(part), \(firstName)!"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            if !ai.hasKey {
                VStack(spacing: 12) {
                    Spacer()
                    AssistantAvatar(size: 56)
                    Text("\(assistantName) comes with Joshu Pro").font(Theme.display(22)).foregroundStyle(Theme.ink)
                    Text("Ask anything, plan your week, write and code with \(assistantName), by voice or text.").font(Theme.ui(13)).multilineTextAlignment(.center)
                    Button("See Joshu Pro") { state.openPro() }.buttonStyle(PrimaryButtonStyle()).fixedSize()
                    Spacer()
                }
                .foregroundStyle(Theme.inkSecondary)
                .padding(24)
            } else {
                messages
                composer
            }
        }
        .modifier(PanelChrome(embedded: embedded))
        .onAppear {
            onScreen = true
            // On iPhone the keyboard only comes up when you tap the message box.
            if !Platform.isPhone { focused = true }
            sendSeed()
        }
        .onChange(of: state.assistantSeed) { sendSeed() }
        .onChange(of: store.busy) { _, busy in if !busy { replyFinished() } }
        .onDisappear { onScreen = false; dictation.cancel(); speaker.stop(); voiceTurn = false }
        .fileImporter(isPresented: $picking, allowedContentTypes: ChatAttachment.allowedTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { add(urls) }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in add([url]) } }
                }
            }
            return true
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.inverse, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Theme.canvas.opacity(0.85))
                    .overlay(Label("Drop to send to \(assistantName)", systemImage: "doc.badge.plus").font(Theme.ui(14, weight: .semibold)))
                    .padding(10)
            }
        }
    }

    private func add(_ urls: [URL]) {
        fileError = nil
        for url in urls.prefix(5) {
            do { attachments.append(try ChatAttachment.load(url)) } catch { fileError = error.localizedDescription }
        }
    }

    /// Reads the reply aloud if that's on, then listens again when you were talking.
    /// The reply was read aloud while it was written; when you were talking, listen again once it's done.
    private func replyFinished() {
        guard voiceTurn, store.error == nil else { voiceTurn = false; return }
        speaker.whenDone {
            guard voiceTurn, onScreen else { return }
            Task { await dictation.start { heard in sendVoice(heard) } }
        }
    }

    private func sendVoice(_ heard: String) {
        guard !heard.isEmpty else { voiceTurn = false; return }
        voiceTurn = true
        store.speakNextReply = true
        send(heard)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AssistantAvatar(size: 36, busy: store.busy || speaker.speaking)
            VStack(alignment: .leading, spacing: 1) {
                Text(assistantName).font(Theme.display(20))
                HStack(spacing: 5) {
                    Circle().fill(store.busy ? Theme.orange : Theme.good).frame(width: 6, height: 6)
                    Text(store.busy ? "Thinking…" : speaker.speaking ? "Speaking…" : wake.awake ? "Listening…" : wake.listening ? "Say “Hey \(assistantName)”" : "Here for anything")
                        .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer()
            Button {
                speaks.toggle()
                if !speaks { speaker.stop(); voiceTurn = false }
            } label: { Image(systemName: speaks ? "speaker.wave.2.fill" : "speaker.slash") }
                .buttonStyle(.plain).foregroundStyle(speaks ? Theme.ink : Theme.inkMuted)
                .help(speaks ? "Reading replies aloud. Click to turn off." : "Read replies aloud")
            Button { wake.startConversation() } label: { Image(systemName: "waveform") }
                .buttonStyle(.plain).help("Talk hands-free")
            Button { wake.enabled.toggle() } label: { Image(systemName: wake.enabled ? "ear.fill" : "ear") }
                .buttonStyle(.plain).foregroundStyle(wake.enabled ? Theme.ink : Theme.inkMuted)
                .help(wake.enabled ? "Listening for “Hey \(assistantName)”. Click to stop." : "Answer hands-free when you say “Hey \(assistantName)”")
            if !embedded || Platform.isPhone { PastChatsMenu() }
            Button { store.newChat() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.plain).help("New chat").disabled(store.busy)
            if !embedded {
                Button { withAnimation(.spring(response: 0.35)) { state.assistantOpen = false } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close (Esc)").keyboardShortcut(.cancelAction)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .padding(16)
    }

    private var messages: some View {
        ChatTranscript(greeting: greeting, suggestions: suggestions, onSend: { send($0) }, onTap: { focused = false })
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(attachments) { a in
                            HStack(spacing: 6) {
                                Image(systemName: a.symbol)
                                Text(a.name).lineLimit(1).frame(maxWidth: 160)
                                Button { attachments.removeAll { $0.id == a.id } } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                            }
                            .font(Theme.ui(11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Theme.canvas))
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            if let e = fileError ?? dictation.error {
                Text(e).font(Theme.ui(11)).foregroundStyle(Theme.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { picking = true } label: { Image(systemName: "paperclip").font(.system(size: 14, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary).help("Send a PDF, photo or document")
                if dictation.listening {
                    Text(dictation.text.isEmpty ? "Listening…" : dictation.text).font(Theme.ui(14))
                        .foregroundStyle(dictation.text.isEmpty ? Theme.inkMuted : Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1...6)
                } else {
                    TextField(attachments.isEmpty ? "Message \(assistantName)…" : "Ask about \(attachments.count == 1 ? "this file" : "these files")…",
                              text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).font(Theme.ui(14)).lineLimit(1...6)
                        .focused($focused)
                        .onSubmit { send(draft) }
                }
                if Platform.isPhone && focused {
                    Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down").font(.system(size: 14, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary).accessibilityLabel("Hide keyboard")
                }
                MicButton { heard in sendVoice(heard) }
                    .disabled(store.busy)
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.onInverse)
                        .frame(width: 30, height: 30).background(Circle().fill(Theme.inverse))
                }
                .buttonStyle(.plain)
                .disabled(store.busy || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(focused ? Theme.ink.opacity(0.25) : Theme.line))
        .padding(14)
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || !attachments.isEmpty, !store.busy else { return }
        // Asked first; what they wrote stays in the box for when they've said yes.
        guard AIConsent.granted else { AIConsent.ask(force: true); return }
        if !dictation.listening && t == draft.trimmingCharacters(in: .whitespacesAndNewlines) { voiceTurn = false }
        draft = ""
        if Platform.isPhone { focused = false }
        let files = attachments
        attachments = []
        speaker.stop()
        Task { await store.send(t, attachments: files, context: context, apple: apple) }
    }

    private func sendSeed() {
        guard let seed = state.assistantSeed else { return }
        state.assistantSeed = nil
        send(seed)
    }
}

/// The conversation itself. Its own view so typing or talking (which change the box below) doesn't redraw every message.
private struct ChatTranscript: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var store = AssistantStore.shared
    let greeting: String
    let suggestions: [(String, String, Color)]
    let onSend: (String) -> Void
    let onTap: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.items.isEmpty && !store.busy {
                        VStack(alignment: .leading, spacing: 14) {
                            AssistantAvatar(size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(greeting).font(Theme.display(28))
                                Text("What's on your mind? Ask me anything, or tell me what to set up: tasks, plans, places, money, books.")
                                    .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(suggestions, id: \.0) { text, symbol, tint in
                                    Button { onSend(text) } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                                                .frame(width: 28, height: 28).background(Circle().fill(tint))
                                            Text(text).font(Theme.ui(12, weight: .medium)).multilineTextAlignment(.leading)
                                                .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.18)))
                                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.5)))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    ForEach(store.items) { item in
                        row(item).id(item.id)
                    }
                    if store.busy {
                        HStack(alignment: .top, spacing: 8) {
                            AssistantAvatar(size: 22, busy: true)
                            Group {
                                if store.revealed.isEmpty { Thinking() } else { AssistantText(text: store.revealed) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                                .fill(Theme.card))
                            Spacer(minLength: 24)
                        }
                        .id("live")
                    }
                    if let e = store.error {
                        Label(e, systemImage: "exclamationmark.triangle.fill").font(Theme.ui(12)).foregroundStyle(Theme.orange)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.never)
            // Scrolling or tapping the conversation puts the keyboard away.
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { onTap() })
            .onChange(of: store.items.count) { withAnimation { proxy.scrollTo(store.items.last?.id, anchor: .bottom) } }
            .onChange(of: store.revealed) { proxy.scrollTo("live", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func row(_ item: ChatItem) -> some View {
        switch item.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if let files = item.files, !files.isEmpty {
                    HStack(spacing: 6) {
                        Spacer(minLength: 50)
                        ForEach(files, id: \.self) { f in
                            Label(f, systemImage: "paperclip").font(Theme.ui(11, weight: .medium)).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Theme.card))
                        }
                    }
                }
                HStack {
                    Spacer(minLength: 50)
                    Text(item.text).font(Theme.ui(14)).textSelection(.enabled)
                        .foregroundStyle(Theme.stickerInk)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.lime, Theme.mint], startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                AssistantAvatar(size: 22)
                AssistantText(text: item.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                        .fill(Theme.card))
                Spacer(minLength: 24)
            }
        case .action:
            if let place = item.place, !item.undone {
                PlaceChatCard(place: place, note: item.text) { store.undo(item, context: context) }
                    .padding(.leading, 30)
            } else {
                let tint = ActionTint.color(for: item.symbol)
                HStack(spacing: 10) {
                    Image(systemName: item.undone ? "arrow.uturn.backward" : item.symbol)
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.stickerInk)
                        .frame(width: 30, height: 30).background(Circle().fill(item.undone ? Theme.line : tint))
                    Text(item.text).font(Theme.ui(13, weight: .medium)).strikethrough(item.undone).lineLimit(3)
                        .foregroundStyle(item.undone ? Theme.inkMuted : Theme.ink)
                    Spacer(minLength: 4)
                    if item.undo != nil && !item.undone {
                        Button("Undo") { store.undo(item, context: context) }
                            .buttonStyle(.plain).font(Theme.ui(11, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Theme.canvas))
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(item.undone ? Theme.card : tint.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(item.undone ? Theme.line : tint.opacity(0.55)))
                .padding(.leading, 30)
            }
        }
    }

}

/// Assistant text with light markdown (bold, italics, links) and calm line spacing.
struct AssistantText: View {
    let text: String

    /// Prose and ``` code blocks, in order.
    private var parts: [(code: Bool, lang: String, text: String)] {
        var out: [(Bool, String, String)] = []
        var rest = Substring(text)
        while let open = rest.range(of: "```") {
            let before = rest[..<open.lowerBound]
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append((false, "", String(before).trimmingCharacters(in: .newlines))) }
            let afterOpen = rest[open.upperBound...]
            let langEnd = afterOpen.firstIndex(of: "\n") ?? afterOpen.endIndex
            let lang = afterOpen[..<langEnd].trimmingCharacters(in: .whitespaces)
            let codeStart = langEnd < afterOpen.endIndex ? afterOpen.index(after: langEnd) : langEnd
            let body = afterOpen[codeStart...]
            if let close = body.range(of: "```") {
                out.append((true, lang, String(body[..<close.lowerBound]).trimmingCharacters(in: .newlines)))
                rest = body[close.upperBound...]
            } else {
                // Still being written: show what's there as code.
                out.append((true, lang, String(body)))
                rest = ""
            }
        }
        if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append((false, "", String(rest).trimmingCharacters(in: .newlines))) }
        return out
    }

    var body: some View {
        if !text.contains("```") {
            prose(text)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    if p.code { CodeBlock(code: p.text, language: p.lang) } else { prose(p.text) }
                }
            }
        }
    }

    private func prose(_ s: String) -> some View {
        let attributed = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        return Text(attributed).font(Theme.ui(14)).lineSpacing(3).textSelection(.enabled)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(alignment: .leading)
    }
}

/// Code from the assistant: monospaced on a dark card, scrolls sideways, with a Copy button.
struct CodeBlock: View {
    let code: String
    let language: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language).font(Theme.ui(11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button {
                    Platform.copy(code)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").font(Theme.ui(11, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.white.opacity(0.06))
            ScrollView(.horizontal) {
                Text(code).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Color(hex: 0xE6E6E6))
                    .textSelection(.enabled).fixedSize(horizontal: true, vertical: true).padding(12)
            }
            .scrollIndicators(.automatic)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x1B1B1F)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct Thinking: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill([Theme.lime, Theme.pink, Theme.cyan][i]).frame(width: 8, height: 8)
                    .scaleEffect(on ? 1 : 0.6)
                    .opacity(on ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: on)
            }
        }
        .padding(.vertical, 8)
        .onAppear { on = true }
    }
}

/// The assistant's face: a soft, slowly turning gradient orb with a sparkle.
/// The slide-over look (fixed width, shadow) when the chat isn't its own tab.
private struct PanelChrome: ViewModifier {
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded {
            content.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.canvas)
        } else {
            content
                .sheetFrame(width: 440)
                .frame(maxHeight: .infinity)
                .background(Theme.canvas)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
                .shadow(color: .black.opacity(0.12), radius: 24, x: -8)
        }
    }
}

/// Past conversations, to pick up where you left off.
struct PastChatsMenu: View {
    @ObservedObject private var store = AssistantStore.shared

    var body: some View {
        Menu {
            if store.chats.isEmpty { Text("No past chats yet") }
            ForEach(store.chats.prefix(25)) { c in
                Button { store.open(c.id) } label: {
                    if c.id == store.currentID { Label(c.title, systemImage: "checkmark") } else { Text(c.title) }
                }
            }
        } label: { Image(systemName: "clock.arrow.circlepath") }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Past chats")
        .disabled(store.busy)
    }
}

/// The AI tab: your past chats on the side and the conversation in the middle.
struct AssistantTabView: View {
    @ObservedObject private var store = AssistantStore.shared
    @State private var hovered: UUID?

    var body: some View {
        if Platform.isPhone {
            AssistantPanel(embedded: true)
        } else {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Button { store.newChat() } label: {
                        Label("New chat", systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SoftButtonStyle()).disabled(store.busy)
                    Text("Past chats").font(Theme.ui(11, weight: .bold)).foregroundStyle(Theme.inkMuted).padding(.top, 6)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if store.chats.isEmpty {
                                Text("Your conversations will show up here.").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                            }
                            ForEach(store.chats) { c in chatRow(c) }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .padding(16)
                .frame(width: 270)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.card.opacity(0.5))
                Rectangle().fill(Theme.line).frame(width: 1)
                AssistantPanel(embedded: true).frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chatRow(_ c: AssistantStore.ChatInfo) -> some View {
        let current = c.id == store.currentID
        return Button { store.open(c.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).font(Theme.ui(13, weight: current ? .semibold : .regular)).lineLimit(2).multilineTextAlignment(.leading)
                Text(c.updated.formatted(.relative(presentation: .named))).font(Theme.ui(10)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(current ? Theme.lime.opacity(0.35) : hovered == c.id ? Theme.cardHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? c.id : nil }
        .contextMenu { Button("Delete chat", role: .destructive) { store.delete(c.id) } }
        .disabled(store.busy)
    }
}

struct AssistantAvatar: View {
    var size: CGFloat = 32
    var busy = false

    private static let colors: [Color] = [Color(hex: 0xC6F432), Color(hex: 0x3DDC97), Color(hex: 0x22D3EE), Color(hex: 0x8B7CF6), Color(hex: 0xF472B6), Color(hex: 0xC6F432)]

    /// One crisp orb everywhere (Mac and iPhone): a colour wheel with a soft highlight and a white spark.
    /// It only turns while the assistant is working, so it never wobbles inside toolbars.
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !busy)) { t in
            let angle = busy ? (t.date.timeIntervalSinceReferenceDate * 120).truncatingRemainder(dividingBy: 360) : 30
            ZStack {
                Circle().fill(AngularGradient(colors: Self.colors, center: .center, angle: .degrees(angle)))
                Circle().fill(RadialGradient(colors: [.white.opacity(0.65), .white.opacity(0)], center: UnitPoint(x: 0.32, y: 0.26),
                                             startRadius: 0, endRadius: size * 0.62))
                Image(systemName: "sparkle").font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: size * 0.05, y: size * 0.02)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: max(0.5, size * 0.025)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The orb as a small full stop after the "joshu" wordmark: the assistant's colours, no spark.
struct OrbDot: View {
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().fill(AngularGradient(colors: [Color(hex: 0xC6F432), Color(hex: 0x3DDC97), Color(hex: 0x22D3EE), Color(hex: 0x8B7CF6),
                                                   Color(hex: 0xF472B6), Color(hex: 0xC6F432)], center: .center, angle: .degrees(30)))
            Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .white.opacity(0)], center: UnitPoint(x: 0.32, y: 0.26),
                                         startRadius: 0, endRadius: size * 0.6))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Colours for the "done" cards in the chat, by what was made.
enum ActionTint {
    static func color(for symbol: String) -> Color {
        switch symbol {
        case let s where s.contains("mappin") || s.contains("location"): Theme.mint
        case let s where s.contains("creditcard") || s.contains("banknote") || s.contains("target") || s.contains("doc.text"): Theme.peach
        case let s where s.contains("calendar") || s.contains("clock"): Theme.cyan
        case let s where s.contains("book"): Theme.lavender
        case let s where s.contains("brain") || s.contains("heart"): Theme.pink
        case let s where s.contains("flag") || s.contains("star"): Theme.sand
        case let s where s.contains("person"): Theme.mint
        default: Theme.lime
        }
    }
}

/// A place the assistant saved: a little map with the pin, the address and directions.
struct PlaceChatCard: View {
    let place: ChatPlace
    let note: String
    let undo: () -> Void

    private var category: PlaceCategory { PlaceCategory(rawValue: place.category) ?? .other }
    private var hasPin: Bool { place.lat != 0 || place.lon != 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasPin {
                let c = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
                Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 700, longitudinalMeters: 700)), interactionModes: []) {
                    Marker(place.name, systemImage: category.symbol, coordinate: c).tint(category.color)
                }
                .frame(height: 120)
                .allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                    Text(note).font(Theme.ui(11, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Button("Undo", action: undo).buttonStyle(.plain).font(Theme.ui(11, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: category.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                        .frame(width: 32, height: 32).background(Circle().fill(category.color))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(Theme.ui(15, weight: .semibold)).lineLimit(2)
                        Text([category.title, place.address].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(Theme.ui(11)).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                    }
                }
                DirectionsMenu(name: place.name, address: place.address, lat: hasPin ? place.lat : nil, lon: hasPin ? place.lon : nil, link: place.link)
            }
            .padding(12)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(category.color.opacity(0.6)))
    }
}
