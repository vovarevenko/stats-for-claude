import Foundation

public struct TokenUsage: Codable, Equatable, Hashable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int

    public static let zero = TokenUsage(
        inputTokens: 0, outputTokens: 0,
        cacheReadTokens: 0, cacheWriteTokens: 0
    )

    public init(inputTokens: Int, outputTokens: Int, cacheReadTokens: Int, cacheWriteTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }

    public var total: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            cacheWriteTokens: lhs.cacheWriteTokens + rhs.cacheWriteTokens
        )
    }
}
