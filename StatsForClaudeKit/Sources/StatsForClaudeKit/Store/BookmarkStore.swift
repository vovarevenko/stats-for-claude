import Foundation

public protocol BookmarkResolving: Sendable {
    var hasBookmark: Bool { get }
    func resolve() throws -> URL?
    func save(url: URL) throws
}

/// Persists and resolves a security-scoped bookmark for the ~/.claude directory.
///
/// `@unchecked Sendable` is sound: `UserDefaults` is documented as thread-safe
/// and the bookmark key is immutable.
public final class BookmarkStore: BookmarkResolving, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "claudeDirectoryBookmark"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasBookmark: Bool {
        defaults.data(forKey: key) != nil
    }

    /// Creates and persists a security-scoped bookmark for `url`.
    public func save(url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: key)
    }

    /// Resolves the stored bookmark to a URL. Returns `nil` if no bookmark is stored.
    /// The caller is responsible for calling `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`.
    public func resolve() throws -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale { try? save(url: url) }
        return url
    }
}
