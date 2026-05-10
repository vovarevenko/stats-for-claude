import Foundation

/// Shared UserDefaults bridge between the main app and the Widget Extension.
public final class AppGroupStore: @unchecked Sendable {
    public static let shared = AppGroupStore()

    public static let appGroupID = "4DDDLR4X3X.group.org.revenko.stats-for-claude"

    private let defaults: UserDefaults?
    private let snapshotKey   = "widgetSnapshot"
    private let settingsKey   = "appSettings"
    private let apiCacheKey   = "cachedAPIResponse"

    public init(groupID: String = AppGroupStore.appGroupID) {
        defaults = UserDefaults(suiteName: groupID)
    }

    // MARK: – Widget snapshot

    public func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    // MARK: – Cached API response (survives token expiry)

    public func save(_ response: UsageAPIResponse, fetchedAt: Date = .now) {
        let envelope = CachedAPIResponse(response: response, fetchedAt: fetchedAt)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults?.set(data, forKey: apiCacheKey)
    }

    public func loadCachedAPIResponse() -> CachedAPIResponse? {
        guard
            let data = defaults?.data(forKey: apiCacheKey),
            let cached = try? JSONDecoder().decode(CachedAPIResponse.self, from: data)
        else { return nil }
        return cached
    }

    // MARK: – Settings (subset needed by widget)

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: settingsKey)
    }
}
