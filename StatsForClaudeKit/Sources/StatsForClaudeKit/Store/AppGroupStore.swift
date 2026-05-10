import Foundation
import OSLog

private let log = Log.make("AppGroupStore")

/// Shared UserDefaults bridge between the main app and the Widget Extension.
///
/// `@unchecked Sendable` is sound: `UserDefaults` is documented as thread-safe
/// and all stored properties are immutable.
public final class AppGroupStore: @unchecked Sendable {
    public static let shared = AppGroupStore()

    /// Must match the value of `com.apple.security.application-groups` in both
    /// `StatsForClaude.entitlements` and the (future) widget entitlements file.
    /// The `4DDDLR4X3X.` prefix is the Apple Team ID.
    public static let appGroupID = "4DDDLR4X3X.group.org.revenko.stats-for-claude"

    private let defaults: UserDefaults?
    private let snapshotKey = "widgetSnapshot"
    private let settingsKey = "appSettings"
    private let apiCacheKey = "cachedAPIResponse"

    public init(groupID: String = AppGroupStore.appGroupID) {
        defaults = UserDefaults(suiteName: groupID)
    }

    // MARK: – Widget snapshot

    public func save(_ snapshot: WidgetSnapshot) {
        do {
            try defaults?.set(JSONEncoder().encode(snapshot), forKey: snapshotKey)
        } catch {
            log.error("WidgetSnapshot encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: – Cached API response (survives token expiry)

    public func save(_ response: UsageAPIResponse, fetchedAt: Date = .now) {
        let envelope = CachedAPIResponse(response: response, fetchedAt: fetchedAt)
        do {
            try defaults?.set(JSONEncoder().encode(envelope), forKey: apiCacheKey)
        } catch {
            log.error("CachedAPIResponse encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func loadCachedAPIResponse() -> CachedAPIResponse? {
        guard let data = defaults?.data(forKey: apiCacheKey) else { return nil }
        do {
            return try JSONDecoder().decode(CachedAPIResponse.self, from: data)
        } catch {
            log.error("CachedAPIResponse decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: – Settings (subset needed by widget)

    public func save(_ settings: AppSettings) {
        do {
            try defaults?.set(JSONEncoder().encode(settings), forKey: settingsKey)
        } catch {
            log.error("AppSettings encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
