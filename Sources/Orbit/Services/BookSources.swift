import Foundation
import SwiftUI
import SwiftData
import SQLite3

/// A book coming from an outside source, before it's merged into the library.
struct ImportedBook {
    var title: String
    var author: String
    var status: ReadingStatus = .toRead
    var rating = 0
    var categories: [String] = []
    var isbn = ""
    var pages = 0
    var year = 0
    var coverURL = ""
    var progress = 0.0
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
    var addedAt: Date? = nil
    var externalID = ""
}

enum BookImportError: LocalizedError {
    case notFound(String), noAccess(String), unreadable(String), network(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let s), .unreadable(let s), .network(let s): s
        case .noAccess(let app):
            "macOS blocked access to \(app)'s library. Turn on Orbit under Full Disk Access (button below), then try again."
        }
    }
}

// MARK: - Merge

enum BookLibrary {
    /// Books on the Currently reading shelf, the one you're actually on first: the book you last read
    /// (timer sessions), then the one you most recently started or added.
    static func currentlyReading(_ books: [Book], sessions: [ReadingSession]) -> [Book] {
        var lastRead: [String: Date] = [:]
        for s in sessions where !s.bookUUID.isEmpty { lastRead[s.bookUUID] = max(lastRead[s.bookUUID] ?? .distantPast, s.start) }
        func key(_ b: Book) -> Date { max(lastRead[b.uuid] ?? .distantPast, b.startedAt ?? .distantPast, b.addedAt) }
        return books.filter { $0.status == .reading }.sorted { key($0) > key($1) }
    }

    static func currentlyReading(context: ModelContext) -> [Book] {
        currentlyReading((try? context.fetch(FetchDescriptor<Book>())) ?? [], sessions: (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? [])
    }

    struct Outcome { var added = 0; var updated = 0; var total: Int { added + updated } }

    /// Adds new books and enriches existing ones. Never downgrades a status you set by hand.
    /// Libraries synced from outside. Their books never get categories automatically: you browse them by library instead.
    static let importedSources: Set<String> = ["goodreads", "apple-books", "kindle"]

    @discardableResult
    static func merge(_ items: [ImportedBook], source: String, category: String?, context: ModelContext) -> Outcome {
        let imported = importedSources.contains(source)
        let category = imported ? nil : category
        let items = imported ? items.map { var i = $0; i.categories = []; return i } : items
        let existing = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        var byID = Dictionary(existing.filter { !$0.externalID.isEmpty }.map { ($0.externalID, $0) }, uniquingKeysWith: { a, _ in a })
        var byKey = Dictionary(existing.map { ($0.matchKey, $0) }, uniquingKeysWith: { a, _ in a })
        let order: [ReadingStatus] = [.toRead, .reading, .dnf, .read]
        var outcome = Outcome()

        if let category { ensureCategory(category, context: context) }
        for c in Set(items.flatMap(\.categories)) { ensureCategory(c, context: context) }

        for item in items where !item.title.trimmingCharacters(in: .whitespaces).isEmpty {
            let key = Book.matchKey(title: item.title, author: item.author)
            let book: Book
            if let found = (item.externalID.isEmpty ? nil : byID[item.externalID]) ?? byKey[key] {
                book = found
                outcome.updated += 1
                if order.firstIndex(of: item.status)! > order.firstIndex(of: book.status)! { book.statusRaw = item.status.rawValue }
            } else {
                book = Book(title: item.title, author: item.author, status: item.status, source: source)
                book.addedAt = item.addedAt ?? .now
                context.insert(book)
                outcome.added += 1
                byKey[key] = book
            }
            if !item.externalID.isEmpty, book.externalID.isEmpty { book.externalID = item.externalID; byID[item.externalID] = book }
            if book.sources.isEmpty { book.sources = [book.source] }
            if !book.sources.contains(source) { book.sources.append(source) }
            if book.rating == 0 { book.rating = item.rating }
            if book.isbn.isEmpty { book.isbn = item.isbn }
            if book.pageCount == 0 { book.pageCount = item.pages }
            if book.year == 0 { book.year = item.year }
            if book.coverURL.isEmpty { book.coverURL = item.coverURL }
            if book.coverURL.isEmpty, !item.isbn.isEmpty { book.coverURL = "https://covers.openlibrary.org/b/isbn/\(item.isbn)-M.jpg?default=false" }
            book.progress = max(book.progress, item.progress)
            if book.startedAt == nil { book.startedAt = item.startedAt }
            if book.finishedAt == nil { book.finishedAt = item.finishedAt }
            var cats = book.categories
            for c in item.categories + (category.map { [$0] } ?? []) where !cats.contains(c) { cats.append(c) }
            book.categories = cats
        }
        try? context.save()
        return outcome
    }

    /// One-time cleanup of Kindle imports: scrambled (encrypted) authors are cleared so covers and authors can be
    /// looked up again, and the dictionaries Kindle comes with are removed.
    static func cleanUpKindleIfNeeded(context: ModelContext) {
        let key = "booksKindleCleaned.v1"
        guard !UserDefaults.standard.bool(forKey: key), !Snapshot.isActive else { return }
        for book in (try? context.fetch(FetchDescriptor<Book>())) ?? [] {
            let clean = Book.cleanAuthor(book.author)
            if clean != book.author {
                book.author = clean
                if BookCovers.isSearchResultURL(book.coverURL) { book.coverURL = "" }
            }
            let onlyKindle = (book.sources.isEmpty ? [book.source] : book.sources) == ["kindle"]
            if onlyKindle, book.title.range(of: "dictionary|woordenboek|shabdabhandar", options: [.regularExpression, .caseInsensitive]) != nil {
                context.delete(book)
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// One-time cleanup: imported books lose the categories imports gave them, and categories nobody uses any more are removed.
    static func migrateLibrariesIfNeeded(context: ModelContext) {
        let key = "booksLibrariesMigrated"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        for b in books {
            if b.sources.isEmpty { b.sources = [b.source] }
            if importedSources.contains(b.source) { b.categories = [] }
        }
        let used = Set(books.flatMap(\.categories))
        for c in (try? context.fetch(FetchDescriptor<BookCategory>())) ?? [] where !used.contains(c.name) { context.delete(c) }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    static func ensureCategory(_ name: String, context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<BookCategory>())) ?? []
        guard !all.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        context.insert(BookCategory(name: name, colorIndex: all.count % BookPalette.colors.count))
    }
}

// MARK: - Open Library (search & covers, no key needed)

enum OpenLibrary {
    struct Result: Identifiable, Hashable {
        let id: String
        let title: String
        let author: String
        let year: Int
        let pages: Int
        let isbn: String
        let coverURL: String
    }

    static func search(_ query: String) async throws -> [Result] {
        var comps = URLComponents(string: "https://openlibrary.org/search.json")!
        comps.queryItems = [
            .init(name: "q", value: query), .init(name: "limit", value: "12"),
            .init(name: "fields", value: "key,title,author_name,first_publish_year,number_of_pages_median,isbn,cover_i"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let docs = json?["docs"] as? [[String: Any]] ?? []
        return docs.compactMap { d in
            guard let title = d["title"] as? String else { return nil }
            let cover = (d["cover_i"] as? Int).map { "https://covers.openlibrary.org/b/id/\($0)-M.jpg" } ?? ""
            return Result(id: d["key"] as? String ?? UUID().uuidString, title: title,
                          author: (d["author_name"] as? [String])?.first ?? "",
                          year: d["first_publish_year"] as? Int ?? 0,
                          pages: d["number_of_pages_median"] as? Int ?? 0,
                          isbn: (d["isbn"] as? [String])?.first ?? "",
                          coverURL: cover)
        }
    }
}

// MARK: - Goodreads

enum Goodreads {
    /// Accepts a numeric user ID or a profile URL like goodreads.com/user/show/12345-name.
    static func userID(from input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: #"(?:user/show/|list/|list_rss/)(\d+)"#, options: .regularExpression) {
            return String(s[r]).components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.first
        }
        return s.allSatisfy(\.isNumber) && !s.isEmpty ? s : nil
    }

    /// Reads the public shelf RSS feed (the profile must be public).
    static func fetchShelves(userID: String) async throws -> [ImportedBook] {
        var all: [ImportedBook] = []
        for page in 1...30 {
            let url = URL(string: "https://www.goodreads.com/review/list_rss/\(userID)?shelf=%23ALL%23&per_page=100&page=\(page)")!
            let data: Data
            do { (data, _) = try await URLSession.shared.data(from: url) } catch {
                throw BookImportError.network("Couldn't reach Goodreads: \(error.localizedDescription)")
            }
            let parser = GoodreadsRSSParser()
            let items = parser.parse(data)
            if page == 1, items.isEmpty, !parser.sawChannel {
                throw BookImportError.notFound("Goodreads didn't return a shelf. Check the user ID and that your profile is public.")
            }
            all += items
            if items.count < 100 { break }
        }
        return all
    }

    /// Goodreads › My Books › Import and export › Export library.
    static func parseCSV(_ url: URL) throws -> [ImportedBook] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw BookImportError.unreadable("Couldn't read that file.")
        }
        let rows = CSV.parse(text)
        guard let header = rows.first, header.contains("Title") else {
            throw BookImportError.unreadable("That doesn't look like a Goodreads library export.")
        }
        func col(_ row: [String], _ name: String) -> String {
            guard let i = header.firstIndex(of: name), i < row.count else { return "" }
            return row[i].trimmingCharacters(in: CharacterSet(charactersIn: "=\" ")).trimmingCharacters(in: .whitespaces)
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy/MM/dd"
        let builtIn: Set<String> = ["read", "to-read", "currently-reading"]

        return rows.dropFirst().compactMap { row in
            let title = col(row, "Title")
            guard !title.isEmpty else { return nil }
            var b = ImportedBook(title: title, author: col(row, "Author"))
            switch col(row, "Exclusive Shelf") {
            case "read": b.status = .read
            case "currently-reading": b.status = .reading
            default: b.status = .toRead
            }
            b.rating = Int(col(row, "My Rating")) ?? 0
            b.isbn = col(row, "ISBN13").isEmpty ? col(row, "ISBN") : col(row, "ISBN13")
            b.pages = Int(col(row, "Number of Pages")) ?? 0
            b.year = Int(col(row, "Original Publication Year")) ?? Int(col(row, "Year Published")) ?? 0
            b.finishedAt = df.date(from: col(row, "Date Read"))
            b.addedAt = df.date(from: col(row, "Date Added"))
            b.categories = col(row, "Bookshelves").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !builtIn.contains($0) }
                .map(Self.prettyShelf)
            let id = col(row, "Book Id")
            b.externalID = id.isEmpty ? "" : "goodreads:\(id)"
            if b.status == .read { b.progress = 1 }
            return b
        }
    }

    static func prettyShelf(_ s: String) -> String {
        s.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

private final class GoodreadsRSSParser: NSObject, XMLParserDelegate {
    private var items: [ImportedBook] = []
    private var current: [String: String]?
    private var text = ""
    private(set) var sawChannel = false

    func parse(_ data: Data) -> [ImportedBook] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "channel" { sawChannel = true }
        if name == "item" { current = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { text += String(decoding: data, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        if name == "item" {
            if let c = current { items.append(book(from: c)) }
            current = nil
        } else {
            current?[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func book(from c: [String: String]) -> ImportedBook {
        var b = ImportedBook(title: c["title"] ?? "", author: c["author_name"] ?? "")
        let shelves = (c["user_shelves"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        b.finishedAt = (c["user_read_at"]).flatMap { rfc.date(from: $0) }
        b.addedAt = (c["user_date_added"]).flatMap { rfc.date(from: $0) }
        if shelves.contains("currently-reading") { b.status = .reading }
        else if shelves.contains("to-read") { b.status = .toRead }
        else { b.status = .read; b.progress = 1 }
        b.rating = Int(c["user_rating"] ?? "") ?? 0
        b.isbn = c["isbn"] ?? ""
        b.pages = Int(c["num_pages"] ?? "") ?? 0
        b.year = Int(c["book_published"] ?? "") ?? 0
        b.coverURL = c["book_large_image_url"] ?? c["book_image_url"] ?? ""
        if b.coverURL.contains("nophoto") { b.coverURL = "" }
        b.categories = shelves.filter { !["read", "to-read", "currently-reading"].contains($0) }.map(Goodreads.prettyShelf)
        if let id = c["book_id"], !id.isEmpty { b.externalID = "goodreads:\(id)" }
        return b
    }
}

enum CSV {
    /// RFC 4180-ish parser: quoted fields, escaped quotes, newlines inside quotes.
    static func parse(_ text: String, delimiter: Unicode.Scalar = ",") -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        var chars = Array(text.unicodeScalars)[...]
        while let c = chars.popFirst() {
            if inQuotes {
                if c == "\"" {
                    if chars.first == "\"" { field.unicodeScalars.append("\""); chars.removeFirst() } else { inQuotes = false }
                } else { field.unicodeScalars.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case delimiter: row.append(field); field = ""
                case "\n", "\r":
                    if c == "\r", chars.first == "\n" { chars.removeFirst() }
                    row.append(field); field = ""
                    if row.count > 1 || !row[0].isEmpty { rows.append(row) }
                    row = []
                default: field.unicodeScalars.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// Picks comma, semicolon or tab, whichever splits the first lines most consistently.
    static func guessDelimiter(_ text: String) -> Unicode.Scalar {
        let lines = text.split(whereSeparator: \.isNewline).prefix(20)
        let scores: [(Unicode.Scalar, Int)] = [",", ";", "\t"].map { d in
            (d, lines.map { $0.unicodeScalars.filter { $0 == d }.count }.filter { $0 > 0 }.count)
        }
        return scores.max { $0.1 < $1.1 }?.0 ?? ","
    }
}

// MARK: - Local libraries (Apple Books, Kindle for Mac)

/// Read-only SQLite access to a copy of another app's database.
private final class SQLiteReader {
    private var db: OpaquePointer?

    init(copyOf url: URL) throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "orbit-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dest = tmp.appending(path: url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: dest)
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: side.path) {
                try? FileManager.default.copyItem(at: side, to: URL(fileURLWithPath: dest.path + suffix))
            }
        }
        guard sqlite3_open_v2(dest.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw BookImportError.unreadable("Couldn't open the library database.")
        }
    }

    deinit { sqlite3_close(db) }

    func rows(_ sql: String) -> [[String: String]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [[String: String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: String] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, i))
                if let v = sqlite3_column_text(stmt, i) { row[name] = String(cString: v) }
            }
            out.append(row)
        }
        return out
    }

    func tables() -> [String] { rows("SELECT name FROM sqlite_master WHERE type='table'").compactMap { $0["name"] } }
    func columns(_ table: String) -> [String] { rows("PRAGMA table_info(\"\(table)\")").compactMap { $0["name"] } }
}

private func coreDataDate(_ s: String?) -> Date? {
    guard let s, let t = Double(s), t > 0 else { return nil }
    return Date(timeIntervalSinceReferenceDate: t)
}

private func findDatabases(in dir: URL, app: String, matching: (URL) -> Bool) throws -> [URL] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: dir.path) else { throw BookImportError.notFound("\(app) isn't set up on this Mac.") }
    guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { throw BookImportError.noAccess(app) }
    var found: [URL] = []
    for case let url as URL in e where url.pathExtension == "sqlite" && matching(url) { found.append(url) }
    // An empty enumeration of a directory that exists usually means macOS denied access.
    if found.isEmpty, (try? fm.contentsOfDirectory(atPath: dir.path)) == nil { throw BookImportError.noAccess(app) }
    return found
}

enum AppleBooks {
    static func load() throws -> [ImportedBook] {
        let dir = URL.homeDirectory.appending(path: "Library/Containers/com.apple.iBooksX/Data/Documents/BKLibrary")
        let dbs = try findDatabases(in: dir, app: "Apple Books") { $0.lastPathComponent.hasPrefix("BKLibrary") }
        guard let url = dbs.first else { throw BookImportError.notFound("No Apple Books library found.") }
        let db = try SQLiteReader(copyOf: url)
        let cols = Set(db.columns("ZBKLIBRARYASSET"))
        guard cols.contains("ZTITLE") else { throw BookImportError.unreadable("Apple Books' library format wasn't recognized.") }
        let wanted = ["ZTITLE", "ZAUTHOR", "ZISFINISHED", "ZREADINGPROGRESS", "ZDATEFINISHED", "ZLASTOPENDATE",
                      "ZGENRE", "ZASSETID", "ZPAGECOUNT", "ZCREATIONDATE", "ZISSAMPLE", "ZCONTENTTYPE"].filter(cols.contains)
        return db.rows("SELECT \(wanted.joined(separator: ",")) FROM ZBKLIBRARYASSET").compactMap { r in
            guard let title = r["ZTITLE"], !title.isEmpty else { return nil }
            if r["ZISSAMPLE"] == "1" { return nil }
            var b = ImportedBook(title: title, author: r["ZAUTHOR"] ?? "")
            let progress = Double(r["ZREADINGPROGRESS"] ?? "") ?? 0
            b.progress = min(max(progress, 0), 1)
            if r["ZISFINISHED"] == "1" { b.status = .read; b.progress = 1 }
            else if progress > 0.01 { b.status = .reading }
            b.finishedAt = coreDataDate(r["ZDATEFINISHED"])
            b.startedAt = b.status == .toRead ? nil : coreDataDate(r["ZLASTOPENDATE"])
            b.addedAt = coreDataDate(r["ZCREATIONDATE"])
            b.pages = Int(r["ZPAGECOUNT"] ?? "") ?? 0
            if let genre = r["ZGENRE"], !genre.isEmpty { b.categories = [genre] }
            if let id = r["ZASSETID"], !id.isEmpty { b.externalID = "applebooks:\(id)" }
            return b
        }
    }
}

enum KindleMac {
    /// Kindle for Mac keeps its library in a Core Data store; column names vary between versions,
    /// so this looks for a table with title and author columns rather than relying on one schema.
    static func load() throws -> [ImportedBook] {
        let dir = URL.homeDirectory.appending(path: "Library/Containers/com.amazon.Lassen/Data/Library")
        let dbs = try findDatabases(in: dir, app: "Kindle") { _ in true }
        let titleCols = ["ZDISPLAYTITLE", "ZTITLE", "ZRAWTITLE", "ZSORTTITLE"]
        let authorCols = ["ZDISPLAYAUTHOR", "ZAUTHOR", "ZRAWAUTHOR", "ZAUTHORS", "ZSORTAUTHOR"]
        var seenTables: [String] = []

        for url in dbs {
            guard let db = try? SQLiteReader(copyOf: url) else { seenTables.append("\(url.lastPathComponent): unreadable"); continue }
            for table in db.tables() where table.hasPrefix("Z") {
                let cols = db.columns(table)
                let titleLike = cols.filter { $0.contains("TITLE") }
                if !titleLike.isEmpty { seenTables.append("\(url.lastPathComponent)/\(table): \(cols.filter { $0.contains("TITLE") || $0.contains("AUTHOR") }.joined(separator: ","))") }
                guard let t = titleCols.first(where: cols.contains) ?? titleLike.first(where: { !$0.contains("SORT") }) ?? titleLike.first else { continue }
                let a = authorCols.first(where: cols.contains) ?? cols.first { $0.contains("AUTHOR") }
                let idCol = ["ZBOOKID", "ZASIN", "ZRAWBOOKID", "ZIDENTIFIER"].first(where: cols.contains)
                let pctCol = cols.first { $0.contains("PERCENT") || $0 == "ZRAWREADINGPROGRESS" }
                let dictCol = cols.contains("ZRAWISDICTIONARY") ? "ZRAWISDICTIONARY" : nil
                let select = [t, a, idCol, pctCol, dictCol].compactMap { $0 }.joined(separator: ",")
                let rows = db.rows("SELECT \(select) FROM \"\(table)\"")
                let books: [ImportedBook] = rows.compactMap { r in
                    guard let title = r[t], !title.isEmpty else { return nil }
                    // The dictionaries Kindle comes with aren't books you read.
                    if let dictCol, r[dictCol] == "1" { return nil }
                    var b = ImportedBook(title: title, author: Book.cleanAuthor(a.flatMap { r[$0] } ?? ""))
                    if let p = pctCol.flatMap({ r[$0] }).flatMap(Double.init) {
                        let frac = p > 1 ? p / 100 : p
                        b.progress = min(max(frac, 0), 1)
                        if frac >= 0.98 { b.status = .read } else if frac > 0.01 { b.status = .reading }
                    }
                    if let id = idCol.flatMap({ r[$0] }), !id.isEmpty { b.externalID = "kindle:\(id)" }
                    return b
                }
                if !books.isEmpty { return books }
            }
        }
        UserDefaults.standard.set("Kindle databases: \(dbs.map(\.lastPathComponent).joined(separator: ", "))\nTables: \(seenTables.joined(separator: " | "))",
                                  forKey: "kindleDiagnostics")
        throw BookImportError.notFound(dbs.isEmpty
            ? "The Kindle app hasn't stored a library on this Mac yet. Open Kindle for Mac, sign in and let it sync, then try again."
            : "Orbit could open Kindle's data but didn't recognise the book list. Use “Copy details” and share them so it can be fixed.")
    }
}

enum LocalLibraries {
    static let booksDir = URL.homeDirectory.appending(path: "Library/Containers/com.apple.iBooksX/Data/Documents")
    static let kindleDir = URL.homeDirectory.appending(path: "Library/Containers/com.amazon.Lassen/Data/Library")

    /// macOS only lets Orbit read the Books and Kindle libraries with Full Disk Access.
    static var hasAccess: Bool {
        for dir in [booksDir, kindleDir] where FileManager.default.fileExists(atPath: dir.path) {
            return (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) != nil
        }
        return false
    }
    static var booksInstalled: Bool { FileManager.default.fileExists(atPath: booksDir.deletingLastPathComponent().path) }
    static var kindleInstalled: Bool {
        FileManager.default.fileExists(atPath: kindleDir.deletingLastPathComponent().path)
            || FileManager.default.fileExists(atPath: "/Applications/Amazon Kindle.app") || FileManager.default.fileExists(atPath: "/Applications/Kindle.app")
    }
}

enum BookPalette {
    static let colors = [Theme.pink, Theme.lime, Theme.orange, Theme.purple, Theme.cyan, Theme.mint, Theme.peach]
    static func color(_ i: Int) -> Color { colors[((i % colors.count) + colors.count) % colors.count] }
}


// MARK: - Daily sync

/// Re-imports every connected reading source once a day while Orbit is running.
@MainActor
final class ReadingSync: ObservableObject {
    static let shared = ReadingSync()

    @AppStorage("readingAutoSync") var autoSync = true
    @AppStorage("readingLastSync") var lastSync = 0.0
    @AppStorage("goodreadsUser") var goodreadsUser = ""
    @AppStorage("goodreadsLastSync") var goodreadsLastSync = 0.0
    @AppStorage("appleBooksLinked") var appleBooksLinked = false
    @AppStorage("kindleLinked") var kindleLinked = false

    @Published private(set) var running = false
    /// Last outcome per source, kept across launches so you can see why something didn't work.
    @Published private(set) var lastResults: [String: String] = (UserDefaults.standard.dictionary(forKey: "readingSyncResults") as? [String: String]) ?? [:] {
        didSet { UserDefaults.standard.set(lastResults, forKey: "readingSyncResults") }
    }

    var hasSources: Bool { Goodreads.userID(from: goodreadsUser) != nil || appleBooksLinked || kindleLinked }

    func syncIfDue(context: ModelContext) async {
        // As soon as Full Disk Access is on, bring in Apple Books and Kindle without waiting for a click.
        if LocalLibraries.hasAccess {
            if !appleBooksLinked, !UserDefaults.standard.bool(forKey: "appleBooksOff"), LocalLibraries.booksInstalled {
                importLocal("apple", source: "apple-books", category: "Apple Books", context: context, load: AppleBooks.load)
            }
            if !kindleLinked, !UserDefaults.standard.bool(forKey: "kindleOff"), LocalLibraries.kindleInstalled {
                importLocal("kindle", source: "kindle", category: "Kindle", context: context, load: KindleMac.load)
            }
        }
        guard autoSync, hasSources, Date.now.timeIntervalSince1970 - lastSync > 20 * 3600 else { return }
        await syncAll(context: context)
    }

    func syncAll(context: ModelContext) async {
        guard !running, !Snapshot.isActive else { return }
        running = true
        defer { running = false }
        if let id = Goodreads.userID(from: goodreadsUser) {
            do {
                let items = try await Goodreads.fetchShelves(userID: id)
                let out = BookLibrary.merge(items, source: "goodreads", category: nil, context: context)
                goodreadsLastSync = Date.now.timeIntervalSince1970
                lastResults["goodreads"] = "Synced \(items.count) books — \(out.added) new."
            } catch { lastResults["goodreads"] = error.localizedDescription }
        }
        guard !Platform.isPhone else { lastSync = Date.now.timeIntervalSince1970; return }  // the Mac imports these
        if appleBooksLinked { importLocal("apple", source: "apple-books", category: "Apple Books", context: context, load: AppleBooks.load) }
        if kindleLinked { importLocal("kindle", source: "kindle", category: "Kindle", context: context, load: KindleMac.load) }
        lastSync = Date.now.timeIntervalSince1970
    }

    /// Stops syncing Apple Books ("apple") or Kindle ("kindle") and removes what came from it: books only in that
    /// library are deleted (with their reading sessions and Kindle highlights); books also on another shelf just lose the tag.
    /// Returns how many books were deleted.
    @discardableResult
    func disconnect(_ key: String, context: ModelContext) -> Int {
        let source = key == "apple" ? "apple-books" : "kindle"
        let category = key == "apple" ? "Apple Books" : "Kindle"
        if key == "apple" { appleBooksLinked = false } else { kindleLinked = false }
        UserDefaults.standard.set(true, forKey: key == "apple" ? "appleBooksOff" : "kindleOff")
        lastResults[key] = nil
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        var deleted = 0
        for b in books {
            let from = b.sources.isEmpty ? [b.source] : b.sources
            guard from.contains(source) || b.source == source else { continue }
            let others = from.filter { $0 != source }
            if others.isEmpty {
                for s in sessions where s.bookUUID == b.uuid && !b.uuid.isEmpty { context.delete(s) }
                context.delete(b)
                deleted += 1
            } else {
                b.sources = others
                if b.source == source { b.source = others[0] }
                b.categories.removeAll { $0 == category }
            }
        }
        if key == "kindle" {
            for h in (try? context.fetch(FetchDescriptor<Highlight>())) ?? [] where h.source.hasPrefix("kindle") { context.delete(h) }
        }
        let still = books.filter { !$0.isDeleted }.contains { $0.categories.contains(category) }
        if !still { for c in (try? context.fetch(FetchDescriptor<BookCategory>())) ?? [] where c.name == category { context.delete(c) } }
        try? context.save()
        return deleted
    }

    /// Imports Apple Books / Kindle; remembers the source for daily sync after the first success.
    @discardableResult
    func importLocal(_ key: String, source: String, category: String, context: ModelContext,
                     load: () throws -> [ImportedBook]) -> Bool {
        do {
            let items = try load()
            let out = BookLibrary.merge(items, source: source, category: category, context: context)
            if key == "apple" { appleBooksLinked = true } else { kindleLinked = true }
            UserDefaults.standard.set(false, forKey: key == "apple" ? "appleBooksOff" : "kindleOff")
            lastResults[key] = "Imported \(items.count) books — \(out.added) new, \(out.updated) updated. Refreshes daily."
            return true
        } catch {
            lastResults[key] = error.localizedDescription
            return false
        }
    }

    func setResult(_ key: String, _ message: String?) { lastResults[key] = message }
}
