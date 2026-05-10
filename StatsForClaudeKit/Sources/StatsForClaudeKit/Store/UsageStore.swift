import Foundation
import Observation
import OSLog

private let log = Log.make("UsageStore")

@Observable
@MainActor
public final class UsageStore {

    // ── API-sourced (authoritative for % and reset times) ────────────────────
    public private(set) var apiResponse: UsageAPIResponse?
    public private(set) var apiDataAge: TimeInterval = 0

    // ── JSONL-sourced (cost + per-project breakdown) ──────────────────────────
    public private(set) var weeklyUsage: WeeklyUsage = .empty
    public private(set) var monthlyUsage: WeeklyUsage = .empty

    /// True while either the API or the JSONL refresh is in flight. The two
    /// pipelines run on independent cadences so they need separate flags;
    /// `isLoading` is the OR projection used by the UI for a single spinner.
    public var isLoading: Bool { apiInFlight || jsonlInFlight }
    private var apiInFlight = false
    private var jsonlInFlight = false

    private let appGroupStore: AppGroupStore
    private let bookmarkStore: BookmarkResolving
    private let usageFetcher: UsageFetching
    private let keychain: KeychainTokenReading
    private let tokenCache: TokenCacheStoring

    // In-memory mirror of the Keychain-cached token; avoids a Security framework
    // round-trip on every refresh inside a single launch.
    private var cachedToken: String?

    public init(
        appGroupStore: AppGroupStore = .shared,
        bookmarkStore: BookmarkResolving = BookmarkStore(),
        usageFetcher: UsageFetching = UsageAPIClient(),
        keychain: KeychainTokenReading = KeychainStore(),
        tokenCache: TokenCacheStoring = KeychainTokenCache()
    ) {
        self.appGroupStore = appGroupStore
        self.bookmarkStore = bookmarkStore
        self.usageFetcher = usageFetcher
        self.keychain = keychain
        self.tokenCache = tokenCache

        // Sanitize: prior versions stored the OAuth token in plain text under
        // UserDefaults.standard. Strip that leftover on first run after upgrade.
        UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
    }

    private static let legacyDefaultsKey = "cachedClaudeAccessToken"

    public var hasBookmark: Bool { bookmarkStore.hasBookmark }

    // ── Derived convenience ───────────────────────────────────────────────────

    public var sessionPercent: Double {
        (apiResponse?.fiveHour?.utilization ?? 0) / 100.0
    }
    public var weekPercent: Double {
        (apiResponse?.sevenDay?.utilization ?? 0) / 100.0
    }
    public var sessionTimeRemaining: TimeInterval {
        apiResponse?.fiveHour?.timeRemaining ?? 0
    }
    public var weekTimeRemaining: TimeInterval {
        apiResponse?.sevenDay?.timeRemaining ?? 0
    }
    public var currentProjectName: String? {
        weeklyUsage.projectBreakdown.first?.name
    }

    // ── Public entry points ───────────────────────────────────────────────────

    /// Refresh both pipelines in sequence. Used on launch and on settings change;
    /// the steady-state schedule calls `refreshAPI` and `refreshJSONL` independently
    /// at their own cadences.
    public func refresh(settings: AppSettings) {
        refreshAPI(settings: settings)
        refreshJSONL(settings: settings)
    }

    /// Pull the latest %% from `/oauth/usage`. Cheap (one HTTP request) and called
    /// often.
    public func refreshAPI(settings: AppSettings) {
        guard !apiInFlight else { return }
        apiInFlight = true
        Task {
            await refreshAPIInternal()
            apiInFlight = false
            publishSnapshot(settings: settings)
        }
    }

    /// Reparse `~/.claude/projects/`. Heavier (file enumeration + per-line
    /// JSONDecoder work) and called less often.
    public func refreshJSONL(settings: AppSettings) {
        guard !jsonlInFlight else { return }
        jsonlInFlight = true
        Task {
            await refreshJSONLInternal(settings: settings)
            jsonlInFlight = false
            publishSnapshot(settings: settings)
        }
    }

    /// Used during onboarding when we have a URL but no bookmark yet.
    public func refresh(claudeURL: URL, settings: AppSettings) {
        guard !apiInFlight && !jsonlInFlight else { return }
        apiInFlight = true
        jsonlInFlight = true
        Task {
            await refreshAPIInternal()
            await loadJSONL(from: claudeURL, securityScoped: false, settings: settings)
            apiInFlight = false
            jsonlInFlight = false
            publishSnapshot(settings: settings)
        }
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func refreshAPIInternal() async {
        do {
            let token = try resolveToken()
            let response = try await usageFetcher.fetchUsage(token: token)
            apiResponse = response
            apiDataAge  = 0
            appGroupStore.save(response)
        } catch let error as APIError {
            if case .httpError(401) = error {
                log.info("API returned 401; invalidating cached token")
                invalidateToken()
            } else {
                log.error("API refresh failed: \(error.localizedDescription, privacy: .public)")
            }
            loadCachedResponseIfNeeded()
        } catch {
            log.error("API refresh failed: \(error.localizedDescription, privacy: .public)")
            loadCachedResponseIfNeeded()
        }
    }

    private func loadCachedResponseIfNeeded() {
        guard let cached = appGroupStore.loadCachedAPIResponse() else { return }
        if apiResponse == nil { apiResponse = cached.response }
        apiDataAge = cached.age
    }

    private func resolveToken() throws -> String {
        // 1. In-memory (same launch).
        if let t = cachedToken { return t }
        // 2. Our Keychain cache — populated on the first successful read from
        //    Claude Code's credentials item, survives relaunch silently.
        if let t = tokenCache.readToken() {
            cachedToken = t
            return t
        }
        // 3. Read from Claude Code's Keychain item. macOS shows the access prompt
        //    once; the resulting token is then mirrored into our own cache.
        let t = try keychain.readClaudeToken()
        cachedToken = t
        tokenCache.writeToken(t)
        return t
    }

    private func invalidateToken() {
        cachedToken = nil
        tokenCache.deleteToken()
    }

    private func refreshJSONLInternal(settings: AppSettings) async {
        let url: URL?
        do {
            url = try bookmarkStore.resolve()
        } catch {
            log.error("Bookmark resolve failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let url else { return }
        await loadJSONL(from: url, securityScoped: true, settings: settings)
    }

    private func loadJSONL(from url: URL, securityScoped: Bool, settings: AppSettings) async {
        let started = securityScoped && url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        let sessions: [SessionRecord]
        do {
            sessions = try await Task.detached(priority: .background) {
                try JSONLParser().parseAllSessions(in: url)
            }.value
        } catch {
            log.error("JSONL parse failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let calc = CostCalculator()
        weeklyUsage = LimitCalculator.weeklyUsage(from: sessions, calculator: calc)
        monthlyUsage = LimitCalculator.monthlyUsage(from: sessions, calculator: calc)
    }

    private func publishSnapshot(settings: AppSettings) {
        let snapshot = WidgetSnapshot(
            updatedAt: .now,
            sessionPercent: sessionPercent,
            weekPercent: weekPercent,
            sessionResetsAt: apiResponse?.fiveHour?.resetsAt,
            weekResetsAt: apiResponse?.sevenDay?.resetsAt,
            currentProject: currentProjectName ?? "",
            weekCostUSD: weeklyUsage.costUSD,
            topProject: weeklyUsage.projectBreakdown.first?.name ?? ""
        )
        appGroupStore.save(snapshot)
        appGroupStore.save(settings)
    }
}
