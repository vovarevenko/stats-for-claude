import SwiftUI
import StatsForClaudeKit
import StatsForClaudeAppKit

struct OverviewTabView: View {
    @Environment(MenuBarViewModel.self) private var vm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LimitsHeaderView()
                ProjectsTableView()
            }
            .padding(20)
        }
    }
}
