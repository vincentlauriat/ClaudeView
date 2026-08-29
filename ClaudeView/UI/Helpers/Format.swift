import Foundation
import SwiftUI

enum Format {
    static func cost(_ value: Double) -> String {
        if value >= 100 { return String(format: "$%.0f", value) }
        if value >= 1 { return String(format: "$%.2f", value) }
        return String(format: "$%.3f", value)
    }

    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Short model label: "claude-sonnet-5-20260101" → "sonnet-5".
    static func modelShort(_ model: String?) -> String {
        guard var m = model, !m.isEmpty else { return "—" }
        if m.hasPrefix("claude-") { m.removeFirst("claude-".count) }
        // Drop a trailing date-like suffix (-20260101)
        let parts = m.components(separatedBy: "-")
        if let last = parts.last, last.count == 8, Int(last) != nil {
            m = parts.dropLast().joined(separator: "-")
        }
        return m
    }
}

extension MessageRow {
    var roleColor: Color {
        switch kind {
        case "user": return isToolResult ? .teal : .blue
        case "assistant": return .orange
        default: return .gray
        }
    }

    var roleIcon: String {
        switch kind {
        case "user": return isToolResult ? "arrow.uturn.left.circle" : "person.circle"
        case "assistant": return "sparkles"
        default: return "gearshape"
        }
    }

    var roleLabel: String {
        switch kind {
        case "user": return isToolResult ? "Tool result" : "Vincent"
        case "assistant": return "Claude"
        default: return "Système"
        }
    }

    var usage: TokenUsage {
        TokenUsage(input: inputTokens, output: outputTokens,
                   cacheRead: cacheReadTokens, cacheCreation: cacheCreationTokens)
    }
}
