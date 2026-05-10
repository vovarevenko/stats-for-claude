import Foundation
import Testing
@testable import StatsForClaudeKit

@Suite("AppGroupStore")
struct AppGroupStoreTests {

    /// Each test gets an isolated UserDefaults suite that we wipe in `tearDown`.
    private final class TestSuite {
        let id: String
        let defaults: UserDefaults
        init() {
            id = "test.AppGroupStore.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: id)!
        }
        func cleanup() {
            UserDefaults().removePersistentDomain(forName: id)
        }
    }

    @Test("save and load CachedAPIResponse round-trips")
    func cachedAPIResponseRoundTrip() {
        let suite = TestSuite()
        defer { suite.cleanup() }
        let store = AppGroupStore(groupID: suite.id)

        let response = UsageAPIResponse(
            fiveHour: UsageWindow(utilization: 33.3, resetsAt: nil),
            sevenDay: UsageWindow(utilization: 66.6, resetsAt: nil)
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_730_000_000)
        store.save(response, fetchedAt: fetchedAt)

        let loaded = store.loadCachedAPIResponse()
        #expect(loaded?.response == response)
        #expect(loaded?.fetchedAt.timeIntervalSince1970 == fetchedAt.timeIntervalSince1970)
    }

    @Test("loadCachedAPIResponse returns nil when nothing saved")
    func loadReturnsNilEmpty() {
        let suite = TestSuite()
        defer { suite.cleanup() }
        let store = AppGroupStore(groupID: suite.id)
        #expect(store.loadCachedAPIResponse() == nil)
    }

    @Test("loadCachedAPIResponse returns nil when stored data is corrupted")
    func loadReturnsNilCorrupted() {
        let suite = TestSuite()
        defer { suite.cleanup() }
        suite.defaults.set("not json".data(using: .utf8)!, forKey: "cachedAPIResponse")

        let store = AppGroupStore(groupID: suite.id)
        #expect(store.loadCachedAPIResponse() == nil)
    }

    @Test("saved WidgetSnapshot is decodable from the underlying suite")
    func snapshotPersisted() throws {
        let suite = TestSuite()
        defer { suite.cleanup() }
        let store = AppGroupStore(groupID: suite.id)

        let snapshot = WidgetSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_730_000_000),
            sessionPercent: 0.5,
            weekPercent: 0.25,
            sessionResetsAt: nil,
            weekResetsAt: nil,
            currentProject: "app",
            weekCostUSD: 1.23,
            topProject: "app"
        )
        store.save(snapshot)

        let raw = try #require(suite.defaults.data(forKey: "widgetSnapshot"))
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: raw)
        #expect(decoded == snapshot)
    }

    @Test("saved AppSettings is decodable from the underlying suite")
    func settingsPersisted() throws {
        let suite = TestSuite()
        defer { suite.cleanup() }
        let store = AppGroupStore(groupID: suite.id)

        var settings = AppSettings()
        settings.apply(plan: .max20x)
        store.save(settings)

        let raw = try #require(suite.defaults.data(forKey: "appSettings"))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: raw)
        #expect(decoded == settings)
    }
}

@Suite("BookmarkStore")
struct BookmarkStoreTests {

    private func freshDefaults() -> UserDefaults {
        let id = "test.BookmarkStore.\(UUID().uuidString)"
        return UserDefaults(suiteName: id)!
    }

    @Test("hasBookmark is false on fresh defaults")
    func hasBookmarkFalseInitially() {
        let store = BookmarkStore(defaults: freshDefaults())
        #expect(store.hasBookmark == false)
    }

    @Test("resolve returns nil when nothing saved")
    func resolveNilWhenEmpty() throws {
        let store = BookmarkStore(defaults: freshDefaults())
        #expect(try store.resolve() == nil)
    }

    @Test("hasBookmark reflects pre-existing data in defaults")
    func hasBookmarkTrueWhenDataPresent() {
        let defaults = freshDefaults()
        defaults.set(Data([0x01, 0x02]), forKey: "claudeDirectoryBookmark")
        let store = BookmarkStore(defaults: defaults)
        #expect(store.hasBookmark == true)
    }
}
