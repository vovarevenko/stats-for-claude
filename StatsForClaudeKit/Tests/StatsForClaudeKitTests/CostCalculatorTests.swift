import Foundation
import Testing
@testable import StatsForClaudeKit

@Suite("CostCalculator")
struct CostCalculatorTests {
    private let calc = CostCalculator()

    private func message(
        model: String,
        input: Int,
        output: Int,
        cacheWrite: Int = 0,
        cacheRead: Int = 0
    ) -> MessageRecord {
        MessageRecord(
            timestamp: .now,
            model: model,
            usage: TokenUsage(
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead,
                cacheWriteTokens: cacheWrite
            )
        )
    }

    // MARK: – Model detection

    @Test("model string maps to expected family", arguments: [
        ("claude-sonnet-4-6", ModelFamily.sonnet),
        ("claude-3-5-sonnet-20241022", .sonnet),
        ("claude-opus-4-7", .opus),
        ("claude-3-opus-20240229", .opus),
        ("claude-haiku-4-5-20251001", .haiku),
        ("claude-3-haiku-20240307", .haiku),
        ("claude-unknown-model", .unknown),
    ])
    func modelFamilyDetection(modelString: String, expected: ModelFamily) {
        #expect(ModelFamily(modelString: modelString) == expected)
    }

    @Test("unknown model falls back to sonnet pricing")
    func unknownModelFallsBackToSonnet() {
        let pricing = Pricing.pricing(for: "claude-unknown-model")
        #expect(abs(pricing.inputPerMillion - Pricing.sonnet.inputPerMillion) < 0.001)
    }

    // MARK: – Cost calculation

    struct CostCase: Sendable {
        let label: String
        let model: String
        let input: Int
        let output: Int
        let cacheWrite: Int
        let cacheRead: Int
        let expected: Double
    }

    @Test("per-message cost", arguments: [
        // Sonnet: $3/M input, $15/M output
        CostCase(label: "sonnet input only",  model: "claude-sonnet-4-6",        input: 1_000_000, output: 0,          cacheWrite: 0,          cacheRead: 0,          expected: 3.0),
        CostCase(label: "sonnet output only", model: "claude-sonnet-4-6",        input: 0,          output: 1_000_000, cacheWrite: 0,          cacheRead: 0,          expected: 15.0),
        // Opus: $15/M input, $75/M output → 100k+100k = $1.50 + $7.50
        CostCase(label: "opus in+out",        model: "claude-opus-4-7",          input: 100_000,    output: 100_000,   cacheWrite: 0,          cacheRead: 0,          expected: 9.0),
        // Haiku cache_read $0.08/M
        CostCase(label: "haiku cache read",   model: "claude-haiku-4-5-20251001", input: 0,          output: 0,         cacheWrite: 0,          cacheRead: 1_000_000, expected: 0.08),
        // Sonnet all token types: $3 + $15 + $3.75 + $0.30
        CostCase(label: "sonnet all types",   model: "claude-sonnet-4-6",        input: 1_000_000, output: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000, expected: 22.05),
        CostCase(label: "zero tokens",        model: "claude-sonnet-4-6",        input: 0,          output: 0,         cacheWrite: 0,          cacheRead: 0,          expected: 0.0),
    ])
    func messageCost(testCase: CostCase) {
        let msg = message(
            model: testCase.model,
            input: testCase.input,
            output: testCase.output,
            cacheWrite: testCase.cacheWrite,
            cacheRead: testCase.cacheRead
        )
        #expect(abs(calc.costUSD(for: msg) - testCase.expected) < 0.0001, "\(testCase.label)")
    }

    @Test("session cost is sum of message costs")
    func sessionCostIsSumOfMessages() {
        let session = SessionRecord(
            sessionId: "s",
            encodedProjectPath: "-Users-test",
            projectName: "test",
            messages: [
                message(model: "claude-sonnet-4-6", input: 1_000_000, output: 0),         // $3.00
                message(model: "claude-sonnet-4-6", input: 0,         output: 1_000_000), // $15.00
            ]
        )
        #expect(abs(calc.costUSD(for: session) - 18.0) < 0.0001)
    }

    @Test("cache_write only — sonnet")
    func cacheWriteOnly() {
        // 1M cache_write at $3.75/M = $3.75
        let msg = message(model: "claude-sonnet-4-6", input: 0, output: 0, cacheWrite: 1_000_000)
        #expect(abs(calc.costUSD(for: msg) - 3.75) < 0.0001)
    }

    @Test("unknown model is priced like sonnet")
    func unknownModelPricedAsSonnet() {
        let unknown = message(model: "claude-mystery", input: 1_000_000, output: 1_000_000)
        let sonnet  = message(model: "claude-sonnet-4-6", input: 1_000_000, output: 1_000_000)
        #expect(abs(calc.costUSD(for: unknown) - calc.costUSD(for: sonnet)) < 0.0001)
    }

    @Test("session with mixed model families sums per-model rates")
    func mixedModelSessionCost() {
        // Opus: 1M output @ $75/M = $75.00
        // Haiku: 1M output @ $4/M  = $4.00
        let session = SessionRecord(
            sessionId: "mix",
            encodedProjectPath: "-Users-test",
            projectName: "test",
            messages: [
                message(model: "claude-opus-4-7",          input: 0, output: 1_000_000),
                message(model: "claude-haiku-4-5-20251001", input: 0, output: 1_000_000),
            ]
        )
        #expect(abs(calc.costUSD(for: session) - 79.0) < 0.0001)
    }

    @Test("empty session has zero cost")
    func emptySessionZeroCost() {
        let session = SessionRecord(
            sessionId: "empty",
            encodedProjectPath: "-x",
            projectName: "x",
            messages: []
        )
        #expect(calc.costUSD(for: session) == 0)
    }

    // MARK: – Fixture integration

    @Test("sonnet fixture produces expected cost")
    func sonnetFixtureCost() throws {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/session_sonnet.jsonl", withExtension: nil)
                ?? Bundle.module.url(forResource: "session_sonnet.jsonl", withExtension: nil, subdirectory: "Fixtures")
        )
        let parsed = try JSONLParser().parseSession(at: url, encodedProjectPath: "-test")
        let record = try #require(parsed)

        // input 30, output 55, cacheWrite 100, cacheRead 400 (tokens, sonnet pricing) ≈ $0.001410
        let cost = calc.costUSD(for: record)
        #expect(abs(cost - 0.001410) < 0.000001)
    }
}
