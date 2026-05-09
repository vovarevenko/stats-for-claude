import Foundation

public struct PlanLimits: Codable, Equatable, Sendable {
    public let sessionTokens: Int
    public let weeklyTokens: Int

    public init(sessionTokens: Int, weeklyTokens: Int) {
        self.sessionTokens = sessionTokens
        self.weeklyTokens = weeklyTokens
    }

    // Limits are measured in OUTPUT TOKENS ONLY (cache_read tokens are ~90× larger
    // and are excluded — they don't count toward Claude Code rate limits).
    // Values are based on community-observed behaviour; override in Settings.
    public static let pro = PlanLimits(
        sessionTokens: 50_000,
        weeklyTokens: 350_000
    )

    public static let max5x = PlanLimits(
        sessionTokens: 250_000,
        weeklyTokens: 1_750_000
    )

    public static let max20x = PlanLimits(
        sessionTokens: 1_000_000,
        weeklyTokens: 7_000_000
    )
}

public enum Plan: String, CaseIterable, Codable, Sendable {
    case pro   = "Pro"
    case max5x = "Max (5×)"
    case max20x = "Max (20×)"

    public var limits: PlanLimits {
        switch self {
        case .pro:    return .pro
        case .max5x:  return .max5x
        case .max20x: return .max20x
        }
    }
}
