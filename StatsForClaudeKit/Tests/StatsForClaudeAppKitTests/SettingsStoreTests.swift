import Testing
import Foundation
@testable import StatsForClaudeKit
@testable import StatsForClaudeAppKit

@Suite("SettingsStore")
struct SettingsStoreTests {

    private func makeStore() -> (SettingsStore, String, String) {
        let prefsSuite = "test-prefs-\(UUID().uuidString)"
        let groupSuite = "test-group-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: prefsSuite)!
        let group = AppGroupStore(groupID: groupSuite)
        let store = SettingsStore(defaults: defaults, appGroupStore: group)
        return (store, prefsSuite, groupSuite)
    }

    @Test("load returns .default when nothing is persisted")
    func loadDefault() {
        let (store, prefs, group) = makeStore()
        defer {
            UserDefaults().removePersistentDomain(forName: prefs)
            UserDefaults().removePersistentDomain(forName: group)
        }
        #expect(store.load() == .default)
    }

    @Test("save then load round-trips a custom AppSettings")
    func roundTrip() {
        let (store, prefs, group) = makeStore()
        defer {
            UserDefaults().removePersistentDomain(forName: prefs)
            UserDefaults().removePersistentDomain(forName: group)
        }

        var custom = AppSettings.default
        custom.subscriptionPriceUSD = 100
        custom.currency = .eur
        custom.apply(plan: .max20x)

        store.save(custom)
        #expect(store.load() == custom)
    }
}
