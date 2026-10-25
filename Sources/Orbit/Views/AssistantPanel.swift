import SwiftUI
import SwiftData
import MapKit

/// Slide-over chat with Claude that can create things in Orbit. Opens from the ✦ button or ⌘J.
struct AssistantPanel: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @EnvironmentObject private var state: AppState
    @ObservedObject private var store = AssistantStore.shared
    @ObservedObject private var ai = AIAssistant.shared

    @AppStorage("assistantName") private var assistantName = "Ask"
    @AppStorage("assistantSpeaks") private var speaks = false
    @ObservedObject private var dictation = Dictation.shared
    @ObservedObject private var speaker = Speaker.shared
    @State private var draft = ""
    @State private var attachments: [ChatAttachment] = []
    @State private var picking = false
    @State private var dropping = false
    @State private var fileError: String?
    /// The last message was spoken, so keep the conversation going by voice.
    @State private var voiceTurn = false
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
                    Text("Add your Anthropic API key to chat with \(assistantName).").font(Theme.ui(13)).multilineTextAlignment(.center)
                    OpenSettingsLink { Text("Open Settings") }.buttonStyle(SoftButtonStyle())
                    Spacer()
                }
                .foregroundStyle(Theme.inkSecondary)
                .padding(24)
            } else {
                messages
                composer
            }
        }
        .sheetFrame(width: 440)
        .frame(maxHeight: .infinity)
        .background(Theme.canvas)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
        .shadow(color: .black.opacity(0.12), radius: 24, x: -8)
        .onAppear { focused = true; sendSeed() }
        .onChange(of: state.assistantSeed) { sendSeed() }
        .onChange(of: store.busy) { _, busy in if !busy { replyFinished() } }
        .onDisappear { dictation.cancel(); speaker.stop(); voiceTurn = false }
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
    private func replyFinished() {
        guard speaks, store.error == nil, let last = store.items.last(where: { $0.role == .assistant }) else { voiceTurn = false; return }
        speaker.speak(last.text) {
            guard voiceTurn, state.assistantOpen else { return }
            Task { await dictation.start { heard in sendVoice(heard) } }
        }
    }

    private func sendVoice(_ heard: String) {
        guard !heard.isEmpty else { voiceTurn = false; return }
        voiceTurn = true
        send(heard)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AssistantAvatar(size: 36, busy: store.busy || speaker.speaking)
            VStack(alignment: .leading, spacing: 1) {
                Text(assistantName).font(Theme.display(20))
                HStack(spacing: 5) {
                    Circle().fill(store.busy ? Theme.orange : Theme.good).frame(width: 6, height: 6)
                    Text(store.busy ? "Thinking…" : speaker.speaking ? "Speaking…" : "Here for anything").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer()
            Button {
                speaks.toggle()
                if !speaks { speaker.stop(); voiceTurn = false }
            } label: { Image(systemName: speaks ? "speaker.wave.2.fill" : "speaker.slash") }
                .buttonStyle(.plain).foregroundStyle(speaks ? Theme.ink : Theme.inkMuted)
                .help(speaks ? "Reading replies aloud. Click to turn off." : "Read replies aloud")
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
                        VStack(alignment: .leading, spacing: 14) {
                            AssistantAvatar(size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(greeting).font(Theme.display(28))
                                Text("What's on your mind? Ask me anything, or tell me what to set up: tasks, plans, places, money, books.")
                                    .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(suggestions, id: \.0) { text, symbol, tint in
                                    Button { send(text) } label: {
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
        if !dictation.listening && t == draft.trimmingCharacters(in: .whitespacesAndNewlines) { voiceTurn = false }
        draft = ""
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

/// Assistant text with light markdown (bold, italics, links) and calm line spacing.
struct AssistantText: View {
    let text: String

    var body: some View {
        let attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        Text(attributed).font(Theme.ui(14)).lineSpacing(3).textSelection(.enabled)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(alignment: .leading)
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
struct AssistantAvatar: View {
    var size: CGFloat = 32
    var busy = false
    @State private var turn = false

    var body: some View {
        ZStack {
            Circle().fill(AngularGradient(colors: [Theme.lime, Theme.mint, Theme.cyan, Theme.purple, Theme.pink, Theme.lime], center: .center))
                .rotationEffect(.degrees(turn ? 360 : 0))
                .blur(radius: size * 0.04)
            Circle().fill(.white.opacity(0.25)).padding(size * 0.18)
            Image(systemName: "sparkles").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(Theme.stickerInk)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onAppear { withAnimation(.linear(duration: busy ? 3 : 14).repeatForever(autoreverses: false)) { turn = true } }
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
