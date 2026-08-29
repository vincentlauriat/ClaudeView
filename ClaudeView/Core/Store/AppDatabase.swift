import Foundation
import GRDB

/// Owns the SQLite database (schema, migrations, settings helpers).
final class AppDatabase {
    let dbQueue: DatabaseQueue

    /// Production database in Application Support.
    static func makeDefault() throws -> AppDatabase {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("ClaudeView", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try AppDatabase(path: dir.appendingPathComponent("claudeview.sqlite").path)
    }

    /// In-memory database (tests).
    static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(queue: DatabaseQueue())
    }

    convenience init(path: String) throws {
        try self.init(queue: DatabaseQueue(path: path))
    }

    private init(queue: DatabaseQueue) throws {
        self.dbQueue = queue
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "project") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("dirName", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("cwd", .text)
            }
            try db.create(table: "session") { t in
                t.primaryKey("id", .text)
                t.belongsTo("project", onDelete: .cascade).notNull()
                t.column("title", .text)
                t.column("filePath", .text).notNull()
                t.column("firstTs", .datetime)
                t.column("lastTs", .datetime)
                t.column("messageCount", .integer).notNull().defaults(to: 0)
                t.column("inputTokens", .integer).notNull().defaults(to: 0)
                t.column("outputTokens", .integer).notNull().defaults(to: 0)
                t.column("cacheReadTokens", .integer).notNull().defaults(to: 0)
                t.column("cacheCreationTokens", .integer).notNull().defaults(to: 0)
                t.column("model", .text)
                t.column("gitBranch", .text)
                t.column("cwd", .text)
                t.column("malformedLines", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "message") { t in
                t.primaryKey("uuid", .text)
                t.column("sessionId", .text).notNull().indexed()
                    .references("session", onDelete: .cascade)
                t.column("projectId", .integer).notNull().indexed()
                t.column("ts", .datetime).notNull().indexed()
                t.column("kind", .text).notNull()
                t.column("role", .text).notNull()
                t.column("model", .text)
                t.column("text", .text).notNull()
                t.column("toolNames", .text).notNull().defaults(to: "")
                t.column("inputTokens", .integer).notNull().defaults(to: 0)
                t.column("outputTokens", .integer).notNull().defaults(to: 0)
                t.column("cacheReadTokens", .integer).notNull().defaults(to: 0)
                t.column("cacheCreationTokens", .integer).notNull().defaults(to: 0)
                t.column("isSidechain", .boolean).notNull().defaults(to: false)
                t.column("hasThinking", .boolean).notNull().defaults(to: false)
                t.column("isToolResult", .boolean).notNull().defaults(to: false)
                t.column("byteOffset", .integer).notNull()
                t.column("byteLength", .integer).notNull()
            }
            try db.create(virtualTable: "message_fts", using: FTS5()) { t in
                t.column("text")
                t.column("uuid").notIndexed()
                t.column("sessionId").notIndexed()
                t.column("projectId").notIndexed()
            }
            try db.create(table: "fileState") { t in
                t.primaryKey("path", .text)
                t.column("byteOffset", .integer).notNull()
                t.column("size", .integer).notNull()
                t.column("mtime", .datetime).notNull()
                t.column("sessionId", .text).notNull()
            }
            try db.create(table: "modelPrice") { t in
                t.primaryKey("model", .text)
                t.column("inputPerMTok", .double).notNull()
                t.column("outputPerMTok", .double).notNull()
                t.column("cacheReadPerMTok", .double).notNull()
                t.column("cacheWritePerMTok", .double).notNull()
                t.column("isCustom", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "appSetting") { t in
                t.primaryKey("key", .text)
                t.column("valueJSON", .text).notNull()
            }
        }
        return migrator
    }

    // MARK: - Settings helpers (JSON-codable values keyed by string)

    func readSetting<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let row = try? dbQueue.read({ try AppSettingRow.fetchOne($0, key: key) }),
              let data = row.valueJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func writeSetting<T: Encodable>(_ key: String, value: T) {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        try? dbQueue.write { db in
            try AppSettingRow(key: key, valueJSON: json).save(db)
        }
    }

    /// Drops all indexed content (projects, sessions, messages, cursors) but
    /// keeps prices and settings. Used by "full resync".
    func clearIndex() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM message_fts")
            _ = try MessageRow.deleteAll(db)
            _ = try SessionRow.deleteAll(db)
            _ = try ProjectRow.deleteAll(db)
            _ = try FileStateRow.deleteAll(db)
        }
    }
}
