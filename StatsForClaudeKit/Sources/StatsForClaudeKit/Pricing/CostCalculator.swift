import Foundation

public struct CostCalculator: Sendable {
    public init() {}

    public func costUSD(for message: MessageRecord) -> Double {
        let p = Pricing.pricing(for: message.model)
        let m = 1_000_000.0
        return Double(message.usage.inputTokens)    / m * p.inputPerMillion
             + Double(message.usage.outputTokens)   / m * p.outputPerMillion
             + Double(message.usage.cacheWriteTokens) / m * p.cacheWritePerMillion
             + Double(message.usage.cacheReadTokens)  / m * p.cacheReadPerMillion
    }

    public func costUSD(for session: SessionRecord) -> Double {
        session.messages.reduce(0) { $0 + costUSD(for: $1) }
    }
}
