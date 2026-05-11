import Foundation

public struct UsageAPIResponse: Codable, Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

public struct UsageWindow: Codable, Equatable, Sendable {
    /// Utilization in percent, 0–100.
    public let utilization: Double
    public let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    public var timeRemaining: TimeInterval {
        resetsAt.map { max(0, $0.timeIntervalSinceNow) } ?? 0
    }
}

public enum APIError: LocalizedError, Sendable {
    case tokenNotFound
    case invalidResponse
    case httpError(Int)
    /// HTTP 429. `retryAfter` is the upstream `Retry-After` parsed as seconds
    /// (`nil` when the header is absent or unparseable). Anthropic enforces a
    /// single rate-limit bucket across `/api/oauth/usage` and `/v1/oauth/token`,
    /// so callers must back off **both** endpoints on this error — otherwise
    /// the next OAuth refresh also 429s and we end up reading the CLI
    /// Keychain item (which is exactly what triggers the ACL prompt).
    case rateLimited(retryAfter: TimeInterval?)
    case decodingFailed(String)
    case keychainWriteFailed(OSStatus)
    /// Refused to write `Claude Code-credentials` because we don't have the
    /// CLI's original envelope to splice fresh tokens into. Writing the bare
    /// OAuth fields would clobber CLI-only keys (`scopes`, `subscriptionType`)
    /// and break the CLI's parsing — logging the user out silently.
    case missingEnvelope

    public var errorDescription: String? {
        switch self {
        case .tokenNotFound: "Claude Code credentials not found in Keychain"
        case .invalidResponse: "Invalid API response"
        case let .httpError(c): "API error (HTTP \(c))"
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "Rate limited (retry in \(Int(retryAfter))s)"
            } else {
                "Rate limited"
            }
        case let .decodingFailed(m): "Decoding failed: \(m)"
        case let .keychainWriteFailed(status): "Keychain write failed (OSStatus \(status))"
        case .missingEnvelope: "Missing CLI keychain envelope; refusing to overwrite with partial payload"
        }
    }
}

/// Decodes an HTTP `Retry-After` header. Supports the two formats permitted
/// by RFC 7231 §7.1.3: delta-seconds (`"120"`) and HTTP-date
/// (`"Wed, 21 Oct 2026 07:28:00 GMT"`). Returns `nil` when neither parses.
public func parseRetryAfter(_ header: String?, now: Date = .now) -> TimeInterval? {
    guard let header, !header.isEmpty else { return nil }
    if let seconds = TimeInterval(header) {
        return max(0, seconds)
    }
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(identifier: "GMT")
    fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    if let date = fmt.date(from: header) {
        return max(0, date.timeIntervalSince(now))
    }
    return nil
}
