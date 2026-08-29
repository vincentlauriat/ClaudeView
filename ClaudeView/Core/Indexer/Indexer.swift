import Foundation
import GRDB

/// One ingested message, re-emitted for the Live view.
struct LiveEvent: Identifiable {
    let id: String            // message uuid
    let message: ParsedMessage
    let projectName: String
    let filePath: String
    let byteOffset: Int64
    let byteLength: Int64
}

/// Incremental JSONL → SQLite ingestion. One instance, called from a
/// background queue; byte-offset cursors in `fileState` make every call cheap.
final class Indexer {
    let database: AppDatabase
    let rootURL: URL

    /// Subscribers receive every message ingested after initial scan completes.
    var onLiveEvent: ((LiveEvent) -> Void)?
    private(set) var initialScanDone = false

    init(database: AppDatabase, rootURL: URL) {
        self.database = database
        self.rootURL = rootURL
    }

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    // MARK: - Scanning

    /// Full recursive scan of the projects directory (session files live at
    /// `<project>/<id>.jsonl` and `<project>/<id>/subagents/<agent>.jsonl`);
    /// ingests every changed file. A file that fails to ingest is skipped —
    /// one bad file must never abort the scan. Returns the number of files
    /// that had new content.
    @discardableResult
    func syncAll() throws -> Int {
        var changed = 0
        let enumerator = FileManager.default.enumerator(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            do {
                if try ingest(fileURL: url) > 0 { changed += 1 }
            } catch {
                NSLog("ClaudeView: skipping \(url.lastPathComponent): \(error)")
            }
        }
        initialScanDone = true
        return changed
    }

    // MARK: - Per-file ingestion

    /// Ingests new lines of one session file. Returns the number of new messages.
    @discardableResult
    func ingest(fileURL rawURL: URL) throws -> Int {
        // Canonical path: /var vs /private/var (or other symlinks) must not
        // produce two distinct fileState cursors for the same file.
        let fileURL = rawURL.resolvingSymlinksInPath()
        let path = fileURL.path
        let sessionId = fileURL.deletingPathExtension().lastPathComponent
        // Project = first path component under the root (a subagent transcript
        // nested in <project>/<session>/subagents/ belongs to <project>).
        let root = rootURL.resolvingSymlinksInPath()
        let relative = path.hasPrefix(root.path + "/")
            ? String(path.dropFirst(root.path.count + 1))
            : fileURL.deletingLastPathComponent().lastPathComponent
        let dirName = relative.components(separatedBy: "/").first ?? relative

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? Int64) ?? 0
        let mtime = (attrs[.modificationDate] as? Date) ?? Date()

        var state = try database.dbQueue.read { try FileStateRow.fetchOne($0, key: path) }

        if let s = state, s.size == size, s.byteOffset >= size {
            return 0 // nothing new
        }
        // Truncated or rewritten file: drop this session's rows and restart.
        if let s = state, size < s.byteOffset {
            try database.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM message_fts WHERE sessionId = ?", arguments: [sessionId])
                _ = try MessageRow.filter(Column("sessionId") == sessionId).deleteAll(db)
                _ = try SessionRow.filter(key: sessionId).deleteAll(db)
            }
            state = nil
        }

        let startOffset = state?.byteOffset ?? 0
        guard let handle = FileHandle(forReadingAtPath: path) else { return 0 }
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(startOffset))
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return 0 }

        var newMessages: [(MessageRow, ParsedMessage)] = []
        var title: String?
        var malformed = 0
        var consumed: Int64 = 0
        let newline = UInt8(ascii: "\n")

        var lineStart = data.startIndex
        while lineStart < data.endIndex {
            guard let nl = data[lineStart...].firstIndex(of: newline) else {
                break // incomplete trailing line: leave it for the next pass
            }
            let lineData = data[lineStart..<nl]
            let offsetInFile = startOffset + Int64(lineStart - data.startIndex)
            let length = Int64(nl - lineStart)
            consumed = Int64(nl - data.startIndex) + 1

            switch JSONLParser.parse(lineData: Data(lineData)) {
            case .message(let m):
                let row = MessageRow(
                    uuid: m.uuid, sessionId: sessionId, projectId: 0,
                    ts: m.timestamp, kind: m.kind, role: m.role, model: m.model,
                    text: m.text, toolNames: m.toolNames.joined(separator: ","),
                    inputTokens: m.usage.input, outputTokens: m.usage.output,
                    cacheReadTokens: m.usage.cacheRead,
                    cacheCreationTokens: m.usage.cacheCreation,
                    isSidechain: m.isSidechain, hasThinking: m.hasThinking,
                    isToolResult: m.isToolResult,
                    byteOffset: offsetInFile, byteLength: length)
                newMessages.append((row, m))
            case .sessionTitle(_, let t):
                title = t
            case .malformed:
                malformed += 1
            case .skipped:
                break
            }
            lineStart = data.index(after: nl)
        }

        guard consumed > 0 else { return 0 }
        let newOffset = startOffset + consumed
        let projectName = Self.displayName(dirName: dirName, cwd: newMessages.last?.1.cwd)

        try database.dbQueue.write { db in
            // Project row (find or create, refresh name when cwd is known)
            var project = try ProjectRow.filter(Column("dirName") == dirName).fetchOne(db)
            if project == nil {
                var p = ProjectRow(id: nil, dirName: dirName, name: projectName,
                                   cwd: newMessages.last?.1.cwd)
                try p.insert(db)
                project = p
            } else if let cwd = newMessages.last?.1.cwd, project?.cwd != cwd {
                project?.cwd = cwd
                project?.name = projectName
                try project?.update(db)
            }
            guard let projectId = project?.id else { return }

            // Session row (create or aggregate)
            var session = try SessionRow.fetchOne(db, key: sessionId)
                ?? SessionRow(id: sessionId, projectId: projectId, title: nil,
                              filePath: path, firstTs: nil, lastTs: nil,
                              messageCount: 0, inputTokens: 0, outputTokens: 0,
                              cacheReadTokens: 0, cacheCreationTokens: 0,
                              model: nil, gitBranch: nil, cwd: nil, malformedLines: 0)
            if let title { session.title = title }
            session.malformedLines += malformed
            // The session row must exist before messages reference it (FK).
            try session.save(db)

            for (var row, m) in newMessages {
                row.projectId = projectId
                try row.save(db)
                if !m.text.isEmpty {
                    try db.execute(
                        sql: "INSERT INTO message_fts (text, uuid, sessionId, projectId) VALUES (?, ?, ?, ?)",
                        arguments: [m.text, m.uuid, sessionId, projectId])
                }
                session.messageCount += 1
                session.inputTokens += m.usage.input
                session.outputTokens += m.usage.output
                session.cacheReadTokens += m.usage.cacheRead
                session.cacheCreationTokens += m.usage.cacheCreation
                if session.firstTs == nil || m.timestamp < session.firstTs! { session.firstTs = m.timestamp }
                if session.lastTs == nil || m.timestamp > session.lastTs! { session.lastTs = m.timestamp }
                if let model = m.model { session.model = model }
                if let branch = m.gitBranch { session.gitBranch = branch }
                if let cwd = m.cwd { session.cwd = cwd }
            }
            try session.save(db)

            try FileStateRow(path: path, byteOffset: newOffset, size: size,
                             mtime: mtime, sessionId: sessionId).save(db)
        }

        if initialScanDone, let emit = onLiveEvent {
            for (row, m) in newMessages {
                emit(LiveEvent(id: m.uuid, message: m, projectName: projectName,
                               filePath: path, byteOffset: row.byteOffset,
                               byteLength: row.byteLength))
            }
        }
        return newMessages.count
    }

    /// Human-readable project name: basename of the real cwd when known,
    /// otherwise the tail of the encoded directory name.
    static func displayName(dirName: String, cwd: String?) -> String {
        if let cwd, !cwd.isEmpty {
            return (cwd as NSString).lastPathComponent
        }
        return dirName.components(separatedBy: "-").last ?? dirName
    }
}
