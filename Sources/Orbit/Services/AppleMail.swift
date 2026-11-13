import Foundation
#if os(macOS)
import AppKit
#endif

/// Apple Mail as Joshu's inbox. On the Mac, Joshu reads recent inbox mail from the Mail app (with your permission, the
/// "Joshu wants to access Mail" prompt) to write the inbox summary, shows whole emails, and opens replies in Mail with
/// the text already written. iPhone apps can't read the Mail app, so the iPhone shows the summary your Mac makes
/// (it syncs with your account), opens each email in Mail, and writes replies in Apple's mail composer.
enum AppleMail {
    /// On when you connect Apple Mail (Settings › Connections); synced so the iPhone knows to show the summary.
    static let key = "inbox.appleMail"
    static var isOn: Bool { MailFeature.enabled && UserDefaults.standard.bool(forKey: key) }

    struct Message {
        let id: String          // the email's Message-ID header, e.g. <abc@mail.example.com>
        let account: String     // the Mail account it arrived in
        let from: String        // "Sara Hassan <sara@example.com>"
        let subject: String
        let date: Date?
        let read: Bool
        let snippet: String     // the start of the email's text

        var fromAddress: String {
            guard let lt = from.lastIndex(of: "<"), let gt = from.lastIndex(of: ">"), lt < gt else { return from }
            return String(from[from.index(after: lt)..<gt])
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Opens the email in Mail (works on Mac and iPhone): message://%3C<id>%3E.
    static func url(_ messageID: String) -> URL? {
        var id = messageID.trimmingCharacters(in: .whitespaces)
        if !id.hasPrefix("<") { id = "<\(id)>" }
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "@.-_"))) else { return nil }
        return URL(string: "message://\(encoded)")
    }

    #if os(macOS)
    static var isMailRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.mail" }
    }

    /// Mail keeps an index of every email (sender, subject, date, read, which mailbox) in a small database, and each email
    /// as a file. Reading those is instant even with tens of thousands of emails, where asking Mail itself takes minutes.
    /// macOS protects that folder: Joshu needs Full Disk Access to read it.
    static var mailFolder: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mail") }

    static var indexURL: URL? {
        let dirs = ((try? FileManager.default.contentsOfDirectory(atPath: mailFolder.path)) ?? [])
            .filter { $0.hasPrefix("V") && Int($0.dropFirst()) != nil }.sorted { Int($0.dropFirst())! > Int($1.dropFirst())! }
        for d in dirs {
            let u = mailFolder.appendingPathComponent("\(d)/MailData/Envelope Index")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    static var canReadMail: Bool {
        guard let u = indexURL else { return false }
        return FileManager.default.isReadableFile(atPath: u.path) && (try? FileHandle(forReadingFrom: u))?.readData(ofLength: 16).count == 16
    }

    static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!

    /// Checks Joshu can read Mail's index (Full Disk Access) and use Mail for replies (the "Joshu wants to access Mail"
    /// prompt). Returns what's missing, or nil when all is set.
    static func checkAccess() async -> String? {
        if indexURL == nil && !FileManager.default.fileExists(atPath: mailFolder.path) { return "Set up Mail on this Mac first (open Mail and add an account)." }
        if !canReadMail {
            await MainActor.run { Platform.open(fullDiskAccessURL) }
            return "Joshu needs Full Disk Access to read Mail (macOS keeps Mail's files private). In System Settings › Privacy & Security › Full Disk Access, turn on Joshu (or add it with +), then press Connect again."
        }
        do { _ = try await accountNames(); return nil }
        catch { return error.localizedDescription }
    }

    /// Account id (the folder name Mail uses) → the name you gave it in Mail. Remembered, so Joshu doesn't wake Mail for it.
    private static func accountNames() async throws -> [String: String] {
        let raw = try await run("""
        with timeout of 60 seconds
        tell application "Mail"
            set out to {}
            repeat with a in accounts
                set end of out to (id of a as string) & (character id 31) & (name of a)
            end repeat
        end tell
        end timeout
        set AppleScript's text item delimiters to (character id 30)
        return out as string
        """)
        var names: [String: String] = [:]
        for rec in raw.split(separator: "\u{1E}") {
            let f = rec.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
            if f.count == 2 { names[f[0]] = f[1] }
        }
        UserDefaults.standard.set(names, forKey: "inbox.appleMail.accounts")
        return names
    }

    private static func cachedAccountNames() async -> [String: String] {
        if isMailRunning, let n = try? await accountNames(), !n.isEmpty { return n }
        return UserDefaults.standard.dictionary(forKey: "inbox.appleMail.accounts") as? [String: String] ?? [:]
    }

    /// Where an email sits, from Mail's index.
    struct Location {
        let row: Int64
        let mailboxURL: String   // where its file is, e.g. imap://<account>/[Gmail]/All Mail
        let inboxURL: String?    // the inbox it shows in (Gmail keeps mail in All Mail with an Inbox label)
        var account: String { URL(string: mailboxURL)?.host ?? "" }
    }

    private static let inboxIDs = "SELECT ROWID FROM mailboxes WHERE url LIKE '%/INBOX' OR url LIKE '%/Inbox'"

    /// Inbox mail from the last `hours`, newest first, at most `limit` messages.
    static func recent(hours: Int, limit: Int = 50) async throws -> [Message] {
        guard canReadMail, let index = indexURL else {
            throw Failure(message: "Joshu can't read Mail. Turn on Joshu in System Settings › Privacy & Security › Full Disk Access.")
        }
        let since = Int64(Date.now.timeIntervalSince1970) - Int64(max(1, hours)) * 3600
        let sql = """
        SELECT m.ROWID, m.date_received, m.read, COALESCE(m.subject_prefix, '') || COALESCE(s.subject, ''),
               COALESCE(a.address, ''), COALESCE(a.comment, ''), COALESCE(g.message_id_header, ''), b.url, COALESCE(sm.summary, '')
        FROM messages m
        JOIN mailboxes b ON b.ROWID = m.mailbox
        LEFT JOIN subjects s ON s.ROWID = m.subject
        LEFT JOIN addresses a ON a.ROWID = m.sender
        LEFT JOIN summaries sm ON sm.ROWID = m.summary
        LEFT JOIN message_global_data g ON g.ROWID = m.global_message_id
        WHERE m.deleted = 0 AND m.date_received > \(since)
          AND (m.mailbox IN (\(inboxIDs)) OR EXISTS (SELECT 1 FROM labels l WHERE l.message_id = m.ROWID AND l.mailbox_id IN (\(inboxIDs))))
        ORDER BY m.date_received DESC
        LIMIT \(max(1, limit))
        """
        let rows = try await Task.detached(priority: .userInitiated) { try MailIndexReader.rows(index, sql) }.value
        let names = await cachedAccountNames()
        return await Task.detached(priority: .userInitiated) {
            var seen = Set<String>()
            return rows.compactMap { r -> Message? in
                let header = r[6]
                // The same email can sit in two accounts' inboxes (forwarding); keep one.
                if !header.isEmpty, !seen.insert(header).inserted { return nil }
                let mailbox = r[7]
                let account = URL(string: mailbox)?.host ?? ""
                let from = r[5].isEmpty ? r[4] : "\(r[5]) <\(r[4])>"
                var snippet = r[8]
                if snippet.isEmpty, let row = Int64(r[0]), let file = emlx(row: row, mailboxURL: mailbox, index: index) {
                    snippet = MIMEText.text(fromEmlx: file, limit: 4000)
                }
                snippet = snippet.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix(">") }.joined(separator: " ")
                return Message(id: header.isEmpty ? "row:\(r[0])" : header, account: names[account] ?? "Mail", from: from, subject: r[3],
                               date: Double(r[1]).map { Date(timeIntervalSince1970: $0) }, read: r[2] == "1",
                               snippet: String(snippet.prefix(400)))
            }
        }.value
    }

    /// Finds an email in Mail's index by its Message-ID header.
    static func locate(_ messageID: String) async throws -> Location {
        guard let index = indexURL, canReadMail else {
            throw Failure(message: "Joshu can't read Mail. Turn on Joshu in System Settings › Privacy & Security › Full Disk Access.")
        }
        let condition: String
        if messageID.hasPrefix("row:"), let row = Int64(messageID.dropFirst(4)) { condition = "m.ROWID = \(row)" }
        else { condition = "g.message_id_header = '\(messageID.replacingOccurrences(of: "'", with: "''"))'" }
        let sql = """
        SELECT m.ROWID, b.url,
               (SELECT ib.url FROM mailboxes ib WHERE ib.ROWID IN (\(inboxIDs)) AND (ib.ROWID = m.mailbox OR ib.ROWID IN (SELECT l.mailbox_id FROM labels l WHERE l.message_id = m.ROWID)) LIMIT 1) AS inbox
        FROM messages m JOIN mailboxes b ON b.ROWID = m.mailbox
        LEFT JOIN message_global_data g ON g.ROWID = m.global_message_id
        WHERE m.deleted = 0 AND \(condition)
        ORDER BY inbox IS NULL, m.date_received DESC LIMIT 1
        """
        let rows = try await Task.detached(priority: .userInitiated) { try MailIndexReader.rows(index, sql) }.value
        guard let r = rows.first, let row = Int64(r[0]) else { throw Failure(message: "That email isn't in Mail any more.") }
        return Location(row: row, mailboxURL: r[1], inboxURL: r[2].isEmpty ? nil : r[2])
    }

    /// The email's file: <Mail>/V10/<account>/<mailbox>.mbox/<id>/Data/<digits>/Messages/<row>.emlx
    /// (the digits are row / 1000, reversed, one folder each).
    nonisolated static func emlx(row: Int64, mailboxURL: String, index: URL) -> URL? {
        guard let u = URL(string: mailboxURL), let host = u.host else { return nil }
        let fm = FileManager.default
        var dir = index.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(host)
        for part in u.path.split(separator: "/") { dir.appendPathComponent(String(part).removingPercentEncoding.map { "\($0).mbox" } ?? "\(part).mbox") }
        var bucket = ""
        var k = row / 1000
        while k > 0 { bucket += "\(k % 10)/"; k /= 10 }
        let inner = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }
        for base in [dir] + inner.map({ dir.appendingPathComponent($0) }) {
            let messages = base.appendingPathComponent("Data/\(bucket)Messages")
            for name in ["\(row).emlx", "\(row).partial.emlx"] {
                let f = messages.appendingPathComponent(name)
                if fm.fileExists(atPath: f.path) { return f }
            }
        }
        return nil
    }

    /// The whole text of an email.
    static func body(messageID: String) async throws -> String {
        let loc = try await locate(messageID)
        guard let index = indexURL else { return "" }
        return await Task.detached(priority: .userInitiated) {
            guard let f = emlx(row: loc.row, mailboxURL: loc.mailboxURL, index: index) else { return "" }
            return MIMEText.text(fromEmlx: f, limit: 60_000)
        }.value
    }

    /// Opens a reply to the email in Mail with `text` already written above the quoted email. You send it from Mail.
    static func openReply(messageID: String, text: String) async throws {
        let loc = try await locate(messageID)
        let mailbox = mailboxSpecifier(loc.inboxURL ?? loc.mailboxURL)
        _ = try await run("""
        with timeout of 60 seconds
        tell application "Mail"
            set m to first message of \(mailbox) whose id is \(loc.row)
            set r to reply m with opening window
            delay 0.4
            set content of r to "\(escape(text))" & return & return & (content of r)
            activate
        end tell
        end timeout
        """)
    }

    /// `mailbox "INBOX" of account id "…"` for a mailbox address from Mail's index.
    static func mailboxSpecifier(_ mailboxURL: String) -> String {
        let u = URL(string: mailboxURL)
        let name = String((u?.path ?? "/INBOX").dropFirst()).removingPercentEncoding ?? "INBOX"
        return "mailbox \"\(escape(name))\" of account id \"\(escape(u?.host ?? ""))\""
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Runs AppleScript in `osascript` (off the main thread, so a slow Mail never freezes Joshu).
    static func run(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-"]
                let input = Pipe(), output = Pipe(), errors = Pipe()
                p.standardInput = input; p.standardOutput = output; p.standardError = errors
                do { try p.run() } catch { done.resume(throwing: error); return }
                input.fileHandleForWriting.write(Data(script.utf8))
                try? input.fileHandleForWriting.close()
                let out = output.fileHandleForReading.readDataToEndOfFile()
                let err = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit()
                guard p.terminationStatus == 0 else {
                    if err.contains("-1743") || err.contains("Not authorized") {
                        done.resume(throwing: Failure(message: "Joshu isn't allowed to use Mail. Turn it on in System Settings › Privacy & Security › Automation › Joshu › Mail."))
                    } else if err.contains("-1712") {
                        done.resume(throwing: Failure(message: "Mail took too long to answer. If macOS asked whether Joshu can use Mail, click OK, then try again."))
                    } else if err.contains("-1728") || err.contains("-1719") || err.contains("Can’t get") || err.contains("Can't get") {
                        done.resume(throwing: Failure(message: "Mail couldn't find that email in your inbox."))
                    } else {
                        done.resume(throwing: Failure(message: "Mail didn't answer. Is Mail set up on this Mac? (\(err.trimmingCharacters(in: .whitespacesAndNewlines).suffix(120)))"))
                    }
                    return
                }
                done.resume(returning: String(data: out, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? "")
            }
        }
    }
    #endif
}
