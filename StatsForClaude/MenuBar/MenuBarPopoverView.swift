import SwiftUI
import StatsForClaudeKit
import StatsForClaudeAppKit

struct MenuBarPopoverView: View {
    /// Don't bother showing the "Updated Xm ago" line if the data is fresher
    /// than this — the user already sees the live numbers above.
    private static let stalenessHintThreshold: TimeInterval = 300

    @Environment(\.openWindow) private var openWindow
    @Environment(MenuBarViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
                .background(MenuBarWindowConfigurator())

            UsageRow(
                label: String(localized: "session_limit"),
                fraction: vm.store.sessionPercent,
                timeRemaining: vm.store.sessionTimeRemaining
            )
            UsageRow(
                label: String(localized: "week_limit"),
                fraction: vm.store.weekPercent,
                timeRemaining: vm.store.weekTimeRemaining,
                resetsAt: vm.store.apiResponse?.sevenDay?.resetsAt
            )

            Divider()
                .padding(.horizontal, 14)
                .padding(.bottom, 9)

            if vm.store.apiDataAge > Self.stalenessHintThreshold {
                let isStale = vm.store.apiDataAge > CachedAPIResponse.staleAfter
                HStack(spacing: 6) {
                    Image(systemName: isStale
                          ? "exclamationmark.triangle.fill"
                          : "clock.arrow.circlepath")
                        .foregroundStyle(isStale ? .orange : .secondary)
                    Text(stalenessLabel)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }

            MenuRow(label: String(localized: "menu_dashboard")) {
                vm.selectedTab = .overview
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
                ConfiguratorView.dismiss()
            }
            MenuRow(label: String(localized: "settings_menu_item")) {
                vm.selectedTab = .settings
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
                ConfiguratorView.dismiss()
            }

            Divider()
                .padding(.horizontal, 14)
                .padding(.vertical, 4)

            MenuRow(label: String(localized: "quit")) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 5)
        .frame(width: 280)
    }

    private var stalenessLabel: String {
        let age = vm.store.apiDataAge
        let mins = Int(age / 60)
        if mins < 60 {
            return String(format: String(localized: "updated_minutes_ago"), mins)
        }
        let hours = Int(age / 3600)
        let remainingMins = (Int(age) % 3600) / 60
        if remainingMins > 0 {
            return String(format: String(localized: "updated_hours_minutes_ago"), hours, remainingMins)
        }
        return String(format: String(localized: "updated_hours_ago"), hours)
    }
}

// MARK: – Usage row

private struct UsageRow: View {
    let label: String
    let fraction: Double
    let timeRemaining: TimeInterval
    var resetsAt: Date? = nil

    private var gaugeTint: Color {
        fraction >= 0.9 ? .red : fraction >= 0.75 ? .orange : .accentColor
    }

    private var resetsLabel: String {
        guard timeRemaining > 0 else { return "—" }
        let base = String(format: String(localized: "resets_in"), CountdownFormatter.format(timeRemaining))
        guard let date = resetsAt else { return base }
        let weekday = weekdayFormatter.string(from: date)
        let time = timeFormatter.string(from: date)
        return base + String(format: String(localized: "resets_weekday_time"), weekday, time)
    }

    private var weekdayFormatter: DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.callout)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.callout.weight(.semibold).monospacedDigit())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(gaugeTint)
                        .frame(width: max(0, geo.size.width * min(fraction, 1)))
                }
            }
            .frame(height: 5)

            Text(resetsLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: – Menu row

private struct MenuRow: View {
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.body)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.07) : .clear)
                        .padding(.horizontal, 5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: – Window configurator

private struct MenuBarWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView { ConfiguratorView() }
    func updateNSView(_ nsView: ConfiguratorView, context: Context) {}
}

// HIToolbox menu-tracking notifications. Posting these makes the system treat
// our window as if a real NSMenu were being tracked, which keeps the menu bar
// pinned even when the user has "Automatically hide and show the menu bar" on.
private extension Notification.Name {
    static let beginMenuTracking = Notification.Name("com.apple.HIToolbox.beginMenuTrackingNotification")
    static let endMenuTracking = Notification.Name("com.apple.HIToolbox.endMenuTrackingNotification")
}

final class ConfiguratorView: NSView {
    @MainActor static weak var currentWindow: NSWindow?

    @MainActor
    static func dismiss() {
        currentWindow?.orderOut(nil)
    }

    private weak var trackedWindow: NSWindow?
    private var isTracking = false
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        teardownObservers()
        endMenuTrackingIfNeeded()

        guard let window else { return }

        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .auxiliary]

        trackedWindow = window
        Self.currentWindow = window

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginMenuTrackingIfNeeded() }
        })

        observers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endMenuTrackingIfNeeded() }
        })

        observers.append(center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endMenuTrackingIfNeeded() }
        })

        if window.isKeyWindow {
            beginMenuTrackingIfNeeded()
        }
    }

    private func beginMenuTrackingIfNeeded() {
        guard !isTracking else { return }
        isTracking = true
        DistributedNotificationCenter.default().post(name: .beginMenuTracking, object: nil)
    }

    private func endMenuTrackingIfNeeded() {
        guard isTracking else { return }
        isTracking = false
        DistributedNotificationCenter.default().post(name: .endMenuTracking, object: nil)
    }

    private func teardownObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
