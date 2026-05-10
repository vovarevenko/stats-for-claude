import SwiftUI
import OSLog
import StatsForClaudeKit

private let log = Log.make("Onboarding")

struct OnboardingView: View {
    @Environment(MenuBarViewModel.self) private var vm

    @State private var phase: Phase = .welcome

    enum Phase { case welcome, success, failed(String) }

    var body: some View {
        VStack(spacing: 32) {
            switch phase {
            case .welcome: welcomeContent
            case .success: successContent
            case .failed(let msg): failedContent(msg)
            }
        }
        .padding(44)
        .frame(width: 520, alignment: .center)
    }

    // MARK: – Phases

    private var welcomeContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 10) {
                Text(String(localized: "onboarding_title"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(String(localized: "onboarding_description"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: chooseFolder) {
                Label(String(localized: "choose_folder"), systemImage: "folder.badge.plus")
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                Text(String(localized: "onboarding_privacy"))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    private var successContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text(String(localized: "onboarding_success_title"))
                .font(.title2.bold())

            Button(String(localized: "get_started")) {
                closeWindow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func failedContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: chooseFolder) {
                Label(String(localized: "choose_folder"), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: – Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true            // .claude is a hidden directory
        panel.prompt = String(localized: "choose_folder")

        // Pre-navigate to ~/.claude so the user only needs to click Open
        let claudeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        panel.directoryURL = claudeURL

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try BookmarkStore().save(url: url)
            vm.store.refresh(settings: vm.settings)
            withAnimation(.easeInOut) { phase = .success }
        } catch {
            log.error("Onboarding bookmark save failed: \(error.localizedDescription, privacy: .public)")
            withAnimation(.easeInOut) { phase = .failed(error.localizedDescription) }
        }
    }

    private func closeWindow() {
        NSApp.windows
            .first { $0.identifier?.rawValue == "onboarding" }?
            .close()
    }
}

#Preview {
    OnboardingView()
        .environment(MenuBarViewModel())
}
