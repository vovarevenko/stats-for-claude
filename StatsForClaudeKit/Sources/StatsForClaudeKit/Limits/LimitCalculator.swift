import Foundation

public enum LimitCalculator {
    public static let weekDuration: TimeInterval = 7 * 24 * 3600

    // MARK: – Weekly usage (rolling 7 days)

    public static func weeklyUsage(
        from sessions: [SessionRecord],
        now: Date = .now,
        calculator: CostCalculator = CostCalculator()
    ) -> WeeklyUsage {
        let cutoff = now.addingTimeInterval(-weekDuration)

        let weekSessions = sessions.filter { s in
            guard let last = s.lastTimestamp else { return false }
            return last >= cutoff
        }

        let byProject = Dictionary(grouping: weekSessions, by: \.encodedProjectPath)
        let projects = byProject.map { encodedPath, projectSessions -> ProjectUsage in
            let name = projectSessions.first?.projectName ?? "Unknown"
            let cost = projectSessions.reduce(0.0) { $0 + calculator.costUSD(for: $1) }
            return ProjectUsage(name: name, encodedPath: encodedPath, sessions: projectSessions, costUSD: cost)
        }
        .sorted { $0.totalUsage.total > $1.totalUsage.total }

        let totalCost = projects.reduce(0.0) { $0 + $1.costUSD }
        return WeeklyUsage(windowStart: cutoff, windowEnd: now, projectBreakdown: projects, costUSD: totalCost)
    }

    // MARK: – Monthly usage (current calendar month, anchored to the 1st)

    public static func monthlyUsage(
        from sessions: [SessionRecord],
        now: Date = .now,
        calendar: Calendar = .current,
        calculator: CostCalculator = CostCalculator()
    ) -> WeeklyUsage {
        let comps = calendar.dateComponents([.year, .month], from: now)
        let monthStart = calendar.date(from: comps) ?? now

        let monthSessions = sessions.filter { s in
            guard let last = s.lastTimestamp else { return false }
            return last >= monthStart
        }

        let byProject = Dictionary(grouping: monthSessions, by: \.encodedProjectPath)
        let projects = byProject.map { encodedPath, projectSessions -> ProjectUsage in
            let name = projectSessions.first?.projectName ?? "Unknown"
            let cost = projectSessions.reduce(0.0) { $0 + calculator.costUSD(for: $1) }
            return ProjectUsage(name: name, encodedPath: encodedPath, sessions: projectSessions, costUSD: cost)
        }
        .sorted { $0.totalUsage.total > $1.totalUsage.total }

        let totalCost = projects.reduce(0.0) { $0 + $1.costUSD }
        return WeeklyUsage(windowStart: monthStart, windowEnd: now, projectBreakdown: projects, costUSD: totalCost)
    }

    /// Splits the monthly subscription price across projects in proportion to each project's
    /// API-priced cost share. Sums to `subscriptionPrice` exactly when `totalCost > 0`.
    /// Returns 0 for every project when there is no usage yet (avoids division by zero).
    public static func amortizedSubscriptionCost(
        forProject project: ProjectUsage,
        totalCost: Double,
        subscriptionPrice: Double
    ) -> Double {
        guard totalCost > 0 else { return 0 }
        return subscriptionPrice * (project.costUSD / totalCost)
    }
}
