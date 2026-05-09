import Foundation

/// Wraps UsageAPIResponse with a fetch timestamp so the UI can show staleness.
public struct CachedAPIResponse: Codable, Sendable {
    public let response: UsageAPIResponse
    public let fetchedAt: Date

    public init(response: UsageAPIResponse, fetchedAt: Date = .now) {
        self.response = response
        self.fetchedAt = fetchedAt
    }

    /// Time since last successful API fetch.
    public var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }

    public var isStale: Bool { age > 3600 }   // older than 1 hour = stale
}
