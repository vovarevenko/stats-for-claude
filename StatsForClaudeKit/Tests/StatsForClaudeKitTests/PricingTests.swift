import Foundation
import Testing
@testable import StatsForClaudeKit

@Suite("Pricing")
struct PricingTests {

    @Test("opus rate sheet")
    func opusRates() {
        let p = Pricing.opus
        #expect(p.inputPerMillion == 15.00)
        #expect(p.outputPerMillion == 75.00)
        #expect(p.cacheWritePerMillion == 18.75)
        #expect(p.cacheReadPerMillion == 1.50)
    }

    @Test("sonnet rate sheet")
    func sonnetRates() {
        let p = Pricing.sonnet
        #expect(p.inputPerMillion == 3.00)
        #expect(p.outputPerMillion == 15.00)
        #expect(p.cacheWritePerMillion == 3.75)
        #expect(p.cacheReadPerMillion == 0.30)
    }

    @Test("haiku rate sheet")
    func haikuRates() {
        let p = Pricing.haiku
        #expect(p.inputPerMillion == 0.80)
        #expect(p.outputPerMillion == 4.00)
        #expect(p.cacheWritePerMillion == 1.00)
        #expect(p.cacheReadPerMillion == 0.08)
    }

    @Test("pricing(for:) routes to correct family", arguments: [
        ("claude-opus-4-7", 15.00),
        ("claude-3-opus-20240229", 15.00),
        ("claude-sonnet-4-6", 3.00),
        ("claude-3-5-sonnet-20241022", 3.00),
        ("claude-haiku-4-5-20251001", 0.80),
        ("claude-3-haiku-20240307", 0.80),
    ])
    func pricingForKnownModel(model: String, expectedInputPerM: Double) {
        #expect(Pricing.pricing(for: model).inputPerMillion == expectedInputPerM)
    }

    @Test("unknown model falls back to sonnet pricing")
    func unknownFallback() {
        let p = Pricing.pricing(for: "claude-mystery-model")
        #expect(p.inputPerMillion == Pricing.sonnet.inputPerMillion)
        #expect(p.outputPerMillion == Pricing.sonnet.outputPerMillion)
        #expect(p.cacheWritePerMillion == Pricing.sonnet.cacheWritePerMillion)
        #expect(p.cacheReadPerMillion == Pricing.sonnet.cacheReadPerMillion)
    }

    @Test("model family detection is case insensitive")
    func familyCaseInsensitive() {
        #expect(ModelFamily(modelString: "CLAUDE-SONNET-4") == .sonnet)
        #expect(ModelFamily(modelString: "Claude-Opus-4") == .opus)
        #expect(ModelFamily(modelString: "HAIKU") == .haiku)
    }

    @Test("empty string maps to unknown family")
    func emptyIsUnknown() {
        #expect(ModelFamily(modelString: "") == .unknown)
    }
}
