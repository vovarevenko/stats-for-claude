import Foundation

public struct UsageAPIResponse: Codable, Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

public struct UsageWindow: Codable, Equatable, Sendable {
    /// Utilization in percent, 0–100.
    public let utilization: Double
    public let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    public var timeRemaining: TimeInterval {
        resetsAt.map { max(0, $0.timeIntervalSinceNow) } ?? 0
    }
}

public enum APIError: LocalizedError, Sendable {
    case tokenNotFound
    case invalidResponse
    case httpError(Int)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .tokenNotFound: "Claude Code credentials not found in Keychain"
        case .invalidResponse: "Invalid API response"
        case let .httpError(c): "API error (HTTP \(c))"
        case let .decodingFailed(m): "Decoding failed: \(m)"
        }
    }
}
