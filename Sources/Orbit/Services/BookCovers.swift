import Foundation
import CryptoKit
import SwiftUI

/// Book covers that always show up: downloaded once and kept on disk, and when a book has no cover (or its link is
/// broken, or is the blank "no photo" image) Orbit looks it up on Google Books, then Open Library, and saves the link.
@MainActor
enum BookCovers {
    private static var memory: [String: PlatformImage] = [:]
    private static var looking: Set<String> = []
    /// Links that didn't give a picture this run, so they aren't tried again.
    private static var broken: Set<String> = []

    static var folder: URL {
        let dir = URL.cachesDirectory.appending(path: "Orbit/covers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(for url: String) -> URL {
        let h = SHA256.hash(data: Data(url.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: "\(h).jpg")
    }

    /// The cover for `book`, finding one if needed.
    static func image(for book: Book) async -> PlatformImage? {
        if !book.coverURL.isEmpty, let img = await image(at: book.coverURL) { return img }
        guard !Snapshot.isActive, !looking.contains(book.matchKey) else { return nil }
        looking.insert(book.matchKey)
        defer { looking.remove(book.matchKey) }
        for candidate in await find(title: book.title, author: book.author, isbn: book.isbn) where candidate != book.coverURL {
            if let img = await image(at: candidate) {
                book.coverURL = candidate
                return img
            }
        }
        return nil
    }

    /// A downloaded (or cached) picture at `url`, or nil if it's missing or a placeholder.
    static func image(at raw: String) async -> PlatformImage? {
        let url = raw.replacingOccurrences(of: "http://", with: "https://")
        if let m = memory[url] { return m }
        let f = file(for: url)
        if let img = PlatformImage.load(f) { memory[url] = img; return img }
        guard !broken.contains(url), let u = URL(string: url) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: u),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1500,
              let img = PlatformImage(data: data), let cg = img.cg, cg.width > 20, cg.height > 20 else {
            broken.insert(url)
            return nil
        }
        try? (img.jpeg(maxSide: 600) ?? data).write(to: f, options: .atomic)
        memory[url] = img
        return img
    }

    /// Cover links to try, best first.
    static func find(title: String, author: String, isbn: String) async -> [String] {
        var out: [String] = []
        // Google Books has covers for most books, including recent and translated ones.
        var g = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        let q = isbn.isEmpty ? "intitle:\(title)" + (author.isEmpty ? "" : " inauthor:\(author)") : "isbn:\(isbn)"
        g.queryItems = [.init(name: "q", value: q), .init(name: "maxResults", value: "5"), .init(name: "printType", value: "books")]
        if let (data, _) = try? await URLSession.shared.data(from: g.url!),
           let items = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["items"] as? [[String: Any]] {
            for item in items {
                let links = (item["volumeInfo"] as? [String: Any])?["imageLinks"] as? [String: String] ?? [:]
                if let t = links["thumbnail"] ?? links["smallThumbnail"] {
                    out.append(t.replacingOccurrences(of: "http://", with: "https://").replacingOccurrences(of: "&edge=curl", with: ""))
                }
            }
        }
        if !isbn.isEmpty { out.append("https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false") }
        if let hits = try? await OpenLibrary.search("\(title) \(author)") {
            out += hits.prefix(3).map(\.coverURL).filter { !$0.isEmpty }.map { $0.replacingOccurrences(of: "-M.jpg", with: "-L.jpg") }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}
