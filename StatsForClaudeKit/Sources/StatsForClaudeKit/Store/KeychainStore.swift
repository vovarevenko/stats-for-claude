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

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else {
            throw APIError.tokenNotFound
        }

        let refreshToken = oauth["refreshToken"] as? String
        let expiresAt = Self.decodeExpiresAt(oauth["expiresAt"])

        return ClaudeCredentials(
            accessToken: token,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            sourceEnvelope: data
        )
    }

    public func readClaudeToken() throws -> String {
        try readClaudeCredentials().accessToken
    }

    public func writeClaudeCredentials(_ credentials: ClaudeCredentials) throws {
        let payload = try Self.encodePayload(for: credentials)
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

    /// Build the JSON that goes back into `Claude Code-credentials` by
    /// splicing fresh OAuth fields into the original envelope, preserving
    /// CLI-only keys (`scopes`, `subscriptionType`, …). Throws when we have
    /// no envelope to splice into — writing a bare payload would silently
    /// log the user out of the CLI on next use.
    private static func encodePayload(for credentials: ClaudeCredentials) throws -> Data {
        guard var json = decodeEnvelope(credentials.sourceEnvelope) else {
            throw APIError.missingEnvelope
        }
        var oauth = (json["claudeAiOauth"] as? [String: Any]) ?? [:]
        applyTokens(credentials, into: &oauth)
        json["claudeAiOauth"] = oauth
        return try JSONSerialization.data(withJSONObject: json)
    }

    private static func decodeEnvelope(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
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
