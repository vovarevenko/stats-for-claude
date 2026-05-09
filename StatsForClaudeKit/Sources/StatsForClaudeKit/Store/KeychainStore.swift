import Foundation
import Security

/// Reads Claude Code OAuth credentials from the macOS Keychain.
/// On first access macOS will prompt the user to allow access.
public final class KeychainStore: @unchecked Sendable {
    private let service = "Claude Code-credentials"

    public init() {}

    public func readClaudeToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw APIError.tokenNotFound
        }

        guard
            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else {
            throw APIError.tokenNotFound
        }

        return token
    }
}
