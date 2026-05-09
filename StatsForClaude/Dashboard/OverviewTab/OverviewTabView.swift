import SwiftUI
import StatsForClaudeKit

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
