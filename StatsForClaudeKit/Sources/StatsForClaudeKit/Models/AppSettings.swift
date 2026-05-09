import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var subscriptionPriceUSD: Double
    public var currency: Currency
    public var sessionTokenLimit: Int
    public var weeklyTokenLimit: Int
    public var plan: Plan

    public enum Currency: String, CaseIterable, Codable, Sendable {
        case usd = "USD"
        case eur = "EUR"

        public var symbol: String { rawValue == "USD" ? "$" : "€" }
    }

    public init(
        subscriptionPriceUSD: Double = 20.0,
        currency: Currency = .usd,
        sessionTokenLimit: Int = PlanLimits.pro.sessionTokens,
        weeklyTokenLimit: Int = PlanLimits.pro.weeklyTokens,
        plan: Plan = .pro
    ) {
        self.subscriptionPriceUSD = subscriptionPriceUSD
        self.currency = currency
        self.sessionTokenLimit = sessionTokenLimit
        self.weeklyTokenLimit = weeklyTokenLimit
        self.plan = plan
    }

    public static let `default` = AppSettings()

    public mutating func apply(plan: Plan) {
        self.plan = plan
        sessionTokenLimit = plan.limits.sessionTokens
        weeklyTokenLimit = plan.limits.weeklyTokens
    }
}
