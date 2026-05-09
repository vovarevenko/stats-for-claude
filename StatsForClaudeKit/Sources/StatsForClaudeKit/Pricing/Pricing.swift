import Foundation

public struct ModelPricing: Sendable {
    public let inputPerMillion: Double
    public let outputPerMillion: Double
    public let cacheWritePerMillion: Double
    public let cacheReadPerMillion: Double
}

public enum ModelFamily: Sendable {
    case opus
    case sonnet
    case haiku
    case unknown

    public init(modelString: String) {
        let lower = modelString.lowercased()
        if lower.contains("opus") { self = .opus }
        else if lower.contains("sonnet") { self = .sonnet }
        else if lower.contains("haiku") { self = .haiku }
        else { self = .unknown }
    }
}

public enum Pricing {
    public static let opus = ModelPricing(
        inputPerMillion: 15.00,
        outputPerMillion: 75.00,
        cacheWritePerMillion: 18.75,
        cacheReadPerMillion: 1.50
    )

    public static let sonnet = ModelPricing(
        inputPerMillion: 3.00,
        outputPerMillion: 15.00,
        cacheWritePerMillion: 3.75,
        cacheReadPerMillion: 0.30
    )

    public static let haiku = ModelPricing(
        inputPerMillion: 0.80,
        outputPerMillion: 4.00,
        cacheWritePerMillion: 1.00,
        cacheReadPerMillion: 0.08
    )

    public static func pricing(for model: String) -> ModelPricing {
        switch ModelFamily(modelString: model) {
        case .opus:    return opus
        case .sonnet:  return sonnet
        case .haiku:   return haiku
        case .unknown: return sonnet
        }
    }
}
