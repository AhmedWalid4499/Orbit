import SwiftUI
import SwiftData

/// More: every other part of Orbit.
struct PhoneMore: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("userName") private var userName = ""

    private let sections: [Tab] = [.insights, .habits, .notes, .reading, .bucket, .documents, .github]

    var body: some View {
        List {
            Section {
                ForEach(sections) { t in
                    NavigationLink(value: t) {
                        Label { Text(t.title).font(Theme.ui(16, weight: .medium)) } icon: { icon(t.symbol, color(t)) }
                    }
                }
            }
            Section {
                row("My Card", "person.text.rectangle.fill", Theme.pink) { state.cardOpen = true }
                row("Week in review", "chart.line.uptrend.xyaxis", Theme.mint) { state.reviewOpen = true }
                row("Plan tomorrow", "moon.stars.fill", Theme.lime) { state.planOpen = true }
                row("Search", "magnifyingglass", Theme.cyan) { state.searchOpen = true }
            }
            Section {
                row("Settings", "gearshape.fill", Theme.card) { state.settingsOpen = true }
            }
        }
        .navigationTitle("More")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { state.openAssistant() } label: {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.stickerInk)
                        .frame(width: 30, height: 30).background(Circle().fill(Theme.lime))
                }
            }
        }
    }

    private func color(_ t: Tab) -> Color {
        switch t {
        case .habits: Theme.orange
        case .notes: Theme.peach
        case .reading: Theme.purple
        case .bucket: Theme.cyan
        case .documents: Theme.mint
        case .insights: Theme.lime
        default: Theme.card
        }
    }

    private func icon(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.stickerInk)
            .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(color))
    }

    private func row(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title).font(Theme.ui(16, weight: .medium)).foregroundStyle(Theme.ink) } icon: { icon(symbol, color) }
        }
    }
}

// MARK: - Sections that use the Mac screens as they are (their grids adapt to the width)

struct PhoneHabits: View {
    var body: some View { HabitsView().phoneChrome("Habits") }
}

struct PhoneBucket: View {
    var body: some View { BucketListView().phoneChrome("Bucket list") }
}

struct PhoneDocuments: View {
    var body: some View { DocumentsView().phoneChrome("Documents") }
}

struct PhoneGitHub: View {
    var body: some View { GitHubView().phoneChrome("GitHub") }
}

// MARK: - Notes and journal

struct PhoneNotes: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var state: AppState
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var showJournal = false
    @State private var query = ""
    @State private var open: Note?

    private var visible: [Note] {
        notes.filter { $0.isJournal == showJournal }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.pinned ? 1 : 0, showJournal ? $0.createdAt : $0.updatedAt) > ($1.pinned ? 1 : 0, showJournal ? $1.createdAt : $1.updatedAt) }
    }

    var body: some View {
        List {
            Section {
                Picker("", selection: $showJournal) { Text("Notes").tag(false); Text("Journal").tag(true) }
                    .pickerStyle(.segmented).plainRow()
                Button { newNote() } label: {
                    Label(showJournal ? "Today's entry" : "New note", systemImage: showJournal ? "sun.max" : "square.and.pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle()).plainRow()
            }
            ForEach(visible) { note in
                Button { open = note } label: { NoteRow(note: note, selected: false) }
                    .buttonStyle(.plain).plainRow()
                    .swipeActions { Button(role: .destructive) { context.delete(note) } label: { Label("Delete", systemImage: "trash") } }
            }
            if visible.isEmpty { EmptyHint(symbol: "text.book.closed", text: showJournal ? "No journal entries yet." : "No notes yet.").plainRow() }
        }
        .listStyle(.plain)
        .searchable(text: $query)
        .navigationDestination(item: $open) { note in
            Group {
                if note.isJournal {
                    JournalEditor(note: note) { context.delete(note); open = nil }
                } else {
                    NoteEditor(note: note) { context.delete(note); open = nil }.padding(.horizontal, 16)
                }
            }
            .background(note.isJournal ? Theme.blush : Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if state.openTodayJournal {
                state.openTodayJournal = false
                showJournal = true
                newNote()
            }
        }
        .phoneChrome("Journal & Notes")
    }

    private func newNote() {
        if showJournal, let existing = notes.first(where: { $0.isJournal && $0.createdAt.isToday }) { open = existing; return }
        let note = showJournal ? Note(title: Date.now.formatted(date: .complete, time: .omitted), isJournal: true) : Note(title: "")
        context.insert(note)
        open = note
    }
}

// MARK: - Reading

struct PhoneReading: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @Query private var sessions: [ReadingSession]
    @AppStorage("readingGoal") private var readingGoal = 24

    @State private var shelf: String = ReadingStatus.reading.rawValue
    @State private var query = ""
    @State private var detail: Book?
    @State private var adding = false
    @State private var sources = false

    private var readThisYear: Int {
        let y = Calendar.current.component(.year, from: .now)
        return books.filter { $0.status == .read && ($0.finishedAt.map { Calendar.current.component(.year, from: $0) == y } ?? false) }.count
    }

    private var shown: [Book] {
        books.filter { shelf == "all" || $0.statusRaw == shelf }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ReadingStat(value: "\(readThisYear)/\(readingGoal)", label: "This year", color: Theme.pink)
                    ReadingStat(value: "\(ReadingTimer.minutes(sessions, since: .now.startOfWeek)) min", label: "This week", color: Theme.orange)
                    ReadingStat(value: "\(ReadingTimer.streak(sessions))", label: "Day streak", color: Theme.lime)
                }
                HStack(spacing: 10) {
                    Button { adding = true } label: { Label("Add book", systemImage: "plus") }.buttonStyle(SoftButtonStyle())
                    Button { sources = true } label: { Label("Goodreads sync", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(SoftButtonStyle())
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        chip("all", "All", "books.vertical.fill")
                        ForEach(ReadingStatus.allCases) { s in chip(s.rawValue, s.title, s.symbol) }
                        chip("highlights", "Highlights", "highlighter")
                    }
                }
                .scrollIndicators(.never)
                if shelf == "highlights" {
                    if highlights.isEmpty { EmptyHint(symbol: "highlighter", text: "Highlights from Kindle show up here after the Mac imports them.") }
                    ForEach(highlights.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.bookTitle.localizedCaseInsensitiveContains(query) }) {
                        HighlightRow(highlight: $0)
                    }
                } else {
                    if shown.isEmpty { EmptyHint(symbol: "books.vertical", text: "No books here yet.") }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)], spacing: 16) {
                        ForEach(shown) { b in BookTile(book: b).onTapGesture { detail = b } }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .searchable(text: $query, prompt: shelf == "highlights" ? "Search highlights" : "Search books")
        .sheet(item: $detail) { BookDetailSheet(book: $0) }
        .sheet(isPresented: $adding) { AddBookSheet(defaultCategory: nil) }
        .sheet(isPresented: $sources) { ReadingSourcesSheet() }
        .phoneChrome(Tab.reading.title)
    }

    private func chip(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button { withAnimation(.snappy) { shelf = id } } label: {
            Label(title, systemImage: symbol).font(Theme.ui(13, weight: .semibold))
                .foregroundStyle(shelf == id ? Theme.onInverse : Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(shelf == id ? Theme.inverse : Theme.card))
        }
        .buttonStyle(.plain)
    }
}
