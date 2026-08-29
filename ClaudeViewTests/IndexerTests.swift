import XCTest
import GRDB
@testable import ClaudeView

final class IndexerTests: XCTestCase {
    var tempRoot: URL!
    var database: AppDatabase!
    var indexer: Indexer!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeViewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        database = try AppDatabase.makeInMemory()
        indexer = Indexer(database: database, rootURL: tempRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func writeSession(dir: String, session: String, lines: [String]) throws -> URL {
        let dirURL = tempRoot.appendingPathComponent(dir, isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let fileURL = dirURL.appendingPathComponent("\(session).jsonl")
        let content = lines.map { $0 + "\n" }.joined()
        try content.data(using: .utf8)!.write(to: fileURL)
        return fileURL
    }

    private func userLine(uuid: String, ts: String, text: String) -> String {
        """
        {"type":"user","uuid":"\(uuid)","sessionId":"s1","timestamp":"\(ts)",\
        "cwd":"/Users/v/DevApps/Demo","gitBranch":"main",\
        "message":{"role":"user","content":"\(text)"}}
        """
    }

    private func assistantLine(uuid: String, ts: String, text: String) -> String {
        """
        {"type":"assistant","uuid":"\(uuid)","sessionId":"s1","timestamp":"\(ts)",\
        "message":{"role":"assistant","model":"claude-sonnet-5",\
        "content":[{"type":"text","text":"\(text)"}],\
        "usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30,\
        "cache_creation_input_tokens":40}}}
        """
    }

    func testInitialScanIndexesMessagesAndAggregates() throws {
        _ = try writeSession(dir: "-Users-v-DevApps-Demo", session: "s1", lines: [
            userLine(uuid: "u1", ts: "2026-08-01T10:00:00Z", text: "bonjour"),
            assistantLine(uuid: "a1", ts: "2026-08-01T10:00:05Z", text: "salut"),
            #"{"type":"ai-title","sessionId":"s1","aiTitle":"Session de démo"}"#,
            #"{"type":"attachment","uuid":"x","sessionId":"s1"}"#,
            "{malformed",
        ])
        try indexer.syncAll()

        let (sessions, messages) = try database.dbQueue.read { db in
            (try SessionRow.fetchAll(db), try MessageRow.fetchAll(db))
        }
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(messages.count, 2)
        let s = try XCTUnwrap(sessions.first)
        XCTAssertEqual(s.title, "Session de démo")
        XCTAssertEqual(s.messageCount, 2)
        XCTAssertEqual(s.inputTokens, 10)
        XCTAssertEqual(s.outputTokens, 20)
        XCTAssertEqual(s.cacheReadTokens, 30)
        XCTAssertEqual(s.cacheCreationTokens, 40)
        XCTAssertEqual(s.malformedLines, 1)
        XCTAssertEqual(s.model, "claude-sonnet-5")

        // Project display name derives from cwd
        let project = try database.dbQueue.read { try ProjectRow.fetchAll($0) }.first
        XCTAssertEqual(project?.name, "Demo")

        // FTS finds the content
        let hits = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM message_fts WHERE message_fts MATCH ?",
                arguments: ["bonjour"]) ?? 0
        }
        XCTAssertEqual(hits, 1)
    }

    func testIncrementalIngestionOnlyReadsNewLines() throws {
        let file = try writeSession(dir: "-d", session: "s1", lines: [
            userLine(uuid: "u1", ts: "2026-08-01T10:00:00Z", text: "un"),
        ])
        try indexer.syncAll()

        // Append one more line
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf:
            (assistantLine(uuid: "a1", ts: "2026-08-01T10:01:00Z", text: "deux") + "\n")
                .data(using: .utf8)!)
        try handle.close()

        let newCount = try indexer.ingest(fileURL: file)
        XCTAssertEqual(newCount, 1)
        let total = try database.dbQueue.read { try MessageRow.fetchCount($0) }
        XCTAssertEqual(total, 2)

        // Re-ingesting with no change is a no-op
        XCTAssertEqual(try indexer.ingest(fileURL: file), 0)
    }

    func testIncompleteTrailingLineIsDeferred() throws {
        let file = try writeSession(dir: "-d", session: "s1", lines: [
            userLine(uuid: "u1", ts: "2026-08-01T10:00:00Z", text: "complet"),
        ])
        // Append an incomplete line (no trailing newline)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: #"{"type":"user","uuid":"u2""#.data(using: .utf8)!)
        try handle.close()

        try indexer.syncAll()
        XCTAssertEqual(try database.dbQueue.read { try MessageRow.fetchCount($0) }, 1)

        // Complete the line and ingest again
        let handle2 = try FileHandle(forWritingTo: file)
        try handle2.seekToEnd()
        try handle2.write(contentsOf:
            (",\"sessionId\":\"s1\",\"timestamp\":\"2026-08-01T10:02:00Z\","
             + "\"message\":{\"role\":\"user\",\"content\":\"fini\"}}\n").data(using: .utf8)!)
        try handle2.close()

        XCTAssertEqual(try indexer.ingest(fileURL: file), 1)
        XCTAssertEqual(try database.dbQueue.read { try MessageRow.fetchCount($0) }, 2)
    }

    func testTruncatedFileTriggersReindex() throws {
        let file = try writeSession(dir: "-d", session: "s1", lines: [
            userLine(uuid: "u1", ts: "2026-08-01T10:00:00Z", text: "un"),
            userLine(uuid: "u2", ts: "2026-08-01T10:01:00Z", text: "deux"),
        ])
        try indexer.syncAll()
        XCTAssertEqual(try database.dbQueue.read { try MessageRow.fetchCount($0) }, 2)

        // Rewrite the file shorter (single different line)
        _ = try writeSession(dir: "-d", session: "s1", lines: [
            userLine(uuid: "u9", ts: "2026-08-02T09:00:00Z", text: "nouveau départ"),
        ])
        _ = try indexer.ingest(fileURL: file)

        let messages = try database.dbQueue.read { try MessageRow.fetchAll($0) }
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.uuid, "u9")
    }

    func testNestedSubagentTranscriptsAreIndexed() throws {
        _ = try writeSession(dir: "-p", session: "sess1", lines: [
            userLine(uuid: "u1", ts: "2026-08-01T10:00:00Z", text: "parent"),
        ])
        _ = try writeSession(dir: "-p/sess1/subagents", session: "agent-explore-abc", lines: [
            userLine(uuid: "u2", ts: "2026-08-01T10:00:30Z", text: "tâche du sous-agent"),
        ])
        try indexer.syncAll()

        let (projects, sessions) = try database.dbQueue.read { db in
            (try ProjectRow.fetchAll(db), try SessionRow.fetchAll(db))
        }
        XCTAssertEqual(projects.count, 1, "subagent dir must not become a project")
        XCTAssertEqual(Set(sessions.map(\.id)), ["sess1", "agent-explore-abc"])
        XCTAssertEqual(Set(sessions.map(\.projectId)).count, 1)
    }

    func testUnreadableFileDoesNotAbortScan() throws {
        _ = try writeSession(dir: "-a", session: "bad", lines: ["x"])
        let badFile = tempRoot.appendingPathComponent("-a/bad.jsonl")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: badFile.path)
        defer { try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: badFile.path) }
        _ = try writeSession(dir: "-z", session: "good", lines: [
            userLine(uuid: "u1", ts: "2026-08-01T10:00:00Z", text: "ok"),
        ])
        try indexer.syncAll()
        let count = try database.dbQueue.read { try MessageRow.fetchCount($0) }
        XCTAssertEqual(count, 1, "the good file must be indexed despite the bad one")
    }

    func testLiveEventsEmittedAfterInitialScan() throws {
        let file = try writeSession(dir: "-d", session: "s1", lines: [
            userLine(uuid: "u1", ts: "2026-08-01T10:00:00Z", text: "avant scan"),
        ])
        var received: [LiveEvent] = []
        indexer.onLiveEvent = { received.append($0) }

        try indexer.syncAll()
        XCTAssertTrue(received.isEmpty, "initial scan must not flood the live feed")

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf:
            (userLine(uuid: "u2", ts: "2026-08-01T10:05:00Z", text: "après scan") + "\n")
                .data(using: .utf8)!)
        try handle.close()
        _ = try indexer.ingest(fileURL: file)

        XCTAssertEqual(received.map(\.id), ["u2"])
        XCTAssertEqual(received.first?.message.text, "après scan")
    }
}
