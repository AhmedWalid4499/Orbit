import Foundation
import CryptoKit
import CommonCrypto

/// End-to-end encryption for API keys and tokens synced through your Orbit account.
/// Keys are encrypted on the device with a key derived from your sync passphrase, so the server
/// (and anyone with database access) only ever sees ciphertext.
///
/// Format (version 1), stable so a Windows app can read it:
///   key  = PBKDF2-HMAC-SHA256(passphrase, salt, 210 000 iterations, 32 bytes)
///   box  = AES-256-GCM(key, plaintext) as nonce ‖ ciphertext ‖ tag, base64
///   mac  = HMAC-SHA256(key, plaintext), hex: lets devices see whether content changed without decrypting
enum VaultCrypto {
    static let iterations: UInt32 = 210_000

    static func newSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let pass = Array(passphrase.utf8)
        _ = salt.withUnsafeBytes { saltPtr in
            pass.withUnsafeBufferPointer { passPtr in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     passPtr.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) }, pass.count,
                                     saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                                     &derived, derived.count)
            }
        }
        return SymmetricKey(data: derived)
    }

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> String {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else { throw CocoaError(.coderInvalidValue) }
        return combined.base64EncodedString()
    }

    /// nil when the passphrase is wrong or the data was tampered with.
    static func open(_ box: String, key: SymmetricKey) -> Data? {
        guard let data = Data(base64Encoded: box), let sealed = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(sealed, using: key)
    }

    static func mac(_ plaintext: Data, key: SymmetricKey) -> String {
        HMAC<SHA256>.authenticationCode(for: plaintext, using: key).map { String(format: "%02x", $0) }.joined()
    }
}
