import Foundation

public enum LimitCalculator {
    public static let sessionWindowDuration: TimeInterval = 5 * 3600
    public static let weekDuration: TimeInterval = 7 * 24 * 3600

    // MARK: – Session window (5-hour rolling)

    /// Groups all messages across sessions into contiguous blocks (gap < 5h between consecutive
    /// messages). The current block is the last one; its first timestamp is the window start.
    public static func currentSessionWindow(
        from sessions: [SessionRecord],
        now: Date = .now,
        limit: Int
    ) -> SessionWindow {
        // Pair each message with its owning session so we can find project name
        let allPairs: [(msg: MessageRecord, session: SessionRecord)] = sessions
            .flatMap { s in s.messages.map { (msg: $0, session: s) } }
            .sorted { $0.msg.timestamp < $1.msg.timestamp }

        guard !allPairs.isEmpty else {
            return .empty(limit: limit)
        }

        var blocks: [[(msg: MessageRecord, session: SessionRecord)]] = []
        var active: [(msg: MessageRecord, session: SessionRecord)] = [allPairs[0]]

        for i in 1..<allPairs.count {
            let gap = allPairs[i].msg.timestamp.timeIntervalSince(allPairs[i - 1].msg.timestamp)
            if gap >= sessionWindowDuration {
                blocks.append(active)
                active = [allPairs[i]]
            } else {
                active.append(allPairs[i])
            }
        }
        blocks.append(active)

        let latest = blocks.last!
        let windowStart = latest.first!.msg.timestamp
        let windowEnd = windowStart.addingTimeInterval(sessionWindowDuration)
        let usage = latest.reduce(TokenUsage.zero) { $0 + $1.msg.usage }
        let projectName = latest.last?.session.projectName

        return SessionWindow(
            windowStart: windowStart,
            windowEnd: windowEnd,
            usage: usage,
            currentProjectName: projectName,
            limit: limit
        )
    }

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

    // MARK: – Daily breakdown (for heatmap)

    public static func dailyUsages(
        from sessions: [SessionRecord],
        daysBack: Int = 365,
        now: Date = .now,
        calculator: CostCalculator = CostCalculator()
    ) -> [DailyUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -daysBack, to: today)!

        var map: [Date: (tokens: Int, cost: Double)] = [:]
        for day in 0...daysBack {
            if let d = calendar.date(byAdding: .day, value: -day, to: today) {
                map[d] = (0, 0)
            }
        }

        for session in sessions {
            for msg in session.messages {
                let day = calendar.startOfDay(for: msg.timestamp)
                guard day >= cutoff else { continue }
                let cost = calculator.costUSD(for: msg)
                let current = map[day] ?? (0, 0)
                map[day] = (current.tokens + msg.usage.total, current.cost + cost)
            }
        }

        return map.map { DailyUsage(date: $0.key, totalTokens: $0.value.tokens, costUSD: $0.value.cost) }
            .sorted { $0.date < $1.date }
    }

    // MARK: – Weekly percent

    /// Weekly percent uses output tokens only, same rationale as SessionWindow.percentUsed.
    public static func weeklyPercent(
        from weeklyUsage: WeeklyUsage,
        limit: Int
    ) -> Double {
        guard limit > 0 else { return 0 }
        return min(1.0, Double(weeklyUsage.totalUsage.outputTokens) / Double(limit))
    }

    public static func weekTimeRemaining(from weeklyUsage: WeeklyUsage) -> TimeInterval {
        max(0, weeklyUsage.windowEnd.addingTimeInterval(weekDuration).timeIntervalSinceNow)
    }
}
