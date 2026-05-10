import Foundation
import Testing
@testable import StatsForClaudeKit

@Suite("ProjectPathDecoder")
struct ProjectPathDecoderTests {
    // MARK: – decodedPath

    @Test("decodes simple encoded paths", arguments: [
        ("-Users-john-Code-myapp", "/Users/john/Code/myapp"),
        ("-Users-vovarevenko-Code-stats-for-claude", "/Users/vovarevenko/Code/stats/for/claude"),
    ])
    func decodesSimplePaths(encoded: String, expected: String) {
        #expect(ProjectPathDecoder.decodedPath(from: encoded) == expected)
    }

    @Test("leading dash becomes leading slash")
    func leadingDashStripped() {
        #expect(ProjectPathDecoder.decodedPath(from: "-Users-john-Desktop").hasPrefix("/"))
    }

    @Test("input without leading dash is still slash-prefixed")
    func noLeadingDashStillSlashed() {
        #expect(ProjectPathDecoder.decodedPath(from: "Users-john") == "/Users/john")
    }

    // MARK: – projectName

    @Test("project name from simple encoded path")
    func projectNameSimple() {
        #expect(ProjectPathDecoder.projectName(from: "-Users-john-Code-myapp") == "myapp")
    }

    @Test("project name from deep encoded path is non-empty")
    func projectNameDeepPath() {
        #expect(!ProjectPathDecoder.projectName(from: "-Users-john-Code-work-api-server").isEmpty)
    }

    @Test("empty input returns Unknown")
    func emptyInputReturnsUnknown() {
        #expect(ProjectPathDecoder.projectName(from: "") == "Unknown")
    }

    @Test("hyphenated directory name is non-empty (known limitation)")
    func hyphenatedKnownLimitation() {
        #expect(!ProjectPathDecoder.projectName(from: "-Users-vovarevenko-Code-stats-for-claude").isEmpty)
    }

    // MARK: – resolvedPath

    @Test("resolvedPath without leading dash returns input unchanged")
    func resolvedPathWithoutDash() {
        #expect(ProjectPathDecoder.resolvedPath(from: "absolute/path") == "absolute/path")
    }

    @Test("resolvedPath falls back to /-joined remainder for non-existent paths")
    func resolvedPathFallback() {
        let result = ProjectPathDecoder.resolvedPath(from: "-thisdoesnotexist1234-foo-bar")
        #expect(result.hasPrefix("/"))
        #expect(result.contains("thisdoesnotexist1234"))
    }

    // MARK: – uniqueSuffixes

    @Test("uniqueSuffixes returns empty dict for empty input")
    func uniqueSuffixesEmpty() {
        #expect(ProjectPathDecoder.uniqueSuffixes(of: []).isEmpty)
    }

    @Test("uniqueSuffixes with one path returns last component")
    func uniqueSuffixesSingle() {
        let result = ProjectPathDecoder.uniqueSuffixes(of: ["/Users/x/Code/foo"])
        #expect(result == ["/Users/x/Code/foo": "foo"])
    }

    @Test("uniqueSuffixes trims common prefix at slash boundary")
    func uniqueSuffixesTrimsCommon() {
        let result = ProjectPathDecoder.uniqueSuffixes(of: [
            "/Users/x/Code/foo/bar",
            "/Users/x/Docs/baz",
        ])
        #expect(result["/Users/x/Code/foo/bar"] == "Code/foo/bar")
        #expect(result["/Users/x/Docs/baz"] == "Docs/baz")
    }

    @Test("uniqueSuffixes does not split inside a folder name")
    func uniqueSuffixesNoMidFolderSplit() {
        // "/Users/abc" and "/Users/abd" share "/Users/ab" but trim must back up to "/".
        let result = ProjectPathDecoder.uniqueSuffixes(of: ["/Users/abc", "/Users/abd"])
        #expect(result["/Users/abc"] == "abc")
        #expect(result["/Users/abd"] == "abd")
    }
}
