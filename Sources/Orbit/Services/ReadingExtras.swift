import Foundation
import SwiftUI
import SwiftData

// MARK: - Kindle highlights

/// Imports highlights and notes from Kindle:
/// - "My Clippings.txt" from a Kindle e-reader (plug it in, it's in the documents folder)
/// - a notebook export from the Kindle app on iPhone/iPad/Android (Notebook › Share › Export notebook, an HTML file)
enum KindleHighlights {
    struct Parsed {
        var bookTitle: String
        var author: String
        var text: String
        var note: String = ""
        var location: String
        var date: Date?
    }

    static func parse(fileAt url: URL) throws -> [Parsed] {
        guard let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .utf16)) else {
            throw BookImportError.unreadable("Couldn't read that file.")
        }
        let text = raw.replacingOccurrences(of: "\u{FEFF}", with: "")
        if text.contains("noteText") || text.lowercased().contains("<html") { return parseNotebookHTML(text) }
        if text.contains("==========") { return parseClippings(text) }
        throw BookImportError.unreadable("That isn't a Kindle “My Clippings.txt” or notebook export.")
    }

    /// Kindle e-reader format: title (author) / - Your Highlight on … | Location 10-12 | Added on … / blank / text / ==========
    static func parseClippings(_ text: String) -> [Parsed] {
        var out: [Parsed] = []
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEEE, d MMMM yyyy HH:mm:ss"
        for entry in text.components(separatedBy: "==========") {
            // Kindle starts each title line with an invisible byte-order mark.
            let lines = entry.components(separatedBy: .newlines)
                .map { $0.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard lines.count >= 3 else { continue }
            let (title, author) = splitTitle(lines[0])
            let meta = lines[1].lowercased()
            let body = lines[2...].joined(separator: "\n")
            let location = position(in: lines[1])
            let date = lines[1].components(separatedBy: "Added on ").last.flatMap { df.date(from: $0.trimmingCharacters(in: .whitespaces)) }
            if meta.contains("bookmark") { continue }
            if meta.contains("note"), let i = out.lastIndex(where: { $0.bookTitle == title && $0.note.isEmpty }) {
                out[i].note = body   // a note belongs to the highlight just before it
                continue
            }
            out.append(Parsed(bookTitle: title, author: author, text: body, location: location, date: date))
        }
        return out
    }

    /// Kindle app notebook export (HTML with bookTitle / authors / noteHeading / noteText).
    static func parseNotebookHTML(_ html: String) -> [Parsed] {
        func strip(_ s: String) -> String {
            s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&nbsp;", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func first(_ cls: String) -> String {
            guard let r = html.range(of: #"class=['"]\#(cls)['"][^>]*>([\s\S]*?)</div>"#, options: .regularExpression) else { return "" }
            return strip(String(html[r]).replacingOccurrences(of: #"^class=['"][^'"]+['"][^>]*>"#, with: "", options: .regularExpression))
        }
        let title = first("bookTitle"), author = first("authors")
        var out: [Parsed] = []
        let pattern = #"class=['"]noteHeading['"][^>]*>([\s\S]*?)</div>\s*<div class=['"]noteText['"][^>]*>([\s\S]*?)</(?:div|h3)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        for m in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let h = Range(m.range(at: 1), in: html), let t = Range(m.range(at: 2), in: html) else { continue }
            let heading = strip(String(html[h]))
            let body = strip(String(html[t]))
            guard !body.isEmpty else { continue }
            let location = position(in: heading)
            if heading.lowercased().hasPrefix("note"), let i = out.indices.last {
                out[i].note = body
            } else {
                out.append(Parsed(bookTitle: title, author: author, text: body, location: location, date: nil))
            }
        }
        return out
    }

    /// "Location 410-412" when there is one, otherwise "Page 27".
    private static func position(in text: String) -> String {
        for p in [#"(?i)(location|loc\.)\s*[\d\-]+"#, #"(?i)page\s*[\d\-]+"#] {
            if let r = text.range(of: p, options: .regularExpression) { return String(text[r]) }
        }
        return ""
    }

    private static func splitTitle(_ line: String) -> (String, String) {
        guard line.hasSuffix(")"), let open = line.range(of: " (", options: .backwards) else { return (line, "") }
        return (String(line[..<open.lowerBound]), String(line[open.upperBound...].dropLast()))
    }

    /// Adds new highlights, linking them to books already in your library. Returns (added, skipped as duplicates).
    @MainActor
    static func importHighlights(_ items: [Parsed], source: String, context: ModelContext) -> (Int, Int) {
        let existing = Set(((try? context.fetch(FetchDescriptor<Highlight>())) ?? []).map(\.externalID))
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let byKey = Dictionary(books.map { ($0.matchKey, $0) }, uniquingKeysWith: { a, _ in a })
        var added = 0, skipped = 0
        for p in items {
            let id = "kindle:" + String(p.bookTitle.lowercased().prefix(60)) + "|" + p.location + "|" + String(p.text.prefix(80))
            guard !existing.contains(id) else { skipped += 1; continue }
            let h = Highlight(bookTitle: p.bookTitle, author: p.author, text: p.text, source: source)
            h.note = p.note
            h.location = p.location
            h.externalID = id
            if let d = p.date { h.createdAt = d }
            if let book = byKey[Book.matchKey(title: p.bookTitle, author: p.author)] ?? books.first(where: { $0.title.caseInsensitiveCompare(p.bookTitle) == .orderedSame }) {
                h.bookUUID = book.uuid
                h.bookTitle = book.title
            }
            context.insert(h)
            added += 1
        }
        try? context.save()
        return (added, skipped)
    }
}

// MARK: - Reading timer

/// Times reading sessions. One session can run at a time; it survives restarts (an open session has no end).
@MainActor
final class ReadingTimer: ObservableObject {
    static let shared = ReadingTimer()

    @Published private(set) var active: ReadingSession?
    /// Set when a session stops, so the UI can ask what page you reached.
    @Published var justFinished: ReadingSession?

    func restore(context: ModelContext) {
        guard active == nil else { return }
        active = ((try? context.fetch(FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.end == nil }))) ?? []).first
    }

    func start(_ book: Book, context: ModelContext) {
        if let active { stop(context: context, session: active) }
        if book.uuid.isEmpty { book.uuid = UUID().uuidString.lowercased() }
        let s = ReadingSession(book: book)
        context.insert(s)
        if book.status != .reading { book.status = .reading }
        try? context.save()
        active = s
    }

    func stop(context: ModelContext, session: ReadingSession? = nil) {
        guard let s = session ?? active else { return }
        s.end = .now
        try? context.save()
        if s.minutes < 0.5 { context.delete(s); try? context.save() } else { justFinished = s }
        active = nil
    }

    static func minutes(_ sessions: [ReadingSession], since: Date) -> Int {
        Int(sessions.filter { $0.start >= since }.reduce(0) { $0 + $1.minutes })
    }

    /// Consecutive days with at least one session, ending today or yesterday.
    static func streak(_ sessions: [ReadingSession]) -> Int {
        let days = Set(sessions.map { $0.start.startOfDay })
        var day = Date.now.startOfDay
        if !days.contains(day) { day = day.adding(days: -1) }
        var n = 0
        while days.contains(day) { n += 1; day = day.adding(days: -1) }
        return n
    }
}

/// Top-bar pill while a reading session runs.
struct ReadingTimerPill: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var state: AppState
    @ObservedObject private var timer = ReadingTimer.shared

    var body: some View {
        if let s = timer.active {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let secs = Int(ctx.date.timeIntervalSince(s.start))
                    Text(String(format: "%d:%02d", secs / 60, secs % 60)).monospacedDigit()
                }
                Text(s.bookTitle).lineLimit(1).frame(maxWidth: 120)
                Button { timer.stop(context: context) } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.plain).help("Stop reading")
            }
            .font(Theme.ui(12, weight: .semibold))
            .foregroundStyle(Theme.stickerInk)
            .padding(.horizontal, 12).frame(height: 42)
            .background(Capsule().fill(Theme.purple))
            .onTapGesture { state.tab = .reading }
        }
    }
}

/// After a session: how long it was, and where you got to.
struct FinishedReadingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let session: ReadingSession
    @State private var page = ""
    @Query private var books: [Book]

    private var book: Book? { books.first { $0.uuid == session.bookUUID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nice reading! 📖").font(Theme.display(26))
            Text("\(Int(session.minutes.rounded())) minutes with \(session.bookTitle).").font(Theme.ui(14)).foregroundStyle(Theme.inkSecondary)
            if let book {
                HStack {
                    Text("What page are you on?").font(Theme.ui(13))
                    TextField(book.pageCount > 0 ? "of \(book.pageCount)" : "page", text: $page).textFieldStyle(.roundedBorder).frame(width: 90)
                }
            }
            HStack {
                Button("Skip") { dismiss() }.buttonStyle(SoftButtonStyle())
                Spacer()
                Button("Save") {
                    if let book, let p = Int(page), p > 0 {
                        let before = book.pageCount > 0 ? Int(book.progress * Double(book.pageCount)) : 0
                        session.pagesRead = max(0, p - before)
                        if book.pageCount > 0 {
                            book.progress = min(1, Double(p) / Double(book.pageCount))
                            if book.progress >= 1 { book.status = .read }
                        }
                        try? context.save()
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle()).frame(width: 110).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).sheetFrame(width: 380)
    }
}
