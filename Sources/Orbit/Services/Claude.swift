import Foundation
import Security

// MARK: - Keychain

/// All of Orbit's secrets (API keys, tokens) live in ONE login-keychain item, read once per launch
/// and cached in memory. Because the item is created by the signed app, later builds read it without
/// any password prompt.
enum Keychain {
    private static let service = "com.personal.orbit"
    private static let vaultAccount = "orbit-secrets"
    private static let lock = NSLock()
    private static var cache: [String: String]?

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func rawRead(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func vault() -> [String: String] {
        if let cache { return cache }
        var dict = rawRead(vaultAccount).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        // One-time move of items saved by older builds (each used to be its own keychain item).
        if !UserDefaults.standard.bool(forKey: "keychainVaultMigrated") {
            let legacy = ["anthropic-api-key", "github-token", "google-client-secret"]
                + (UserDefaults.standard.stringArray(forKey: "gmailAccounts") ?? []).map { "gmail:\($0)" }
            for account in legacy {
                if dict[account] == nil, let data = rawRead(account), let value = String(data: data, encoding: .utf8), !value.isEmpty {
                    dict[account] = value
                }
                SecItemDelete(query(account) as CFDictionary)
            }
            persist(dict)
            UserDefaults.standard.set(true, forKey: "keychainVaultMigrated")
        }
        cache = dict
        return dict
    }

    private static func persist(_ dict: [String: String]) {
        SecItemDelete(query(vaultAccount) as CFDictionary)
        var q = query(vaultAccount)
        q[kSecValueData as String] = (try? JSONEncoder().encode(dict)) ?? Data()
        q[kSecAttrLabel as String] = "Orbit secrets"
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return vault()[account]
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var dict = vault()
        dict[account] = value
        cache = dict
        persist(dict)
        return true
    }

    static func delete(_ account: String) {
        lock.lock(); defer { lock.unlock() }
        var dict = vault()
        dict[account] = nil
        cache = dict
        persist(dict)
    }

    /// Loads the vault early so any one-time prompt happens at launch, not mid-task.
    static func warmUp() { _ = read("anthropic-api-key") }

    // Anthropic API key
    static var apiKey: String? { read("anthropic-api-key") }
    @discardableResult static func save(_ key: String) -> Bool { write(key, account: "anthropic-api-key") }
    static func delete() { delete("anthropic-api-key") }
}

// MARK: - Messages API client

/// Minimal Claude Messages API client (Swift has no official Anthropic SDK, so this is raw HTTP).
struct ClaudeClient {
    static let model = "claude-opus-5-5"

    enum Failure: LocalizedError {
        case noKey, badKey, rateLimited, overloaded, refused, server(Int, String), network(String), badResponse

        var errorDescription: String? {
            switch self {
            case .noKey: "Add your Anthropic API key in Settings › AI."
            case .badKey: "The API key was rejected. Check it in Settings › AI."
            case .rateLimited: "Rate limited by the API. Try again in a minute."
            case .overloaded: "Claude is busy right now. Try again shortly."
            case .refused: "Claude declined this request."
            case .server(let code, let msg): "API error \(code): \(msg)"
            case .network(let msg): "Network problem: \(msg)"
            case .badResponse: "Unexpected response from the API."
            }
        }
    }

    let apiKey: String

    init?(apiKey: String? = Keychain.apiKey) {
        guard let apiKey else { return nil }
        self.apiKey = apiKey
    }

    /// Sends one request with a JSON-schema constrained answer and decodes it.
    func structured<T: Decodable>(_ type: T.Type, system: String, user: String, schema: [String: Any],
                                  effort: String, maxTokens: Int = 16000) async throws -> T {
        let reply = try await send(system: system, messages: [["role": "user", "content": user]],
                                   schema: schema, effort: effort, maxTokens: maxTokens)
        return try reply.decode(T.self)
    }

    struct Reply {
        /// The text block (JSON when a schema was given).
        let text: String
        /// The assistant's full `content` array, to be replayed unchanged in later turns.
        let rawContent: Data

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(T.self, from: data) else {
                throw Failure.badResponse
            }
            return value
        }
    }

    /// One Messages API call. `messages` is passed through as-is, so multi-turn callers own the history.
    func send(system: String, messages: [[String: Any]], schema: [String: Any]?,
              effort: String, maxTokens: Int = 16000) async throws -> Reply {
        var outputConfig: [String: Any] = ["effort": effort]
        if let schema { outputConfig["format"] = ["type": "json_schema", "schema": schema] }
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages,
            "output_config": outputConfig,
            // Server-side fallback: if a safety classifier declines, the API retries on a suitable model.
            "fallbacks": "default",
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        switch http.statusCode {
        case 200: break
        case 401, 403: throw Failure.badKey
        case 429: throw Failure.rateLimited
        case 529: throw Failure.overloaded
        default:
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "Unknown error"
            throw Failure.server(http.statusCode, msg)
        }

        guard let json else { throw Failure.badResponse }
        if json["stop_reason"] as? String == "refusal" { throw Failure.refused }
        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
            throw Failure.badResponse
        }
        let raw = (try? JSONSerialization.data(withJSONObject: blocks)) ?? Data()
        return Reply(text: text, rawContent: raw)
    }

    /// Streams a plain-text reply. `onText` receives the full text so far after every delta.
    /// Returns the final content blocks, sanitised for replay after a mid-stream fallback.
    func stream(system: String, messages: [[String: Any]], effort: String, maxTokens: Int = 8000,
                onText: @escaping @MainActor (String) -> Void) async throws -> Reply {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages,
            "output_config": ["effort": effort],
            "fallbacks": "default",
            "stream": true,
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let bytes: URLSession.AsyncBytes, response: URLResponse
        do { (bytes, response) = try await URLSession.shared.bytes(for: req) } catch {
            throw Failure.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        guard http.statusCode == 200 else {
            switch http.statusCode {
            case 401, 403: throw Failure.badKey
            case 429: throw Failure.rateLimited
            case 529: throw Failure.overloaded
            default: throw Failure.server(http.statusCode, "Request failed")
            }
        }

        var blocks: [Int: [String: Any]] = [:]
        var stopReason: String?
        func visibleText() -> String {
            blocks.keys.sorted().compactMap { i in blocks[i]?["type"] as? String == "text" ? blocks[i]?["text"] as? String : nil }.joined()
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:"), let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            switch event["type"] as? String {
            case "content_block_start":
                if let i = event["index"] as? Int, let block = event["content_block"] as? [String: Any] { blocks[i] = block }
            case "content_block_delta":
                guard let i = event["index"] as? Int, let delta = event["delta"] as? [String: Any], var block = blocks[i] else { continue }
                switch delta["type"] as? String {
                case "text_delta":
                    block["text"] = (block["text"] as? String ?? "") + (delta["text"] as? String ?? "")
                    blocks[i] = block
                    let text = visibleText()
                    await onText(text)
                case "thinking_delta":
                    block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                    blocks[i] = block
                case "signature_delta":
                    block["signature"] = delta["signature"]
                    blocks[i] = block
                default: break
                }
            case "message_delta":
                if let d = event["delta"] as? [String: Any], let r = d["stop_reason"] as? String { stopReason = r }
            case "error":
                let msg = ((event["error"] as? [String: Any])?["message"] as? String) ?? "Stream error"
                if msg.lowercased().contains("overloaded") { throw Failure.overloaded }
                throw Failure.server(0, msg)
            default: break
            }
        }

        if stopReason == "refusal" { throw Failure.refused }
        var ordered = blocks.keys.sorted().compactMap { blocks[$0] }
        // After a mid-output fallback, blocks before the last `fallback` marker other than text can't be echoed back.
        if let boundary = ordered.lastIndex(where: { $0["type"] as? String == "fallback" }) {
            ordered = ordered.enumerated().compactMap { i, b in
                let t = b["type"] as? String ?? ""
                return i < boundary && t != "text" ? nil : b
            }
        }
        let text = visibleText()
        guard !text.isEmpty else { throw Failure.badResponse }
        return Reply(text: text, rawContent: (try? JSONSerialization.data(withJSONObject: ordered)) ?? Data())
    }
}
