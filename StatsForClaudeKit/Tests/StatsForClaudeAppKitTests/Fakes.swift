import Foundation
@testable import StatsForClaudeAppKit
@testable import StatsForClaudeKit

struct FakeFetcher: UsageFetching {
    let result: Result<UsageAPIResponse, Error>
    func fetchUsage(token _: String) async throws -> UsageAPIResponse {
        try result.get()
    }
}

/// Fetcher that fails the first N calls with the given error then succeeds.
/// Used to drive the 401-then-refresh-and-retry path in UsageStore.
final class StepFetcher: UsageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var remainingFailures: Int
    private let failure: Error
    private let success: UsageAPIResponse
    private(set) var callCount = 0

    init(failuresBeforeSuccess: Int, failure: Error, success: UsageAPIResponse) {
        remainingFailures = failuresBeforeSuccess
        self.failure = failure
        self.success = success
    }

    func fetchUsage(token _: String) async throws -> UsageAPIResponse {
        try lock.withLock {
            callCount += 1
            if remainingFailures > 0 {
                remainingFailures -= 1
                throw failure
            }
            return success
        }
    }
}

final class FakeKeychain: KeychainCredentialsReading, KeychainCredentialsWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _credentials: ClaudeCredentials?
    private(set) var writeLog: [ClaudeCredentials] = []
    var writeOutcome: Result<Void, Error> = .success(())

    init(credentials: ClaudeCredentials? = nil) {
        _credentials = credentials
    }

    func readClaudeCredentials() throws -> ClaudeCredentials {
        try lock.withLock {
            guard let creds = _credentials else { throw APIError.tokenNotFound }
            return creds
        }
    }

    func writeClaudeCredentials(_ credentials: ClaudeCredentials) throws {
        try lock.withLock {
            try writeOutcome.get()
            _credentials = credentials
            writeLog.append(credentials)
        }
    }

    static func token(_ token: String?) -> FakeKeychain {
        FakeKeychain(credentials: token.map { ClaudeCredentials(accessToken: $0) })
    }
}

final class FakeBookmarkStore: BookmarkResolving, @unchecked Sendable {
    var stored: URL?
    var hasBookmark: Bool {
        stored != nil
    }

    func resolve() throws -> URL? {
        stored
    }

    func save(url: URL) throws {
        stored = url
    }
}

final class FakeCredentialsCache: CredentialsCacheStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _stored: ClaudeCredentials?
    private(set) var deleteCount = 0
    private(set) var writeCount = 0

    init(_ initial: ClaudeCredentials? = nil) {
        _stored = initial
    }

    func read() -> ClaudeCredentials? {
        lock.withLock { _stored }
    }

    func write(_ credentials: ClaudeCredentials) {
        lock.withLock {
            _stored = credentials
            writeCount += 1
        }
    }

    func delete() {
        lock.withLock {
            _stored = nil
            deleteCount += 1
        }
    }
}

/// Fake OAuth client. Either returns a canned response or throws on every
/// invocation. Tracks call count so tests can assert refresh was attempted.
final class FakeOAuthClient: TokenRefreshing, @unchecked Sendable {
    private let lock = NSLock()
    private let outcome: Result<ClaudeCredentials, Error>
    private(set) var callCount = 0

    init(outcome: Result<ClaudeCredentials, Error>) {
        self.outcome = outcome
    }

    static func never() -> FakeOAuthClient {
        FakeOAuthClient(outcome: .failure(APIError.invalidResponse))
    }

    func refresh(using _: String) async throws -> ClaudeCredentials {
        lock.withLock { callCount += 1 }
        return try outcome.get()
    }
}

final class FakeSettingsPersistence: SettingsPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var _stored: AppSettings
    private(set) var saveCount = 0

    init(initial: AppSettings = .default) {
        _stored = initial
    }

    func load() -> AppSettings {
        lock.withLock { _stored }
    }

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
