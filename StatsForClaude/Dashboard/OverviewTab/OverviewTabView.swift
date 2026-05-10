import StatsForClaudeAppKit
import StatsForClaudeKit
import SwiftUI

struct OverviewTabView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(MenuBarViewModel.self) private var vm

    var body: some View {
        switch state {
        case .needsOnboarding:
            ContentUnavailableView {
                Label(String(localized: "overview_no_folder_title"), systemImage: "folder.badge.questionmark")
            } description: {
                Text(String(localized: "overview_no_folder_hint"))
            } actions: {
                Button(String(localized: "choose_folder")) {
                    openWindow(id: "onboarding")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)
            }
        case .loading:
            ContentUnavailableView {
                ProgressView()
                    .controlSize(.large)
            } description: {
                Text(String(localized: "overview_loading"))
            }
        case .unavailable:
            ContentUnavailableView {
                Label(String(localized: "overview_unavailable_title"), systemImage: "wifi.slash")
            } description: {
                Text(String(localized: "overview_unavailable_hint"))
            } actions: {
                Button(String(localized: "try_again")) {
                    vm.store.refresh(settings: vm.settings)
                }
                .buttonStyle(.borderedProminent)
            }
        case .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LimitsHeaderView()
                    ProjectsTableView()
                }
                .padding(20)
            }
        }
    }

    private enum State { case needsOnboarding, loading, unavailable, ready }

    private var state: State {
        if vm.needsOnboarding { return .needsOnboarding }
        if vm.store.apiResponse != nil { return .ready }
        return vm.store.isLoading ? .loading : .unavailable
    }
}
