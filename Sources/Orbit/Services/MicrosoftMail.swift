import Foundation
import CryptoKit

/// "Sign in with Microsoft" for Outlook, Hotmail and Live mail: Microsoft's own sign-in page (loopback + PKCE, no
/// secret), then Joshu reads the inbox over IMAP with the token. The refresh token stays in the Keychain.
/// Needs the app's Microsoft registration (see MICROSOFT_SIGNIN.md); the button stays hidden until it's set.
enum MicrosoftMail {
    /// Application (client) ID from the Microsoft Entra app registration. Public: it identifies Joshu, it isn't a secret.
    static let clientID = ""
    static var isConfigured: Bool { !clientID.isEmpty }

    static let host = "outlook.office365.com"
    private static let scope = "openid email profile offline_access https://outlook.office.com/IMAP.AccessAsUser.All"
    private static let base = "https://login.microsoftonline.com/common/oauth2/v2.0"

    static func tokenKey(_ email: String) -> String { "msmail:\(email.lowercased())" }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Microsoft's sign-in page; returns the account to save (its refresh token is already in the Keychain).
    @MainActor
    static func signIn(hint: String? = nil) async throws -> IMAPAccount {
        guard isConfigured else { throw Failure(message: "Microsoft sign-in isn't set up in this copy of Joshu yet.") }
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let server = try LoopbackServer()
        let port = try await server.start()
        let redirect = "http://127.0.0.1:\(port)"
        var comps = URLComponents(string: "\(base)/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirect), .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account"),
        ] + (hint.map { [URLQueryItem(name: "login_hint", value: $0)] } ?? [])
        let code: String
        do { code = try await GoogleAuth.answer(from: comps.url!, server: server) }
        catch is CancellationError { throw CancellationError() }
        catch { throw Failure(message: "Microsoft sign-in was cancelled.") }
        let tokens = try await token(["grant_type": "authorization_code", "code": code, "redirect_uri": redirect, "code_verifier": verifier])
        guard let refresh = tokens["refresh_token"] as? String, let access = tokens["access_token"] as? String else {
            throw Failure(message: "Microsoft didn't finish signing in. Try again.")
        }
        guard let email = (tokens["id_token"] as? String).flatMap(emailFromIDToken), email.contains("@") else {
            throw Failure(message: "Microsoft didn't say which email address this is.")
        }
        let account = IMAPAccount(email: email.lowercased(), host: host, port: 993, username: email.lowercased(), provider: "outlook", auth: "microsoft")
        Keychain.write(refresh, account: tokenKey(account.email))
        cache[account.email] = (access, Date.now.addingTimeInterval(Double(tokens["expires_in"] as? Int ?? 3600) - 120))
        return account
    }

    @MainActor private static var cache: [String: (token: String, expires: Date)] = [:]

    /// A current access token for reading the inbox, renewed with the saved refresh token when needed.
    @MainActor
    static func accessToken(_ email: String) async throws -> String {
        if let c = cache[email], c.expires > .now { return c.token }
        guard let refresh = Keychain.read(tokenKey(email)) else {
            throw Failure(message: "Sign in to \(email) with Microsoft again (Settings › Connections).")
        }
        let tokens = try await token(["grant_type": "refresh_token", "refresh_token": refresh])
        guard let access = tokens["access_token"] as? String else { throw Failure(message: "Microsoft sign-in expired. Connect \(email) again.") }
        // Microsoft hands out a new refresh token each time; keep the newest.
        if let newRefresh = tokens["refresh_token"] as? String { Keychain.write(newRefresh, account: tokenKey(email)) }
        cache[email] = (access, Date.now.addingTimeInterval(Double(tokens["expires_in"] as? Int ?? 3600) - 120))
        return access
    }

    static func forget(_ email: String) { Keychain.delete(tokenKey(email)) }

    private static func token(_ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "\(base)/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let all = form.merging(["client_id": clientID, "scope": scope]) { a, _ in a }
        req.httpBody = all.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let err = json["error"] as? String {
            let detail = (json["error_description"] as? String ?? err).components(separatedBy: .newlines).first ?? err
            throw Failure(message: "Microsoft sign-in failed: \(detail)")
        }
        return json
    }

    /// The address in the sign-in token (its middle part is plain JSON).
    static func emailFromIDToken(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (claims["email"] as? String) ?? (claims["preferred_username"] as? String)
    }

    /// The SASL XOAUTH2 string IMAP servers take: base64("user=<email>^Aauth=Bearer <token>^A^A").
    static func xoauth2(email: String, token: String) -> String {
        Data("user=\(email)\u{01}auth=Bearer \(token)\u{01}\u{01}".utf8).base64EncodedString()
    }
}
