import SwiftUI
import AuthenticationServices
import CryptoKit

/// "Sign in with Apple", shown next to Google sign-in in the App Store build of the iPhone app (Apple requires it there).
/// Builds without the entitlement (installs from a free developer account, the Mac app) leave it out.
enum AppleSignIn {
    static var available: Bool {
        #if os(iOS)
        (Bundle.main.object(forInfoDictionaryKey: "JoshuSignInWithApple") as? String) == "YES"
        #else
        false
        #endif
    }

    /// A one-time random string; Apple gets its SHA-256 and puts it in the token, the server checks it against this.
    static func newNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    #if os(iOS)
    private static var request: CodeRequest?

    /// Asks Apple for a fresh one-time code, which Joshu's server trades in to end Sign in with Apple (see
    /// supabase/functions/apple-revoke). Throws CancellationError if they back out of Apple's sheet.
    @MainActor static func authorizationCode() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            let r = CodeRequest(continuation)
            request = r
            r.start()
        }
    }

    private final class CodeRequest: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        private let continuation: CheckedContinuation<String?, Error>
        init(_ continuation: CheckedContinuation<String?, Error>) { self.continuation = continuation }

        func start() {
            let controller = ASAuthorizationController(authorizationRequests: [ASAuthorizationAppleIDProvider().createRequest()])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?.authorizationCode
            continuation.resume(returning: code.flatMap { String(data: $0, encoding: .utf8) })
            AppleSignIn.request = nil
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            if (error as? ASAuthorizationError)?.code == .canceled { continuation.resume(throwing: CancellationError()) }
            else { continuation.resume(returning: nil) }
            AppleSignIn.request = nil
        }
    }
    #else
    @MainActor static func authorizationCode() async throws -> String? { nil }
    #endif
}

struct AppleSignInButton: View {
    var working = false
    /// Gets Apple's token, the nonce it was made with, and the person's name if Apple shared it.
    let onToken: (_ idToken: String, _ nonce: String, _ name: String?) -> Void
    let onError: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            nonce = AppleSignIn.newNonce()
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignIn.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                      let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                    onError("Apple didn't send a sign-in. Try again."); return
                }
                let name = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
                onToken(token, nonce, name?.trimmingCharacters(in: .whitespaces))
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                onError(error.localizedDescription)
            }
        }
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(working)
    }
}
