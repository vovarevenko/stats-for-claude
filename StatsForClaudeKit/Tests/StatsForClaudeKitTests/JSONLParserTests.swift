import XCTest
@testable import StatsForClaudeKit

final class JSONLParserTests: XCTestCase {
    private let parser = JSONLParser()

    private func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
            ?? Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    // MARK: – Sonnet

    func testSonnetParsesThreeMessages() throws {
        let url = fixture("session_sonnet.jsonl")
        let record = try XCTUnwrap(parser.parseSession(at: url, encodedProjectPath: "-Users-test-my-project"))

        XCTAssertEqual(record.messages.count, 3)
        XCTAssertEqual(record.sessionId, "test-session-sonnet")
    }

    func testSonnetTotalTokens() throws {
        let url = fixture("session_sonnet.jsonl")
        let record = try XCTUnwrap(parser.parseSession(at: url, encodedProjectPath: "-Users-test-my-project"))

        let usage = record.totalUsage
        // input: 10+15+5 = 30
        XCTAssertEqual(usage.inputTokens, 30)
        // output: 20+25+10 = 55
        XCTAssertEqual(usage.outputTokens, 55)
        // cacheWrite: 100+0+0 = 100
        XCTAssertEqual(usage.cacheWriteTokens, 100)
        // cacheRead: 50+150+200 = 400
        XCTAssertEqual(usage.cacheReadTokens, 400)
        // total: 30+55+100+400 = 585
        XCTAssertEqual(usage.total, 585)
    }

    func testSonnetModelDetected() throws {
        let url = fixture("session_sonnet.jsonl")
        let record = try XCTUnwrap(parser.parseSession(at: url, encodedProjectPath: "-Users-test-my-project"))

        XCTAssertTrue(record.messages.allSatisfy { $0.model == "claude-sonnet-4-6" })
    }

    // MARK: – Opus

    func testOpusParsesToMessages() throws {
        let url = fixture("session_opus.jsonl")
        let record = try XCTUnwrap(parser.parseSession(at: url, encodedProjectPath: "-Users-test-opus"))

        XCTAssertEqual(record.messages.count, 2)
        XCTAssertEqual(record.sessionId, "test-session-opus")
    }

    func testOpusTotalTokens() throws {
        let url = fixture("session_opus.jsonl")
        let record = try XCTUnwrap(parser.parseSession(at: url, encodedProjectPath: "-Users-test-opus"))

        let usage = record.totalUsage
        XCTAssertEqual(usage.inputTokens, 80)    // 50+30
        XCTAssertEqual(usage.outputTokens, 180)  // 100+80
        XCTAssertEqual(usage.cacheWriteTokens, 500) // 500+0
        XCTAssertEqual(usage.cacheReadTokens, 900)  // 200+700
    }

    // MARK: – Haiku

    func testHaikuParsesCorrectModel() throws {
        let url = fixture("session_haiku.jsonl")
        let record = try XCTUnwrap(parser.parseSession(at: url, encodedProjectPath: "-Users-test-haiku"))

        XCTAssertTrue(record.messages.allSatisfy { $0.model.contains("haiku") })
    }

    // MARK: – Edge cases

    func testEmptyFileReturnsNil() {
        let data = "".data(using: .utf8)!
        let record = parser.parseSession(from: data, encodedProjectPath: "", fallbackSessionId: "empty")
        XCTAssertNil(record)
    }

    func testSkipsNonAssistantRows() throws {
        let jsonl = """
        {"type":"permission-mode","permissionMode":"default","sessionId":"s1"}
        {"message":{"role":"user","content":"hi"},"timestamp":"2026-05-01T10:00:00.000Z","sessionId":"s1"}
        """.data(using: .utf8)!
        let record = parser.parseSession(from: jsonl, encodedProjectPath: "", fallbackSessionId: "s1")
        XCTAssertNil(record)
    }

    func testHandlesMissingUsageGracefully() {
        let jsonl = """
        {"message":{"role":"assistant","model":"claude-sonnet-4-6"},"timestamp":"2026-05-01T10:00:00.000Z","sessionId":"s2"}
        """.data(using: .utf8)!
        let record = parser.parseSession(from: jsonl, encodedProjectPath: "", fallbackSessionId: "s2")
        XCTAssertNil(record)
    }

    func testTimestampsAreParsedCorrectly() throws {
        let url = fixture("session_sonnet.jsonl")
        let record = try XCTUnwrap(parser.parseSession(at: url, encodedProjectPath: "-Users-test-my-project"))

        let first = try XCTUnwrap(record.messages.first?.timestamp)
        let last  = try XCTUnwrap(record.lastTimestamp)

        // First message at 10:00:05, last at 10:10:15
        XCTAssertLessThan(first, last)
        let gap = last.timeIntervalSince(first)
        XCTAssertEqual(gap, 10 * 60 + 10, accuracy: 1.0)
    }
}
