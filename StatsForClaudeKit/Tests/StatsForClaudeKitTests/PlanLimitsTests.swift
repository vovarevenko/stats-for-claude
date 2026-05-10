import Foundation
import Testing
@testable import StatsForClaudeKit

@Suite("PlanLimits")
struct PlanLimitsTests {
    @Test("Pro plan limits")
    func proLimits() {
        #expect(PlanLimits.pro.sessionTokens == 50000)
        #expect(PlanLimits.pro.weeklyTokens == 350_000)
    }

    @Test("Max5x plan limits")
    func max5xLimits() {
        #expect(PlanLimits.max5x.sessionTokens == 250_000)
        #expect(PlanLimits.max5x.weeklyTokens == 1_750_000)
    }

    @Test("Max20x plan limits")
    func max20xLimits() {
        #expect(PlanLimits.max20x.sessionTokens == 1_000_000)
        #expect(PlanLimits.max20x.weeklyTokens == 7_000_000)
    }

    @Test("Plan.limits maps to the corresponding PlanLimits", arguments: [
        (Plan.pro, PlanLimits.pro),
        (.max5x, .max5x),
        (.max20x, .max20x),
    ])
    func planMapping(plan: Plan, expected: PlanLimits) {
        #expect(plan.limits == expected)
    }

    @Test("Plan.allCases covers exactly three plans")
    func allCases() {
        #expect(Plan.allCases.count == 3)
        #expect(Set(Plan.allCases) == [.pro, .max5x, .max20x])
    }

    @Test("Plan raw values are stable user-facing labels", arguments: [
        (Plan.pro, "Pro"),
        (.max5x, "Max (5×)"),
        (.max20x, "Max (20×)"),
    ])
    func planRawValues(plan: Plan, raw: String) {
        #expect(plan.rawValue == raw)
    }

    @Test("PlanLimits Codable round-trip")
    func codableRoundTrip() throws {
        let original = PlanLimits.max5x
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlanLimits.self, from: data)
        #expect(decoded == original)
    }
}
