import Foundation

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let updatedAt: Date
    public let sessionPercent: Double   // 0.0–1.0
    public let weekPercent: Double      // 0.0–1.0
    public let sessionResetsAt: Date?
    public let weekResetsAt: Date?
    public let currentProject: String
    public let weekCostUSD: Double
    public let topProject: String

    public init(
        updatedAt: Date,
        sessionPercent: Double,
        weekPercent: Double,
        sessionResetsAt: Date?,
        weekResetsAt: Date?,
        currentProject: String,
        weekCostUSD: Double,
        topProject: String
    ) {
        self.updatedAt = updatedAt
        self.sessionPercent = sessionPercent
        self.weekPercent = weekPercent
        self.sessionResetsAt = sessionResetsAt
        self.weekResetsAt = weekResetsAt
        self.currentProject = currentProject
        self.weekCostUSD = weekCostUSD
        self.topProject = topProject
    }
}
