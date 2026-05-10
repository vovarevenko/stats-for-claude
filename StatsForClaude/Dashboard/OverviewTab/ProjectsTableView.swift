import SwiftUI
import StatsForClaudeKit
import StatsForClaudeAppKit

struct ProjectsTableView: View {
    @Environment(MenuBarViewModel.self) private var vm
    @State private var sortOrder = [KeyPathComparator(\ProjectRow.costUSD, order: .reverse)]

    private var rows: [ProjectRow] {
        let monthly = vm.store.monthlyUsage
        let totalCost = monthly.costUSD
        let subscription = vm.settings.subscriptionPriceUSD

        // Resolve full paths once and compute disambiguated display strings.
        let projects = monthly.projectBreakdown
        let fullPaths = projects.map { ProjectPathDecoder.resolvedPath(from: $0.encodedPath) }
        let suffixes = ProjectPathDecoder.uniqueSuffixes(of: fullPaths)

        return zip(projects, fullPaths)
            .map { project, fullPath -> ProjectRow in
                let cost = LimitCalculator.amortizedSubscriptionCost(
                    forProject: project,
                    totalCost: totalCost,
                    subscriptionPrice: subscription
                )
                return ProjectRow(
                    id: project.id,
                    displayPath: suffixes[fullPath] ?? project.name,
                    fullPath: fullPath,
                    outputTokens: project.totalUsage.outputTokens,
                    costUSD: cost
                )
            }
            .sorted(using: sortOrder)
    }

    private var totalTokens: Int { rows.reduce(0) { $0 + $1.outputTokens } }
    private var totalCost: Double { rows.reduce(0) { $0 + $1.costUSD } }

    private static let rowHeight: CGFloat = 30
    private static let headerHeight: CGFloat = 30

    private var tableHeight: CGFloat {
        CGFloat(rows.count) * Self.rowHeight + Self.headerHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "projects_this_month"))
                .font(.headline)

            (Text(String(localized: "cost")).bold()
                + Text(" — ")
                + Text(String(localized: "cost_explanation")))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            if rows.isEmpty {
                ContentUnavailableView(
                    String(localized: "no_data"),
                    systemImage: "tray",
                    description: Text(String(localized: "no_data_hint"))
                )
                .frame(height: 120)
            } else {
                table
                    .frame(height: tableHeight)
            }
        }
    }

    private var table: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn(String(localized: "project_name"), value: \.displayPath) { row in
                projectNameText(row.displayPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.fullPath)
            }
            .width(min: 140, ideal: 220)

            TableColumn(String(localized: "tokens"), value: \.outputTokens) { row in
                ValueBarCell(
                    text: TokenFormatter.format(row.outputTokens),
                    percent: totalTokens > 0 ? Double(row.outputTokens) / Double(totalTokens) * 100 : 0,
                    emphasized: false
                )
            }
            .width(min: 210, ideal: 230)
            .alignment(.trailing)

            TableColumn(String(localized: "cost"), value: \.costUSD) { row in
                ValueBarCell(
                    text: formatMoney(row.costUSD),
                    percent: totalCost > 0 ? row.costUSD / totalCost * 100 : 0,
                    emphasized: true
                )
            }
            .width(min: 210, ideal: 230)
            .alignment(.trailing)
        }
    }

    // MARK: – Helpers

    /// Splits the display path at the last "/" so the parent segments render muted
    /// while the leaf (the part the user actually identifies the project by) stays
    /// in the primary colour.
    private func projectNameText(_ path: String) -> Text {
        guard let slashIndex = path.lastIndex(of: "/") else {
            return Text(path)
        }
        let prefix = String(path[..<path.index(after: slashIndex)])
        let leaf = String(path[path.index(after: slashIndex)...])
        return Text(prefix).foregroundStyle(.tertiary) + Text(leaf)
    }

    private func formatMoney(_ value: Double) -> String {
        "\(vm.settings.currency.symbol)\(String(format: "%.2f", value))"
    }
}

// MARK: – Cell with value text + magnitude bar

/// A right-aligned numeric cell that shows three reinforcing pieces of info for the column:
/// a progress bar (share of column total), the percent number itself in muted style, and
/// the formatted value at the right edge. Visual emphasis is controlled by `emphasized`:
/// emphasized cells use accent colour and primary text; others use a muted bar and
/// secondary text — useful as a hierarchy hint between columns.
private struct ValueBarCell: View {
    let text: String
    let percent: Double   // 0…100, share of column total
    let emphasized: Bool

    /// Fixed widths so bars and value slots line up identically across both columns
    /// and don't jitter row-to-row when value strings differ in length.
    private static let barWidth: CGFloat = 90
    private static let percentWidth: CGFloat = 32
    private static let valueWidth: CGFloat = 70

    private var fraction: Double { min(1, max(0, percent / 100)) }

    private var barTint: Color {
        emphasized ? Color.accentColor : Color.secondary
    }

    private var trackTint: Color {
        Color.primary.opacity(emphasized ? 0.10 : 0.06)
    }

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            ZStack(alignment: .leading) {
                Capsule().fill(trackTint)
                Capsule()
                    .fill(barTint)
                    .frame(width: Self.barWidth * fraction)
                    .animation(.easeInOut, value: fraction)
            }
            .frame(width: Self.barWidth, height: 5)

            Text("\(Int(percent.rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: Self.percentWidth, alignment: .trailing)

            Text(text)
                .monospacedDigit()
                .fontWeight(emphasized ? .medium : .regular)
                .foregroundStyle(emphasized ? .primary : .secondary)
                .frame(width: Self.valueWidth, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: – Row model

struct ProjectRow: Identifiable {
    let id: String
    let displayPath: String
    let fullPath: String
    let outputTokens: Int
    let costUSD: Double
}
