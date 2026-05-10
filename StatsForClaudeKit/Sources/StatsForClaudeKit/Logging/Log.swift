import OSLog

/// Common subsystem identifier for every `os.Logger` in the app and its kit.
/// Keeping this in one place avoids drift between modules and makes Console.app
/// filtering predictable for users sending diagnostic captures.
public enum Log {
    public static let subsystem = "org.revenko.stats-for-claude"

    public static func make(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
