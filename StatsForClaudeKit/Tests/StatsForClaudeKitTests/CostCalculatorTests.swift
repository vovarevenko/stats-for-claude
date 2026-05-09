import XCTest
@testable import StatsForClaudeKit

final class CostCalculatorTests: XCTestCase {
    private let calc = CostCalculator()

    private func message(model: String, input: Int, output: Int, cacheWrite: Int = 0, cacheRead: Int = 0) -> MessageRecord {
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

    func testSonnetModelFamily() {
        XCTAssertEqual(ModelFamily(modelString: "claude-sonnet-4-6"), .sonnet)
        XCTAssertEqual(ModelFamily(modelString: "claude-3-5-sonnet-20241022"), .sonnet)
    }

    func testOpusModelFamily() {
        XCTAssertEqual(ModelFamily(modelString: "claude-opus-4-7"), .opus)
        XCTAssertEqual(ModelFamily(modelString: "claude-3-opus-20240229"), .opus)
    }

    func testHaikuModelFamily() {
        XCTAssertEqual(ModelFamily(modelString: "claude-haiku-4-5-20251001"), .haiku)
        XCTAssertEqual(ModelFamily(modelString: "claude-3-haiku-20240307"), .haiku)
    }

    func testUnknownModelFallsBackToSonnet() {
        XCTAssertEqual(ModelFamily(modelString: "claude-unknown-model"), .unknown)
        let pricing = Pricing.pricing(for: "claude-unknown-model")
        XCTAssertEqual(pricing.inputPerMillion, Pricing.sonnet.inputPerMillion, accuracy: 0.001)
    }

    // MARK: – Cost calculation

    func testSonnetCostOnlyInput() {
        // 1M input tokens at $3/M = $3.00
        let msg = message(model: "claude-sonnet-4-6", input: 1_000_000, output: 0)
        XCTAssertEqual(calc.costUSD(for: msg), 3.0, accuracy: 0.0001)
    }

    func testSonnetCostOnlyOutput() {
        // 1M output tokens at $15/M = $15.00
        let msg = message(model: "claude-sonnet-4-6", input: 0, output: 1_000_000)
        XCTAssertEqual(calc.costUSD(for: msg), 15.0, accuracy: 0.0001)
    }

    func testOpusCostInputOutput() {
        // 100K input @$15/M + 100K output @$75/M = $1.50 + $7.50 = $9.00
        let msg = message(model: "claude-opus-4-7", input: 100_000, output: 100_000)
        XCTAssertEqual(calc.costUSD(for: msg), 9.0, accuracy: 0.0001)
    }

    func testHaikuCostCacheRead() {
        // 1M cache_read at $0.08/M = $0.08
        let msg = message(model: "claude-haiku-4-5-20251001", input: 0, output: 0, cacheRead: 1_000_000)
        XCTAssertEqual(calc.costUSD(for: msg), 0.08, accuracy: 0.0001)
    }

    func testSonnetCostAllTokenTypes() {
        // Sonnet: $3 input + $15 output + $3.75 cache_write + $0.30 cache_read (all per M)
        // Using 1M of each: $3 + $15 + $3.75 + $0.30 = $22.05
        let msg = message(
            model: "claude-sonnet-4-6",
            input: 1_000_000, output: 1_000_000,
            cacheWrite: 1_000_000, cacheRead: 1_000_000
        )
        XCTAssertEqual(calc.costUSD(for: msg), 22.05, accuracy: 0.0001)
    }

    func testZeroTokensCostIsZero() {
        let msg = message(model: "claude-sonnet-4-6", input: 0, output: 0)
        XCTAssertEqual(calc.costUSD(for: msg), 0.0, accuracy: 0.0001)
    }

    func testSessionCostIsSumOfMessages() {
        let session = SessionRecord(
            sessionId: "s",
            encodedProjectPath: "-Users-test",
            projectName: "test",
            messages: [
                message(model: "claude-sonnet-4-6", input: 1_000_000, output: 0),  // $3.00
                message(model: "claude-sonnet-4-6", input: 0, output: 1_000_000),  // $15.00
            ]
        )
        XCTAssertEqual(calc.costUSD(for: session), 18.0, accuracy: 0.0001)
    }

    // MARK: – Fixture integration

    func testSonnetFixtureCost() throws {
        let url = Bundle.module.url(forResource: "Fixtures/session_sonnet.jsonl", withExtension: nil)
            ?? Bundle.module.url(forResource: "session_sonnet.jsonl", withExtension: nil, subdirectory: "Fixtures")!
        let record = try XCTUnwrap(JSONLParser().parseSession(at: url, encodedProjectPath: "-test"))

        let cost = calc.costUSD(for: record)
        // input: 30, output: 55, cacheWrite: 100, cacheRead: 400 (all in tokens)
        // input: 30/1M * $3 = $0.000090
        // output: 55/1M * $15 = $0.000825
        // cacheWrite: 100/1M * $3.75 = $0.000375
        // cacheRead: 400/1M * $0.30 = $0.000120
        // total ≈ $0.001410
        XCTAssertEqual(cost, 0.001410, accuracy: 0.000001)
    }
}
