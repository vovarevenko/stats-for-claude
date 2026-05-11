import Foundation
import OSLog
import Security

public protocol TokenCacheStoring: Sendable {
    func readToken() -> String?
    func writeToken(_ token: String)
    func deleteToken()
}

public protocol CredentialsCacheStoring: Sendable {
    func read() -> ClaudeCredentials?
    func write(_ credentials: ClaudeCredentials)
    func delete()
}

private let log = Log.make("KeychainCredentialsCache")

/// Caches the full Claude OAuth credentials (access + refresh + expiry) in
/// our own Keychain item so we can refresh tokens against Anthropic without
/// ever re-reading Claude Code's CLI Keychain item. The CLI rotates that
/// item on every token refresh, and rotation resets its ACL — which is what
/// causes the periodic "Allow access" prompt users see when relying solely
/// on reads from `Claude Code-credentials`.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` keeps the credentials
/// off iCloud Keychain backups while still letting the menu bar agent read
/// them without the user typing their login password again.
public struct KeychainCredentialsCache: CredentialsCacheStoring, Sendable {
    public static let defaultService = "org.revenko.stats-for-claude.token-cache"
    /// Bumped from `claude-oauth` (v1, stored only the access token as raw
    /// UTF-8) to `claude-oauth-v2` (JSON-encoded `ClaudeCredentials`).
    private static let account = "claude-oauth-v2"
    private static let legacyAccount = "claude-oauth"

    private let service: String

    public init(service: String = KeychainCredentialsCache.defaultService) {
        self.service = service
        Self.deleteLegacyItem(service: service)
    }

    public func read() -> ClaudeCredentials? {
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
            guard let data = item as? Data else { return nil }
            do {
                return try JSONDecoder().decode(ClaudeCredentials.self, from: data)
            } catch {
                log.error("Credentials cache decode failed; treating as miss")
                return nil
            }
        case errSecItemNotFound:
            return nil
        default:
            log.error("Credentials cache read failed: \(Self.describe(status), privacy: .public)")
            return nil
        }
    }

    public func write(_ credentials: ClaudeCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else {
            log.error("Credentials cache encode failed")
            return
        }
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(match as CFDictionary, updateAttrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            log.error("Credentials cache update failed: \(Self.describe(updateStatus), privacy: .public)")
            return
        }

        var addAttrs = match
        addAttrs[kSecValueData as String] = data
        addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
        if addStatus != errSecSuccess {
            log.error("Credentials cache add failed: \(Self.describe(addStatus), privacy: .public)")
        } else {
            log.info("Credentials cache populated; subsequent launches refresh silently")
        }
    }

    public func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            log.error("Credentials cache delete failed: \(Self.describe(status), privacy: .public)")
        }
    }

    /// One-shot migration: drop the v1 raw-token item left over from earlier
    /// versions. Safe to call repeatedly — `errSecItemNotFound` is ignored.
    private static func deleteLegacyItem(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            log.info("Removed legacy v1 token cache item")
        }
    }

    private static func describe(_ status: OSStatus) -> String {
        let copy = SecCopyErrorMessageString(status, nil) as String?
        return "\(status) (\(copy ?? "unknown"))"
    }
}
