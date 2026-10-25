import Foundation
import CryptoKit
import SwiftUI

/// Book covers that always show up, sharp and of the right book: downloaded once and kept on disk. When a book has no
/// cover (or a broken, blank or tiny one), Orbit searches Apple Books, Google Books and Open Library, keeps only results
/// whose title and author match (no summaries or workbooks), and picks the largest picture.
@MainActor
enum BookCovers {
    private static var memory: [String: PlatformImage] = [:]
    private static var looking: Set<String> = []
    /// Links that didn't give a picture this run, so they aren't tried again.
    private static var broken: Set<String> = []
    /// Books whose found cover was re-checked once with the better search (so old wrong or blurry ones get replaced).
    private static var rechecked: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "covers.rechecked.v3") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "covers.rechecked.v3") }
    }

    static var folder: URL {
        let dir = URL.cachesDirectory.appending(path: "Orbit/covers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(for url: String) -> URL {
        let h = SHA256.hash(data: Data(url.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: "\(h).jpg")
    }

    /// The cover for `book`, finding a better one if needed.
    static func image(for book: Book) async -> PlatformImage? {
        let current = book.coverURL.isEmpty ? nil : await image(at: upgrade(book.coverURL))
        // A cover you picked yourself, or one that's already sharp and wasn't found by a search, stays.
        let searched = isSearchResult(book.coverURL)
        let tiny = (current?.cg?.height ?? 0) < 300
        let key = book.matchKey
        if let current, book.coverURL.hasPrefix("orbit-cover:") || (!tiny && (!searched || rechecked.contains(key))) { return current }
        guard !Snapshot.isActive, !looking.contains(key) else { return current }
        looking.insert(key)
        defer { looking.remove(key); rechecked.insert(key) }
        for candidate in await candidates(title: book.title, author: book.author, isbn: book.isbn).prefix(4) {
            guard let img = await image(at: candidate.url) else { continue }
            // A cover that came with the book (Kindle, Goodreads…) is only swapped for a clearly sharper one; an older
            // search result is replaced by the best match, since it may have been the wrong book.
            if let current, !searched, (img.cg?.height ?? 0) < max(400, (current.cg?.height ?? 0) + 100) { return current }
            book.coverURL = candidate.url
            // Books that came without an author (Kindle keeps them unreadable) get the one the match lists.
            if book.author.isEmpty, candidate.score >= 2.5, !candidate.author.isEmpty { book.author = candidate.author }
            return img
        }
        return current
    }

    /// A downloaded (or cached) picture at `url`, or nil if it's missing or a placeholder.
    static func image(at raw: String) async -> PlatformImage? {
        let url = raw.replacingOccurrences(of: "http://", with: "https://")
        if let m = memory[url] { return m }
        let f = file(for: url)
        if let img = PlatformImage.load(f) { memory[url] = img; return img }
        guard !broken.contains(url), !url.hasPrefix("orbit-cover:"), let u = URL(string: url) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: u),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1500,
              let img = PlatformImage(data: data), let cg = img.cg, cg.width > 20, cg.height > 20 else {
            broken.insert(url)
            return nil
        }
        try? (img.jpeg(maxSide: 1000, quality: 0.85) ?? data).write(to: f, options: .atomic)
        memory[url] = img
        return img
    }

    /// Uses a picture you chose as the book's cover (kept on this device).
    static func setCustom(_ image: PlatformImage, for book: Book) {
        guard let jpeg = image.jpeg(maxSide: 1000, quality: 0.85) else { return }
        let id = "orbit-cover:" + SHA256.hash(data: jpeg).prefix(10).map { String(format: "%02x", $0) }.joined()
        try? jpeg.write(to: file(for: id), options: .atomic)
        memory[id] = image
        book.coverURL = id
    }

    /// The biggest version of a cover link: Amazon without its size suffix, Google at 800 px, Open Library's large size.
    static func upgrade(_ url: String) -> String {
        var u = url.replacingOccurrences(of: "http://", with: "https://")
        if u.contains("media-amazon.com") || u.contains("images-amazon.com") || u.contains("gr-assets.com") {
            u = u.replacingOccurrences(of: #"\._[A-Z0-9_,]+_(?=\.(jpg|jpeg|png))"#, with: "", options: .regularExpression)
        }
        if u.contains("books.google") && !u.contains("fife=") { u += (u.contains("?") ? "&" : "?") + "fife=w800-h1200" }
        if u.contains("covers.openlibrary.org") { u = u.replacingOccurrences(of: #"-[SM]\.jpg"#, with: "-L.jpg", options: .regularExpression) }
        if u.contains("mzstatic.com") { u = u.replacingOccurrences(of: #"\d{2,4}x\d{2,4}bb"#, with: "1000x1000bb", options: .regularExpression) }
        return u
    }

    nonisolated static func isSearchResultURL(_ url: String) -> Bool { !url.isEmpty && isSearchResult(url) }

    nonisolated private static func isSearchResult(_ url: String) -> Bool {
        url.isEmpty || url.contains("books.google") || url.contains("covers.openlibrary.org") || url.contains("mzstatic.com")
    }

    // MARK: Finding

    private struct Candidate { let url: String; let score: Double; var author = "" }

    /// Cover links to try, best match first.
    static func find(title: String, author: String, isbn: String) async -> [String] {
        await candidates(title: title, author: author, isbn: isbn).map(\.url)
    }

    /// The title without subtitles, series and store blurbs ("Katabasis: A Fantastical… from Author of…" → "Katabasis").
    private static func shortTitle(_ title: String) -> String {
        let main = title.split(whereSeparator: { ":(".contains($0) }).first.map(String.init) ?? title
        let cut = main.components(separatedBy: " from ").first ?? main
        return cut.trimmingCharacters(in: .whitespaces).isEmpty ? title : cut.trimmingCharacters(in: .whitespaces)
    }

    private static func candidates(title: String, author: String, isbn: String) async -> [Candidate] {
        let wantTitle = norm(title), wantAuthor = norm(author)
        let title = shortTitle(title)
        var found: [Candidate] = []

        func score(_ t: String, _ a: String, bonus: Double = 0) -> Double? {
            let gotTitle = norm(t), gotAuthor = norm(a)
            // Not the book itself: summaries, workbooks, guides and the like.
            let junk = ["summary", "workbook", "study guide", "analysis", "notes on", "sparknotes", "cliffsnotes", "box set", "boxed set", "collection", "journal"]
            if junk.contains(where: { gotTitle.contains($0) && !wantTitle.contains($0) }) { return nil }
            let titleScore: Double = gotTitle == wantTitle ? 3
                : (gotTitle.hasPrefix(wantTitle) || wantTitle.hasPrefix(gotTitle)) && min(gotTitle.count, wantTitle.count) >= 4 ? 2
                : overlap(gotTitle, wantTitle) >= 0.7 ? 1 : 0
            // Without an author to check, only a clear title match counts (so "We" doesn't pass for "Before We Say Goodbye").
            guard titleScore >= (wantAuthor.isEmpty ? 2 : 1) else { return nil }
            let authorScore: Double = wantAuthor.isEmpty ? 0.5 : (overlap(gotAuthor, wantAuthor) >= 0.5 || gotAuthor.contains(wantAuthor.split(separator: " ").last.map(String.init) ?? "~") ? 2 : -2)
            return titleScore + authorScore + bonus
        }

        // 1. Apple Books: sharp covers of the edition most people read.
        var a = URLComponents(string: "https://itunes.apple.com/search")!
        a.queryItems = [.init(name: "term", value: "\(title) \(author)"), .init(name: "entity", value: "ebook"), .init(name: "limit", value: "10")]
        if let (data, _) = try? await URLSession.shared.data(from: a.url!),
           let results = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["results"] as? [[String: Any]] {
            for r in results {
                guard let art = r["artworkUrl100"] as? String,
                      let s = score(r["trackName"] as? String ?? "", r["artistName"] as? String ?? "", bonus: 0.6) else { continue }
                found.append(Candidate(url: upgrade(art), score: s, author: r["artistName"] as? String ?? ""))
            }
        }

        // 2. Google Books, preferring the most-rated edition.
        var g = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        let q = isbn.isEmpty ? "intitle:\(title)" + (author.isEmpty ? "" : " inauthor:\(author)") : "isbn:\(isbn)"
        g.queryItems = [.init(name: "q", value: q), .init(name: "maxResults", value: "10"), .init(name: "printType", value: "books")]
        if let (data, _) = try? await URLSession.shared.data(from: g.url!),
           let items = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["items"] as? [[String: Any]] {
            for item in items {
                let info = item["volumeInfo"] as? [String: Any] ?? [:]
                let links = info["imageLinks"] as? [String: String] ?? [:]
                guard let t = links["thumbnail"] ?? links["smallThumbnail"] else { continue }
                let authors = (info["authors"] as? [String] ?? []).joined(separator: " ")
                let popular = min(0.5, Double(info["ratingsCount"] as? Int ?? 0) / 200)
                guard let s = score(info["title"] as? String ?? "", authors, bonus: popular + (isbn.isEmpty ? 0 : 1)) else { continue }
                found.append(Candidate(url: upgrade(t.replacingOccurrences(of: "&edge=curl", with: "")), score: s,
                                       author: (info["authors"] as? [String] ?? []).joined(separator: ", ")))
            }
        }

        // 3. Open Library: by ISBN, then by search.
        if !isbn.isEmpty { found.append(Candidate(url: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false", score: 3.5)) }
        if let hits = try? await OpenLibrary.search("\(title) \(author)") {
            for h in hits.prefix(5) where !h.coverURL.isEmpty {
                if let s = score(h.title, h.author, bonus: -0.2) { found.append(Candidate(url: upgrade(h.coverURL), score: s, author: h.author)) }
            }
        }

        var seen = Set<String>()
        // Ties keep the order the stores ranked them in (their best-known edition first).
        return found.enumerated().sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element).filter { seen.insert($0.url).inserted }
    }

    private static func norm(_ s: String) -> String {
        // "Atomic Habits: An Easy & Proven Way…" → "atomic habits"; drop series numbers and punctuation.
        let main = s.split(whereSeparator: { ":(".contains($0) }).first.map(String.init) ?? s
        return main.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N} ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .split(separator: " ").filter { !["the", "a", "an"].contains($0) }.joined(separator: " ")
    }

    private static func overlap(_ a: String, _ b: String) -> Double {
        let x = Set(a.split(separator: " ")), y = Set(b.split(separator: " "))
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return Double(x.intersection(y).count) / Double(max(x.count, y.count))
    }
}
