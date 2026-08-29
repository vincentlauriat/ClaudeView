import Foundation

/// Token usage of a single assistant message (cache-aware).
struct TokenUsage: Equatable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheCreation: Int = 0

    var total: Int { input + output + cacheRead + cacheCreation }
}

/// A transcript message extracted from one JSONL line.
struct ParsedMessage: Equatable {
    var uuid: String
    var sessionId: String
    var timestamp: Date
    var kind: String            // "user" | "assistant" | "system"
    var role: String
    var model: String?
    var cwd: String?
    var gitBranch: String?
    var isSidechain: Bool
    var text: String            // extracted textual content (for FTS + previews)
    var toolNames: [String]     // tool_use names in this message
    var hasThinking: Bool
    var isToolResult: Bool
    var usage: TokenUsage
}

/// Result of parsing one JSONL line.
enum ParsedLine: Equatable {
    case message(ParsedMessage)
    case sessionTitle(sessionId: String, title: String)
    case skipped        // known but irrelevant line type (attachment, mode, …)
    case malformed
}

/// Fully decoded content of one line, for the transcript detail view
/// (lazily re-read from disk via byte offsets — never stored in SQLite).
struct MessageDetail {
    enum Block {
        case text(String)
        case thinking(String)
        case toolUse(id: String, name: String, inputJSON: String)
        case toolResult(toolUseId: String, isError: Bool, content: String)
    }
    var blocks: [Block]
    var rawJSON: String
}
