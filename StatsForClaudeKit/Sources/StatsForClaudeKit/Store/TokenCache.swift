import Foundation
import Security

public protocol TokenCacheStoring: Sendable {
    func readToken() -> String?
    func writeToken(_ token: String)
    func deleteToken()
}

/// Caches the Claude OAuth token in our own Keychain item so the system prompt
/// for Claude Code's credentials fires only once per install. Storing it in
/// UserDefaults (the previous approach) leaked the token to anything able to
/// read app preferences for the same UID.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` keeps the token off iCloud
/// Keychain backups while still letting the menu bar agent read it without the
/// user typing their login password again.
public struct KeychainTokenCache: TokenCacheStoring, Sendable {
    public static let defaultService = "org.revenko.stats-for-claude.token-cache"
    private static let account = "claude-oauth"

    private let service: String

    public init(service: String = KeychainTokenCache.defaultService) {
        self.service = service
    }

    public func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func writeToken(_ token: String) {
        deleteToken()
        let attrs: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     Self.account,
            kSecValueData as String:       Data(token.utf8),
            kSecAttrAccessible as String:  kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    public func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
