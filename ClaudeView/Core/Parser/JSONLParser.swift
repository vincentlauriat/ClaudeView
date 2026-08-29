import Foundation

/// Tolerant parser for Claude Code transcript JSONL lines.
/// Any malformed line yields `.malformed`; nothing ever throws to the caller.
enum JSONLParser {

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoParserNoFraction = ISO8601DateFormatter()

    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoParser.date(from: s) ?? isoParserNoFraction.date(from: s)
    }

    static func parse(lineData: Data) -> ParsedLine {
        guard !lineData.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: lineData),
              let dict = obj as? [String: Any] else {
            return .malformed
        }
        guard let type = dict["type"] as? String else { return .malformed }

        switch type {
        case "ai-title":
            if let sid = dict["sessionId"] as? String, let title = dict["aiTitle"] as? String {
                return .sessionTitle(sessionId: sid, title: title)
            }
            return .skipped
        case "user", "assistant", "system":
            return parseMessage(type: type, dict: dict)
        default:
            return .skipped
        }
    }

    private static func parseMessage(type: String, dict: [String: Any]) -> ParsedLine {
        guard let uuid = dict["uuid"] as? String,
              let sessionId = (dict["sessionId"] as? String) ?? (dict["session_id"] as? String),
              let ts = parseDate(dict["timestamp"] as? String) else {
            return .skipped
        }

        var text = ""
        var toolNames: [String] = []
        var hasThinking = false
        var isToolResult = false
        var usage = TokenUsage()
        var role = type
        var model: String?

        if let message = dict["message"] as? [String: Any] {
            role = (message["role"] as? String) ?? type
            model = message["model"] as? String
            if let u = message["usage"] as? [String: Any] {
                usage.input = (u["input_tokens"] as? Int) ?? 0
                usage.output = (u["output_tokens"] as? Int) ?? 0
                usage.cacheRead = (u["cache_read_input_tokens"] as? Int) ?? 0
                usage.cacheCreation = (u["cache_creation_input_tokens"] as? Int) ?? 0
            }
            let extracted = extractContent(message["content"])
            text = extracted.text
            toolNames = extracted.toolNames
            hasThinking = extracted.hasThinking
            isToolResult = extracted.isToolResult
        } else if type == "system" {
            text = (dict["subtype"] as? String) ?? ""
        }

        let parsed = ParsedMessage(
            uuid: uuid,
            sessionId: sessionId,
            timestamp: ts,
            kind: type,
            role: role,
            model: model,
            cwd: dict["cwd"] as? String,
            gitBranch: dict["gitBranch"] as? String,
            isSidechain: (dict["isSidechain"] as? Bool) ?? false,
            text: text,
            toolNames: toolNames,
            hasThinking: hasThinking,
            isToolResult: isToolResult,
            usage: usage
        )
        return .message(parsed)
    }

    private static func extractContent(_ content: Any?)
        -> (text: String, toolNames: [String], hasThinking: Bool, isToolResult: Bool) {
        if let s = content as? String {
            return (s, [], false, false)
        }
        guard let blocks = content as? [[String: Any]] else { return ("", [], false, false) }
        var parts: [String] = []
        var toolNames: [String] = []
        var hasThinking = false
        var isToolResult = false
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let t = block["text"] as? String { parts.append(t) }
            case "thinking":
                hasThinking = true
            case "tool_use":
                if let name = block["name"] as? String { toolNames.append(name) }
            case "tool_result":
                isToolResult = true
                parts.append(toolResultText(block["content"]))
            default:
                break
            }
        }
        return (parts.joined(separator: "\n"), toolNames, hasThinking, isToolResult)
    }

    static func toolResultText(_ content: Any?) -> String {
        if let s = content as? String { return s }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    // MARK: - Detail decoding (lazy, for the transcript/live inspector)

    static func parseDetail(lineData: Data) -> MessageDetail? {
        guard let obj = try? JSONSerialization.jsonObject(with: lineData),
              let dict = obj as? [String: Any] else { return nil }
        let raw = prettyJSON(dict) ?? String(data: lineData, encoding: .utf8) ?? ""
        var blocks: [MessageDetail.Block] = []
        if let message = dict["message"] as? [String: Any] {
            if let s = message["content"] as? String {
                blocks.append(.text(s))
            } else if let list = message["content"] as? [[String: Any]] {
                for b in list {
                    switch b["type"] as? String {
                    case "text":
                        blocks.append(.text((b["text"] as? String) ?? ""))
                    case "thinking":
                        blocks.append(.thinking((b["thinking"] as? String) ?? ""))
                    case "tool_use":
                        blocks.append(.toolUse(
                            id: (b["id"] as? String) ?? "",
                            name: (b["name"] as? String) ?? "?",
                            inputJSON: prettyJSON(b["input"]) ?? "{}"
                        ))
                    case "tool_result":
                        blocks.append(.toolResult(
                            toolUseId: (b["tool_use_id"] as? String) ?? "",
                            isError: (b["is_error"] as? Bool) ?? false,
                            content: toolResultText(b["content"])
                        ))
                    default:
                        break
                    }
                }
            }
        }
        return MessageDetail(blocks: blocks, rawJSON: raw)
    }

    static func prettyJSON(_ obj: Any?) -> String? {
        guard let obj, JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(
                withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
