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
    public var isLoading: Bool {
        apiInFlight || jsonlInFlight
    }

    private var apiInFlight = false
    private var jsonlInFlight = false

    /// Until this moment all Anthropic-bound HTTP traffic is suppressed.
    /// Anthropic shares a single rate-limit bucket across `/api/oauth/usage`
    /// and `/v1/oauth/token`, so a 429 from either endpoint must back off
    /// both — otherwise the next OAuth refresh also 429s, `tryRefresh`
    /// returns `nil`, we fall through to reading `Claude Code-credentials`,
    /// and the ACL prompt comes back.
    private var cooldownUntil: Date?
    /// Count of consecutive 429s. Drives exponential back-off when the upstream
    /// `Retry-After` is missing or ≤ 0 (Anthropic occasionally returns
    /// `Retry-After: 0`, which would otherwise reduce the cooldown to a no-op).
    /// Reset on the next successful response.
    private var consecutive429Count = 0

    /// Schedule of fall-back cooldowns indexed by `consecutive429Count - 1`,
    /// capped at 30 min so a stuck rate limit doesn't permanently stop us.
    static let backoffSchedule: [TimeInterval] = [60, 120, 240, 480, 960, 1800]

    private let appGroupStore: AppGroupStore
    private let bookmarkStore: BookmarkResolving
    private let usageFetcher: UsageFetching
    private let keychain: KeychainCredentialsAccessing
    private let credentialsCache: CredentialsCacheStoring
    private let oauthClient: TokenRefreshing

    /// In-memory mirror of the cached credentials; avoids a Security framework
    /// round-trip on every refresh inside a single launch.
    private var cachedCredentials: ClaudeCredentials?

    public init(
        appGroupStore: AppGroupStore = .shared,
        bookmarkStore: BookmarkResolving = BookmarkStore(),
        usageFetcher: UsageFetching = UsageAPIClient(),
        keychain: KeychainCredentialsAccessing = KeychainStore(),
        credentialsCache: CredentialsCacheStoring = KeychainCredentialsCache(),
        oauthClient: TokenRefreshing = ClaudeOAuthClient()
    ) {
        self.appGroupStore = appGroupStore
        self.bookmarkStore = bookmarkStore
        self.usageFetcher = usageFetcher
        self.keychain = keychain
        self.credentialsCache = credentialsCache
        self.oauthClient = oauthClient

        // Sanitize: prior versions stored the OAuth token in plain text under
        // UserDefaults.standard. Strip that leftover on first run after upgrade.
        UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
    }

    private static let legacyDefaultsKey = "cachedClaudeAccessToken"

    public var hasBookmark: Bool {
        bookmarkStore.hasBookmark
    }

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
        guard !isInCooldown() else {
            log.debug("Skipping API refresh; in rate-limit cooldown")
            return
        }
        apiInFlight = true
        Task {
            await refreshAPIInternal()
            apiInFlight = false
            publishSnapshot(settings: settings)
        }
    }

    /// True while we're still inside the rate-limit cooldown window. Exposed
    /// internally so callers and tests can reason about why a refresh was a
    /// no-op.
    func isInCooldown(now: Date = .now) -> Bool {
        guard let until = cooldownUntil else { return false }
        return now < until
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
        guard !apiInFlight, !jsonlInFlight else { return }
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

    /// Test seam: tests drive this directly instead of waiting on the spawned
    /// Task to settle.
    func refreshAPIInternal() async {
        do {
            let token = try await resolveAccessToken()
            do {
                let response = try await usageFetcher.fetchUsage(token: token)
                apiResponse = response
                apiDataAge = 0
                appGroupStore.save(response)
                clearCooldown()
            } catch APIError.httpError(401) {
                // Access token rejected mid-flight. Try one refresh+retry before
                // giving up on the cached credentials.
                log.info("API returned 401; attempting refresh-and-retry")
                let retried = try await refreshAndRetry()
                apiResponse = retried
                apiDataAge = 0
                appGroupStore.save(retried)
                clearCooldown()
            }
        } catch let error as APIError {
            switch error {
            case .httpError(401):
                log.info("Refresh-and-retry exhausted; invalidating cached credentials")
                invalidateCredentials()
            case let .rateLimited(retryAfter):
                enterCooldown(retryAfter: retryAfter)
            default:
                log.error("API refresh failed: \(error.localizedDescription, privacy: .public)")
            }
            loadCachedResponseIfNeeded()
        } catch {
            log.error("API refresh failed: \(error.localizedDescription, privacy: .public)")
            loadCachedResponseIfNeeded()
        }
    }

    private func enterCooldown(retryAfter: TimeInterval?) {
        consecutive429Count += 1
        let wait: TimeInterval
        if let retryAfter, retryAfter > 0 {
            wait = retryAfter
        } else {
            let idx = min(consecutive429Count - 1, Self.backoffSchedule.count - 1)
            wait = Self.backoffSchedule[idx]
        }
        cooldownUntil = Date(timeIntervalSinceNow: wait)
        let attempt = consecutive429Count
        log
            .info(
                "Rate limited (attempt \(attempt, privacy: .public)); pausing Anthropic requests for \(Int(wait), privacy: .public)s"
            )
    }

    /// Cleared on the next successful Anthropic response. Without this, a
    /// transient rate limit would leave `consecutive429Count` permanently
    /// elevated and force long cooldowns even after the upstream recovers.
    private func clearCooldown() {
        let prior = consecutive429Count
        if prior > 0 {
            log.info("Rate-limit cleared after \(prior, privacy: .public) attempt(s)")
        }
        consecutive429Count = 0
        cooldownUntil = nil
    }

    private func loadCachedResponseIfNeeded() {
        guard let cached = appGroupStore.loadCachedAPIResponse() else { return }
        if apiResponse == nil { apiResponse = cached.response }
        apiDataAge = cached.age
    }

    /// Resolves a usable access token. The chain is:
    /// 1. In-memory credentials (same launch).
    /// 2. Our own Keychain cache (`KeychainCredentialsCache`). If the access
    ///    token is expiring soon and we hold a refresh token, exchange it via
    ///    `ClaudeOAuthClient` instead of touching the CLI Keychain.
    /// 3. Read `Claude Code-credentials` from the Keychain. This is the only
    ///    step that can trigger the macOS ACL prompt; the goal of the whole
    ///    cache+refresh design is to keep step 3 to a one-time event.
    private func resolveAccessToken() async throws -> String {
        if let creds = cachedCredentials, !creds.isExpiringSoon() {
            return creds.accessToken
        }

        if let creds = credentialsCache.read() {
            cachedCredentials = creds
            if !creds.isExpiringSoon() {
                log.debug("Access token resolved from local Keychain cache")
                return creds.accessToken
            }
            if let refreshed = await tryRefresh(using: creds) {
                return refreshed.accessToken
            }
            // If refresh failed because of a rate limit, do NOT fall through
            // to the CLI Keychain — that's exactly the path that surfaces an
            // ACL prompt. Surface the cooldown to the caller so the API tick
            // is skipped and the cached (slightly expired) token survives.
            if isInCooldown() { throw APIError.rateLimited(retryAfter: nil) }
            // Other failure (no refresh token, network error). Drop the
            // stale cache and fall through to reading the CLI item.
            log.info("Cached credentials unusable; falling back to CLI Keychain")
            invalidateCredentials()
        }

        log.info("Credentials cache empty; reading Claude Code credentials")
        return try readAndCacheFromCLI()
    }

    /// Reads `Claude Code-credentials` and seeds both the in-memory and
    /// Keychain caches. The only path that can trigger the macOS ACL prompt
    /// — kept behind explicit `log.info` to make any unexpected hit visible.
    private func readAndCacheFromCLI() throws -> String {
        let creds = try keychain.readClaudeCredentials()
        cachedCredentials = creds
        credentialsCache.write(creds)
        return creds.accessToken
    }

    /// Called after a mid-flight 401: rotate the access token and retry the
    /// API once. Rethrows `APIError.httpError(401)` if the retry also fails so
    /// the caller can decide to invalidate.
    private func refreshAndRetry() async throws -> UsageAPIResponse {
        guard let creds = cachedCredentials ?? credentialsCache.read() else {
            throw APIError.httpError(401)
        }
        guard let refreshed = await tryRefresh(using: creds) else {
            // If `tryRefresh` set a cooldown (its own 429), surface that
            // instead of 401 so the outer catch keeps the cache intact.
            if isInCooldown() { throw APIError.rateLimited(retryAfter: nil) }
            throw APIError.httpError(401)
        }
        return try await usageFetcher.fetchUsage(token: refreshed.accessToken)
    }

    /// Best-effort exchange of `creds.refreshToken` for a new access token.
    /// Updates both the in-memory and Keychain caches on success.
    private func tryRefresh(using creds: ClaudeCredentials) async -> ClaudeCredentials? {
        guard let refreshToken = creds.refreshToken else { return nil }
        do {
            let new = try await oauthClient.refresh(using: refreshToken)
            cachedCredentials = new
            credentialsCache.write(new)
            // Mirror the refreshed tokens into the CLI's keychain item.
            // Our refresh invalidated the CLI's old refresh token, so without
            // this step the CLI's next refresh attempt fails and logs the
            // user out. `writeClaudeCredentials` reads the current envelope
            // first so CLI-only fields (`scopes`, `subscriptionType`, …)
            // always reflect the CLI's latest state.
            do {
                try keychain.writeClaudeCredentials(new)
                log.info("Refreshed access token via OAuth (CLI keychain mirrored)")
            } catch {
                log
                    .error(
                        "OAuth refresh succeeded but CLI keychain write-back failed: \(error.localizedDescription, privacy: .public)"
                    )
            }
            return new
        } catch let APIError.rateLimited(retryAfter) {
            // Don't burn the cache — token is probably still good for a bit.
            // The cooldown will gate the next refresh attempt too.
            enterCooldown(retryAfter: retryAfter)
            return nil
        } catch {
            log.error("OAuth refresh failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func invalidateCredentials() {
        cachedCredentials = nil
        credentialsCache.delete()
    }

    func refreshJSONLInternal(settings: AppSettings) async {
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

    private func loadJSONL(from url: URL, securityScoped: Bool, settings _: AppSettings) async {
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
