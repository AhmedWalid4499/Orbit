#if os(macOS)
import Foundation
import SQLite3

/// Read-only queries on another app's SQLite database (Mail's index), returning every column as text.
enum MailIndexReader {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    nonisolated static func rows(_ file: URL, _ sql: String) throws -> [[String]] {
        var db: OpaquePointer?
        // Read-only, and never create or change anything: Mail owns this file and keeps writing to it.
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI
        let uri = "file:\(file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw Failure(message: "Joshu can't open Mail's index. Turn on Joshu in System Settings › Privacy & Security › Full Disk Access.")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 3000)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw Failure(message: msg.contains("authoriz") || msg.contains("unable to open")
                          ? "Joshu can't open Mail's index. Turn on Joshu in System Settings › Privacy & Security › Full Disk Access."
                          : "Mail's index changed in a way Joshu doesn't understand (\(msg)).")
        }
        defer { sqlite3_finalize(stmt) }
        var out: [[String]] = []
        let n = sqlite3_column_count(stmt)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw Failure(message: "Couldn't read Mail's index (\(String(cString: sqlite3_errmsg(db)))).") }
            out.append((0..<n).map { i in sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" })
        }
        return out
    }
}

/// The readable text of an email file: Mail's .emlx (a byte count line, then the raw email). Picks the plain-text part
/// (or the HTML part with the tags taken out), and decodes base64, quoted-printable and the character set.
enum MIMEText {
    nonisolated static func text(fromEmlx file: URL, limit: Int) -> String {
        guard var data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return "" }
        if let nl = data.firstIndex(of: 0x0A), let count = Int(String(decoding: data[data.startIndex..<nl], as: UTF8.self).trimmingCharacters(in: .whitespaces)) {
            let start = data.index(after: nl)
            data = Data(data[start..<min(data.endIndex, start + count)])
        }
        let t = part(data, depth: 0) ?? ""
        return String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    /// Splits headers from body, unfolding continued header lines. Header names are lowercased.
    private nonisolated static func split(_ data: Data) -> ([String: String], Data) {
        let crlf = Data("\r\n\r\n".utf8), lf = Data("\n\n".utf8)
        let r1 = data.range(of: crlf), r2 = data.range(of: lf)
        let r = [r1, r2].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
        guard let r else { return ([:], data) }
        let head = String(decoding: data[data.startIndex..<r.lowerBound], as: UTF8.self)
        var headers: [String: String] = [:]
        var last: String?
        for line in head.components(separatedBy: .newlines) where !line.isEmpty {
            if line.first == " " || line.first == "\t", let k = last {
                headers[k, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let c = line.firstIndex(of: ":") {
                let k = line[..<c].lowercased()
                headers[k] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
                last = k
            }
        }
        return (headers, Data(data[r.upperBound...]))
    }

    /// `charset` from `text/plain; charset="utf-8"`.
    private nonisolated static func param(_ header: String, _ name: String) -> String? {
        for piece in header.split(separator: ";").dropFirst() {
            let kv = piece.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0].lowercased() == name { return kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        }
        return nil
    }

    /// The best text in this MIME part: plain text first, else HTML made into text.
    private nonisolated static func part(_ data: Data, depth: Int) -> String? {
        let (h, body) = split(data)
        let type = h["content-type"] ?? "text/plain"
        let kind = type.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "text/plain"
        if kind.hasPrefix("multipart/"), let boundary = param(type, "boundary"), depth < 8 {
            let parts = sections(body, boundary: boundary)
            var html: String?
            for p in parts {
                let (ph, _) = split(p)
                let pk = (ph["content-type"] ?? "text/plain").lowercased()
                if (ph["content-disposition"] ?? "").lowercased().hasPrefix("attachment") { continue }
                if pk.hasPrefix("text/plain") || pk.hasPrefix("multipart/") {
                    if let t = part(p, depth: depth + 1), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if pk.hasPrefix("text/plain") || !kind.hasPrefix("multipart/alternative") { return t }
                        html = html ?? t
                    }
                } else if pk.hasPrefix("text/html"), html == nil {
                    html = part(p, depth: depth + 1)
                }
            }
            return html
        }
        guard kind.hasPrefix("text/") || h["content-type"] == nil else { return nil }
        var raw = body
        switch (h["content-transfer-encoding"] ?? "").lowercased() {
        case "base64": raw = Data(base64Encoded: raw, options: .ignoreUnknownCharacters) ?? Data()
        case "quoted-printable": raw = quotedPrintable(raw)
        default: break
        }
        let text = decode(raw, charset: param(type, "charset"))
        return kind == "text/html" ? plain(html: text) : text
    }

    private nonisolated static func sections(_ body: Data, boundary: String) -> [Data] {
        let marker = Data("--\(boundary)".utf8)
        var out: [Data] = []
        var cursor = body.startIndex
        var start: Data.Index?
        while let r = body.range(of: marker, in: cursor..<body.endIndex) {
            if let s = start { out.append(Data(body[s..<r.lowerBound])) }
            var next = r.upperBound
            if body[next...].starts(with: Data("--".utf8)) { start = nil; break }
            while next < body.endIndex, body[next] == 0x0D || body[next] == 0x0A { next = body.index(after: next) }
            start = next
            cursor = next
        }
        if let s = start, s < body.endIndex { out.append(Data(body[s...])) }   // a partial file can stop mid-way
        return out
    }

    private nonisolated static func quotedPrintable(_ d: Data) -> Data {
        var out = Data(capacity: d.count)
        var i = d.startIndex
        func hex(_ b: UInt8) -> UInt8? {
            switch b { case 48...57: b - 48; case 65...70: b - 55; case 97...102: b - 87; default: nil }
        }
        while i < d.endIndex {
            let b = d[i]
            if b == 61 /* = */ {
                let n1 = d.index(after: i)
                if n1 < d.endIndex, d[n1] == 0x0A { i = d.index(after: n1); continue }
                if n1 < d.endIndex, d[n1] == 0x0D { i = d.index(n1, offsetBy: 2, limitedBy: d.endIndex) ?? d.endIndex; continue }
                let n2 = d.index(n1, offsetBy: 1, limitedBy: d.endIndex) ?? d.endIndex
                if n2 < d.endIndex, let h = hex(d[n1]), let l = hex(d[n2]) { out.append(h << 4 | l); i = d.index(after: n2); continue }
            }
            out.append(b)
            i = d.index(after: i)
        }
        return out
    }

    private nonisolated static func decode(_ d: Data, charset: String?) -> String {
        if let cs = charset {
            let cf = CFStringConvertIANACharSetNameToEncoding(cs as CFString)
            if cf != kCFStringEncodingInvalidId,
               let s = String(data: d, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) { return s }
        }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) ?? ""
    }

    /// HTML to readable text: drops styles and scripts, keeps line breaks, removes tags, decodes common entities.
    nonisolated static func plain(html: String) -> String {
        var s = html
        for tag in ["style", "script", "head", "title"] {
            s = s.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<(br|/p|/div|/tr|/li|/h[1-6])[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&zwnj;": "", "&#8217;": "’", "&#8211;": "–", "&#8212;": "—"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v, options: .caseInsensitive) }
        s = s.replacingOccurrences(of: "[ \\t\\u{00A0}\\u{200C}\\u{034F}]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " *\\n[ \\n]*", with: "\n", options: .regularExpression)
        return s
    }
}
#endif
