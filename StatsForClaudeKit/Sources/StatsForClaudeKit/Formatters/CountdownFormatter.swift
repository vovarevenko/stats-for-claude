import Foundation

public enum CountdownFormatter {
    /// Formats a time interval as "2h 15m" or "45m" or "—" when zero/negative.
    public static func format(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "—" }
        let total = Int(interval)
        let days    = total / 86400
        let hours   = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
}
