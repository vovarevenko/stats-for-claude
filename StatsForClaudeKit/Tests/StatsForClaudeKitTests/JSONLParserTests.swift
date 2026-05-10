import Foundation
import Testing
@testable import StatsForClaudeKit

@Suite("JSONLParser")
struct JSONLParserTests {
    private let parser = JSONLParser()

    private func fixture(_ name: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
                ?? Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
        )
    }

    // MARK: – Sonnet

    @Suite("Sonnet fixture")
    struct Sonnet {
        private let parser = JSONLParser()

        private func record() throws -> SessionRecord {
            let url = try #require(
                Bundle.module.url(forResource: "Fixtures/session_sonnet.jsonl", withExtension: nil)
                    ?? Bundle.module.url(
                        forResource: "session_sonnet.jsonl",
                        withExtension: nil,
                        subdirectory: "Fixtures"
                    )
            )
            let parsed = try parser.parseSession(at: url, encodedProjectPath: "-Users-test-my-project")
            return try #require(parsed)
        }

        @Test("parses three messages with expected sessionId")
        func parsesThreeMessages() throws {
            let r = try record()
            #expect(r.messages.count == 3)
            #expect(r.sessionId == "test-session-sonnet")
        }

        @Test("aggregates token totals across messages")
        func totalTokens() throws {
            let usage = try record().totalUsage
            #expect(usage.inputTokens == 30) // 10+15+5
            #expect(usage.outputTokens == 55) // 20+25+10
            #expect(usage.cacheWriteTokens == 100) // 100+0+0
            #expect(usage.cacheReadTokens == 400) // 50+150+200
            #expect(usage.total == 585)
        }

        @Test("all messages report sonnet model")
        func modelDetected() throws {
            #expect(try record().messages.allSatisfy { $0.model == "claude-sonnet-4-6" })
        }

        @Test("first vs last timestamp gap is 10m10s")
        func timestampsParsed() throws {
            let r = try record()
            let first = try #require(r.messages.first?.timestamp)
            let last = try #require(r.lastTimestamp)
            #expect(first < last)
            let gap = last.timeIntervalSince(first)
            #expect(abs(gap - (10 * 60 + 10)) < 1.0)
        }
    }

    // MARK: – Opus

    @Suite("Opus fixture")
    struct Opus {
        private let parser = JSONLParser()

        private func record() throws -> SessionRecord {
            let url = try #require(
                Bundle.module.url(forResource: "Fixtures/session_opus.jsonl", withExtension: nil)
                    ?? Bundle.module.url(
                        forResource: "session_opus.jsonl",
                        withExtension: nil,
                        subdirectory: "Fixtures"
                    )
            )
            let parsed = try parser.parseSession(at: url, encodedProjectPath: "-Users-test-opus")
            return try #require(parsed)
        }

        @Test("parses two messages with expected sessionId")
        func parsesTwoMessages() throws {
            let r = try record()
            #expect(r.messages.count == 2)
            #expect(r.sessionId == "test-session-opus")
        }

        @Test("aggregates token totals")
        func totalTokens() throws {
            let usage = try record().totalUsage
            #expect(usage.inputTokens == 80) // 50+30
            #expect(usage.outputTokens == 180) // 100+80
            #expect(usage.cacheWriteTokens == 500) // 500+0
            #expect(usage.cacheReadTokens == 900) // 200+700
        }
    }

    // MARK: – Haiku

    @Test("haiku fixture detects haiku model")
    func haikuModelDetected() throws {
        let url = try fixture("session_haiku.jsonl")
        let parsed = try parser.parseSession(at: url, encodedProjectPath: "-Users-test-haiku")
        let record = try #require(parsed)
        #expect(record.messages.allSatisfy { $0.model.contains("haiku") })
    }

    // MARK: – Edge cases

    @Test("empty input returns nil")
    func emptyFileReturnsNil() {
        let data = Data()
        let record = parser.parseSession(from: data, encodedProjectPath: "", fallbackSessionId: "empty")
        #expect(record == nil)
    }

    @Test("non-assistant rows are skipped (no record produced)")
    func skipsNonAssistantRows() {
        let jsonl = #"""
        {"type":"permission-mode","permissionMode":"default","sessionId":"s1"}
        {"message":{"role":"user","content":"hi"},"timestamp":"2026-05-01T10:00:00.000Z","sessionId":"s1"}
        """#.data(using: .utf8)!
        #expect(parser.parseSession(from: jsonl, encodedProjectPath: "", fallbackSessionId: "s1") == nil)
    }

    @Test("missing usage field is handled gracefully")
    func handlesMissingUsageGracefully() {
        let jsonl = #"""
        {"message":{"role":"assistant","model":"claude-sonnet-4-6"},"timestamp":"2026-05-01T10:00:00.000Z","sessionId":"s2"}
        """#.data(using: .utf8)!
        #expect(parser.parseSession(from: jsonl, encodedProjectPath: "", fallbackSessionId: "s2") == nil)
    }

    @Test("malformed JSONL line is skipped, valid lines still produce a record")
    func malformedLineSkipped() throws {
        let jsonl = #"""
        not-json-at-all
        {"message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20}},"timestamp":"2026-05-01T10:00:00.000Z","sessionId":"sX"}
        """#.data(using: .utf8)!
        let record = try #require(parser.parseSession(from: jsonl, encodedProjectPath: "", fallbackSessionId: "sX"))
        #expect(record.messages.count == 1)
        #expect(record.totalUsage.inputTokens == 10)
        #expect(record.totalUsage.outputTokens == 20)
    }

    @Test("partial usage (only input/output) defaults missing fields to zero")
    func partialUsageDefaultsToZero() throws {
        let jsonl = #"""
        {"message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":7,"output_tokens":9}},"timestamp":"2026-05-01T10:00:00.000Z","sessionId":"sP"}
        """#.data(using: .utf8)!
        let record = try #require(parser.parseSession(from: jsonl, encodedProjectPath: "", fallbackSessionId: "sP"))
        let usage = record.totalUsage
        #expect(usage.inputTokens == 7)
        #expect(usage.outputTokens == 9)
        #expect(usage.cacheReadTokens == 0)
        #expect(usage.cacheWriteTokens == 0)
    }

    @Test("multiple assistant messages with different models all parsed")
    func mixedModelMessages() throws {
        let jsonl = #"""
        {"message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":1,"output_tokens":1}},"timestamp":"2026-05-01T10:00:00.000Z","sessionId":"sM"}
        {"message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":2,"output_tokens":2}},"timestamp":"2026-05-01T10:00:01.000Z","sessionId":"sM"}
        {"message":{"role":"assistant","model":"claude-haiku-4-5-20251001","usage":{"input_tokens":3,"output_tokens":3}},"timestamp":"2026-05-01T10:00:02.000Z","sessionId":"sM"}
        """#.data(using: .utf8)!
        let record = try #require(parser.parseSession(from: jsonl, encodedProjectPath: "", fallbackSessionId: "sM"))
        #expect(record.messages.count == 3)
        let models = Set(record.messages.map(\.model))
        #expect(models == ["claude-sonnet-4-6", "claude-opus-4-7", "claude-haiku-4-5-20251001"])
    }

    @Test("ISO-8601 timestamp without fractional seconds is accepted")
    func plainISOTimestampAccepted() throws {
        let jsonl = #"""
        {"message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":1,"output_tokens":1}},"timestamp":"2026-05-01T10:00:00Z","sessionId":"sIso"}
        """#.data(using: .utf8)!
        let record = try #require(parser.parseSession(from: jsonl, encodedProjectPath: "", fallbackSessionId: "sIso"))
        #expect(record.messages.count == 1)
    }

    @Test("missing sessionId in JSONL falls back to provided default")
    func sessionIdFallback() throws {
        let jsonl = #"""
        {"message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":1,"output_tokens":1}},"timestamp":"2026-05-01T10:00:00.000Z"}
        """#.data(using: .utf8)!
        let record = try #require(parser.parseSession(
            from: jsonl,
            encodedProjectPath: "",
            fallbackSessionId: "fallback-id"
        ))
        #expect(record.sessionId == "fallback-id")
    }

    @Test("empty encodedProjectPath produces Unknown projectName")
    func emptyEncodedPathProducesUnknown() throws {
        let jsonl = #"""
        {"message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":1,"output_tokens":1}},"timestamp":"2026-05-01T10:00:00.000Z","sessionId":"sU"}
        """#.data(using: .utf8)!
        let record = try #require(parser.parseSession(from: jsonl, encodedProjectPath: "", fallbackSessionId: "sU"))
        #expect(record.projectName == "Unknown")
        #expect(record.encodedProjectPath.isEmpty)
    }
}
