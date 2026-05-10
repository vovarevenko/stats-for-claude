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
}
