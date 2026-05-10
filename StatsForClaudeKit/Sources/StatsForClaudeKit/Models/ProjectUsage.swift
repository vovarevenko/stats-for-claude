import Foundation

public struct ProjectUsage: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let encodedPath: String
    public let sessions: [SessionRecord]
    public let costUSD: Double

    public init(name: String, encodedPath: String, sessions: [SessionRecord], costUSD: Double) {
        id = encodedPath
        self.name = name
        self.encodedPath = encodedPath
        self.sessions = sessions
        self.costUSD = costUSD
    }

    public var totalUsage: TokenUsage {
        sessions.reduce(.zero) { $0 + $1.totalUsage }
    }
}
