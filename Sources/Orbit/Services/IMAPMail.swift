import Foundation
import Network

/// An email account Joshu reads directly from its mail server (IMAP), on iPhone and Mac. You sign in with an
/// app-specific password, which stays in the Keychain on this device; Joshu talks straight to the provider.
struct IMAPAccount: Codable, Hashable, Identifiable {
    var id: String { email }
    var email: String
    var host: String
    var port: Int = 993
    var username: String
    var provider: String
}

enum IMAPMail {
    static let key = "inbox.imapAccounts"

    static var accounts: [IMAPAccount] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([IMAPAccount].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
    static var isOn: Bool { !accounts.isEmpty }

    static func passwordKey(_ email: String) -> String { "imap:\(email.lowercased())" }
    static func password(_ a: IMAPAccount) -> String? { Keychain.read(passwordKey(a.email)) }

    struct Provider: Identifiable, Hashable {
        let id: String
        let name: String
        let host: String
        /// Where you make an app-specific password, and how.
        let passwordPage: URL?
        let steps: [String]
    }

    static let providers: [Provider] = [
        Provider(id: "icloud", name: "iCloud Mail", host: "imap.mail.me.com",
                 passwordPage: URL(string: "https://account.apple.com/account/manage"),
                 steps: ["Open account.apple.com and sign in.", "Go to Sign-In and Security › App-Specific Passwords.",
                         "Press +, name it \"Joshu\", and copy the password it shows.", "Paste it in the password box above."]),
        Provider(id: "gmail", name: "Gmail", host: "imap.gmail.com",
                 passwordPage: URL(string: "https://myaccount.google.com/apppasswords"),
                 steps: ["Open myaccount.google.com/apppasswords and sign in. (It needs 2-Step Verification on: Security › 2-Step Verification.)",
                         "Type \"Joshu\" as the app name and press Create.", "Copy the 16-letter password and paste it in the password box above."]),
        Provider(id: "yahoo", name: "Yahoo Mail", host: "imap.mail.yahoo.com",
                 passwordPage: URL(string: "https://login.yahoo.com/myaccount/security/app-password"),
                 steps: ["Open Yahoo's Account Security page and sign in.", "Choose Generate app password, name it \"Joshu\".",
                         "Copy the password and paste it in the password box above."]),
        Provider(id: "other", name: "Other", host: "",
                 passwordPage: nil,
                 steps: ["Use your email provider's IMAP server (it's in their help pages, often imap.<your domain>).",
                         "If they offer app passwords, make one for Joshu; otherwise use your email password."]),
    ]

    /// The provider an address most likely belongs to.
    static func guessProvider(_ email: String) -> String {
        let domain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        if ["icloud.com", "me.com", "mac.com"].contains(domain) { return "icloud" }
        if ["gmail.com", "googlemail.com"].contains(domain) { return "gmail" }
        if domain.hasPrefix("yahoo.") || domain.hasPrefix("ymail.") || domain == "rocketmail.com" { return "yahoo" }
        return "other"
    }

    static func isMicrosoft(_ email: String) -> Bool {
        let domain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        return ["outlook.com", "hotmail.com", "live.com", "msn.com"].contains { domain == $0 || domain.hasPrefix($0.split(separator: ".")[0] + ".") }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Connecting

    /// Signs in once to check the details, trying the usual user-name forms. Returns the account to save.
    static func connect(email: String, password: String, provider: String, host: String, port: Int = 993) async throws -> IMAPAccount {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        let host = host.trimmingCharacters(in: .whitespaces).lowercased()
        guard email.contains("@") else { throw Failure(message: "Type your full email address.") }
        guard !host.isEmpty else { throw Failure(message: "Type your provider's IMAP server.") }
        if isMicrosoft(email) {
            throw Failure(message: "Outlook and Hotmail no longer allow app passwords, so Joshu can't connect them yet. Add the account to Apple Mail on your Mac and connect Apple Mail instead.")
        }
        // iCloud accepts the full address or just the part before @.
        var names = [email]
        if provider == "icloud", let local = email.split(separator: "@").first { names.append(String(local)) }
        var lastError: Error = Failure(message: "Couldn't sign in.")
        for name in names {
            let account = IMAPAccount(email: email, host: host, port: port, username: name, provider: provider)
            do {
                let s = try await IMAPSession.open(account, password: password)
                defer { s.close() }
                _ = try await s.run("EXAMINE INBOX")
                return account
            } catch let e as IMAPSession.LoginRejected {
                lastError = e
            }
        }
        throw lastError
    }

    static func add(_ account: IMAPAccount, password: String) {
        Keychain.write(password.replacingOccurrences(of: " ", with: ""), account: passwordKey(account.email))
        var list = accounts.filter { $0.email != account.email }
        list.append(account)
        accounts = list
    }

    static func remove(_ email: String) {
        Keychain.delete(passwordKey(email))
        accounts = accounts.filter { $0.email != email }
    }

    // MARK: Reading

    private static func imapDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d-MMM-yyyy"
        return f.string(from: d)
    }

    /// Inbox mail from the last `hours`, newest first (at most `limit`). Reads without marking anything read.
    static func recent(_ account: IMAPAccount, hours: Int, limit: Int, password given: String? = nil) async throws -> [AppleMail.Message] {
        guard let password = given ?? password(account) else { throw Failure(message: "Sign in to \(account.email) again (Settings › Connections).") }
        let cutoff = Date.now.addingTimeInterval(-Double(max(1, hours)) * 3600)
        let s = try await IMAPSession.open(account, password: password)
        defer { s.close() }
        _ = try await s.run("EXAMINE INBOX")
        var search = "UID SEARCH SINCE \(imapDate(cutoff))"
        // Gmail: leave out Promotions and Social, like the Gmail app's Primary tab.
        if account.host == "imap.gmail.com" { search += " X-GM-RAW \"-category:promotions -category:social\"" }
        let found = try await s.run(search)
        let uids = found.flatMap { r -> [Int] in
            guard r.text.hasPrefix("* SEARCH") else { return [] }
            return r.text.dropFirst(8).split(separator: " ").compactMap { Int($0) }
        }.sorted()
        let wanted = uids.suffix(limit)
        guard !wanted.isEmpty else { return [] }
        let fetched = try await s.run("UID FETCH \(wanted.map(String.init).joined(separator: ",")) (UID FLAGS INTERNALDATE BODY.PEEK[]<0.24000>)")
        let serverDate = DateFormatter()
        serverDate.locale = Locale(identifier: "en_US_POSIX")
        serverDate.dateFormat = "dd-MMM-yyyy HH:mm:ss Z"
        var out: [AppleMail.Message] = []
        for r in fetched where r.text.contains("FETCH (") {
            guard let raw = r.literals.first else { continue }
            let flags = IMAPSession.capture(r.text, #"FLAGS \(([^)]*)\)"#) ?? ""
            let dateText = (IMAPSession.capture(r.text, #"INTERNALDATE "([^"]+)""#) ?? "").trimmingCharacters(in: .whitespaces)
            let h = MIMEText.headers(raw)
            let date = serverDate.date(from: dateText)
            if let date, date < cutoff { continue }
            let text = MIMEText.text(fromRFC822: raw, limit: 4000)
                .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix(">") }.joined(separator: " ")
            let uid = IMAPSession.capture(r.text, #"UID (\d+)"#) ?? ""
            let messageID = (h["message-id"] ?? "").trimmingCharacters(in: .whitespaces)
            out.append(AppleMail.Message(id: messageID.isEmpty ? "uid:\(uid)" : messageID, account: account.email,
                                         from: h["from"] ?? "", subject: h["subject"] ?? "", date: date,
                                         read: flags.contains("\\Seen"), snippet: String(text.prefix(400))))
        }
        return out.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// The whole text of one email, found by its Message-ID.
    static func body(_ account: IMAPAccount, messageID: String, password given: String? = nil) async throws -> String {
        guard let password = given ?? password(account) else { throw Failure(message: "Sign in to \(account.email) again (Settings › Connections).") }
        let s = try await IMAPSession.open(account, password: password)
        defer { s.close() }
        _ = try await s.run("EXAMINE INBOX")
        var uid: Int?
        if messageID.hasPrefix("uid:") { uid = Int(messageID.dropFirst(4)) }
        else {
            let quoted = messageID.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "")
            let found = try await s.run("UID SEARCH HEADER Message-ID \"\(quoted)\"")
            uid = found.first { $0.text.hasPrefix("* SEARCH") }?.text.dropFirst(8).split(separator: " ").compactMap { Int($0) }.last
        }
        guard let uid else { throw Failure(message: "That email isn't in your inbox any more.") }
        let fetched = try await s.run("UID FETCH \(uid) (BODY.PEEK[]<0.400000>)")
        guard let raw = fetched.first(where: { !$0.literals.isEmpty })?.literals.first else { return "" }
        return MIMEText.text(fromRFC822: raw, limit: 60_000)
    }

    static func account(_ email: String) -> IMAPAccount? { accounts.first { $0.email == email } }
}

/// One signed-in IMAP connection over TLS. Commands run one at a time.
final class IMAPSession: @unchecked Sendable {
    struct Response { var text: String; var literals: [Data] }
    struct LoginRejected: LocalizedError {
        let detail: String
        var errorDescription: String? {
            "The email or app password wasn't accepted. Check you pasted the app-specific password (not your usual password)\(detail.isEmpty ? "" : ": \(detail)")."
        }
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "joshu.imap")
    private var buffer = Data()
    private var counter = 0
    private var closed = false

    private init(host: String, port: Int, tls: Bool) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 993,
                                  using: tls ? .tls : .tcp)
    }

    /// Connects and signs in. `ORBIT_IMAP_PLAIN=1` allows an unencrypted local test server (self-test only).
    static func open(_ account: IMAPAccount, password: String) async throws -> IMAPSession {
        let plain = account.host == "127.0.0.1" && ProcessInfo.processInfo.environment["ORBIT_IMAP_PLAIN"] == "1"
        let s = IMAPSession(host: account.host, port: account.port, tls: !plain)
        try await s.start()
        let greeting = try await s.readResponse()
        guard greeting.text.hasPrefix("* OK") || greeting.text.hasPrefix("* PREAUTH") else {
            s.close(); throw IMAPMail.Failure(message: "The mail server didn't say hello (\(greeting.text.prefix(80))).")
        }
        do {
            _ = try await s.run("LOGIN \(quote(account.username)) \(quote(password.replacingOccurrences(of: " ", with: "")))", secret: true)
        } catch let e as IMAPMail.Failure {
            s.close()
            throw LoginRejected(detail: e.message)
        }
        return s
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            // Every callback below runs on `queue`, so this flag is only touched there.
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            let finish: @Sendable (Result<Void, Error>) -> Void = { r in
                guard !once.done else { return }
                once.done = true
                done.resume(with: r)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(()))
                case .failed(let e): finish(.failure(IMAPMail.Failure(message: "Couldn't reach the mail server (\(e.localizedDescription)).")))
                case .waiting(let e): finish(.failure(IMAPMail.Failure(message: "Couldn't reach the mail server. Are you online? (\(e.localizedDescription))")))
                case .cancelled: finish(.failure(IMAPMail.Failure(message: "The connection to the mail server closed.")))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 20) { [weak self] in
                if !once.done { self?.connection.cancel(); finish(.failure(IMAPMail.Failure(message: "The mail server didn't answer."))) }
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.send(content: Data("Z LOGOUT\r\n".utf8), completion: .contentProcessed { [connection] _ in connection.cancel() })
    }

    /// Sends a command and returns its untagged responses. Throws when the server answers NO or BAD.
    func run(_ command: String, secret: Bool = false) async throws -> [Response] {
        counter += 1
        let tag = "J\(counter)"
        try await send(Data("\(tag) \(command)\r\n".utf8))
        var out: [Response] = []
        while true {
            let r = try await readResponse()
            if r.text.hasPrefix(tag + " ") {
                let rest = r.text.dropFirst(tag.count + 1)
                if rest.hasPrefix("OK") { return out }
                let reason = rest.drop { $0 != " " }.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"^\[[^\]]*\]\s*"#, with: "", options: .regularExpression)
                throw IMAPMail.Failure(message: secret ? reason : "The mail server said: \(reason)")
            }
            out.append(r)
        }
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { e in
                if let e { done.resume(throwing: IMAPMail.Failure(message: "Lost the connection to the mail server (\(e.localizedDescription)).")) }
                else { done.resume() }
            })
        }
    }

    /// More bytes from the server (waits at most 45 seconds).
    private func receive() async throws {
        let chunk: Data = try await withCheckedThrowingContinuation { (done: CheckedContinuation<Data, Error>) in
            var finished = false
            let timeout = DispatchWorkItem { [weak self] in
                guard !finished else { return }
                finished = true
                self?.connection.cancel()
                done.resume(throwing: IMAPMail.Failure(message: "The mail server stopped answering."))
            }
            queue.asyncAfter(deadline: .now() + 45, execute: timeout)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
                self.queue.async {
                    guard !finished else { return }
                    finished = true
                    timeout.cancel()
                    if let data, !data.isEmpty { done.resume(returning: data) }
                    else if let error { done.resume(throwing: IMAPMail.Failure(message: "Lost the connection to the mail server (\(error.localizedDescription)).")) }
                    else if isComplete { done.resume(throwing: IMAPMail.Failure(message: "The mail server closed the connection.")) }
                    else { done.resume(returning: Data()) }
                }
            }
        }
        buffer.append(chunk)
    }

    /// The first capture group of `pattern` in `text`.
    static func capture(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private func readLine() async throws -> String {
        while true {
            if let r = buffer.range(of: Data("\r\n".utf8)) {
                let line = String(decoding: buffer[buffer.startIndex..<r.lowerBound], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex..<r.upperBound)
                return line
            }
            try await receive()
        }
    }

    private func readBytes(_ n: Int) async throws -> Data {
        while buffer.count < n { try await receive() }
        let d = Data(buffer.prefix(n))
        buffer.removeSubrange(buffer.startIndex..<buffer.startIndex + n)
        return d
    }

    /// One response: a line, plus any {n} literals it carries (an email's bytes) and the text after them.
    private func readResponse() async throws -> Response {
        var r = Response(text: try await readLine(), literals: [])
        while let open = r.text.range(of: #"\{\d+\}$"#, options: .regularExpression), let n = Int(r.text[open].dropFirst().dropLast()) {
            r.literals.append(try await readBytes(n))
            r.text = String(r.text[..<open.lowerBound]) + "<literal>" + (try await readLine())
        }
        return r
    }
}
