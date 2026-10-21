import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var state: AppState
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var selection: Note?
    @State private var showJournal = false
    @State private var query = ""

    private var visible: [Note] {
        notes.filter { $0.isJournal == showJournal }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.pinned ? 1 : 0, showJournal ? $0.createdAt : $0.updatedAt) > ($1.pinned ? 1 : 0, showJournal ? $1.createdAt : $1.updatedAt) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(get: { !showJournal }, set: { showJournal = !$0 })) {
                        Text("Notes").frame(maxWidth: .infinity)
                    }
                    Toggle(isOn: $showJournal) { Text("Journal").frame(maxWidth: .infinity) }
                }
                .toggleStyle(PillToggleStyle())

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
                    TextField("Search", text: $query).textFieldStyle(.plain)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))

                Button { newNote() } label: {
                    Label(showJournal ? "Today's entry" : "New note", systemImage: showJournal ? "sun.max" : "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visible) { note in
                            NoteRow(note: note, selected: selection == note).onTapGesture { selection = note }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .frame(width: 300)

            Group {
                if let selection, notes.contains(selection) {
                    if selection.isJournal {
                        JournalEditor(note: selection) {
                            context.delete(selection)
                            self.selection = nil
                        }
                        .id(selection.persistentModelID)
                    } else {
                        NoteEditor(note: selection) {
                            context.delete(selection)
                            self.selection = nil
                        }
                        .id(selection.persistentModelID)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "text.book.closed").font(.system(size: 40, weight: .light))
                        Text("Pick a note or start a new one").font(Theme.display(20, weight: .regular))
                    }
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(showJournal ? Theme.blush : Theme.card))
        }
        .padding(.horizontal, 32)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .onAppear {
            if state.openTodayJournal {
                state.openTodayJournal = false
                showJournal = true
                newNote()
                return
            }
            if selection == nil, let todays = notes.first(where: { $0.isJournal && $0.createdAt.isToday }), todays.body.isEmpty {
                showJournal = true
                selection = todays
            }
            if selection == nil { selection = visible.first }
        }
    }

    private func newNote() {
        if showJournal, let existing = notes.first(where: { $0.isJournal && $0.createdAt.isToday }) {
            selection = existing
            return
        }
        let note = showJournal
            ? Note(title: Date.now.formatted(date: .complete, time: .omitted), isJournal: true)
            : Note(title: "")
        context.insert(note)
        selection = note
    }
}

private struct NoteRow: View {
    let note: Note
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title.isEmpty ? "Untitled" : note.title).font(Theme.ui(14, weight: .semibold)).lineLimit(1)
                Spacer()
                if note.pinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
                if note.isJournal, note.mood > 0 { Text(Mood.faces[note.mood]) }
            }
            Text(note.body.isEmpty ? "No content" : note.body)
                .font(Theme.ui(12)).lineLimit(2)
                .foregroundStyle(selected ? Theme.onInverse.opacity(0.7) : Theme.inkSecondary)
            Text(Fmt.relativeDay(note.isJournal ? note.createdAt : note.updatedAt))
                .font(Theme.ui(11))
                .foregroundStyle(selected ? Theme.onInverse.opacity(0.5) : Theme.inkMuted)
        }
        .foregroundStyle(selected ? Theme.onInverse : Theme.ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Theme.inverse : Theme.card))
        .contentShape(Rectangle())
    }
}

private struct NoteEditor: View {
    @Bindable var note: Note
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(note.isJournal ? "Journal" : "Edited \(note.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                Spacer()
                Button { note.pinned.toggle() } label: { Image(systemName: note.pinned ? "pin.fill" : "pin") }
                    .buttonStyle(.plain).help("Pin")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("Delete")
            }
            TextField("Title", text: $note.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.display(32))
            TextEditor(text: $note.body)
                .font(Theme.display(17, weight: .regular))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
        }
        .foregroundStyle(Theme.ink)
        .padding(32)
        .onChange(of: note.body) { note.updatedAt = .now }
        .onChange(of: note.title) { note.updatedAt = .now }
    }
}

struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .font(Theme.ui(14, weight: .medium))
                .foregroundStyle(configuration.isOn ? Theme.onInverse : Theme.ink)
                .padding(.vertical, 9)
                .background(Capsule().fill(configuration.isOn ? Theme.inverse : Theme.card))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Journal with Claude check-in

private struct JournalEditor: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var apple: AppleSync
    @ObservedObject private var ai = AIAssistant.shared
    @Bindable var note: Note
    let onDelete: () -> Void

    @State private var draft = ""
    @State private var busy = false
    @State private var error: String?
    @State private var received = ""      // streamed so far
    @State private var shown = ""         // what the reader sees, revealed at a calm pace
    @State private var revealing = false
    @State private var streamStart = Date.distantFuture
    @State private var undoBody: String?
    @FocusState private var inputFocused: Bool

    private var allTurns: [JournalTurn] { note.chat?.turns.filter { !$0.hidden } ?? [] }
    /// While a reply is still being revealed, its finished turn stays hidden behind the live bubble.
    private var turns: [JournalTurn] {
        if revealing, let last = allTurns.last, last.role == "assistant", last.at >= streamStart {
            return Array(allTurns.dropLast())
        }
        return allTurns
    }
    private var isToday: Bool { note.createdAt.isToday }

    var body: some View {
        HStack(spacing: 0) {
            writing
            Rectangle().fill(Theme.line).frame(width: 1)
            chat.frame(width: 400)
        }
    }

    // Left: the entry itself

    private var writing: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Journal").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("Delete entry")
            }
            TextField("Title", text: $note.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.display(30))
            HStack(spacing: 6) {
                Text("Mood").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkSecondary).padding(.trailing, 4)
                ForEach(1...5, id: \.self) { m in
                    Button {
                        note.mood = note.mood == m ? 0 : m
                        note.moodSetByUser = note.mood != 0
                    } label: {
                        Text(Mood.faces[m]).font(.system(size: 20))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(note.mood == m ? Theme.lime : Theme.canvas.opacity(0.6)))
                            .opacity(note.mood == 0 || note.mood == m ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .help(Mood.words[m])
                }
                if note.mood > 0 {
                    Text(Mood.words[note.mood]).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.inkSecondary).padding(.leading, 4)
                }
            }
            ZStack(alignment: .topLeading) {
                if note.body.isEmpty {
                    Text("Write freely, or chat with Claude on the right and let it write the entry for you.")
                        .font(Theme.display(17, weight: .regular))
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.top, 1).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note.body)
                    .font(Theme.display(17, weight: .regular))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(32)
        .onChange(of: note.body) { note.updatedAt = .now }
    }

    // Right: conversation

    private var chat: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.stickerInk)
                    .frame(width: 28, height: 28).background(Circle().fill(Theme.lime))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Check-in with Claude").font(Theme.ui(14, weight: .semibold))
                    Text("Talk it through, then turn it into your entry").font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            }
            .padding(16)

            if !ai.hasKey {
                VStack(spacing: 12) {
                    Spacer()
                    Text("Add your Anthropic API key to chat about your day.").font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                    SettingsLink { Text("Open Settings") }.buttonStyle(SoftButtonStyle())
                    Spacer()
                }
                .padding(24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            if turns.isEmpty && !busy {
                                VStack(spacing: 14) {
                                    Text(isToday ? "How was today?" : "Look back on this day")
                                        .font(Theme.display(22))
                                    Text("Claude will ask about your mood and what you got up to, one question at a time.")
                                        .font(Theme.ui(13)).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
                                    Button { stream { try await JournalCompanion.start(note: note, context: context, apple: apple, onText: $0) } } label: {
                                        Label("Start check-in", systemImage: "bubble.left.and.text.bubble.right.fill")
                                    }
                                    .buttonStyle(PrimaryButtonStyle()).frame(width: 200)
                                }
                                .padding(.top, 60)
                            }
                            ForEach(turns) { Bubble(turn: $0).id($0.id) }
                            if revealing && !shown.isEmpty {
                                Bubble(turn: JournalTurn(role: "assistant", text: shown)).id("live")
                            } else if busy {
                                HStack { TypingDots(); Spacer() }.id("typing")
                            }
                            if let error {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
                                    Text(error).font(Theme.ui(12))
                                    Spacer()
                                    Button("Retry") { stream { try await JournalCompanion.reply(note: note, onText: $0) } }
                                        .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold))
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.canvas))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: turns.count) {
                        withAnimation { proxy.scrollTo(turns.last?.id, anchor: .bottom) }
                    }
                    .onChange(of: busy) { if busy { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
                    .onChange(of: shown) { proxy.scrollTo("live", anchor: .bottom) }
                }

                if !turns.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            run { undoBody = try await JournalCompanion.writeEntry(note: note) }
                        } label: {
                            Label(note.body.isEmpty ? "Write my entry" : "Update my entry", systemImage: "wand.and.stars")
                        }
                        if let previous = undoBody {
                            Button("Undo") { note.body = previous; undoBody = nil }
                                .buttonStyle(.plain).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(busy || !turns.contains { $0.role == "user" })
                    .padding(.bottom, 8)
                }

                HStack(spacing: 8) {
                    TextField("Reply…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.ui(14))
                        .lineLimit(1...5)
                        .focused($inputFocused)
                        .onSubmit(sendDraft)
                        .disabled(busy)
                    Button(action: sendDraft) {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.onInverse)
                            .frame(width: 30, height: 30).background(Circle().fill(Theme.inverse))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.canvas))
                .padding([.horizontal, .bottom], 14)
            }
        }
        .background(Theme.canvas.opacity(0.35))
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        draft = ""
        stream { try await JournalCompanion.send(text, note: note, context: context, apple: apple, onText: $0) }
    }

    /// Runs a streaming request and reveals the reply gently, a few characters at a time.
    private func stream(_ work: @escaping (@escaping @MainActor (String) -> Void) async throws -> Void) {
        busy = true
        error = nil
        received = ""
        shown = ""
        revealing = true
        streamStart = .now
        var finished = false
        Task {
            // Typewriter: catch up with the stream at a calm, readable pace.
            while !finished || shown.count < received.count {
                if shown.count < received.count {
                    let next = received.dropFirst(shown.count).prefix(3)
                    shown += next
                    try? await Task.sleep(for: .milliseconds(next.contains(where: { ".?!".contains($0) }) ? 220 : 28))
                } else {
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
            revealing = false
            busy = false
            inputFocused = true
        }
        Task {
            do {
                try await work { text in received = text }
            } catch {
                self.error = error.localizedDescription
            }
            finished = true
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
            busy = false
            inputFocused = true
        }
    }
}

private struct Bubble: View {
    let turn: JournalTurn
    var mine: Bool { turn.role == "user" }

    /// Claude separates thoughts with a blank line; each becomes its own soft bubble.
    private var parts: [String] {
        mine ? [turn.text] : turn.text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                HStack {
                    if mine { Spacer(minLength: 40) }
                    Text(part)
                        .font(Theme.ui(14))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .foregroundStyle(mine ? Theme.onInverse : Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(mine ? Theme.inverse : Theme.canvas))
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    if !mine { Spacer(minLength: 40) }
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: parts.count)
    }
}

private struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(Theme.inkMuted).frame(width: 7, height: 7)
                    .opacity(on ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: on)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.canvas))
        .onAppear { on = true }
    }
}
