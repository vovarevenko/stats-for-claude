import Testing
@testable import StatsForClaudeKit

@Suite("ProjectPathDecoder")
struct ProjectPathDecoderTests {

    @Test("decodes simple encoded paths", arguments: [
        ("-Users-john-Code-myapp", "/Users/john/Code/myapp"),
        ("-Users-vovarevenko-Code-stats-for-claude", "/Users/vovarevenko/Code/stats/for/claude"),
    ])
    func decodesSimplePaths(encoded: String, expected: String) {
        #expect(ProjectPathDecoder.decodedPath(from: encoded) == expected)
    }

    @Test("leading dash becomes leading slash")
    func leadingDashStripped() {
        let decoded = ProjectPathDecoder.decodedPath(from: "-Users-john-Desktop")
        #expect(decoded.hasPrefix("/"))
    }

    @Test("project name from simple encoded path")
    func projectNameSimple() {
        #expect(ProjectPathDecoder.projectName(from: "-Users-john-Code-myapp") == "myapp")
    }

    @Test("project name from deep encoded path is non-empty")
    func projectNameDeepPath() {
        // Without filesystem resolution, last component of naive decode is returned.
        #expect(!ProjectPathDecoder.projectName(from: "-Users-john-Code-work-api-server").isEmpty)
    }

    @Test("empty input returns Unknown")
    func emptyInputReturnsUnknown() {
        #expect(ProjectPathDecoder.projectName(from: "") == "Unknown")
    }

    @Test("hyphenated directory name is non-empty (known limitation)")
    func hyphenatedKnownLimitation() {
        // Documents the naive-decode limitation for hyphenated dirs without filesystem resolution.
        #expect(!ProjectPathDecoder.projectName(from: "-Users-vovarevenko-Code-stats-for-claude").isEmpty)
    }
}
