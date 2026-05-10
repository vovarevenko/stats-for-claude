import Testing
import Foundation
@testable import StatsForClaudeKit
@testable import StatsForClaudeAppKit

@MainActor
@Suite("UsageStore")
struct UsageStoreTests {

    @Test("happy path: API success populates apiResponse")
    func happyPath() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let expected = makeUsageResponse(fiveHour: 50, sevenDay: 25)
        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .success(expected)),
            keychain: FakeKeychain(token: "tok"),
            tokenCache: FakeTokenCache()
        )

        await store.refreshAPIInternal()

        #expect(store.apiResponse == expected)
        #expect(store.sessionPercent == 0.5)
        #expect(store.weekPercent == 0.25)
    }

    @Test("401 invalidates the cached token")
    func http401InvalidatesToken() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let cache = FakeTokenCache()
        cache.writeToken("stale")

        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .failure(APIError.httpError(401))),
            keychain: FakeKeychain(token: "stale"),
            tokenCache: cache
        )

        await store.refreshAPIInternal()

        #expect(cache.deleteCount == 1)
        #expect(cache.readToken() == nil)
        #expect(store.apiResponse == nil)
    }

    @Test("500 leaves the cached token alone")
    func http500KeepsToken() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let cache = FakeTokenCache()
        cache.writeToken("good")

        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .failure(APIError.httpError(500))),
            keychain: FakeKeychain(token: "good"),
            tokenCache: cache
        )

        await store.refreshAPIInternal()

        #expect(cache.deleteCount == 0)
        #expect(cache.readToken() == "good")
    }

    @Test("network error falls back to cached response when present")
    func networkErrorFallsBackToCache() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        // Pre-seed an older cached response into the App Group container.
        let oldResponse = makeUsageResponse(fiveHour: 10, sevenDay: 5)
        group.save(oldResponse, fetchedAt: .now.addingTimeInterval(-120))

        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .failure(URLError(.notConnectedToInternet))),
            keychain: FakeKeychain(token: "tok"),
            tokenCache: FakeTokenCache()
        )

        await store.refreshAPIInternal()

        #expect(store.apiResponse == oldResponse)
        #expect(store.apiDataAge >= 120)
    }

    @Test("hasBookmark proxies BookmarkResolving")
    func hasBookmarkProxy() {
        let bookmark = FakeBookmarkStore()
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: bookmark,
            usageFetcher: FakeFetcher(result: .failure(APIError.tokenNotFound)),
            keychain: FakeKeychain(token: nil),
            tokenCache: FakeTokenCache()
        )

        #expect(store.hasBookmark == false)
        bookmark.stored = URL(fileURLWithPath: "/tmp")
        #expect(store.hasBookmark == true)
    }
}
