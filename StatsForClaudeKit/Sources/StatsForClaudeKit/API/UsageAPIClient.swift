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

        let decoder = JSONDecoder()
        // API returns ISO8601 with milliseconds: "2026-05-09T15:00:00.000Z"
        let withMillis: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        let plain: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
        decoder.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = withMillis.date(from: s) { return d }
            if let d = plain.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }

        do {
            return try decoder.decode(UsageAPIResponse.self, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }
}
