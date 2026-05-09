import Foundation

public enum TokenFormatter {
    public static func format(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            return String(format: "%.2fM", Double(count) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(count) / 1_000)
        default:
            return "\(count)"
        }
    }

    /// e.g. "1.2M / 2.5M (48%)"
    public static func formatWithLimit(_ count: Int, limit: Int) -> String {
        guard limit > 0 else { return format(count) }
        let pct = Int(Double(count) / Double(limit) * 100)
        return "\(format(count)) / \(format(limit)) (\(pct)%)"
    }
}
