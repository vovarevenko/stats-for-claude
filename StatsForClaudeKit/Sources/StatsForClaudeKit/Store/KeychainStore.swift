import Foundation
import Security

public protocol KeychainTokenReading: Sendable {
    func readClaudeToken() throws -> String
}

public protocol KeychainCredentialsReading: Sendable {
    func readClaudeCredentials() throws -> ClaudeCredentials
}

/// Reads Claude Code OAuth credentials from the macOS Keychain.
/// On first access macOS will prompt the user to allow access.
///
/// `@unchecked Sendable` is sound: Security framework `SecItemCopyMatching`
/// is documented as thread-safe and `service` is immutable.
public final class KeychainStore: KeychainTokenReading, KeychainCredentialsReading, @unchecked Sendable {
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
            expiresAt: expiresAt
        )
    }

    public func readClaudeToken() throws -> String {
        try readClaudeCredentials().accessToken
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
