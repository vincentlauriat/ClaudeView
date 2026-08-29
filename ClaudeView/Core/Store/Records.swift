import Foundation
import GRDB

struct ProjectRow: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "project"
    var id: Int64?
    var dirName: String     // encoded dir name under ~/.claude/projects
    var name: String        // display name (from cwd basename when known)
    var cwd: String?

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

struct SessionRow: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "session"
    var id: String          // file basename (session uuid)
    var projectId: Int64
    var title: String?
    var filePath: String
    var firstTs: Date?
    var lastTs: Date?
    var messageCount: Int
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheCreationTokens: Int
    var model: String?      // dominant/last model seen
    var gitBranch: String?
    var cwd: String?
    var malformedLines: Int
}

struct MessageRow: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "message"
    var uuid: String
    var sessionId: String
    var projectId: Int64
    var ts: Date
    var kind: String        // user | assistant | system
    var role: String
    var model: String?
    var text: String
    var toolNames: String   // comma-separated
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheCreationTokens: Int
    var isSidechain: Bool
    var hasThinking: Bool
    var isToolResult: Bool
    var byteOffset: Int64
    var byteLength: Int64

    var id: String { uuid }
    var toolNameList: [String] { toolNames.isEmpty ? [] : toolNames.components(separatedBy: ",") }
}

struct FileStateRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "fileState"
    var path: String        // primary key
    var byteOffset: Int64
    var size: Int64
    var mtime: Date
    var sessionId: String
}

struct ModelPriceRow: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "modelPrice"
    var model: String       // primary key
    var inputPerMTok: Double
    var outputPerMTok: Double
    var cacheReadPerMTok: Double
    var cacheWritePerMTok: Double
    var isCustom: Bool

    var id: String { model }
}

struct AppSettingRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appSetting"
    var key: String
    var valueJSON: String
}
