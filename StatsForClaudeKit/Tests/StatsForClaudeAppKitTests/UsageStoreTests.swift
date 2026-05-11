import Foundation
import Testing
@testable import StatsForClaudeAppKit
@testable import StatsForClaudeKit

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
            keychain: FakeKeychain.token("tok"),
            credentialsCache: FakeCredentialsCache(),
            oauthClient: FakeOAuthClient.never()
        )

        await store.refreshAPIInternal()

        #expect(store.apiResponse == expected)
        #expect(store.sessionPercent == 0.5)
        #expect(store.weekPercent == 0.25)
    }

    @Test("401 without refresh token invalidates the cache")
    func http401WithoutRefreshInvalidates() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let cache = FakeCredentialsCache(ClaudeCredentials(accessToken: "stale"))

        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .failure(APIError.httpError(401))),
            keychain: FakeKeychain.token("stale"),
            credentialsCache: cache,
            oauthClient: FakeOAuthClient.never()
        )

        await store.refreshAPIInternal()

        #expect(cache.deleteCount == 1)
        #expect(cache.read() == nil)
        #expect(store.apiResponse == nil)
    }

    @Test("401 with refresh token refreshes and retries instead of invalidating")
    func http401TriggersRefreshAndRetry() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let expected = makeUsageResponse(fiveHour: 60, sevenDay: 30)
        let cache = FakeCredentialsCache(ClaudeCredentials(
            accessToken: "stale",
            refreshToken: "refresh-1"
        ))
        let oauth = FakeOAuthClient(outcome: .success(ClaudeCredentials(
            accessToken: "fresh",
            refreshToken: "refresh-2",
            expiresAt: .now.addingTimeInterval(3600)
        )))
        let fetcher = StepFetcher(
            failuresBeforeSuccess: 1,
            failure: APIError.httpError(401),
            success: expected
        )

        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: fetcher,
            keychain: FakeKeychain.token("never-read"),
            credentialsCache: cache,
            oauthClient: oauth
        )

        await store.refreshAPIInternal()

        #expect(store.apiResponse == expected)
        #expect(oauth.callCount == 1)
        #expect(fetcher.callCount == 2)
        #expect(cache.deleteCount == 0)
        #expect(cache.read()?.accessToken == "fresh")
    }

    @Test("expiring cached token is refreshed proactively before the API call")
    func expiringTokenRefreshedProactively() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let expected = makeUsageResponse(fiveHour: 12, sevenDay: 3)
        let cache = FakeCredentialsCache(ClaudeCredentials(
            accessToken: "about-to-expire",
            refreshToken: "refresh-1",
            expiresAt: .now.addingTimeInterval(30) // inside 300s leeway
        ))
        let oauth = FakeOAuthClient(outcome: .success(ClaudeCredentials(
            accessToken: "fresh",
            refreshToken: "refresh-2",
            expiresAt: .now.addingTimeInterval(3600)
        )))

        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .success(expected)),
            keychain: FakeKeychain(credentials: nil),
            credentialsCache: cache,
            oauthClient: oauth
        )

        await store.refreshAPIInternal()

        #expect(store.apiResponse == expected)
        #expect(oauth.callCount == 1)
        #expect(cache.read()?.accessToken == "fresh")
    }

    @Test("500 leaves the cached token alone")
    func http500KeepsToken() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let cache = FakeCredentialsCache(ClaudeCredentials(accessToken: "good"))

        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .failure(APIError.httpError(500))),
            keychain: FakeKeychain.token("good"),
            credentialsCache: cache,
            oauthClient: FakeOAuthClient.never()
        )

        await store.refreshAPIInternal()

        #expect(cache.deleteCount == 0)
        #expect(cache.read()?.accessToken == "good")
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
            keychain: FakeKeychain.token("tok"),
            credentialsCache: FakeCredentialsCache(),
            oauthClient: FakeOAuthClient.never()
        )

        await store.refreshAPIInternal()

        #expect(store.apiResponse == oldResponse)
        #expect(store.apiDataAge >= 120)
    }

    @Test("429 from usage endpoint enters cooldown and suppresses next refresh")
    func http429EntersCooldown() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let cache = FakeCredentialsCache(ClaudeCredentials(
            accessToken: "good",
            refreshToken: "refresh-1",
            expiresAt: .now.addingTimeInterval(3600)
        ))
        let fetcher = StepFetcher(
            failuresBeforeSuccess: 1,
            failure: APIError.rateLimited(retryAfter: 120),
            success: makeUsageResponse()
        )

        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: fetcher,
            keychain: FakeKeychain.token("never-read"),
            credentialsCache: cache,
            oauthClient: FakeOAuthClient.never()
        )

        await store.refreshAPIInternal()

        // Cache preserved (no 401 invalidation path)
        #expect(cache.deleteCount == 0)
        #expect(cache.read()?.accessToken == "good")
        // Cooldown active; further refreshAPI ticks should no-op
        #expect(store.isInCooldown() == true)
        store.refreshAPI(settings: .default)
        #expect(fetcher.callCount == 1) // not bumped
    }

    @Test("429 during OAuth refresh enters cooldown without invalidating cache")
    func http429FromOAuthRefreshKeepsCache() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        // Token already expired → proactive refresh path
        let cache = FakeCredentialsCache(ClaudeCredentials(
            accessToken: "stale",
            refreshToken: "refresh-1",
            expiresAt: .now.addingTimeInterval(-60)
        ))
        let oauth = FakeOAuthClient(outcome: .failure(APIError.rateLimited(retryAfter: 90)))

        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .success(makeUsageResponse())),
            keychain: FakeKeychain.token("never-read"),
            credentialsCache: cache,
            oauthClient: oauth
        )

        await store.refreshAPIInternal()

        #expect(oauth.callCount == 1)
        #expect(cache.deleteCount == 0)
        #expect(cache.read()?.accessToken == "stale")
        #expect(store.isInCooldown() == true)
    }

    @Test("retryAfter <= 0 falls back to exponential schedule, not a no-op cooldown")
    func zeroRetryAfterUsesExponentialBackoff() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let cache = FakeCredentialsCache(ClaudeCredentials(
            accessToken: "good",
            refreshToken: "refresh-1",
            expiresAt: .now.addingTimeInterval(3600)
        ))
        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .failure(APIError.rateLimited(retryAfter: 0))),
            keychain: FakeKeychain.token("never-read"),
            credentialsCache: cache,
            oauthClient: FakeOAuthClient.never()
        )

        await store.refreshAPIInternal()
        // First 429 with retryAfter:0 → schedule[0] == 60s cooldown
        #expect(store.isInCooldown() == true)
        #expect(store.isInCooldown(now: .now.addingTimeInterval(59)) == true)
        #expect(store.isInCooldown(now: .now.addingTimeInterval(61)) == false)

        // Second consecutive 429 — bypass the cooldown gate by driving the
        // internal entry point directly — escalates to schedule[1] == 120s.
        await store.refreshAPIInternal()
        #expect(store.isInCooldown(now: .now.addingTimeInterval(119)) == true)
        #expect(store.isInCooldown(now: .now.addingTimeInterval(121)) == false)
    }

    @Test("successful response clears the cooldown counter")
    func successClearsConsecutiveCount() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let cache = FakeCredentialsCache(ClaudeCredentials(
            accessToken: "good",
            refreshToken: "refresh-1",
            expiresAt: .now.addingTimeInterval(3600)
        ))
        let fetcher = StepFetcher(
            failuresBeforeSuccess: 2,
            failure: APIError.rateLimited(retryAfter: 0),
            success: makeUsageResponse(fiveHour: 10, sevenDay: 3)
        )
        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: fetcher,
            keychain: FakeKeychain.token("never-read"),
            credentialsCache: cache,
            oauthClient: FakeOAuthClient.never()
        )

        await store.refreshAPIInternal() // 1st 429 → 60s
        await store.refreshAPIInternal() // 2nd 429 → 120s
        await store.refreshAPIInternal() // success → cleared
        #expect(store.isInCooldown() == false)
        #expect(fetcher.callCount == 3)

        // After clear, a fresh 429 should restart from 60s, not 240s
        let fetcher2 = FakeFetcher(result: .failure(APIError.rateLimited(retryAfter: 0)))
        let store2 = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: fetcher2,
            keychain: FakeKeychain.token("never-read"),
            credentialsCache: cache,
            oauthClient: FakeOAuthClient.never()
        )
        await store2.refreshAPIInternal()
        #expect(store2.isInCooldown(now: .now.addingTimeInterval(59)) == true)
        #expect(store2.isInCooldown(now: .now.addingTimeInterval(61)) == false)
    }

    @Test("Retry-After header parses both seconds and HTTP-date")
    func retryAfterParsing() {
        #expect(parseRetryAfter("120") == 120)
        #expect(parseRetryAfter("0") == 0)
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "GMT")
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let header = fmt.string(from: now.addingTimeInterval(100))
        let parsed = parseRetryAfter(header, now: now)
        #expect(parsed != nil)
        if let parsed { #expect(abs(parsed - 100) < 1.5) }
        #expect(parseRetryAfter(nil) == nil)
        #expect(parseRetryAfter("") == nil)
        #expect(parseRetryAfter("garbage") == nil)
    }

    @Test("OAuth refresh mirrors the new tokens back into the CLI keychain")
    func refreshMirrorsBackToCLIKeychain() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let cache = FakeCredentialsCache(ClaudeCredentials(
            accessToken: "stale",
            refreshToken: "r1",
            expiresAt: .now.addingTimeInterval(-60)
        ))
        let keychain = FakeKeychain(credentials: ClaudeCredentials(accessToken: "stale"))
        let oauth = FakeOAuthClient(outcome: .success(ClaudeCredentials(
            accessToken: "fresh",
            refreshToken: "r2",
            expiresAt: .now.addingTimeInterval(3600)
        )))
        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .success(makeUsageResponse())),
            keychain: keychain,
            credentialsCache: cache,
            oauthClient: oauth
        )

        await store.refreshAPIInternal()

        #expect(oauth.callCount == 1)
        #expect(keychain.writeLog.count == 1)
        let written = keychain.writeLog[0]
        #expect(written.accessToken == "fresh")
        #expect(written.refreshToken == "r2")
    }

    @Test("CLI keychain write-back failure doesn't break our own refresh flow")
    func writeBackFailureIsTolerated() async {
        let (group, suite) = makeEphemeralAppGroupStore()
        defer { cleanupSuite(suite) }

        let cache = FakeCredentialsCache(ClaudeCredentials(
            accessToken: "stale",
            refreshToken: "r1",
            expiresAt: .now.addingTimeInterval(-60)
        ))
        let keychain = FakeKeychain(credentials: ClaudeCredentials(accessToken: "stale"))
        keychain.writeOutcome = .failure(APIError.keychainWriteFailed(-25300))
        let oauth = FakeOAuthClient(outcome: .success(ClaudeCredentials(
            accessToken: "fresh",
            refreshToken: "r2",
            expiresAt: .now.addingTimeInterval(3600)
        )))
        let expected = makeUsageResponse(fiveHour: 42, sevenDay: 10)
        let store = UsageStore(
            appGroupStore: group,
            bookmarkStore: FakeBookmarkStore(),
            usageFetcher: FakeFetcher(result: .success(expected)),
            keychain: keychain,
            credentialsCache: cache,
            oauthClient: oauth
        )

        await store.refreshAPIInternal()

        #expect(store.apiResponse == expected)
        #expect(cache.read()?.accessToken == "fresh")
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
            keychain: FakeKeychain(credentials: nil),
            credentialsCache: FakeCredentialsCache(),
            oauthClient: FakeOAuthClient.never()
        )

        #expect(store.hasBookmark == false)
        bookmark.stored = URL(fileURLWithPath: "/tmp")
        #expect(store.hasBookmark == true)
    }
}
