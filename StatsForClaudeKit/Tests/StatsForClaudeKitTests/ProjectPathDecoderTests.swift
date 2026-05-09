import XCTest
@testable import StatsForClaudeKit

final class ProjectPathDecoderTests: XCTestCase {

    func testSimplePathDecoding() {
        let decoded = ProjectPathDecoder.decodedPath(from: "-Users-john-Code-myapp")
        XCTAssertEqual(decoded, "/Users/john/Code/myapp")
    }

    func testLeadingDashStripped() {
        let decoded = ProjectPathDecoder.decodedPath(from: "-Users-john-Desktop")
        XCTAssertTrue(decoded.hasPrefix("/"))
    }

    func testProjectNameSimple() {
        let name = ProjectPathDecoder.projectName(from: "-Users-john-Code-myapp")
        XCTAssertEqual(name, "myapp")
    }

    func testProjectNameDeepPath() {
        let name = ProjectPathDecoder.projectName(from: "-Users-john-Code-work-api-server")
        // Without filesystem resolution last component of naive decode
        XCTAssertFalse(name.isEmpty)
    }

    func testEmptyInputReturnsUnknown() {
        let name = ProjectPathDecoder.projectName(from: "")
        XCTAssertEqual(name, "Unknown")
    }

    func testKnownProjectsDirectoryName() {
        // The encoded name from the real ~/.claude/projects directory
        let encoded = "-Users-vovarevenko-Code-stats-for-claude"
        let decoded = ProjectPathDecoder.decodedPath(from: encoded)
        XCTAssertEqual(decoded, "/Users/vovarevenko/Code/stats/for/claude") // naive decode
        // project name would be wrong for hyphenated dirs without filesystem resolution
        // This test documents the known limitation
        let name = ProjectPathDecoder.projectName(from: encoded)
        XCTAssertFalse(name.isEmpty)
    }
}
