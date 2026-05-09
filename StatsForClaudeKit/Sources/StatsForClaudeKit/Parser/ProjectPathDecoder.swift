import Foundation

public enum ProjectPathDecoder {
    /// Decodes a Claude Code encoded directory name to an absolute path.
    /// Claude Code encodes "/" as "-", so "-Users-name-Code-my-project" → "/Users/name/Code/my-project".
    /// NOTE: this is ambiguous when directory names contain hyphens.
    /// Use `resolvedProjectName(from:)` to verify against the actual filesystem.
    public static func decodedPath(from encoded: String) -> String {
        let stripped = encoded.hasPrefix("-") ? String(encoded.dropFirst()) : encoded
        return "/" + stripped.replacingOccurrences(of: "-", with: "/")
    }

    /// Fast project name without filesystem access. May be wrong for hyphenated dirs.
    public static func projectName(from encoded: String) -> String {
        guard !encoded.isEmpty else { return "Unknown" }
        let decoded = decodedPath(from: encoded)
        let name = URL(fileURLWithPath: decoded).lastPathComponent
        return name.isEmpty ? encoded : name
    }

    /// Resolves the actual path greedily against the filesystem.
    /// Handles directory names that contain hyphens.
    public static func resolvedProjectName(from encoded: String) -> String {
        URL(fileURLWithPath: resolvedPath(from: encoded)).lastPathComponent
    }

    /// Full filesystem-resolved path for a Claude Code encoded directory name.
    /// Falls back to a naive `/`-decoding if filesystem lookups can't disambiguate
    /// hyphenated folder names.
    public static func resolvedPath(from encoded: String) -> String {
        guard encoded.hasPrefix("-") else { return encoded }
        let fm = FileManager.default

        // Split: "-Users-vovarevenko-Code-my-project" → ["", "Users", "vovarevenko", "Code", "my", "project"]
        let parts = encoded.components(separatedBy: "-")
        guard parts.count > 1 else { return encoded }

        let pathParts = Array(parts.dropFirst()) // drop leading ""
        var resolvedPath = "/"
        var i = 0

        while i < pathParts.count {
            var found = false
            let lookAhead = min(i + 8, pathParts.count - 1)
            // Try longest match first to handle hyphenated names
            for j in stride(from: lookAhead, through: i, by: -1) {
                let segment = pathParts[i...j].joined(separator: "-")
                let candidate = (resolvedPath as NSString).appendingPathComponent(segment)
                if fm.fileExists(atPath: candidate) {
                    resolvedPath = candidate
                    i = j + 1
                    found = true
                    break
                }
            }
            if !found {
                let remaining = pathParts[i...].joined(separator: "/")
                resolvedPath = (resolvedPath as NSString).appendingPathComponent(remaining)
                break
            }
        }

        return resolvedPath
    }

    /// Given a list of absolute paths, returns each path's shortest unique suffix anchored
    /// to a `/` boundary. Useful for de-cluttering tables where most paths share a long
    /// common prefix like `/Users/<name>/Code/`.
    ///
    /// Example: `["/Users/x/Code/foo/bar", "/Users/x/Docs/baz"]` →
    /// `["Code/foo/bar", "Docs/baz"]`.
    ///
    /// With a single path or no shared prefix at a `/` boundary, returns the last path
    /// component for that path so it stays readable.
    public static func uniqueSuffixes(of paths: [String]) -> [String: String] {
        guard !paths.isEmpty else { return [:] }
        guard paths.count > 1 else {
            let only = paths[0]
            return [only: URL(fileURLWithPath: only).lastPathComponent]
        }

        // Common prefix length (in Unicode scalars).
        let arrays = paths.map { Array($0.unicodeScalars) }
        var commonLen = arrays[0].count
        for arr in arrays.dropFirst() {
            let limit = min(commonLen, arr.count)
            var i = 0
            while i < limit && arrays[0][i] == arr[i] { i += 1 }
            commonLen = i
            if commonLen == 0 { break }
        }

        // Trim back to last `/` to avoid splitting in the middle of a folder name.
        var trim = commonLen
        let slash = Unicode.Scalar(UInt8(ascii: "/"))
        while trim > 0 && arrays[0][trim - 1] != slash { trim -= 1 }

        var result: [String: String] = [:]
        for (path, scalars) in zip(paths, arrays) {
            let suffix = String(String.UnicodeScalarView(scalars.dropFirst(trim)))
            result[path] = suffix.isEmpty
                ? URL(fileURLWithPath: path).lastPathComponent
                : suffix
        }
        return result
    }
}
