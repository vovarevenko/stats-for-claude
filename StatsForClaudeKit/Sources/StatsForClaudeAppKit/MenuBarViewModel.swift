import Foundation
import Observation
import StatsForClaudeKit

public enum DashboardTab: Int, Hashable, CaseIterable, Sendable {
    case overview, history, settings
}

/// Owns the per-launch app state: which tab is open, what `AppSettings` are
/// in effect, and the two refresh timers. Lives in `StatsForClaudeAppKit` so
/// `swift test` can construct it with fake stores; the SwiftUI views in the
/// app target depend on this module.
@Observable
@MainActor
public final class MenuBarViewModel {
    public let store: UsageStore
    public private(set) var settings: AppSettings
    private let bookmarkStore: BookmarkResolving
    private let settingsPersistence: SettingsPersisting

    /// Currently selected tab in the Dashboard window. Mutable so the menu bar popover
    /// (which lives in a different scene) can request a specific tab when opening it.
    public var selectedTab: DashboardTab = .overview

    private static let apiRefreshInterval: Duration = .seconds(60)
    private static let jsonlRefreshInterval: Duration = .seconds(300)

    private var apiTimer: Task<Void, Never>?
    private var jsonlTimer: Task<Void, Never>?

    public init(
        store: UsageStore = UsageStore(),
        settings: AppSettings? = nil,
        bookmarkStore: BookmarkResolving = BookmarkStore(),
        settingsPersistence: SettingsPersisting = SettingsStore()
    ) {
        self.store = store
        self.bookmarkStore = bookmarkStore
        self.settingsPersistence = settingsPersistence
        self.settings = settings ?? settingsPersistence.load()
    }

    // MARK: – Menu bar label

    public var menuBarTitle: String {
        guard store.apiResponse != nil else { return "Claude…" }
        let sp = Int((store.sessionPercent * 100).rounded())
        let wp = Int((store.weekPercent * 100).rounded())
        return "\(sp)% · \(wp)%"
    }

    public var needsOnboarding: Bool {
        !bookmarkStore.hasBookmark
    }

    // MARK: – Lifecycle

    public func start() {
        guard apiTimer == nil else { return }
        store.refresh(settings: settings)
        apiTimer = Task { [weak self] in
            await Self.tick(every: Self.apiRefreshInterval) {
                guard let self else { return }
                self.store.refreshAPI(settings: self.settings)
            }
        }
        jsonlTimer = Task { [weak self] in
            await Self.tick(every: Self.jsonlRefreshInterval) {
                guard let self else { return }
                self.store.refreshJSONL(settings: self.settings)
            }
        }
    }

    public func updateSettings(_ new: AppSettings) {
        settings = new
        settingsPersistence.save(new)
        store.refresh(settings: new)
    }

    private static func tick(every interval: Duration, _ action: @MainActor () -> Void) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { break }
            await MainActor.run(body: action)
        }
    }
}
