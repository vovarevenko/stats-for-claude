import Foundation

public protocol TokenRefreshing: Sendable {
    /// Exchanges a refresh token for a fresh access token. The returned
    /// credentials may also include a rotated `refreshToken`.
    func refresh(using refreshToken: String) async throws -> ClaudeCredentials
}

extension ClaudeOAuthClient: TokenRefreshing {}

/// Talks to Claude Code's OAuth token endpoint to mint a fresh access token
/// from a refresh token. Lets us avoid re-reading `Claude Code-credentials`
/// from the system Keychain (which is what causes the recurring ACL
/// prompt — the CLI rotates that item and the ACL resets with it).
public struct ClaudeOAuthClient: Sendable {
    public static let endpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    /// Public client ID baked into Claude Code CLI's PKCE OAuth flow.
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let userAgent = "stats-for-claude/1.0"
    public static let requestTimeout: TimeInterval = 10

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func refresh(using refreshToken: String) async throws -> ClaudeCredentials {
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = Self.requestTimeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 429 {
            throw APIError.rateLimited(retryAfter: parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")))
        }
        guard http.statusCode == 200 else { throw APIError.httpError(http.statusCode) }

        let decoded: TokenResponse
        do {
            decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }

        let expiresAt = decoded.expires_in.map { Date(timeIntervalSinceNow: TimeInterval($0)) }
        return ClaudeCredentials(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? refreshToken,
            expiresAt: expiresAt
        )
    }

    private struct TokenResponse: Decodable {
        // swiftlint:disable identifier_name
        let access_token: String
        let refresh_token: String?
        let expires_in: Int?
        // swiftlint:enable identifier_name
    }
}
