import Foundation

public protocol UsageFetching: Sendable {
    func fetchUsage(token: String) async throws -> UsageAPIResponse
}

extension UsageAPIClient: UsageFetching {}

public struct UsageAPIClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchUsage(token: String) async throws -> UsageAPIResponse {
        var req = URLRequest(url: Self.endpoint)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)",          forHTTPHeaderField: "Authorization")
        req.setValue("application/json",          forHTTPHeaderField: "Accept")
        req.setValue("application/json",          forHTTPHeaderField: "Content-Type")
        req.setValue("claude-code/2.0.32",        forHTTPHeaderField: "User-Agent")
        req.setValue("oauth-2025-04-20",          forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard http.statusCode == 200 else { throw APIError.httpError(http.statusCode) }

        do {
            return try JSONDecoder.iso8601WithOptionalMillis().decode(UsageAPIResponse.self, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }
}
