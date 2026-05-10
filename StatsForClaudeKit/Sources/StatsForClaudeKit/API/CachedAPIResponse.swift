import Foundation

/// Wraps UsageAPIResponse with a fetch timestamp so the UI can show staleness.
public struct CachedAPIResponse: Codable, Sendable {
    public let response: UsageAPIResponse
    public let fetchedAt: Date

    public init(response: UsageAPIResponse, fetchedAt: Date = .now) {
        self.response = response
        self.fetchedAt = fetchedAt
    }

    /// Cache entries older than this are treated as too stale to display
    /// without an "outdated" indicator. Drives `isStale` and the warning icon
    /// in the menu bar popover.
    public static let staleAfter: TimeInterval = 3600

    /// Time since last successful API fetch.
    public var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }

    public var isStale: Bool { age > Self.staleAfter }
}
