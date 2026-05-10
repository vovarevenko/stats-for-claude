import Foundation
import Testing
@testable import StatsForClaudeKit

/// Coarse upper bounds against accidental O(n²) regressions in hot paths.
/// A 1-minute ceiling is generous on purpose: the goal is to catch a parser
/// rewrite that is orders of magnitude slower, not to police microseconds.
@Suite("Performance budgets")
struct PerformanceTests {
    @Test(.timeLimit(.minutes(1)))
    func jsonlParseTenThousandMessages() throws {
        let messageCount = 10000
        var data = Data()
        let timestamp = "2026-05-09T12:00:00.000Z"
        for _ in 0 ..< messageCount {
            let line = """
            {"timestamp":"\(
                timestamp
            )","sessionId":"perf","message":{"role":"assistant","model":"claude-sonnet-4","usage":{"input_tokens":120,"output_tokens":340,"cache_read_input_tokens":50,"cache_creation_input_tokens":12}}}
            """
            data.append(Data(line.utf8))
            data.append(UInt8(ascii: "\n"))
        }

        let parser = JSONLParser()
        let session = parser.parseSession(
            from: data,
            encodedProjectPath: "-tmp-perf",
            fallbackSessionId: "perf"
        )
        try #require(session != nil)
        #expect(session?.messages.count == messageCount)
    }

    @Test(.timeLimit(.minutes(1)))
    func uniqueSuffixesScalesLinearly() {
        let paths = (0 ..< 5000).map { "/Users/test/Projects/group-\($0 / 100)/proj-\($0)" }
        let result = ProjectPathDecoder.uniqueSuffixes(of: paths)
        #expect(result.count == paths.count)
    }
}
