import Foundation

/// `ISO8601DateFormatter` instances are documented as thread-safe for parsing
/// once configured, so caching them as `nonisolated(unsafe)` static lets us
/// reuse them across actors without paying for per-decode allocation.
private enum ISO8601Formatters {
    nonisolated(unsafe) static let withMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

extension JSONDecoder {
    /// Decoder accepting both `2026-05-09T15:00:00.000Z` (Anthropic API) and
    /// `2026-05-09T15:00:00Z` (JSONL session files) date strings.
    public static func iso8601WithOptionalMillis() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601Formatters.withMillis.date(from: raw) { return date }
            if let date = ISO8601Formatters.plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised ISO-8601 date: \(raw)"
            )
        }
        return decoder
    }
}
