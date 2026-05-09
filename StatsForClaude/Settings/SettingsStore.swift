import Foundation
import StatsForClaudeKit

/// Persists AppSettings to UserDefaults.standard (main app only, not shared).
enum SettingsStore {
    private static let key = "appSettings"

    static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
        // Also push to App Group so the widget gets the latest
        AppGroupStore.shared.save(settings)
    }
}
