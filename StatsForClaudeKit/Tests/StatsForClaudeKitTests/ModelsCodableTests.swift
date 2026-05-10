import Foundation
import Testing
@testable import StatsForClaudeKit

// MARK: – Helpers

private func iso8601Encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.sortedKeys]
    return e
}

private func iso8601Decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}

private func roundTrip<T: Codable & Equatable>(_ value: T, file _: StaticString = #file, line _: UInt = #line) throws {
    let encoder = iso8601Encoder()
    let decoder = iso8601Decoder()
    let data = try encoder.encode(value)
    let decoded = try decoder.decode(T.self, from: data)
    #expect(decoded == value)
}

private func date(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: iso)!
}

// MARK: – TokenUsage

@Suite("TokenUsage Codable")
struct TokenUsageCodableTests {
    @Test("round-trip preserves all fields")
    func roundTripBasic() throws {
        try roundTrip(TokenUsage(
            inputTokens: 10, outputTokens: 20,
            cacheReadTokens: 30, cacheWriteTokens: 40
        ))
    }

    @Test("zero round-trip")
    func zeroRoundTrip() throws {
        try roundTrip(TokenUsage.zero)
    }

    @Test("decodes golden JSON shape")
    func decodesGolden() throws {
        let json = #"""
        {"inputTokens":1,"outputTokens":2,"cacheReadTokens":3,"cacheWriteTokens":4}
        """#.data(using: .utf8)!
        let usage = try iso8601Decoder().decode(TokenUsage.self, from: json)
        #expect(usage.inputTokens == 1)
        #expect(usage.outputTokens == 2)
        #expect(usage.cacheReadTokens == 3)
        #expect(usage.cacheWriteTokens == 4)
    }

    @Test("unknown extra keys are ignored on decode")
    func ignoresExtraKeys() throws {
        let json = #"""
        {"inputTokens":1,"outputTokens":2,"cacheReadTokens":3,"cacheWriteTokens":4,"newField":"future"}
        """#.data(using: .utf8)!
        let usage = try iso8601Decoder().decode(TokenUsage.self, from: json)
        #expect(usage.inputTokens == 1)
    }
}

// MARK: – MessageRecord / SessionRecord

@Suite("Session models Codable")
struct SessionCodableTests {
    private func sampleSession() -> SessionRecord {
        SessionRecord(
            sessionId: "sid-1",
            encodedProjectPath: "-Users-x-Code-app",
            projectName: "app",
            messages: [
                MessageRecord(
                    timestamp: date("2026-05-01T10:00:00Z"),
                    model: "claude-sonnet-4-6",
                    usage: TokenUsage(inputTokens: 1, outputTokens: 2, cacheReadTokens: 3, cacheWriteTokens: 4)
                ),
                MessageRecord(
                    timestamp: date("2026-05-01T10:05:00Z"),
                    model: "claude-opus-4-7",
                    usage: TokenUsage(inputTokens: 5, outputTokens: 6, cacheReadTokens: 7, cacheWriteTokens: 8)
                ),
            ]
        )
    }

    @Test("MessageRecord round-trip")
    func messageRoundTrip() throws {
        let msg = MessageRecord(
            timestamp: date("2026-05-01T10:00:00Z"),
            model: "claude-haiku-4-5-20251001",
            usage: TokenUsage(inputTokens: 1, outputTokens: 2, cacheReadTokens: 3, cacheWriteTokens: 4)
        )
        try roundTrip(msg)
    }

    @Test("SessionRecord round-trip")
    func sessionRoundTrip() throws {
        try roundTrip(sampleSession())
    }

    @Test("SessionRecord decodes golden JSON shape")
    func sessionGoldenDecode() throws {
        let golden = #"""
        {
          "sessionId": "sid-1",
          "encodedProjectPath": "-Users-x-Code-app",
          "projectName": "app",
          "messages": [
            {
              "timestamp": "2026-05-01T10:00:00Z",
              "model": "claude-sonnet-4-6",
              "usage": {"inputTokens":1,"outputTokens":2,"cacheReadTokens":3,"cacheWriteTokens":4}
            }
          ]
        }
        """#.data(using: .utf8)!
        let record = try iso8601Decoder().decode(SessionRecord.self, from: golden)
        #expect(record.sessionId == "sid-1")
        #expect(record.messages.count == 1)
        #expect(record.messages[0].model == "claude-sonnet-4-6")
        #expect(record.messages[0].usage.inputTokens == 1)
    }
}

// MARK: – ProjectUsage / WeeklyUsage

@Suite("Aggregate usage Codable")
struct AggregateUsageCodableTests {
    private func sampleProject() -> ProjectUsage {
        ProjectUsage(
            name: "app",
            encodedPath: "-Users-x-Code-app",
            sessions: [
                SessionRecord(
                    sessionId: "s1",
                    encodedProjectPath: "-Users-x-Code-app",
                    projectName: "app",
                    messages: [
                        MessageRecord(
                            timestamp: date("2026-05-01T10:00:00Z"),
                            model: "claude-sonnet-4-6",
                            usage: TokenUsage(inputTokens: 1, outputTokens: 2, cacheReadTokens: 0, cacheWriteTokens: 0)
                        ),
                    ]
                ),
            ],
            costUSD: 1.23
        )
    }

    @Test("ProjectUsage round-trip")
    func projectRoundTrip() throws {
        try roundTrip(sampleProject())
    }

    @Test("ProjectUsage.id equals encodedPath after decode")
    func projectIdMatchesEncodedPath() throws {
        let original = sampleProject()
        let data = try iso8601Encoder().encode(original)
        let decoded = try iso8601Decoder().decode(ProjectUsage.self, from: data)
        #expect(decoded.id == decoded.encodedPath)
    }

    @Test("WeeklyUsage round-trip")
    func weeklyRoundTrip() throws {
        let weekly = WeeklyUsage(
            windowStart: date("2026-05-01T00:00:00Z"),
            windowEnd: date("2026-05-08T00:00:00Z"),
            projectBreakdown: [sampleProject()],
            costUSD: 1.23
        )
        try roundTrip(weekly)
    }

    @Test("WeeklyUsage.empty round-trip")
    func emptyRoundTrip() throws {
        try roundTrip(WeeklyUsage.empty)
    }
}

// MARK: – WidgetSnapshot

@Suite("WidgetSnapshot Codable")
struct WidgetSnapshotCodableTests {
    @Test("round-trip with non-nil reset dates")
    func roundTripWithDates() throws {
        try roundTrip(WidgetSnapshot(
            updatedAt: date("2026-05-10T12:00:00Z"),
            sessionPercent: 0.42,
            weekPercent: 0.73,
            sessionResetsAt: date("2026-05-10T17:00:00Z"),
            weekResetsAt: date("2026-05-13T12:00:00Z"),
            currentProject: "app",
            weekCostUSD: 12.34,
            topProject: "app"
        ))
    }

    @Test("round-trip with nil reset dates")
    func roundTripWithNilDates() throws {
        try roundTrip(WidgetSnapshot(
            updatedAt: date("2026-05-10T12:00:00Z"),
            sessionPercent: 0,
            weekPercent: 0,
            sessionResetsAt: nil,
            weekResetsAt: nil,
            currentProject: "—",
            weekCostUSD: 0,
            topProject: "—"
        ))
    }
}

// MARK: – AppSettings

@Suite("AppSettings Codable")
struct AppSettingsCodableTests {
    @Test("default round-trip")
    func defaultRoundTrip() throws {
        try roundTrip(AppSettings.default)
    }

    @Test("apply(plan:) updates limits and round-trips")
    func applyPlanRoundTrip() throws {
        var s = AppSettings()
        s.apply(plan: .max20x)
        #expect(s.plan == .max20x)
        #expect(s.sessionTokenLimit == PlanLimits.max20x.sessionTokens)
        #expect(s.weeklyTokenLimit == PlanLimits.max20x.weeklyTokens)
        try roundTrip(s)
    }

    @Test("Currency raw values are stable", arguments: [
        (AppSettings.Currency.usd, "USD", "$"),
        (.eur, "EUR", "€"),
    ])
    func currencyValues(currency: AppSettings.Currency, raw: String, symbol: String) {
        #expect(currency.rawValue == raw)
        #expect(currency.symbol == symbol)
    }

    @Test("decodes golden settings JSON")
    func decodesGolden() throws {
        let golden = #"""
        {
          "subscriptionPriceUSD": 100.0,
          "currency": "EUR",
          "sessionTokenLimit": 250000,
          "weeklyTokenLimit": 1750000,
          "plan": "Max (5×)"
        }
        """#.data(using: .utf8)!
        let s = try iso8601Decoder().decode(AppSettings.self, from: golden)
        #expect(s.subscriptionPriceUSD == 100.0)
        #expect(s.currency == .eur)
        #expect(s.plan == .max5x)
    }
}

// MARK: – UsageAPIResponse / UsageWindow

@Suite("UsageAPIResponse Codable")
struct UsageAPIResponseCodableTests {
    @Test("decodes realistic snake_case payload")
    func decodesSnakeCase() throws {
        let payload = #"""
        {
          "five_hour": {"utilization": 42.5, "resets_at": "2026-05-10T17:00:00Z"},
          "seven_day": {"utilization": 73.0, "resets_at": "2026-05-17T12:00:00Z"}
        }
        """#.data(using: .utf8)!
        let response = try iso8601Decoder().decode(UsageAPIResponse.self, from: payload)
        #expect(response.fiveHour?.utilization == 42.5)
        #expect(response.sevenDay?.utilization == 73.0)
        #expect(response.fiveHour?.resetsAt != nil)
    }

    @Test("missing windows decode as nil")
    func missingWindowsDecodeAsNil() throws {
        let payload = Data("{}".utf8)
        let response = try iso8601Decoder().decode(UsageAPIResponse.self, from: payload)
        #expect(response.fiveHour == nil)
        #expect(response.sevenDay == nil)
    }

    @Test("UsageWindow.timeRemaining is zero when resetsAt is nil")
    func timeRemainingNil() {
        let window = UsageWindow(utilization: 50, resetsAt: nil)
        #expect(window.timeRemaining == 0)
    }

    @Test("UsageWindow.timeRemaining is zero for past reset")
    func timeRemainingPast() {
        let window = UsageWindow(utilization: 50, resetsAt: Date().addingTimeInterval(-3600))
        #expect(window.timeRemaining == 0)
    }

    @Test("UsageWindow.timeRemaining is positive for future reset")
    func timeRemainingFuture() {
        let window = UsageWindow(utilization: 50, resetsAt: Date().addingTimeInterval(3600))
        #expect(window.timeRemaining > 0)
    }

    @Test("UsageAPIResponse round-trip preserves wire keys")
    func responseRoundTripPreservesKeys() throws {
        let original = UsageAPIResponse(
            fiveHour: UsageWindow(utilization: 12.5, resetsAt: date("2026-05-10T17:00:00Z")),
            sevenDay: UsageWindow(utilization: 30, resetsAt: date("2026-05-17T12:00:00Z"))
        )
        let data = try iso8601Encoder().encode(original)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("five_hour"))
        #expect(json.contains("seven_day"))
        #expect(json.contains("resets_at"))
        let decoded = try iso8601Decoder().decode(UsageAPIResponse.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: – CachedAPIResponse

@Suite("CachedAPIResponse Codable")
struct CachedAPIResponseCodableTests {
    @Test("round-trip preserves response and fetchedAt")
    func roundTrip() throws {
        let original = CachedAPIResponse(
            response: UsageAPIResponse(
                fiveHour: UsageWindow(utilization: 1, resetsAt: nil),
                sevenDay: nil
            ),
            fetchedAt: date("2026-05-10T12:00:00Z")
        )
        let data = try iso8601Encoder().encode(original)
        let decoded = try iso8601Decoder().decode(CachedAPIResponse.self, from: data)
        #expect(decoded.response == original.response)
        #expect(decoded.fetchedAt == original.fetchedAt)
    }

    @Test("isStale=false within 1 hour, true past 1 hour")
    func staleness() {
        let fresh = CachedAPIResponse(
            response: UsageAPIResponse(fiveHour: nil, sevenDay: nil),
            fetchedAt: Date().addingTimeInterval(-60)
        )
        #expect(fresh.isStale == false)

        let stale = CachedAPIResponse(
            response: UsageAPIResponse(fiveHour: nil, sevenDay: nil),
            fetchedAt: Date().addingTimeInterval(-3700)
        )
        #expect(stale.isStale == true)
    }
}
