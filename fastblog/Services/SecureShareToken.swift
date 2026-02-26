import CryptoKit
import Foundation

/// Generates AES-GCM encrypted, URL-safe share tokens.
///
/// The token encodes `username:blogKey` so the web server can decrypt and
/// extract both values without any server-side state (stateless).
///
/// **Key setup:**
/// 1. Generate:  `openssl rand -base64 32`
/// 2. Copy `Secrets.xcconfig.example` → `Secrets.xcconfig` and fill in the key.
/// 3. Set the same value as `SHARE_TOKEN_KEY` env var on the web server.
///
/// **Token layout (before base64url encoding):**
/// `nonce (12 B) | AES-GCM ciphertext | GCM auth tag (16 B)`
struct SecureShareToken {

    // MARK: - Configuration

    /// Reads the 32-byte AES-256 key from Info.plist.
    /// Info.plist expands $(SHARE_TOKEN_KEY), which comes from the
    /// git-ignored Secrets.xcconfig at build time — never hardcoded in source.
    private static var symmetricKey: SymmetricKey {
        guard
            let b64 = Bundle.main.object(forInfoDictionaryKey: "ShareTokenKey") as? String,
            !b64.isEmpty,
            let data = Data(base64Encoded: b64),
            data.count == 32
        else {
            fatalError(
                "SecureShareToken: SHARE_TOKEN_KEY is missing or invalid.\n" +
                "Copy Secrets.xcconfig.example → Secrets.xcconfig and fill in the key.\n" +
                "Generate one with:  openssl rand -base64 32"
            )
        }
        return SymmetricKey(data: data)
    }

    // MARK: - Public API

    /// Returns an AES-GCM encrypted share URL for the given username and blog key.
    /// Returns nil only if CryptoKit fails (should never happen in practice).
    static func shareURL(username: String, blogKey: Int) -> URL? {
        guard let token = try? encrypt(username: username, blogKey: blogKey) else { return nil }
        return URL(string: "https://bloggo.linkedspaces.com/trip/t/\(token)")
    }

    // MARK: - Internals

    /// Encrypts `"username:blogKey"` into a single base64url token.
    static func encrypt(username: String, blogKey: Int) throws -> String {
        let plaintext = Data("\(username):\(blogKey)".utf8)
        let sealed = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = sealed.combined else {
            throw SecureShareError.sealFailed
        }
        return combined.base64URLEncoded()
    }

    enum SecureShareError: Error {
        case sealFailed
    }
}

private extension Data {
    /// Base64url encoding (RFC 4648 §5) — no padding, URL-safe characters.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
