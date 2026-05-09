import Foundation

public struct WeeklyUsage: Codable, Equatable, Sendable {
    public let windowStart: Date
    public let windowEnd: Date
    public let projectBreakdown: [ProjectUsage]
    public let costUSD: Double

    public init(windowStart: Date, windowEnd: Date, projectBreakdown: [ProjectUsage], costUSD: Double) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.projectBreakdown = projectBreakdown
        self.costUSD = costUSD
    }

    public var totalUsage: TokenUsage {
        projectBreakdown.reduce(.zero) { $0 + $1.totalUsage }
    }

    public static let empty = WeeklyUsage(
        windowStart: .distantPast, windowEnd: .distantPast,
        projectBreakdown: [], costUSD: 0
    )
}
