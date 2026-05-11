import Foundation

public protocol UsageFetching: Sendable {
    func fetchUsage(token: String) async throws -> UsageAPIResponse
}

extension UsageAPIClient: UsageFetching {}

public struct UsageAPIClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let userAgent = "stats-for-claude/1.0"
    public static let oauthBetaHeader = "oauth-2025-04-20"
    public static let requestTimeout: TimeInterval = 10

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchUsage(token: String) async throws -> UsageAPIResponse {
        var req = URLRequest(url: Self.endpoint)
        req.timeoutInterval = Self.requestTimeout
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(Self.oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 429 {
            throw APIError.rateLimited(retryAfter: parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")))
        }
        guard http.statusCode == 200 else { throw APIError.httpError(http.statusCode) }

        do {
            return try JSONDecoder.iso8601WithOptionalMillis().decode(UsageAPIResponse.self, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }
}
