import Foundation
import Testing
@testable import StatsForClaudeKit

@Suite("LimitCalculator")
struct LimitCalculatorTests {

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

    @Test("weekly usage includes sessions newer than 7 days")
    func weeklyUsageIncludesRecentSessions() {
        let now = Date()
        let recent = makeSession(messages: [makeMessage(timestamp: now.addingTimeInterval(-3600))])
        let old = makeSession(messages: [makeMessage(timestamp: now.addingTimeInterval(-8 * 24 * 3600))])

        let weekly = LimitCalculator.weeklyUsage(from: [recent, old], now: now)
        #expect(weekly.projectBreakdown.count == 1)
    }

    @Test("weekly usage excludes sessions older than 7 days")
    func weeklyUsageExcludesOldSessions() {
        let now = Date()
        let old = makeSession(messages: [makeMessage(timestamp: now.addingTimeInterval(-8 * 24 * 3600))])

        let weekly = LimitCalculator.weeklyUsage(from: [old], now: now)
        #expect(weekly.projectBreakdown.count == 0)
        #expect(weekly.totalUsage.total == 0)
    }
}
