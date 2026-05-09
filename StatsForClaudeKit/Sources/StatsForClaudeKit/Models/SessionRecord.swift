import Foundation

public struct MessageRecord: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let model: String
    public let usage: TokenUsage

    public init(timestamp: Date, model: String, usage: TokenUsage) {
        self.timestamp = timestamp
        self.model = model
        self.usage = usage
    }
}

public struct SessionRecord: Codable, Equatable, Sendable {
    public let sessionId: String
    public let encodedProjectPath: String
    public let projectName: String
    public let messages: [MessageRecord]

    public init(
        sessionId: String,
        encodedProjectPath: String,
        projectName: String,
        messages: [MessageRecord]
    ) {
        self.sessionId = sessionId
        self.encodedProjectPath = encodedProjectPath
        self.projectName = projectName
        self.messages = messages
    }

    public var firstTimestamp: Date? { messages.map(\.timestamp).min() }
    public var lastTimestamp: Date? { messages.map(\.timestamp).max() }

    public var totalUsage: TokenUsage {
        messages.reduce(.zero) { $0 + $1.usage }
    }

    public var usageByModel: [String: TokenUsage] {
        Dictionary(grouping: messages, by: \.model)
            .mapValues { $0.reduce(.zero) { $0 + $1.usage } }
    }
}
