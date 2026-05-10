import Foundation
import OSLog
import Security

public protocol TokenCacheStoring: Sendable {
    func readToken() -> String?
    func writeToken(_ token: String)
    func deleteToken()
}

private let log = Log.make("KeychainTokenCache")

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
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                log.error("Token cache read returned non-UTF8 data; treating as miss")
                return nil
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            log.error("Token cache read failed: \(Self.describe(status), privacy: .public)")
            return nil
        }
    }

    public func writeToken(_ token: String) {
        // Try update-in-place first so we keep ACLs, then fall back to add.
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
        ]
        let updateStatus = SecItemUpdate(match as CFDictionary, updateAttrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break // fall through to add
        default:
            log.error("Token cache update failed: \(Self.describe(updateStatus), privacy: .public)")
            return
        }

        var addAttrs = match
        addAttrs[kSecValueData as String] = Data(token.utf8)
        addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
        if addStatus != errSecSuccess {
            log.error("Token cache add failed: \(Self.describe(addStatus), privacy: .public)")
        } else {
            log.info("Token cache populated; subsequent launches should not prompt")
        }
    }

    public func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            log.error("Token cache delete failed: \(Self.describe(status), privacy: .public)")
        }
    }

    private static func describe(_ status: OSStatus) -> String {
        let copy = SecCopyErrorMessageString(status, nil) as String?
        return "\(status) (\(copy ?? "unknown"))"
    }
}
