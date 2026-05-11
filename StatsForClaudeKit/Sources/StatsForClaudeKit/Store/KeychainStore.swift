import Foundation
import Security

public protocol KeychainTokenReading: Sendable {
    func readClaudeToken() throws -> String
}

public protocol KeychainCredentialsReading: Sendable {
    func readClaudeCredentials() throws -> ClaudeCredentials
}

public protocol KeychainCredentialsWriting: Sendable {
    /// Persist refreshed credentials back into the CLI's keychain item so
    /// the CLI continues to see fresh tokens. Without this the CLI's next
    /// refresh attempt would hit Anthropic with our now-invalidated
    /// `refreshToken` and log the user out.
    func writeClaudeCredentials(_ credentials: ClaudeCredentials) throws
}

public typealias KeychainCredentialsAccessing = KeychainCredentialsReading & KeychainCredentialsWriting

/// Reads Claude Code OAuth credentials from the macOS Keychain.
/// On first access macOS will prompt the user to allow access.
///
/// `@unchecked Sendable` is sound: Security framework `SecItemCopyMatching`
/// is documented as thread-safe and `service` is immutable.
public final class KeychainStore: KeychainCredentialsAccessing, KeychainTokenReading, @unchecked Sendable {
    private let service: String

    public init(service: String = "Claude Code-credentials") {
        self.service = service
    }

    public func readClaudeCredentials() throws -> ClaudeCredentials {
        let data = try readEnvelopeData()
        guard let creds = Self.parseCredentials(from: data) else {
            throw APIError.tokenNotFound
        }
        return creds
    }

    public func readClaudeToken() throws -> String {
        try readClaudeCredentials().accessToken
    }

    /// Splices the fresh OAuth fields into the **current** CLI envelope.
    /// Reading the live envelope every time (instead of relying on a cached
    /// copy) means CLI-only keys like `scopes`, `subscriptionType`, and
    /// `rateLimitTier` always reflect the latest CLI state — even if the
    /// user has re-run `claude /login` between our refreshes. After the
    /// initial Allow prompt, the read costs no additional prompts because
    /// `SecItemUpdate` preserves the keychain item's ACL.
    public func writeClaudeCredentials(_ credentials: ClaudeCredentials) throws {
        let envelope = try readEnvelopeData()
        let payload = try Self.encodePayload(for: credentials, envelope: envelope)
        // Defense in depth: before committing to keychain, parse the encoded
        // payload through the same reader the CLI parsing depends on and
        // verify the tokens we intended to write actually round-trip. Catches
        // any regression in `encodePayload` and any future drift in the CLI
        // envelope schema before it can log the user out of the CLI.
        guard
            let verified = Self.parseCredentials(from: payload),
            verified.accessToken == credentials.accessToken,
            verified.refreshToken == credentials.refreshToken
        else {
            throw APIError.missingEnvelope
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: payload,
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        guard status == errSecSuccess else {
            throw APIError.keychainWriteFailed(status)
        }
    }

    private func readEnvelopeData() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw APIError.tokenNotFound
        }
        return data
    }

    /// Splices the fresh OAuth fields into a copy of the supplied envelope,
    /// preserving every CLI-only key. Refuses to write a synthesised payload
    /// if the envelope can't be parsed — a bare 3-field write would log the
    /// CLI out on next use.
    static func encodePayload(for credentials: ClaudeCredentials, envelope: Data) throws -> Data {
        guard var json = (try? JSONSerialization.jsonObject(with: envelope)) as? [String: Any] else {
            throw APIError.missingEnvelope
        }
        var oauth = (json["claudeAiOauth"] as? [String: Any]) ?? [:]
        applyTokens(credentials, into: &oauth)
        json["claudeAiOauth"] = oauth
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// Parses an envelope payload into `ClaudeCredentials`. Shared between
    /// the read path and the write-back verification step so any change to
    /// what counts as a valid envelope automatically applies to both.
    static func parseCredentials(from data: Data) -> ClaudeCredentials? {
        guard
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else {
            return nil
        }
        return ClaudeCredentials(
            accessToken: token,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: decodeExpiresAt(oauth["expiresAt"])
        )
    }

    private static func applyTokens(_ credentials: ClaudeCredentials, into oauth: inout [String: Any]) {
        oauth["accessToken"] = credentials.accessToken
        if let refreshToken = credentials.refreshToken {
            oauth["refreshToken"] = refreshToken
        }
        if let expiresAt = credentials.expiresAt {
            oauth["expiresAt"] = Int64(expiresAt.timeIntervalSince1970 * 1000)
        }
    }

    /// Claude Code stores `expiresAt` as milliseconds since Unix epoch
    /// (`Number`). Be lenient: also accept seconds (heuristic: <10^12) and
    /// ISO-8601 strings, since the wire format is set by the CLI and may
    /// change.
    private static func decodeExpiresAt(_ raw: Any?) -> Date? {
        guard let raw else { return nil }
        if let ms = raw as? Double {
            return ms > 1_000_000_000_000
                ? Date(timeIntervalSince1970: ms / 1000)
                : Date(timeIntervalSince1970: ms)
        }
        if let ms = raw as? Int64 {
            return decodeExpiresAt(Double(ms))
        }
        if let ms = raw as? Int {
            return decodeExpiresAt(Double(ms))
        }
        if let str = raw as? String {
            if let n = Double(str) { return decodeExpiresAt(n) }
            return ISO8601DateFormatter().date(from: str)
        }
        return nil
    }
}
