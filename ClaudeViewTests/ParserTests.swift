import XCTest
@testable import ClaudeView

final class ParserTests: XCTestCase {

    func line(_ json: String) -> Data { json.data(using: .utf8)! }

    func testUserMessageWithStringContent() throws {
        let data = line("""
        {"type":"user","uuid":"u1","sessionId":"s1","timestamp":"2026-08-04T09:26:22.743Z",\
        "cwd":"/Users/v/DevApps/Sudoku","gitBranch":"main","isSidechain":false,\
        "message":{"role":"user","content":"corrige le bug de la grille"}}
        """)
        guard case .message(let m) = JSONLParser.parse(lineData: data) else {
            return XCTFail("expected .message")
        }
        XCTAssertEqual(m.uuid, "u1")
        XCTAssertEqual(m.kind, "user")
        XCTAssertEqual(m.text, "corrige le bug de la grille")
        XCTAssertEqual(m.usage, TokenUsage())
        XCTAssertEqual(m.cwd, "/Users/v/DevApps/Sudoku")
    }

    func testAssistantMessageWithBlocksAndUsage() throws {
        let data = line("""
        {"type":"assistant","uuid":"a1","sessionId":"s1","timestamp":"2026-08-04T09:26:25.992Z",\
        "isSidechain":false,"message":{"role":"assistant","model":"claude-fable-5",\
        "content":[{"type":"thinking","thinking":"hmm","signature":"x"},\
        {"type":"text","text":"Voici le correctif."},\
        {"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}],\
        "usage":{"input_tokens":2,"output_tokens":292,"cache_read_input_tokens":20953,\
        "cache_creation_input_tokens":41611}}}
        """)
        guard case .message(let m) = JSONLParser.parse(lineData: data) else {
            return XCTFail("expected .message")
        }
        XCTAssertEqual(m.model, "claude-fable-5")
        XCTAssertEqual(m.text, "Voici le correctif.")
        XCTAssertTrue(m.hasThinking)
        XCTAssertEqual(m.toolNames, ["Bash"])
        XCTAssertEqual(m.usage,
            TokenUsage(input: 2, output: 292, cacheRead: 20953, cacheCreation: 41611))
    }

    func testToolResultMessage() throws {
        let data = line("""
        {"type":"user","uuid":"u2","sessionId":"s1","timestamp":"2026-08-04T09:27:00Z",\
        "message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1",\
        "is_error":false,"content":"file1\\nfile2"}]}}
        """)
        guard case .message(let m) = JSONLParser.parse(lineData: data) else {
            return XCTFail("expected .message")
        }
        XCTAssertTrue(m.isToolResult)
        XCTAssertEqual(m.text, "file1\nfile2")
    }

    func testAiTitle() throws {
        let data = line(#"{"type":"ai-title","sessionId":"s1","aiTitle":"Fix grille Sudoku"}"#)
        guard case .sessionTitle(let sid, let title) = JSONLParser.parse(lineData: data) else {
            return XCTFail("expected .sessionTitle")
        }
        XCTAssertEqual(sid, "s1")
        XCTAssertEqual(title, "Fix grille Sudoku")
    }

    func testIrrelevantAndMalformedLines() {
        XCTAssertEqual(JSONLParser.parse(lineData: line(
            #"{"type":"attachment","uuid":"x","sessionId":"s1"}"#)), .skipped)
        XCTAssertEqual(JSONLParser.parse(lineData: line(
            #"{"type":"mode","mode":"default","sessionId":"s1"}"#)), .skipped)
        XCTAssertEqual(JSONLParser.parse(lineData: line("{not json")), .malformed)
        XCTAssertEqual(JSONLParser.parse(lineData: line(#"{"no":"type"}"#)), .malformed)
    }

    func testDetailDecoding() throws {
        let data = line("""
        {"type":"assistant","uuid":"a1","sessionId":"s1","timestamp":"2026-08-04T09:26:25Z",\
        "message":{"role":"assistant","content":[\
        {"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/tmp/x"}},\
        {"type":"text","text":"ok"}]}}
        """)
        let detail = try XCTUnwrap(JSONLParser.parseDetail(lineData: data))
        XCTAssertEqual(detail.blocks.count, 2)
        guard case .toolUse(_, let name, let input) = detail.blocks[0] else {
            return XCTFail("expected toolUse block")
        }
        XCTAssertEqual(name, "Edit")
        XCTAssertTrue(input.contains("file_path"))
        XCTAssertTrue(detail.rawJSON.contains("assistant"))
    }
}
