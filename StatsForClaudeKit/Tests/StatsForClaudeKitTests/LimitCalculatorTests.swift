import XCTest
@testable import StatsForClaudeKit

final class LimitCalculatorTests: XCTestCase {

    // MARK: – Helpers

    private func makeMessage(
        timestamp: Date,
        model: String = "claude-sonnet-4-6",
        input: Int = 100, output: Int = 200
    ) -> MessageRecord {
        MessageRecord(
            timestamp: timestamp,
            model: model,
            usage: TokenUsage(inputTokens: input, outputTokens: output, cacheReadTokens: 0, cacheWriteTokens: 0)
        )
    }

    private func makeSession(messages: [MessageRecord], project: String = "test") -> SessionRecord {
        SessionRecord(
            sessionId: UUID().uuidString,
            encodedProjectPath: "-Users-test-\(project)",
            projectName: project,
            messages: messages
        )
    }

    // MARK: – Session window

    func testCurrentWindowFromSingleSession() {
        let now = Date()
        let start = now.addingTimeInterval(-3600)  // 1h ago
        let messages = [
            makeMessage(timestamp: start),
            makeMessage(timestamp: start.addingTimeInterval(600)),
        ]
        let session = makeSession(messages: messages)
        let window = LimitCalculator.currentSessionWindow(from: [session], now: now, limit: 500_000)

        XCTAssertEqual(window.windowStart.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(window.windowEnd.timeIntervalSince1970, start.addingTimeInterval(5 * 3600).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(window.usage.inputTokens, 200)
        XCTAssertEqual(window.usage.outputTokens, 400)
    }

    func testExpiredWindowHasZeroTimeRemaining() {
        let expiredStart = Date().addingTimeInterval(-6 * 3600)  // 6h ago
        let messages = [makeMessage(timestamp: expiredStart)]
        let session = makeSession(messages: messages)
        let window = LimitCalculator.currentSessionWindow(from: [session], limit: 500_000)

        XCTAssertTrue(window.isExpired)
        XCTAssertEqual(window.timeRemaining, 0)
    }

    func testWindowSplitsOnGapOver5h() {
        let now = Date()
        let block1Start = now.addingTimeInterval(-8 * 3600)
        let block2Start = now.addingTimeInterval(-1 * 3600)

        let session = makeSession(messages: [
            makeMessage(timestamp: block1Start, input: 1000, output: 2000),
            makeMessage(timestamp: block2Start, input: 10, output: 20),
        ])
        let window = LimitCalculator.currentSessionWindow(from: [session], now: now, limit: 500_000)

        // Should be anchored to block2 (most recent block)
        XCTAssertEqual(window.windowStart.timeIntervalSince1970, block2Start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(window.usage.inputTokens, 10)
    }

    func testPercentUsed() {
        let start = Date().addingTimeInterval(-600)
        // percentUsed is based on OUTPUT tokens only (cache_read is ~90× larger and excluded)
        let messages = [makeMessage(timestamp: start, input: 900_000, output: 10_000)]
        let session = makeSession(messages: messages)
        let window = LimitCalculator.currentSessionWindow(from: [session], limit: 50_000)

        // output 10K / limit 50K = 20%
        XCTAssertEqual(window.percentUsed, 0.2, accuracy: 0.001)
    }

    func testEmptySessionsReturnsEmptyWindow() {
        let window = LimitCalculator.currentSessionWindow(from: [], limit: 500_000)
        XCTAssertEqual(window.usage.total, 0)
    }

    // MARK: – Weekly usage

    func testWeeklyUsageIncludesRecentSessions() {
        let now = Date()
        let recent = makeSession(messages: [makeMessage(timestamp: now.addingTimeInterval(-3600))])
        let old = makeSession(messages: [makeMessage(timestamp: now.addingTimeInterval(-8 * 24 * 3600))])

        let weekly = LimitCalculator.weeklyUsage(from: [recent, old], now: now)

        XCTAssertEqual(weekly.projectBreakdown.count, 1)
    }

    func testWeeklyUsageExcludesOldSessions() {
        let now = Date()
        let old = makeSession(messages: [makeMessage(timestamp: now.addingTimeInterval(-8 * 24 * 3600))])

        let weekly = LimitCalculator.weeklyUsage(from: [old], now: now)
        XCTAssertEqual(weekly.projectBreakdown.count, 0)
        XCTAssertEqual(weekly.totalUsage.total, 0)
    }

    // MARK: – Daily usages

    func testDailyUsagesCount() {
        let now = Date()
        let sessions = [
            makeSession(messages: [makeMessage(timestamp: now.addingTimeInterval(-3600))]),
        ]
        let daily = LimitCalculator.dailyUsages(from: sessions, daysBack: 30, now: now)
        XCTAssertEqual(daily.count, 31) // 30 days back + today
    }

    func testDailyUsagesTodayHasTokens() {
        let now = Date()
        let msg = makeMessage(timestamp: now.addingTimeInterval(-60), input: 500, output: 1000)
        let sessions = [makeSession(messages: [msg])]
        let daily = LimitCalculator.dailyUsages(from: sessions, daysBack: 7, now: now)

        let today = Calendar.current.startOfDay(for: now)
        let entry = daily.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
        XCTAssertEqual(entry?.totalTokens, 1500)
    }
}
