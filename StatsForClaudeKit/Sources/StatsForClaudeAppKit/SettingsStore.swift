import Foundation
import StatsForClaudeKit

public protocol SettingsPersisting: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

/// Persists `AppSettings` to UserDefaults.standard (main app only) and mirrors
/// the value into the App Group so the widget — when it returns in v2 — can
/// pick up the user's currency and plan without a second source of truth.
///
/// `@unchecked Sendable` is sound: `UserDefaults` is documented as thread-safe
/// and all stored properties are immutable.
public final class SettingsStore: SettingsPersisting, @unchecked Sendable {
    public static let key = "appSettings"

    private let defaults: UserDefaults
    private let appGroupStore: AppGroupStore

    public init(
        defaults: UserDefaults = .standard,
        appGroupStore: AppGroupStore = .shared
    ) {
        self.defaults = defaults
        self.appGroupStore = appGroupStore
    }

    public func load() -> AppSettings {
        guard
            let data = defaults.data(forKey: Self.key),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
        appGroupStore.save(settings)
    }
}
