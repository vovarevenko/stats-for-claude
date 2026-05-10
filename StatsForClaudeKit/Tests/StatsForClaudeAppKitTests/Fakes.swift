import Foundation
@testable import StatsForClaudeKit
@testable import StatsForClaudeAppKit

struct FakeFetcher: UsageFetching {
    let result: Result<UsageAPIResponse, Error>
    func fetchUsage(token: String) async throws -> UsageAPIResponse {
        try result.get()
    }
}

struct FakeKeychain: KeychainTokenReading {
    let token: String?
    func readClaudeToken() throws -> String {
        guard let token else { throw APIError.tokenNotFound }
        return token
    }
}

final class FakeBookmarkStore: BookmarkResolving, @unchecked Sendable {
    var stored: URL?
    var hasBookmark: Bool { stored != nil }
    func resolve() throws -> URL? { stored }
    func save(url: URL) throws { stored = url }
}

final class FakeTokenCache: TokenCacheStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _stored: String?
    private(set) var deleteCount = 0

    func readToken() -> String? { lock.withLock { _stored } }
    func writeToken(_ token: String) { lock.withLock { _stored = token } }
    func deleteToken() {
        lock.withLock {
            _stored = nil
            deleteCount += 1
        }
    }
}

final class FakeSettingsPersistence: SettingsPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var _stored: AppSettings
    private(set) var saveCount = 0

    init(initial: AppSettings = .default) {
        self._stored = initial
    }

    func load() -> AppSettings { lock.withLock { _stored } }
    func save(_ settings: AppSettings) {
        lock.withLock {
            _stored = settings
            saveCount += 1
        }
    }
}

/// Returns an `AppGroupStore` backed by a unique `UserDefaults` suite so each
/// test gets a fresh container with no carry-over state.
func makeEphemeralAppGroupStore() -> (AppGroupStore, String) {
    let id = "test-stats-\(UUID().uuidString)"
    return (AppGroupStore(groupID: id), id)
}

func cleanupSuite(_ id: String) {
    UserDefaults().removePersistentDomain(forName: id)
}

func makeUsageResponse(fiveHour: Double = 42, sevenDay: Double = 17) -> UsageAPIResponse {
    let json = """
    {
      "five_hour": { "utilization": \(fiveHour), "resets_at": "2030-01-01T00:00:00Z" },
      "seven_day": { "utilization": \(sevenDay), "resets_at": "2030-01-08T00:00:00Z" }
    }
    """
    return try! JSONDecoder.iso8601WithOptionalMillis()
        .decode(UsageAPIResponse.self, from: Data(json.utf8))
}
