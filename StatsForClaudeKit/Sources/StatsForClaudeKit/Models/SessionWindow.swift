import Foundation

public struct SessionWindow: Codable, Equatable, Sendable {
    public let windowStart: Date
    public let windowEnd: Date
    public let usage: TokenUsage
    public let currentProjectName: String?
    public let limit: Int

    public init(
        windowStart: Date,
        windowEnd: Date,
        usage: TokenUsage,
        currentProjectName: String?,
        limit: Int
    ) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.usage = usage
        self.currentProjectName = currentProjectName
        self.limit = limit
    }

    /// Percentage based on output tokens only.
    /// Claude Code rate-limits on output tokens; cache_read tokens are 90×+ larger
    /// and would make the percentage meaningless if included.
    public var percentUsed: Double {
        guard limit > 0 else { return 0 }
        return min(1.0, Double(usage.outputTokens) / Double(limit))
    }

    public var timeRemaining: TimeInterval {
        max(0, windowEnd.timeIntervalSinceNow)
    }

    public var isExpired: Bool { windowEnd < Date() }

    public static func empty(limit: Int) -> SessionWindow {
        let now = Date()
        return SessionWindow(
            windowStart: now,
            windowEnd: now.addingTimeInterval(5 * 3600),
            usage: .zero,
            currentProjectName: nil,
            limit: limit
        )
    }
}
