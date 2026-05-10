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

    private var refreshTask: Task<Void, Never>?

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
        guard refreshTask == nil else { return }
        refreshTask = Task {
            store.refresh(settings: settings)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                store.refresh(settings: settings)
            }
        }
    }

    func updateSettings(_ new: AppSettings) {
        settings = new
        SettingsStore.save(new)
        store.refresh(settings: new)
    }
}
