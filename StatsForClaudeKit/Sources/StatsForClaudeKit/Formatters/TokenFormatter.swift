import Foundation

public enum TokenFormatter {
    public static func format(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            String(format: "%.2fM", Double(count) / 1_000_000)
        case 1000...:
            String(format: "%.1fK", Double(count) / 1000)
        default:
            "\(count)"
        }
    }
}
