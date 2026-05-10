import Foundation
import Testing
@testable import StatsForClaudeAppKit
@testable import StatsForClaudeKit

@Suite("SettingsStore")
struct SettingsStoreTests {
    private struct Fixture {
        let store: SettingsStore
        let prefsSuite: String
        let groupSuite: String

        func cleanup() {
            UserDefaults().removePersistentDomain(forName: prefsSuite)
            UserDefaults().removePersistentDomain(forName: groupSuite)
        }
    }

    private func makeFixture() -> Fixture {
        let prefsSuite = "test-prefs-\(UUID().uuidString)"
        let groupSuite = "test-group-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: prefsSuite)!
        let group = AppGroupStore(groupID: groupSuite)
        let store = SettingsStore(defaults: defaults, appGroupStore: group)
        return Fixture(store: store, prefsSuite: prefsSuite, groupSuite: groupSuite)
    }

    @Test("load returns .default when nothing is persisted")
    func loadDefault() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        #expect(fixture.store.load() == .default)
    }

    @Test("save then load round-trips a custom AppSettings")
    func roundTrip() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        var custom = AppSettings.default
        custom.subscriptionPriceUSD = 100
        custom.currency = .eur
        custom.apply(plan: .max20x)

        fixture.store.save(custom)
        #expect(fixture.store.load() == custom)
    }
}
