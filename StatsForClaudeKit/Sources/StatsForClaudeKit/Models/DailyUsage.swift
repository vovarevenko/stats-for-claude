import Foundation

public struct DailyUsage: Identifiable, Codable, Equatable, Sendable {
    public let date: Date
    public let totalTokens: Int
    public let costUSD: Double

    public var id: Date { date }

    public init(date: Date, totalTokens: Int, costUSD: Double) {
        self.date = date
        self.totalTokens = totalTokens
        self.costUSD = costUSD
    }
}
