import SwiftUI
import StatsForClaudeKit
import StatsForClaudeAppKit

struct DashboardView: View {
    @Environment(MenuBarViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm

        TabView(selection: $vm.selectedTab) {
            OverviewTabView()
                .tabItem { Label(String(localized: "overview"), systemImage: "chart.bar.fill") }
                .tag(DashboardTab.overview)

            ContentUnavailableView(
                String(localized: "history"),
                systemImage: "calendar",
                description: Text("Coming soon")
            )
            .tabItem { Label(String(localized: "history"), systemImage: "calendar") }
            .tag(DashboardTab.history)

            SettingsView()
                .tabItem { Label(String(localized: "settings"), systemImage: "gearshape") }
                .tag(DashboardTab.settings)
        }
        .frame(minWidth: 860, minHeight: 540)
    }
}
