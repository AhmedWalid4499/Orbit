import Foundation

/// Reads whole emails and sends replies through Gmail, so you can deal with mail without leaving Orbit.
/// Sending needs the gmail.send permission; accounts connected before Orbit could send are asked once to allow it.
struct MailMessage: Identifiable, Equatable {
    let id: String
    let threadID: String
    let account: String
    let from: String
    let fromAddress: String
    let to: String
    let subject: String
    let date: Date?
    let body: String
    let messageIDHeader: String
    let references: String
    var unread: Bool
    /// The email's own HTML (how it looks in Gmail), or "" for plain-text mail.
    var html = ""

    var sender: String { InboxStore.displayName(from) }
}

struct MailListItem: Identifiable, Equatable {
    let id: String
    let account: String
    let from: String
    let subject: String
    let snippet: String
    let date: Date?
    let unread: Bool
}

@MainActor
enum MailReader {
    struct NeedsPermission: LocalizedError {
        let account: String
        var errorDescription: String? { "Orbit needs your OK to send from \(account). Tap “Allow sending” and approve it once." }
    }

    static func message(_ id: String, account: String) async throws -> MailMessage {
        if Snapshot.isDemo { return demoMessage(id, account: account) }
        let token = try await GoogleAuth.accessToken(for: account)
        let json = try await gmailJSON(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full")!, token: token)
        let payload = json["payload"] as? [String: Any] ?? [:]
        let headers = payload["headers"] as? [[String: Any]] ?? []
        func h(_ n: String) -> String { headers.first { ($0["name"] as? String)?.lowercased() == n.lowercased() }?["value"] as? String ?? "" }
        let from = h("From")
        let address = from.firstIndex(of: "<").map { String(from[from.index(after: $0)...].prefix { $0 != ">" }) } ?? from
        let labels = json["labelIds"] as? [String] ?? []
        return MailMessage(id: id, threadID: json["threadId"] as? String ?? "", account: account, from: from, fromAddress: address,
                           to: h("To"), subject: h("Subject"), date: Self.date(json["internalDate"]), body: text(of: payload),
                           messageIDHeader: h("Message-ID").isEmpty ? h("Message-Id") : h("Message-ID"), references: h("References"),
                           unread: labels.contains("UNREAD"), html: htmlPart(of: payload))
    }

    /// The text/html part of a message, if it has one.
    static func htmlPart(of payload: [String: Any]) -> String {
        func walk(_ p: [String: Any]) -> String? {
            if (p["mimeType"] as? String ?? "").lowercased() == "text/html",
               let data = (p["body"] as? [String: Any])?["data"] as? String, let s = decode(data) { return s }
            for part in p["parts"] as? [[String: Any]] ?? [] { if let s = walk(part) { return s } }
            return nil
        }
        return walk(payload) ?? ""
    }

    /// Recent inbox mail across your accounts, newest first.
    static func recent(accounts: [String], limit: Int = 25) async throws -> [MailListItem] {
        if Snapshot.isDemo { return demoList }
        var all: [MailListItem] = []
        for account in accounts {
            let token = try await GoogleAuth.accessToken(for: account)
            var c = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
            c.queryItems = [.init(name: "q", value: "in:inbox -category:promotions -category:social"), .init(name: "maxResults", value: "\(limit)")]
            let ids = ((try await gmailJSON(c.url!, token: token))["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            try await withThrowingTaskGroup(of: MailListItem?.self) { group in
                for id in ids {
                    group.addTask {
                        let u = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=metadata&metadataHeaders=From&metadataHeaders=Subject")!
                        let j = try await gmailJSON(u, token: token)
                        let headers = (j["payload"] as? [String: Any])?["headers"] as? [[String: Any]] ?? []
                        func h(_ n: String) -> String { headers.first { ($0["name"] as? String) == n }?["value"] as? String ?? "" }
                        return MailListItem(id: id, account: account, from: InboxStore.displayName(h("From")), subject: h("Subject"),
                                            snippet: (j["snippet"] as? String ?? "").htmlDecoded, date: await MailReader.date(j["internalDate"]),
                                            unread: (j["labelIds"] as? [String] ?? []).contains("UNREAD"))
                    }
                }
                for try await item in group { if let item { all.append(item) } }
            }
        }
        return all.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Sends `body` as a reply in the same thread.
    static func reply(to m: MailMessage, body: String) async throws {
        if Snapshot.isDemo { return }
        let token = try await GoogleAuth.accessToken(for: m.account)
        let subject = m.subject.lowercased().hasPrefix("re:") ? m.subject : "Re: \(m.subject)"
        var lines = ["To: \(m.from)", "Subject: \(encodeHeader(subject))", "MIME-Version: 1.0", "Content-Type: text/plain; charset=UTF-8",
                     "Content-Transfer-Encoding: 8bit"]
        if !m.messageIDHeader.isEmpty {
            lines.append("In-Reply-To: \(m.messageIDHeader)")
            lines.append("References: \((m.references + " " + m.messageIDHeader).trimmingCharacters(in: .whitespaces))")
        }
        let raw = (lines.joined(separator: "\r\n") + "\r\n\r\n" + body.replacingOccurrences(of: "\n", with: "\r\n"))
        var req = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["raw": Data(raw.utf8).base64URL, "threadId": m.threadID])
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 || (status == 401 && String(data: data, encoding: .utf8)?.contains("scope") == true) { throw NeedsPermission(account: m.account) }
        guard status == 200 else { throw GmailError("Gmail couldn't send it (\(status)).") }
    }

    /// A reply in your voice, drafted by Claude from the email and what you want to say (can be empty).
    static func draftReply(to m: MailMessage, intent: String) async throws -> String {
        guard let client = ClaudeClient() else { throw ClaudeClient.Failure.noKey }
        let me = Platform.userName.split(separator: " ").first.map(String.init) ?? ""
        struct Out: Decodable { let reply: String }
        let out = try await client.structured(Out.self, system: """
            You write email replies for \(me.isEmpty ? "the user" : me). Read the email carefully and write the complete reply they would send.
            - Their notes are rough instructions about what to say ("yes 8:30 works", "decline politely, busy that week"), not the reply itself. \
            Never copy the notes word for word: turn them into a proper, well-written reply that answers what the email actually asks, \
            mentions the specifics (names, dates, times, places from the email) and adds the small courtesies a person would.
            - Without notes, write the most sensible reply to what the email asks.
            - Match the tone of the email (casual for friends, polite for work). Greeting with their name, 2-5 short sentences, a friendly close, then \(me.isEmpty ? "their first name" : me).
            - Plain text, no subject line, no placeholders like [Name]. Reply in the email's language.
            """, user: "THE EMAIL\nFrom: \(m.from)\nSubject: \(m.subject)\n\n\(m.body.prefix(6000))\n\nMY NOTES FOR THE REPLY: \(intent.isEmpty ? "(none, decide a sensible reply)" : intent)",
            schema: ["type": "object", "properties": ["reply": ["type": "string"]], "required": ["reply"], "additionalProperties": false],
            effort: "medium", maxTokens: 6000)
        return out.reply
    }

    // MARK: Parsing

    static func date(_ v: Any?) -> Date? {
        (v as? String).flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// The readable text of a message: its plain-text part, or the HTML part turned into text.
    static func text(of payload: [String: Any]) -> String {
        var plain: String?, html: String?
        func walk(_ p: [String: Any]) {
            let mime = (p["mimeType"] as? String ?? "").lowercased()
            if let data = (p["body"] as? [String: Any])?["data"] as? String, let s = decode(data) {
                if mime == "text/plain", plain == nil { plain = s }
                if mime == "text/html", html == nil { html = s }
            }
            for part in p["parts"] as? [[String: Any]] ?? [] { walk(part) }
        }
        walk(payload)
        if let plain, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return tidy(plain) }
        return tidy(stripHTML(html ?? ""))
    }

    private static func decode(_ b64url: String) -> String? {
        var s = b64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s).flatMap { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1) }
    }

    static func stripHTML(_ html: String) -> String {
        var s = html
        for (pattern, with) in [(#"(?is)<(script|style|head)[^>]*>.*?</\1>"#, ""), (#"(?i)<br\s*/?>"#, "\n"), (#"(?i)</(p|div|tr|li|h\d)>"#, "\n"),
                                (#"(?i)<li[^>]*>"#, "• "), (#"<[^>]+>"#, "")] {
            s = s.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        return s.htmlDecoded
    }

    /// Collapses blank lines and drops the quoted earlier messages ("On … wrote:").
    private static func tidy(_ s: String) -> String {
        var lines: [String] = []
        for line in s.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(">") { continue }
            if t.range(of: #"^On .+ wrote:$"#, options: .regularExpression) != nil { break }
            if t.isEmpty && (lines.last?.isEmpty ?? true) { continue }
            lines.append(t)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func encodeHeader(_ s: String) -> String {
        s.allSatisfy(\.isASCII) ? s : "=?UTF-8?B?\(Data(s.utf8).base64EncodedString())?="
    }

    // MARK: Sample mail for screenshots

    static let demoList: [MailListItem] = [
        .init(id: "demo1", account: "alex@example.com", from: "Sara", subject: "Dinner Saturday?", snippet: "Hey! Are we still on for Saturday at 8? I booked…", date: .now.addingTimeInterval(-3600), unread: true),
        .init(id: "demo2", account: "alex@example.com", from: "Amazon", subject: "Your order is on its way", snippet: "Your headphones arrive tomorrow before 6 pm.", date: .now.addingTimeInterval(-7200), unread: false),
        .init(id: "demo3", account: "alex@example.com", from: "Omar", subject: "Slides for Monday", snippet: "Attached the latest deck, can you take a look before…", date: .now.addingTimeInterval(-26000), unread: true),
    ]

    private static func demoMessage(_ id: String, account: String) -> MailMessage {
        let item = demoList.first { $0.id == id } ?? demoList[0]
        return MailMessage(id: id, threadID: id, account: account, from: "\(item.from) <\(item.from.lowercased())@example.com>",
                           fromAddress: "\(item.from.lowercased())@example.com", to: account, subject: item.subject, date: item.date,
                           body: "Hey Alex!\n\nAre we still on for Saturday at 8? I booked a table at Zooba in Zamalek, the one with the terrace.\n\nLet me know if 8 still works or if we should push it to 8:30.\n\nSara",
                           messageIDHeader: "", references: "", unread: item.unread)
    }
}

extension String {
    /// Turns &amp; &#39; and friends back into characters.
    var htmlDecoded: String {
        guard contains("&") else { return self }
        var s = self
        for (k, v) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&rsquo;": "’", "&lsquo;": "‘",
                       "&ldquo;": "“", "&rdquo;": "”", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…", "&zwnj;": ""] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s.replacingOccurrences(of: #"&#(\d+);"#, with: "", options: .regularExpression)
    }
}
