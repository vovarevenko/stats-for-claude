import OSLog
import StatsForClaudeAppKit
import StatsForClaudeKit
import SwiftUI

private let log = Log.make("SettingsView")

struct SettingsView: View {
    @Environment(MenuBarViewModel.self) private var vm

    // Local draft — synced to vm on every change
    @State private var draft: AppSettings = .default
    @State private var claudeDirectoryPath = ""

    var body: some View {
        Form {
            // ── Subscription ─────────────────────────────────────────────────
            Section {
                LabeledContent(String(localized: "subscription_price")) {
                    HStack(spacing: 6) {
                        TextField(
                            String(""),
                            value: $draft.subscriptionPriceUSD,
                            format: .number.precision(.fractionLength(0 ... 2))
                        )
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)

                        Picker(String(""), selection: $draft.currency) {
                            ForEach(AppSettings.Currency.allCases, id: \.self) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }
                        .frame(width: 72)
                        .labelsHidden()
                    }
                }

                Picker(String(localized: "plan"), selection: $draft.plan) {
                    ForEach(Plan.allCases, id: \.self) { plan in
                        Text(plan.rawValue).tag(plan)
                    }
                }
                .onChange(of: draft.plan) { _, newPlan in
                    draft.apply(plan: newPlan)
                }
            } header: {
                Text(String(localized: "subscription_price"))
            }

            // ── Limits ───────────────────────────────────────────────────────
            Section {
                LabeledContent(String(localized: "session_limit_label")) {
                    TextField(
                        String(""),
                        value: $draft.sessionTokenLimit,
                        format: .number.grouping(.automatic)
                    )
                    .frame(width: 120)
                    .multilineTextAlignment(.trailing)
                }

                LabeledContent(String(localized: "weekly_limit_label")) {
                    TextField(
                        String(""),
                        value: $draft.weeklyTokenLimit,
                        format: .number.grouping(.automatic)
                    )
                    .frame(width: 120)
                    .multilineTextAlignment(.trailing)
                }

                Button(String(localized: "reset_to_defaults")) {
                    draft.apply(plan: draft.plan)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } header: {
                Text("Limits (output tokens)")
            } footer: {
                Text("Percentages are based on output tokens only. Cache reads are excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Claude directory ─────────────────────────────────────────────
            Section {
                HStack {
                    Text(claudeDirectoryPath.isEmpty ? String(localized: "not_set") : claudeDirectoryPath)
                        .foregroundStyle(claudeDirectoryPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(String(localized: "browse")) {
                        chooseDirectory()
                    }
                }
            } header: {
                Text(String(localized: "claude_directory"))
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear {
            draft = vm.settings
            claudeDirectoryPath = resolveBookmarkPath()
        }
        .onChange(of: draft) { _, new in
            vm.updateSettings(new)
        }
    }

    // MARK: – Helpers

    private func resolveBookmarkPath() -> String {
        guard let url = try? BookmarkStore().resolve() else { return "" }
        return url.path
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = String(localized: "browse")
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try BookmarkStore().save(url: url)
            claudeDirectoryPath = url.path
            vm.store.refresh(settings: vm.settings)
        } catch {
            log.error("Saving bookmark failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
