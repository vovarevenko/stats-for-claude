import Foundation

public struct JSONLParser: Sendable {
    public init() {}

    // MARK: – Public API

    public func parseSession(at url: URL, encodedProjectPath: String) throws -> SessionRecord? {
        let data = try Data(contentsOf: url)
        return parseSession(from: data, encodedProjectPath: encodedProjectPath, fallbackSessionId: url.deletingPathExtension().lastPathComponent)
    }

    public func parseAllSessions(in claudeDir: URL) throws -> [SessionRecord] {
        let projectsDir = claudeDir.appendingPathComponent("projects")
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var records: [SessionRecord] = []

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // The project dir is the parent of the .jsonl file
            let projectDir = fileURL.deletingLastPathComponent()
            // Only go one level deep: projects/<encoded>/<session>.jsonl
            guard projectDir.deletingLastPathComponent().lastPathComponent == "projects" else { continue }

            let encodedPath = projectDir.lastPathComponent
            if let record = try? parseSession(at: fileURL, encodedProjectPath: encodedPath) {
                records.append(record)
            }
        }

        return records
    }

    // MARK: – Internal parsing

    func parseSession(from data: Data, encodedProjectPath: String, fallbackSessionId: String) -> SessionRecord? {
        let decoder = JSONDecoder.iso8601WithOptionalMillis()
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)

        var messages: [MessageRecord] = []
        var sessionId: String?

        for line in lines {
            guard let entry = try? decoder.decode(RawEntry.self, from: Data(line)) else { continue }
            guard
                let msg = entry.message,
                msg.role == "assistant",
                let model = msg.model,
                let timestamp = entry.timestamp,
                let rawUsage = msg.usage
            else { continue }

            if sessionId == nil { sessionId = entry.sessionId }

            let usage = TokenUsage(
                inputTokens: rawUsage.inputTokens ?? 0,
                outputTokens: rawUsage.outputTokens ?? 0,
                cacheReadTokens: rawUsage.cacheReadInputTokens ?? 0,
                cacheWriteTokens: rawUsage.cacheCreationInputTokens ?? 0
            )
            messages.append(MessageRecord(timestamp: timestamp, model: model, usage: usage))
        }

        guard !messages.isEmpty else { return nil }

        let sid = sessionId ?? fallbackSessionId
        let projectName: String
        if encodedProjectPath.isEmpty {
            projectName = "Unknown"
        } else {
            projectName = ProjectPathDecoder.resolvedProjectName(from: encodedProjectPath)
        }

        return SessionRecord(
            sessionId: sid,
            encodedProjectPath: encodedProjectPath,
            projectName: projectName,
            messages: messages
        )
    }

}

// MARK: – Private decoding types

private struct RawEntry: Decodable {
    let timestamp: Date?
    let sessionId: String?
    let message: RawMessage?

    struct RawMessage: Decodable {
        let role: String?
        let model: String?
        let usage: RawUsage?
    }

    struct RawUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens              = "input_tokens"
            case outputTokens             = "output_tokens"
            case cacheReadInputTokens     = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }
    }
}
