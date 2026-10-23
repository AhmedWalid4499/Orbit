import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ReadingView: View {
    enum Filter: Hashable {
        case all, status(ReadingStatus), category(String)
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]
    @Query(sort: \BookCategory.createdAt) private var categories: [BookCategory]
    @AppStorage("readingGoal") private var yearlyGoal = 24

    @State private var filter: Filter = .all
    /// nil = all libraries; otherwise "goodreads", "kindle", "apple-books" or "mine".
    @State private var library: String?
    @State private var query = ""
    @State private var sort = "Recently added"
    @State private var adding = false
    @State private var sources = false
    @State private var editing: Book?
    @State private var newCategory = false
    @State private var renaming: BookCategory?
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @Query(sort: \ReadingSession.start, order: .reverse) private var sessions: [ReadingSession]
    @ObservedObject private var timer = ReadingTimer.shared
    @State private var importingHighlights = false
    @State private var highlightMessage: String?
    @State private var highlightQuery = ""

    private var year: Int { Calendar.current.component(.year, from: .now) }
    private var readThisYear: [Book] {
        books.filter { $0.status == .read && ($0.finishedAt.map { Calendar.current.component(.year, from: $0) == year } ?? false) }
    }
    private var reading: [Book] { books.filter { $0.status == .reading } }

    private var visible: [Book] {
        var list = books
        switch filter {
        case .all: break
        case .status(let s): list = list.filter { $0.status == s }
        case .category(let c): list = list.filter { $0.categories.contains(c) }
        }
        switch library {
        case nil: break
        case "mine": list = list.filter { $0.sources.isEmpty ? !BookLibrary.importedSources.contains($0.source) : $0.sources.contains { !BookLibrary.importedSources.contains($0) } }
        case let lib?: list = list.filter { $0.sources.contains(lib) || $0.source == lib }
        }
        if !query.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case "Title": list.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case "Author": list.sort { $0.author.localizedCompare($1.author) == .orderedAscending }
        case "Rating": list.sort { $0.rating > $1.rating }
        case "Recently finished": list.sort { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        default: break
        }
        return list
    }

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            sidebar.frame(width: 240)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statRow
                    libraryTabs
                    if library == "highlights" {
                        highlightsList
                    } else {
                        if filter == .all && library == nil && query.isEmpty && !reading.isEmpty { currentlyReading }
                        shelf
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 32)
        .padding(.top, 10)
        .sheet(isPresented: $adding) { AddBookSheet(defaultCategory: currentCategory) }
        .sheet(isPresented: $sources) { ReadingSourcesSheet() }
        .sheet(item: $editing) { BookDetailSheet(book: $0) }
        .sheet(isPresented: $newCategory) { CategoryEditor(category: nil) }
        .sheet(item: $renaming) { CategoryEditor(category: $0) }
        .sheet(item: Binding(get: { timer.justFinished }, set: { timer.justFinished = $0 })) { FinishedReadingSheet(session: $0) }
        .fileImporter(isPresented: $importingHighlights, allowedContentTypes: [.plainText, .html, .text]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let items = try KindleHighlights.parse(fileAt: url)
                let source = url.pathExtension.lowercased() == "txt" ? "kindle-clippings" : "kindle-notebook"
                let (added, skipped) = KindleHighlights.importHighlights(items, source: source, context: context)
                highlightMessage = "Imported \(added) highlight\(added == 1 ? "" : "s")" + (skipped > 0 ? " (\(skipped) already here)." : ".")
            } catch {
                highlightMessage = error.localizedDescription
            }
        }
        .onAppear { timer.restore(context: context) }
    }

    private var currentCategory: String? {
        if case .category(let c) = filter { return c }
        return nil
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(Tab.reading.title).font(Theme.display(38))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
                TextField("Search books", text: $query).textFieldStyle(.plain).frame(width: 150)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Theme.card))
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(["Recently added", "Recently finished", "Title", "Author", "Rating"], id: \.self) { Text($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down").frame(width: 36, height: 36).background(Circle().fill(Theme.card))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Button { sources = true } label: { Label("Connect & import", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(SoftButtonStyle())
            Button { adding = true } label: { Label("Add book", systemImage: "plus") }
                .buttonStyle(SoftButtonStyle())
        }
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            goalTile
            ReadingStat(value: "\(reading.count)", label: "Reading now", color: Theme.lime)
            ReadingStat(value: "\(books.filter { $0.status == .toRead }.count)", label: "To read", color: Theme.cyan)
            ReadingStat(value: "\(books.filter { $0.status == .read }.count)", label: "Read all time", color: Theme.purple)
            ReadingStat(value: "\(ReadingTimer.minutes(sessions, since: Date.now.startOfWeek)) min",
                        label: ReadingTimer.streak(sessions) > 1 ? "This week · \(ReadingTimer.streak(sessions))-day streak" : "Read this week",
                        color: Theme.orange)
        }
    }

    private var goalTile: some View {
        let ratio = yearlyGoal > 0 ? min(Double(readThisYear.count) / Double(yearlyGoal), 1) : 0
        return HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.black.opacity(0.12), lineWidth: 6)
                Circle().trim(from: 0, to: ratio).stroke(Color(hex: 0x111111), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(readThisYear.count)/\(yearlyGoal)").font(Theme.display(26))
                Stepper("\(String(year)) goal", value: $yearlyGoal, in: 1...365).font(Theme.ui(12, weight: .semibold))
            }
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.pink))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ReadingFilterRow(title: "All books", symbol: "books.vertical.fill", count: books.count, selected: filter == .all) { filter = .all }
                ForEach(ReadingStatus.allCases) { s in
                    ReadingFilterRow(title: s.title, symbol: s.symbol, count: books.filter { $0.status == s }.count,
                                     selected: filter == .status(s)) { filter = .status(s) }
                }
                HStack {
                    Text("Categories").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Button { newCategory = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkSecondary).help("New category")
                }
                .padding(.top, 18).padding(.bottom, 4).padding(.horizontal, 12)
                if categories.isEmpty {
                    Button { newCategory = true } label: { Label("Create a category", systemImage: "tag") }
                        .buttonStyle(SoftButtonStyle()).padding(.leading, 6)
                }
                ForEach(categories) { c in
                    ReadingFilterRow(title: c.name, symbol: c.symbol, count: books.filter { $0.categories.contains(c.name) }.count,
                                     selected: filter == .category(c.name), tint: BookPalette.color(c.colorIndex)) {
                        filter = .category(c.name)
                    }
                    .contextMenu {
                        Button("Edit…") { renaming = c }
                        Button("Delete", role: .destructive) { delete(c) }
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func delete(_ c: BookCategory) {
        for b in books where b.categories.contains(c.name) { b.categories.removeAll { $0 == c.name } }
        if filter == .category(c.name) { filter = .all }
        context.delete(c)
    }

    // MARK: Shelves

    private var currentlyReading: some View { CurrentlyReadingStrip(books: reading) { editing = $0 } }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(shelfTitle).font(Theme.display(22))
                Text("\(visible.count)").font(Theme.display(22, weight: .regular)).foregroundStyle(Theme.inkMuted)
            }
            if visible.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical").font(.system(size: 36, weight: .light))
                    Text(books.isEmpty ? "Your shelf is empty. Add a book, or connect Goodreads, Apple Books or Kindle."
                                       : "No books here yet.")
                        .font(Theme.ui(14))
                    if books.isEmpty {
                        HStack {
                            Button("Add book") { adding = true }.buttonStyle(SoftButtonStyle())
                            Button("Connect & import") { sources = true }.buttonStyle(SoftButtonStyle())
                        }
                    }
                }
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20, alignment: .top)], spacing: 24) {
                ForEach(visible) { b in
                    BookTile(book: b).onTapGesture { editing = b }
                        .contextMenu {
                            Menu("Status") { ForEach(ReadingStatus.allCases) { s in Button(s.title) { b.status = s } } }
                            Menu("Category") {
                                ForEach(categories) { c in
                                    Toggle(c.name, isOn: Binding(
                                        get: { b.categories.contains(c.name) },
                                        set: { on in if on { b.categories.append(c.name) } else { b.categories.removeAll { $0 == c.name } } }))
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { context.delete(b) }
                        }
                }
            }
        }
    }

    // MARK: Highlights

    private var highlightsList: some View {
        let filtered = highlights.filter {
            highlightQuery.isEmpty || $0.text.localizedCaseInsensitiveContains(highlightQuery) || $0.bookTitle.localizedCaseInsensitiveContains(highlightQuery)
        }
        let grouped = Dictionary(grouping: filtered, by: \.bookTitle).sorted { $0.key.localizedCompare($1.key) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("Highlights").font(Theme.display(22))
                Text("\(highlights.count)").font(Theme.display(22, weight: .regular)).foregroundStyle(Theme.inkMuted)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
                    TextField("Search highlights", text: $highlightQuery).textFieldStyle(.plain).frame(width: 160)
                }
                .padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(Theme.card))
                Button { importingHighlights = true } label: { Label("Import Kindle highlights…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(SoftButtonStyle())
            }
            if let highlightMessage { Text(highlightMessage).font(Theme.ui(12, weight: .medium)) }
            if highlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bring in your Kindle highlights and notes:").font(Theme.ui(14, weight: .semibold))
                    Text("• **Kindle e-reader:** plug it in with USB, open it in Finder, and import **documents › My Clippings.txt**.")
                    Text("• **Kindle app on iPhone, iPad or Android:** open a book › Notebook › Share › **Export notebook**, send the file to your Mac, and import it.")
                    Text("Orbit matches highlights to the books in your library and skips ones it already has.").foregroundStyle(Theme.inkMuted)
                }
                .font(Theme.ui(13)).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
            }
            ForEach(grouped, id: \.key) { title, items in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(title).font(Theme.ui(16, weight: .semibold))
                        if let a = items.first?.author, !a.isEmpty { Text(a).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary) }
                        Spacer()
                        Text("\(items.count)").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    }
                    ForEach(items) { HighlightRow(highlight: $0) }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
            }
        }
    }

    /// All · Goodreads · Kindle · Books · Added by me
    private var libraryTabs: some View {
        let tabs: [(String?, String, String, Color)] = [
            (nil, "All", "books.vertical.fill", Theme.ink),
            ("goodreads", "Goodreads", "g.circle.fill", Theme.peach),
            ("kindle", "Kindle", "flame.fill", Theme.cyan),
            ("apple-books", "Books", "book.fill", Theme.orange),
            ("mine", "Added by me", "person.fill", Theme.mint),
            ("highlights", "Highlights", "highlighter", Theme.lime),
        ]
        return HStack(spacing: 8) {
            ForEach(tabs, id: \.1) { key, title, symbol, color in
                let count = key == "highlights" ? highlights.count : key == nil ? books.count : books.filter { b in
                    key == "mine" ? !(b.sources.isEmpty ? [b.source] : b.sources).allSatisfy(BookLibrary.importedSources.contains)
                                  : (b.sources.contains(key!) || b.source == key!)
                }.count
                if key == nil || key == "highlights" || count > 0 {
                    Button { withAnimation(.snappy) { library = key } } label: {
                        HStack(spacing: 7) {
                            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                                .foregroundStyle(key == nil ? (library == nil ? Theme.onInverse : Theme.ink) : Theme.stickerInk)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(key == nil ? .clear : color))
                            Text(title).font(Theme.ui(13, weight: .semibold))
                            Text("\(count)").font(Theme.ui(11, weight: .semibold)).opacity(0.6)
                        }
                        .foregroundStyle(library == key ? Theme.onInverse : Theme.ink)
                        .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
                        .background(Capsule().fill(library == key ? Theme.inverse : Theme.card))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }

    private var shelfTitle: String {
        switch filter {
        case .all: "All books"
        case .status(let s): s.title
        case .category(let c): c
        }
    }
}

// MARK: - Pieces

struct ReadingStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.ui(12, weight: .semibold)).opacity(0.8)
        }
        .foregroundStyle(Theme.stickerInk)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color))
    }
}

struct ReadingFilterRow: View {
    let title: String
    let symbol: String
    let count: Int
    let selected: Bool
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint != nil ? Theme.stickerInk : (selected ? Theme.onInverse : Theme.ink))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(tint ?? .clear))
                Text(title).font(Theme.ui(14, weight: .medium)).lineLimit(1)
                Spacer()
                if count > 0 { Text("\(count)").font(Theme.ui(12, weight: .semibold)).opacity(0.7) }
            }
            .foregroundStyle(selected ? Theme.onInverse : Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(selected ? Theme.inverse : (hovering ? Theme.card : .clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct BookCover: View {
    let book: Book

    var body: some View {
        ZStack {
            placeholder
            if let url = URL(string: book.coverURL), !book.coverURL.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 4)
    }

    private var placeholder: some View {
        let color = BookPalette.color(book.title.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(Theme.display(13)).lineLimit(4)
                Text(book.author).font(Theme.ui(9, weight: .medium)).opacity(0.7).lineLimit(2)
            }
            .foregroundStyle(Theme.stickerInk)
            .padding(8)
        }
    }
}

/// The books you're reading now, with progress and a reading timer. Shown at the top of Reading on Mac and iPhone.
struct CurrentlyReadingStrip: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var timer = ReadingTimer.shared
    let books: [Book]
    var onOpen: (Book) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Currently reading").font(Theme.display(22))
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(books) { b in
                        HStack(alignment: .top, spacing: 14) {
                            BookCover(book: b).frame(width: 84, height: 126)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(b.title).font(Theme.ui(15, weight: .semibold)).lineLimit(2)
                                Text(b.author).font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                                Spacer()
                                Text("\(Int(b.progress * 100))%\(b.pageCount > 0 ? " · page \(Int(b.progress * Double(b.pageCount))) of \(b.pageCount)" : "")")
                                    .font(Theme.ui(11, weight: .medium)).foregroundStyle(Theme.inkSecondary)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Theme.line)
                                        Capsule().fill(Theme.ink).frame(width: max(6, g.size.width * b.progress))
                                    }
                                }
                                .frame(height: 6)
                                if timer.active?.bookUUID == b.uuid && !b.uuid.isEmpty {
                                    Button { timer.stop(context: context) } label: { Label("Stop", systemImage: "stop.fill") }
                                        .buttonStyle(SoftButtonStyle())
                                } else {
                                    Button { timer.start(b, context: context) } label: { Label("Start reading", systemImage: "timer") }
                                        .buttonStyle(SoftButtonStyle())
                                }
                            }
                            .frame(width: 180)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(b) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

struct BookTile: View {
    let book: Book
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCover(book: book)
                .aspectRatio(2/3, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if book.status != .toRead {
                        Image(systemName: book.status.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.stickerInk)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(book.status == .read ? Theme.lime : book.status == .reading ? Theme.cyan : Theme.peach))
                            .padding(6)
                    }
                }
                .scaleEffect(hovering ? 1.03 : 1)
                .animation(.spring(response: 0.25), value: hovering)
            Text(book.title).font(Theme.ui(13, weight: .semibold)).lineLimit(2)
            Text(book.author).font(Theme.ui(11)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
            if book.rating > 0 { Stars(rating: book.rating, size: 10) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            ForEach(ReadingStatus.allCases) { s in
                Button { withAnimation { book.status = s } } label: {
                    Label(s == .reading ? "Mark as currently reading" : "Move to \(s.title)", systemImage: book.status == s ? "checkmark" : s.symbol)
                }
            }
        }
    }
}

struct Stars: View {
    let rating: Int
    var size: CGFloat = 12
    var onChange: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(i <= rating ? Theme.orange : Theme.inkMuted)
                    .onTapGesture { onChange?(rating == i ? 0 : i) }
            }
        }
    }
}

// MARK: - Sheets

struct AddBookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BookCategory.createdAt) private var categories: [BookCategory]
    let defaultCategory: String?

    @State private var query = ""
    @State private var results: [OpenLibrary.Result] = []
    @State private var searching = false
    @State private var status: ReadingStatus = .toRead
    @State private var picked: Set<String> = []
    @State private var manualTitle = ""
    @State private var manualAuthor = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a book").font(Theme.display(28))
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
                TextField("Search by title, author or ISBN", text: $query)
                    .textFieldStyle(.plain).font(Theme.ui(15))
                    .onSubmit(search)
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))

            HStack {
                if Platform.isPhone {
                    Picker("Shelf", selection: $status) { ForEach(ReadingStatus.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                        .pickerStyle(.menu)
                    Spacer()
                } else {
                    Picker("Shelf", selection: $status) { ForEach(ReadingStatus.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                }
            }
            if !categories.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(categories) { c in
                        Text(c.name).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.stickerInk)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(BookPalette.color(c.colorIndex).opacity(picked.contains(c.name) ? 1 : 0.3)))
                            .onTapGesture { if picked.contains(c.name) { picked.remove(c.name) } else { picked.insert(c.name) } }
                    }
                }
            }

            ScrollView {
                VStack(spacing: 8) {
                    if let error { Text(error).font(Theme.ui(12)).foregroundStyle(Theme.critical) }
                    ForEach(results) { r in
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: r.coverURL)) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Theme.card }
                                .frame(width: 40, height: 60).clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(Theme.ui(14, weight: .semibold)).lineLimit(2)
                                Text([r.author, r.year > 0 ? String(r.year) : "", r.pages > 0 ? "\(r.pages) pages" : ""]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer()
                            Button("Add") { add(r) }.buttonStyle(SoftButtonStyle())
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card.opacity(0.5)))
                    }
                }
            }
            .frame(height: 300)

            Divider()
            Text("Or add it by hand").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            HStack {
                TextField("Title", text: $manualTitle).textFieldStyle(.roundedBorder)
                TextField("Author", text: $manualAuthor).textFieldStyle(.roundedBorder)
                Button("Add") {
                    insert(ImportedBook(title: manualTitle, author: manualAuthor), source: "manual")
                }
                .disabled(manualTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).frame(width: 120).keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .sheetFrame(width: 600)
        .onAppear { if let defaultCategory { picked = [defaultCategory] } }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        error = nil
        Task {
            do { results = try await OpenLibrary.search(q) } catch { self.error = "Search failed: \(error.localizedDescription)" }
            if results.isEmpty, error == nil { error = "No matches. Add it by hand below." }
            searching = false
        }
    }

    private func add(_ r: OpenLibrary.Result) {
        var b = ImportedBook(title: r.title, author: r.author)
        b.isbn = r.isbn; b.pages = r.pages; b.year = r.year; b.coverURL = r.coverURL
        b.externalID = "openlibrary:\(r.id)"
        insert(b, source: "openlibrary")
        results.removeAll { $0.id == r.id }
    }

    private func insert(_ item: ImportedBook, source: String) {
        var item = item
        item.status = status
        item.categories = Array(picked)
        if status == .read { item.finishedAt = .now; item.progress = 1 }
        if status == .reading { item.startedAt = .now }
        BookLibrary.merge([item], source: source, category: nil, context: context)
        manualTitle = ""; manualAuthor = ""
    }
}

struct BookDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BookCategory.createdAt) private var categories: [BookCategory]
    @Bindable var book: Book

    @Query(sort: \Highlight.createdAt) private var allHighlights: [Highlight]
    @Query private var allSessions: [ReadingSession]
    @ObservedObject private var timer = ReadingTimer.shared

    /// Reading time, the timer button, and this book's highlights.
    @ViewBuilder private var bookExtras: some View {
        let mine = allHighlights.filter { (!book.uuid.isEmpty && $0.bookUUID == book.uuid) || $0.bookTitle.caseInsensitiveCompare(book.title) == .orderedSame }
        let minutes = Int(allSessions.filter { !book.uuid.isEmpty && $0.bookUUID == book.uuid }.reduce(0) { $0 + $1.minutes })
        HStack {
            Label(minutes == 0 ? "No reading time yet" : minutes < 60 ? "\(minutes) min read" : String(format: "%.1f h read", Double(minutes) / 60),
                  systemImage: "timer").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
            Spacer()
            if timer.active?.bookUUID == book.uuid && !book.uuid.isEmpty {
                Button { timer.stop(context: context) } label: { Label("Stop reading", systemImage: "stop.fill") }.buttonStyle(SoftButtonStyle())
            } else {
                Button { timer.start(book, context: context) } label: { Label("Start reading", systemImage: "timer") }.buttonStyle(SoftButtonStyle())
            }
        }
        if !mine.isEmpty {
            Text("Highlights (\(mine.count))").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            ScrollView {
                VStack(spacing: 6) { ForEach(mine) { HighlightRow(highlight: $0) } }
            }
            .frame(maxHeight: 180)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                shelfPicker
                if book.status == .reading { progressCard }
                detailsCard
                categoriesSection
                VStack(alignment: .leading, spacing: 10) { bookExtras }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    TextEditor(text: $book.notes)
                        .font(Theme.display(14, weight: .regular))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                        .frame(height: 110)
                }
                HStack {
                    Button("Delete", role: .destructive) { context.delete(book); dismiss() }.buttonStyle(SoftButtonStyle())
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).frame(width: 110).keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, Platform.isPhone ? 20 : 32)
            .padding(.vertical, 24)
        }
        .scrollIndicators(.never)
        .background(Theme.canvas)
        .sheetFrame(width: 520, height: 760)
    }

    /// The cover, centred on a wash of its own colour, with the title, author and rating under it.
    private var hero: some View {
        let tint = BookPalette.color(book.title.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        return VStack(spacing: 10) {
            BookCover(book: book).frame(width: 150, height: 225)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
                .padding(.bottom, 8)
            TextField("Title", text: $book.title, axis: .vertical)
                .textFieldStyle(.plain).font(Theme.display(24)).multilineTextAlignment(.center)
            TextField("Author", text: $book.author)
                .textFieldStyle(.plain).font(Theme.ui(15)).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            Stars(rating: book.rating, size: 20) { book.rating = $0 }.padding(.top, 2)
            Text(sourceLabel).font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24).padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.08)], startPoint: .top, endPoint: .bottom))
        )
    }

    /// One big button per shelf, the current one filled.
    private var shelfPicker: some View {
        HStack(spacing: 8) {
            ForEach(ReadingStatus.allCases) { status in
                let on = book.status == status
                Button {
                    withAnimation(.snappy(duration: 0.2)) { book.status = status }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: status.symbol).font(.system(size: 17, weight: .semibold))
                        Text(status == .dnf ? "Stopped" : status.title).font(Theme.ui(12, weight: .semibold))
                            .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58).padding(.vertical, 10).padding(.horizontal, 4)
                    .foregroundStyle(on ? Theme.stickerInk : Theme.inkSecondary)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? shelfColor(status) : Theme.card))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shelfColor(_ status: ReadingStatus) -> Color {
        switch status {
        case .reading: Theme.orange
        case .toRead: Theme.cyan
        case .read: Theme.lime
        case .dnf: Theme.pink
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress").font(Theme.ui(13, weight: .semibold))
                Spacer()
                Text("\(Int(book.progress * 100))%").font(Theme.ui(13, weight: .semibold)).monospacedDigit()
            }
            Slider(value: $book.progress, in: 0...1).tint(Theme.orange)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailRow("Pages") {
                TextField("", value: $book.pageCount, format: .number).textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing).frame(width: 90)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }
            if book.status != .toRead {
                Divider()
                detailRow("Started") {
                    DatePicker("", selection: Binding(get: { book.startedAt ?? .now }, set: { book.startedAt = $0 }),
                               displayedComponents: .date).labelsHidden()
                }
            }
            if book.status == .read {
                Divider()
                detailRow("Finished") {
                    DatePicker("", selection: Binding(get: { book.finishedAt ?? .now }, set: { book.finishedAt = $0 }),
                               displayedComponents: .date).labelsHidden()
                }
            }
        }
        .font(Theme.ui(14))
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }

    private func detailRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.inkSecondary)
            Spacer()
            content()
        }
        .frame(minHeight: 46)
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories").font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            if categories.isEmpty {
                Text("Create categories from the Reading sidebar.").font(Theme.ui(12)).foregroundStyle(Theme.inkMuted)
            }
            FlowLayout(spacing: 6) {
                ForEach(categories) { c in
                    let on = book.categories.contains(c.name)
                    Text(c.name).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.stickerInk)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(BookPalette.color(c.colorIndex).opacity(on ? 1 : 0.3)))
                        .onTapGesture { if on { book.categories.removeAll { $0 == c.name } } else { book.categories.append(c.name) } }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceLabel: String {
        switch book.source {
        case "goodreads": "From Goodreads"
        case "apple-books": "From Apple Books"
        case "kindle": "From Kindle"
        case "openlibrary": "From Open Library"
        default: "Added by you"
        }
    }
}

struct CategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var books: [Book]
    @Query private var all: [BookCategory]
    let category: BookCategory?

    @State private var name = ""
    @State private var color = 0
    @State private var symbol = "tag.fill"
    private let symbols = ["tag.fill", "heart.fill", "star.fill", "brain.head.profile", "briefcase.fill", "sparkles",
                           "globe.europe.africa.fill", "flask.fill", "theatermasks.fill", "leaf.fill", "moon.stars.fill", "bolt.fill",
                           "book.closed.fill", "graduationcap.fill", "dollarsign.circle.fill", "person.2.fill"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(category == nil ? "New category" : "Edit category").font(Theme.display(26))
            TextField("e.g. Philosophy, Book club, Favourites", text: $name)
                .textFieldStyle(.plain).font(Theme.ui(15))
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            HStack(spacing: 8) {
                ForEach(0..<BookPalette.colors.count, id: \.self) { i in
                    Circle().fill(BookPalette.color(i)).frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: color == i ? 2 : 0))
                        .onTapGesture { color = i }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38)), count: 8), spacing: 8) {
                ForEach(symbols, id: \.self) { s in
                    Image(systemName: s).frame(width: 36, height: 36)
                        .background(Circle().fill(symbol == s ? BookPalette.color(color) : Theme.card))
                        .foregroundStyle(symbol == s ? Theme.stickerInk : Theme.ink)
                        .onTapGesture { symbol = s }
                }
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
                Spacer()
                Button(category == nil ? "Create" : "Save", action: save)
                    .buttonStyle(PrimaryButtonStyle()).frame(width: 120)
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .sheetFrame(width: 420)
        .onAppear {
            if let category { name = category.name; color = category.colorIndex; symbol = category.symbol }
            else { color = all.count % BookPalette.colors.count }
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool {
        !trimmed.isEmpty && !all.contains { $0 !== category && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private func save() {
        if let category {
            let old = category.name
            if old != trimmed {
                for b in books where b.categories.contains(old) {
                    b.categories = b.categories.map { $0 == old ? trimmed : $0 }
                }
            }
            category.name = trimmed
            category.colorIndex = color
            category.symbol = symbol
        } else {
            context.insert(BookCategory(name: trimmed, colorIndex: color, symbol: symbol))
        }
        dismiss()
    }
}

struct ReadingSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var sync = ReadingSync.shared
    @State private var busy: String?
    @State private var importingCSV = false
    @Query private var books: [Book]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connect & import").font(Theme.display(28))
                Text("Books are matched by title and author, so syncing again never creates duplicates, and shelves you set in Orbit are never moved backwards.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)

                if Platform.isPhone {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Refresh every day", isOn: $sync.autoSync).font(Theme.ui(14, weight: .medium))
                        HStack {
                            if sync.lastSync > 0 {
                                Text("Last refresh \(Date(timeIntervalSince1970: sync.lastSync).formatted(.relative(presentation: .named)))")
                                    .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                            }
                            Spacer()
                            Button(sync.running ? "Syncing…" : "Sync now") { Task { await sync.syncAll(context: context) } }
                                .buttonStyle(SoftButtonStyle()).disabled(sync.running || Goodreads.userID(from: sync.goodreadsUser) == nil)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.blush))
                } else {
                HStack {
                    Toggle("Refresh every day automatically", isOn: $sync.autoSync).font(Theme.ui(13, weight: .medium))
                    Spacer()
                    if sync.lastSync > 0 {
                        Text("Last refresh \(Date(timeIntervalSince1970: sync.lastSync).formatted(.relative(presentation: .named)))")
                            .font(Theme.ui(11)).foregroundStyle(Theme.inkMuted)
                    }
                    Button(sync.running ? "Syncing…" : "Sync all now") { Task { await sync.syncAll(context: context) } }
                        .disabled(sync.running || !sync.hasSources)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.blush))
                }

                source("Goodreads", symbol: "g.circle.fill", color: Theme.peach, key: "goodreads", linked: Goodreads.userID(from: sync.goodreadsUser) != nil) {
                    Text("Orbit reads your public Goodreads shelves. Paste your profile link or user ID (goodreads.com/user/show/12345-yourname).")
                    HStack {
                        TextField("Profile link or user ID", text: $sync.goodreadsUser).textFieldStyle(.roundedBorder)
                        Button("Sync") {
                            busy = "goodreads"
                            Task { await syncGoodreadsOnly(); busy = nil }
                        }
                        .disabled(Goodreads.userID(from: sync.goodreadsUser) == nil || busy != nil)
                    }
                    Button("Import library export (CSV)…") { importingCSV = true }.font(Theme.ui(11)).disabled(busy != nil)
                }

                #if os(macOS)
                if !LocalLibraries.hasAccess { fullDiskAccessGuide }

                source("Apple Books", symbol: "book.fill", color: Theme.orange, key: "apple", linked: sync.appleBooksLinked) {
                    Text("Reads the Books library on this Mac: what you've finished and how far along you are. Refreshes every day by itself.")
                    HStack {
                        Spacer()
                        Button(sync.appleBooksLinked ? "Import again" : "Import from Apple Books") {
                            _ = sync.importLocal("apple", source: "apple-books", category: "Apple Books", context: context, load: AppleBooks.load)
                        }
                        .disabled(busy != nil || !LocalLibraries.hasAccess)
                    }
                }

                source("Kindle", symbol: "flame.fill", color: Theme.cyan, key: "kindle", linked: sync.kindleLinked) {
                    Text("Reads the library the Kindle app on this Mac has downloaded (Amazon doesn't let other apps sign in to your account). Open Kindle for Mac and sign in first so it syncs.")
                    HStack {
                        Link("Also link Kindle to Goodreads", destination: URL(string: "https://www.goodreads.com/user/edit?tab=apps")!)
                            .help("Kindle reading progress then flows into Goodreads too")
                        Spacer()
                        if UserDefaults.standard.string(forKey: "kindleDiagnostics") != nil && !sync.kindleLinked {
                            Button("Copy details") {
                                Platform.copy(UserDefaults.standard.string(forKey: "kindleDiagnostics") ?? "")
                            }
                        }
                        Button(sync.kindleLinked ? "Import again" : "Import from Kindle") {
                            _ = sync.importLocal("kindle", source: "kindle", category: "Kindle", context: context, load: KindleMac.load)
                        }
                        .disabled(busy != nil || !LocalLibraries.hasAccess)
                    }
                }
                #else
                macLibrariesNote
                #endif

                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).frame(width: 120).keyboardShortcut(.cancelAction)
                }
            }
            .padding(28)
        }
        .sheetFrame(width: 600, height: 720)
        .fileImporter(isPresented: $importingCSV, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let items = try Goodreads.parseCSV(url)
                let out = BookLibrary.merge(items, source: "goodreads", category: nil, context: context)
                sync.setResult("goodreads", "Imported \(items.count) books — \(out.added) new, \(out.updated) updated.")
            } catch {
                sync.setResult("goodreads", error.localizedDescription)
            }
        }
    }

    /// iPhone can't read the Apple Books or Kindle libraries; Orbit on the Mac imports them and they sync here.
    private var macLibrariesNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "laptopcomputer").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 10).fill(Theme.cyan))
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Books and Kindle").font(Theme.ui(15, weight: .semibold))
                Text("iPhone doesn't let apps read these libraries, so Orbit on your Mac imports them and the books appear here on their own.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                let counts = (apple: books.filter { $0.sources.contains("apple-books") || $0.source == "apple-books" }.count,
                              kindle: books.filter { $0.sources.contains("kindle") || $0.source == "kindle" }.count)
                if counts.apple + counts.kindle > 0 {
                    Text("\(counts.apple) from Apple Books · \(counts.kindle) from Kindle").font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.good)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }

    /// Orbit doesn't appear in the Full Disk Access list on its own, so walk through adding it.
    private var fullDiskAccessGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Theme.orange)
                Text("One step to connect Apple Books and Kindle").font(Theme.ui(15, weight: .semibold))
            }
            Text("macOS keeps those libraries private until you let Orbit read them with Full Disk Access.")
                .font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Click **Open Full Disk Access** below.")
                step(2, "Click **+** under the list, then pick **Orbit** in Applications and click **Open**. (Or drag Orbit from the Finder window into the list.)")
                step(3, "Make sure the switch next to Orbit is **on**.")
                step(4, "Click **Relaunch Orbit**. Your Apple Books and Kindle books are imported right after.")
            }
            #if os(macOS)
            HStack(spacing: 8) {
                Button("Open Full Disk Access") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                .buttonStyle(.borderedProminent)
                Button("Show Orbit in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                Spacer()
                Button("Relaunch Orbit") { Updater.relaunch() }
            }
            #endif
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.orange, lineWidth: 1.5))
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(Theme.ui(11, weight: .bold)).frame(width: 20, height: 20).background(Circle().fill(Theme.card))
            Text(text).font(Theme.ui(12)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func syncGoodreadsOnly() async {
        guard let id = Goodreads.userID(from: sync.goodreadsUser) else { return }
        do {
            let items = try await Goodreads.fetchShelves(userID: id)
            let out = BookLibrary.merge(items, source: "goodreads", category: nil, context: context)
            sync.goodreadsLastSync = Date.now.timeIntervalSince1970
            sync.setResult("goodreads", "Synced \(items.count) books — \(out.added) new, \(out.updated) updated. Refreshes daily.")
        } catch {
            sync.setResult("goodreads", error.localizedDescription)
        }
    }

    private func source<Content: View>(_ name: String, symbol: String, color: Color, key: String, linked: Bool,
                                       @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.stickerInk)
                .frame(width: 38, height: 38).background(Circle().fill(color))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(name).font(Theme.ui(15, weight: .semibold))
                    if linked { Label("Daily sync on", systemImage: "checkmark.circle.fill").font(Theme.ui(11, weight: .medium)).foregroundStyle(Theme.good) }
                    if busy == key || (sync.running && linked) { ProgressView().controlSize(.small) }
                }
                content().font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                if let m = sync.lastResults[key] { Text(m).font(Theme.ui(12, weight: .medium)).foregroundStyle(Theme.ink) }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }
}

struct HighlightRow: View {
    @Environment(\.modelContext) private var context
    let highlight: Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.lime).frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.text).font(Theme.display(15, weight: .regular)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if !highlight.note.isEmpty {
                    Label(highlight.note, systemImage: "note.text").font(Theme.ui(12)).foregroundStyle(Theme.inkSecondary)
                }
                if !highlight.location.isEmpty {
                    Text(highlight.location.capitalized).font(Theme.ui(10)).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
        .contextMenu {
            Button("Copy") {
                Platform.copy("“\(highlight.text)” — \(highlight.bookTitle)")
            }
            Button("Delete", role: .destructive) { context.delete(highlight) }
        }
    }
}
