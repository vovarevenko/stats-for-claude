import SwiftUI
import StatsForClaudeKit
import StatsForClaudeAppKit

@main
struct StatsForClaudeApp: App {
    @State private var vm = MenuBarViewModel()

    var body: some Scene {
        Window(String(localized: "dashboard_title"), id: "dashboard") {
            DashboardView()
                .environment(vm)
        }
        .defaultSize(width: 900, height: 620)

        Window(String(localized: "onboarding_title"), id: "onboarding") {
            OnboardingView()
                .environment(vm)
        }
        .defaultSize(width: 520, height: 400)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarPopoverView()
                .environment(vm)
        } label: {
            MenuBarLabelView(vm: vm)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabelView: View {
    @Environment(\.openWindow) private var openWindow
    let vm: MenuBarViewModel

    var body: some View {
        Text(vm.menuBarTitle)
            .font(.system(.body, design: .default).monospacedDigit())
            .task { vm.start() }
            .task(id: vm.needsOnboarding) {
                guard vm.needsOnboarding else { return }
                try? await Task.sleep(for: .milliseconds(300))
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
