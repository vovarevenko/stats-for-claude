import Foundation
import Observation
import StatsForClaudeKit

enum DashboardTab: Int, Hashable, CaseIterable {
    case overview, history, settings
}

@Observable
@MainActor
final class MenuBarViewModel {
    let store: UsageStore
    private(set) var settings: AppSettings
    private let bookmarkStore: BookmarkResolving

    /// Currently selected tab in the Dashboard window. Mutable so the menu bar popover
    /// (which lives in a different scene) can request a specific tab when opening it.
    var selectedTab: DashboardTab = .overview

    private static let apiRefreshInterval: Duration = .seconds(60)
    private static let jsonlRefreshInterval: Duration = .seconds(300)

    private var apiTimer: Task<Void, Never>?
    private var jsonlTimer: Task<Void, Never>?

    init(
        store: UsageStore = UsageStore(),
        settings: AppSettings = SettingsStore.load(),
        bookmarkStore: BookmarkResolving = BookmarkStore()
    ) {
        self.store = store
        self.settings = settings
        self.bookmarkStore = bookmarkStore
    }

    // MARK: – Menu bar label

    var menuBarTitle: String {
        guard store.apiResponse != nil else { return "Claude…" }
        let sp = Int((store.sessionPercent * 100).rounded())
        let wp = Int((store.weekPercent * 100).rounded())
        return "\(sp)% · \(wp)%"
    }

    var needsOnboarding: Bool {
        !bookmarkStore.hasBookmark
    }

    // MARK: – Lifecycle

    func start() {
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

    func updateSettings(_ new: AppSettings) {
        settings = new
        SettingsStore.save(new)
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
