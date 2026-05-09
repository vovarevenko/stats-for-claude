import SwiftUI
import StatsForClaudeKit

struct LimitsHeaderView: View {
    @Environment(MenuBarViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 12) {
            LimitCard(
                title: String(localized: "session_limit"),
                fraction: vm.store.sessionPercent,
                percent: vm.store.apiResponse.map { Int($0.fiveHour?.utilization.rounded() ?? 0) },
                timeRemaining: vm.store.sessionTimeRemaining,
                resetsAt: vm.store.apiResponse?.fiveHour?.resetsAt
            )
            LimitCard(
                title: String(localized: "week_limit"),
                fraction: vm.store.weekPercent,
                percent: vm.store.apiResponse.map { Int($0.sevenDay?.utilization.rounded() ?? 0) },
                timeRemaining: vm.store.weekTimeRemaining,
                resetsAt: vm.store.apiResponse?.sevenDay?.resetsAt
            )
        }
    }
}

private struct LimitCard: View {
    let title: String
    let fraction: Double
    let percent: Int?      // nil = no data
    let timeRemaining: TimeInterval
    var resetsAt: Date? = nil

    private var gaugeTint: Color {
        fraction >= 0.9 ? .red : fraction >= 0.75 ? .orange : .accentColor
    }

    private var resetsLabel: String {
        guard timeRemaining > 0 else { return "—" }
        let base = String(format: String(localized: "resets_in"), CountdownFormatter.format(timeRemaining))
        guard let date = resetsAt else { return base }
        let weekday = Self.weekdayFormatter.string(from: date)
        let time = Self.timeFormatter.string(from: date)
        return base + String(format: String(localized: "resets_weekday_time"), weekday, time)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Group {
                    if let pct = percent {
                        Text("\(pct)%")
                            .contentTransition(.numericText())
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(gaugeTint)
                        .frame(width: max(0, geo.size.width * min(fraction, 1)))
                        .animation(.easeInOut, value: fraction)
                }
            }
            .frame(height: 6)

            Text(resetsLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 14))
    }
}
