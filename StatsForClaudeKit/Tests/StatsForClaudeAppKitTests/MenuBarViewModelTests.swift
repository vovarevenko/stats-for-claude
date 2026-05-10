import Testing
import Foundation
@testable import StatsForClaudeKit
@testable import StatsForClaudeAppKit

@MainActor
@Suite("MenuBarViewModel")
struct MenuBarViewModelTests {

    private func makeStore(
        fetcher: UsageFetching,
        bookmark: FakeBookmarkStore = FakeBookmarkStore(),
        token: String? = "tok"
    ) -> (UsageStore, String) {
        let (group, suite) = makeEphemeralAppGroupStore()
        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: bookmark,
            usageFetcher: fetcher,
            keychain: FakeKeychain(token: token),
            tokenCache: FakeTokenCache()
        )
        return (store, suite)
    }

    @Test("menuBarTitle is placeholder until first API response")
    func placeholderTitle() async {
        let (store, suite) = makeStore(
            fetcher: FakeFetcher(result: .failure(APIError.tokenNotFound))
        )
        defer { cleanupSuite(suite) }

        let vm = MenuBarViewModel(
            store: store,
            settings: .default,
            bookmarkStore: FakeBookmarkStore(),
            settingsPersistence: FakeSettingsPersistence()
        )

        #expect(vm.menuBarTitle == "Claude…")
    }

    @Test("menuBarTitle renders both percentages once data is loaded")
    func loadedTitle() async {
        let (store, suite) = makeStore(
            fetcher: FakeFetcher(result: .success(makeUsageResponse(fiveHour: 75, sevenDay: 33)))
        )
        defer { cleanupSuite(suite) }

        await store.refreshAPIInternal()

        let vm = MenuBarViewModel(
            store: store,
            settings: .default,
            bookmarkStore: FakeBookmarkStore(),
            settingsPersistence: FakeSettingsPersistence()
        )

        #expect(vm.menuBarTitle == "75% · 33%")
    }

    @Test("needsOnboarding tracks the bookmark store")
    func onboardingFlag() async {
        let (store, suite) = makeStore(
            fetcher: FakeFetcher(result: .failure(APIError.tokenNotFound))
        )
        defer { cleanupSuite(suite) }

        let bookmark = FakeBookmarkStore()
        let vm = MenuBarViewModel(
            store: store,
            settings: .default,
            bookmarkStore: bookmark,
            settingsPersistence: FakeSettingsPersistence()
        )

        #expect(vm.needsOnboarding == true)
        bookmark.stored = URL(fileURLWithPath: "/tmp")
        #expect(vm.needsOnboarding == false)
    }

    @Test("updateSettings persists through SettingsPersisting and updates state")
    func updateSettingsPersists() async {
        let (store, suite) = makeStore(
            fetcher: FakeFetcher(result: .failure(APIError.tokenNotFound))
        )
        defer { cleanupSuite(suite) }

        let persistence = FakeSettingsPersistence()
        let vm = MenuBarViewModel(
            store: store,
            settings: .default,
            bookmarkStore: FakeBookmarkStore(),
            settingsPersistence: persistence
        )

        var custom = AppSettings.default
        custom.subscriptionPriceUSD = 99
        custom.currency = .eur

        vm.updateSettings(custom)

        #expect(vm.settings == custom)
        #expect(persistence.saveCount == 1)
        #expect(persistence.load() == custom)
    }
}
