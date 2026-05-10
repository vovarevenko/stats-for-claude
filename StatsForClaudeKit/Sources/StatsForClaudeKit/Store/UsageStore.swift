import Foundation
import Observation

@Observable
@MainActor
public final class UsageStore {

    // ── API-sourced (authoritative for % and reset times) ────────────────────
    public private(set) var apiResponse: UsageAPIResponse?
    public private(set) var apiDataAge: TimeInterval = 0

    // ── JSONL-sourced (cost + per-project breakdown) ──────────────────────────
    public private(set) var weeklyUsage: WeeklyUsage = .empty
    public private(set) var monthlyUsage: WeeklyUsage = .empty

    public private(set) var isLoading = false

    private let appGroupStore: AppGroupStore
    private let bookmarkStore: BookmarkResolving
    private let usageFetcher: UsageFetching
    private let keychain: KeychainTokenReading

    // Token is cached in-memory AND in UserDefaults so the Keychain prompt
    // fires only once across app launches (not on every startup).
    private static let tokenDefaultsKey = "cachedClaudeAccessToken"
    private var cachedToken: String?

    public init(
        appGroupStore: AppGroupStore = .shared,
        bookmarkStore: BookmarkResolving = BookmarkStore(),
        usageFetcher: UsageFetching = UsageAPIClient(),
        keychain: KeychainTokenReading = KeychainStore()
    ) {
        self.appGroupStore = appGroupStore
        self.bookmarkStore = bookmarkStore
        self.usageFetcher = usageFetcher
        self.keychain = keychain
    }

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

    /// Full refresh: API + JSONL from stored bookmark.
    public func refresh(settings: AppSettings) {
        guard !isLoading else { return }
        isLoading = true
        Task {
            await refreshAPI()
            await refreshJSONL(settings: settings)
            isLoading = false
            publishSnapshot(settings: settings)
        }
    }

    /// Used during onboarding when we have a URL but no bookmark yet.
    public func refresh(claudeURL: URL, settings: AppSettings) {
        guard !isLoading else { return }
        isLoading = true
        Task {
            await refreshAPI()
            await loadJSONL(from: claudeURL, securityScoped: false, settings: settings)
            isLoading = false
            publishSnapshot(settings: settings)
        }
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func refreshAPI() async {
        do {
            let token = try resolveToken()
            let response = try await usageFetcher.fetchUsage(token: token)
            apiResponse = response
            apiDataAge  = 0
            appGroupStore.save(response)
        } catch let error as APIError {
            if case .httpError(401) = error { invalidateToken() }
            loadCachedResponseIfNeeded()
        } catch {
            loadCachedResponseIfNeeded()
        }
    }

    private func loadCachedResponseIfNeeded() {
        guard let cached = appGroupStore.loadCachedAPIResponse() else { return }
        if apiResponse == nil { apiResponse = cached.response }
        apiDataAge = cached.age
    }

    private func resolveToken() throws -> String {
        // 1. In-memory (same launch)
        if let t = cachedToken { return t }
        // 2. Persisted across launches — avoids Keychain prompt on every startup
        if let t = UserDefaults.standard.string(forKey: Self.tokenDefaultsKey) {
            cachedToken = t
            return t
        }
        // 3. Read from Keychain — shows system prompt once, then persists above
        let t = try keychain.readClaudeToken()
        cachedToken = t
        UserDefaults.standard.set(t, forKey: Self.tokenDefaultsKey)
        return t
    }

    private func invalidateToken() {
        cachedToken = nil
        UserDefaults.standard.removeObject(forKey: Self.tokenDefaultsKey)
    }

    private func refreshJSONL(settings: AppSettings) async {
        guard let url = (try? bookmarkStore.resolve()) ?? nil else { return }
        await loadJSONL(from: url, securityScoped: true, settings: settings)
    }

    private func loadJSONL(from url: URL, securityScoped: Bool, settings: AppSettings) async {
        let started = securityScoped && url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        let sessions = (try? await Task.detached(priority: .background) {
            try JSONLParser().parseAllSessions(in: url)
        }.value) ?? []
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
