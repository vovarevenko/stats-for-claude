import Foundation
import Testing
@testable import StatsForClaudeKit

@Suite("TokenFormatter")
struct TokenFormatterTests {
    @Test("plain digits below 1k", arguments: [
        (0, "0"),
        (1, "1"),
        (42, "42"),
        (999, "999"),
    ])
    func belowOneThousand(value: Int, expected: String) {
        #expect(TokenFormatter.format(value) == expected)
    }

    @Test("k-suffix between 1k and 1M (boundary inclusive)", arguments: [
        (1000, "1.0K"),
        (1500, "1.5K"),
        (12345, "12.3K"),
        (999_999, "1000.0K"),
    ])
    func thousandsRange(value: Int, expected: String) {
        #expect(TokenFormatter.format(value) == expected)
    }

    @Test("M-suffix at and above 1M", arguments: [
        (1_000_000, "1.00M"),
        (1_234_567, "1.23M"),
        (10_000_000, "10.00M"),
        (1_000_000_000, "1000.00M"),
    ])
    func millionsRange(value: Int, expected: String) {
        #expect(TokenFormatter.format(value) == expected)
    }
}

@Suite("CountdownFormatter")
struct CountdownFormatterTests {
    @Test("zero or negative interval renders em-dash", arguments: [
        TimeInterval(0),
        TimeInterval(-1),
        TimeInterval(-3600),
    ])
    func zeroOrNegative(interval: TimeInterval) {
        #expect(CountdownFormatter.format(interval) == "—")
    }

    @Test("sub-minute renders <1m")
    func subMinute() {
        #expect(CountdownFormatter.format(30) == "<1m")
        #expect(CountdownFormatter.format(59) == "<1m")
    }

    @Test("minutes-only", arguments: [
        (TimeInterval(60), "1m"),
        (TimeInterval(15 * 60), "15m"),
        (TimeInterval(59 * 60 + 59), "59m"),
    ])
    func minutesOnly(interval: TimeInterval, expected: String) {
        #expect(CountdownFormatter.format(interval) == expected)
    }

    @Test("hours and minutes under 1 day", arguments: [
        (TimeInterval(3600), "1h 0m"),
        (TimeInterval(2 * 3600 + 15 * 60), "2h 15m"),
        (TimeInterval(23 * 3600 + 59 * 60), "23h 59m"),
    ])
    func hoursAndMinutes(interval: TimeInterval, expected: String) {
        #expect(CountdownFormatter.format(interval) == expected)
    }

    @Test("days plus hours", arguments: [
        (TimeInterval(86400), "1d"),
        (TimeInterval(86400 + 3600), "1d 1h"),
        (TimeInterval(2 * 86400 + 5 * 3600), "2d 5h"),
        (TimeInterval(7 * 86400), "7d"),
    ])
    func daysAndHours(interval: TimeInterval, expected: String) {
        #expect(CountdownFormatter.format(interval) == expected)
    }
}
