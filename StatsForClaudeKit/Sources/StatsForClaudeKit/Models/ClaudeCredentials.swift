import Foundation

/// OAuth credentials issued to Claude Code. We mirror Claude Code's Keychain
/// payload so we can refresh tokens ourselves and avoid re-reading the CLI's
/// Keychain item on every access-token expiry (each re-read risks an ACL
/// prompt because the CLI rotates that item and resets its ACL).
public struct ClaudeCredentials: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    /// Absolute moment when `accessToken` stops being valid. `nil` when the
    /// upstream payload omitted `expiresAt`.
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// True when the access token is expired or will expire within `leeway`.
    /// Default leeway of 5 min covers clock skew + the time it takes us to
    /// run a refresh round-trip before the next request goes out.
    public func isExpiringSoon(now: Date = .now, leeway: TimeInterval = 300) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= leeway
    }
}
