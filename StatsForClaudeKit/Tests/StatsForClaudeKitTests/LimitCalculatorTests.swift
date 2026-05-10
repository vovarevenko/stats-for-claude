import Foundation
import Testing
@testable import StatsForClaudeKit

@Suite("LimitCalculator")
struct LimitCalculatorTests {
    private func makeMessage(
        timestamp: Date,
        model: String = "claude-sonnet-4-6",
        input: Int = 100,
        output: Int = 200
    ) -> MessageRecord {
        MessageRecord(
            timestamp: timestamp,
            model: model,
            usage: TokenUsage(inputTokens: input, outputTokens: output, cacheReadTokens: 0, cacheWriteTokens: 0)
        )
    }

    private func makeSession(
        messages: [MessageRecord],
        project: String = "test",
        sessionId: String = UUID().uuidString
    ) -> SessionRecord {
        SessionRecord(
            sessionId: sessionId,
            encodedProjectPath: "-Users-test-\(project)",
            projectName: project,
            messages: messages
        )
    }

    // MARK: – Weekly window

    @Test("weekly usage includes sessions newer than 7 days")
    func weeklyIncludesRecent() {
        let now = Date()
        let recent = makeSession(messages: [makeMessage(timestamp: now.addingTimeInterval(-3600))])
        let old = makeSession(messages: [makeMessage(timestamp: now.addingTimeInterval(-8 * 24 * 3600))])
        let weekly = LimitCalculator.weeklyUsage(from: [recent, old], now: now)
        #expect(weekly.projectBreakdown.count == 1)
    }

    @Test("weekly usage excludes sessions older than 7 days")
    func weeklyExcludesOld() {
        let now = Date()
        let old = makeSession(messages: [makeMessage(timestamp: now.addingTimeInterval(-8 * 24 * 3600))])
        let weekly = LimitCalculator.weeklyUsage(from: [old], now: now)
        #expect(weekly.projectBreakdown.isEmpty)
        #expect(weekly.totalUsage.total == 0)
    }

    @Test("session exactly at 7-day cutoff is included (>= cutoff)")
    func weeklyBoundaryInclusive() {
        let now = Date()
        let exactly = now.addingTimeInterval(-7 * 24 * 3600) // == cutoff
        let session = makeSession(messages: [makeMessage(timestamp: exactly)])
        let weekly = LimitCalculator.weeklyUsage(from: [session], now: now)
        #expect(weekly.projectBreakdown.count == 1)
    }

    @Test("session one second before cutoff is excluded")
    func weeklyBoundaryExclusive() {
        let now = Date()
        let justBefore = now.addingTimeInterval(-7 * 24 * 3600 - 1)
        let session = makeSession(messages: [makeMessage(timestamp: justBefore)])
        let weekly = LimitCalculator.weeklyUsage(from: [session], now: now)
        #expect(weekly.projectBreakdown.isEmpty)
    }

    @Test("weekly window dates match expected range")
    func weeklyWindowDates() {
        let now = Date()
        let weekly = LimitCalculator.weeklyUsage(from: [], now: now)
        #expect(weekly.windowEnd == now)
        #expect(abs(weekly.windowStart.timeIntervalSince(now) - (-7 * 24 * 3600)) < 0.001)
    }

    @Test("empty input produces empty weekly breakdown")
    func weeklyEmptyInput() {
        let weekly = LimitCalculator.weeklyUsage(from: [], now: Date())
        #expect(weekly.projectBreakdown.isEmpty)
        #expect(weekly.costUSD == 0)
        #expect(weekly.totalUsage.total == 0)
    }

    @Test("session with no messages (no lastTimestamp) is excluded")
    func sessionWithoutTimestampsIsExcluded() {
        let now = Date()
        let empty = makeSession(messages: [])
        let weekly = LimitCalculator.weeklyUsage(from: [empty], now: now)
        #expect(weekly.projectBreakdown.isEmpty)
    }

    // MARK: – Project aggregation

    @Test("sessions are grouped by encodedProjectPath")
    func groupedByProject() {
        let now = Date()
        let sessionA1 = makeSession(messages: [makeMessage(timestamp: now)], project: "alpha")
        let sessionA2 = makeSession(messages: [makeMessage(timestamp: now)], project: "alpha")
        let sessionB = makeSession(messages: [makeMessage(timestamp: now)], project: "beta")
        let weekly = LimitCalculator.weeklyUsage(from: [sessionA1, sessionA2, sessionB], now: now)
        #expect(weekly.projectBreakdown.count == 2)
        let alpha = weekly.projectBreakdown.first { $0.name == "alpha" }
        #expect(alpha?.sessions.count == 2)
    }

    @Test("project breakdown sorts by total tokens descending")
    func sortedByTotalDescending() {
        let now = Date()
        let small = makeSession(
            messages: [makeMessage(timestamp: now, input: 1, output: 1)],
            project: "small"
        )
        let big = makeSession(
            messages: [makeMessage(timestamp: now, input: 10000, output: 10000)],
            project: "big"
        )
        let weekly = LimitCalculator.weeklyUsage(from: [small, big], now: now)
        #expect(weekly.projectBreakdown.map(\.name) == ["big", "small"])
    }

    // MARK: – Monthly window

    @Test("monthly usage anchored to first of current calendar month")
    func monthlyAnchored() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        // Pick a deterministic "now" in the middle of a month.
        let comps = DateComponents(year: 2026, month: 5, day: 15, hour: 12)
        let now = try #require(calendar.date(from: comps))
        let beforeMonth = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30, hour: 23)))
        let inMonth = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 1,
            hour: 0,
            minute: 0,
            second: 1
        )))

        let s1 = makeSession(messages: [makeMessage(timestamp: beforeMonth)], project: "old")
        let s2 = makeSession(messages: [makeMessage(timestamp: inMonth)], project: "new")

        let monthly = LimitCalculator.monthlyUsage(from: [s1, s2], now: now, calendar: calendar)
        #expect(monthly.projectBreakdown.count == 1)
        #expect(monthly.projectBreakdown.first?.name == "new")
        let monthStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        #expect(monthly.windowStart == monthStart)
        #expect(monthly.windowEnd == now)
    }

    // MARK: – Amortized subscription

    @Test("amortizedSubscriptionCost splits price proportionally")
    func amortizedProportional() {
        let pA = ProjectUsage(name: "a", encodedPath: "-a", sessions: [], costUSD: 3.0)
        let pB = ProjectUsage(name: "b", encodedPath: "-b", sessions: [], costUSD: 1.0)
        let total = pA.costUSD + pB.costUSD
        let priceA = LimitCalculator.amortizedSubscriptionCost(forProject: pA, totalCost: total, subscriptionPrice: 20)
        let priceB = LimitCalculator.amortizedSubscriptionCost(forProject: pB, totalCost: total, subscriptionPrice: 20)
        #expect(abs(priceA - 15.0) < 0.0001)
        #expect(abs(priceB - 5.0) < 0.0001)
        #expect(abs(priceA + priceB - 20.0) < 0.0001)
    }

    @Test("amortizedSubscriptionCost returns zero when total is zero")
    func amortizedZeroTotal() {
        let p = ProjectUsage(name: "x", encodedPath: "-x", sessions: [], costUSD: 0)
        #expect(LimitCalculator.amortizedSubscriptionCost(forProject: p, totalCost: 0, subscriptionPrice: 20) == 0)
    }
}
