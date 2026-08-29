import Foundation

/// Lazily re-reads one JSONL line from disk (payloads are not stored in SQLite).
enum MessageDetailLoader {
    static func load(filePath: String, byteOffset: Int64, byteLength: Int64) -> MessageDetail? {
        guard byteLength > 0, let handle = FileHandle(forReadingAtPath: filePath) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(byteOffset))
            guard let data = try handle.read(upToCount: Int(byteLength)) else { return nil }
            return JSONLParser.parseDetail(lineData: data)
        } catch {
            return nil
        }
    }
}
