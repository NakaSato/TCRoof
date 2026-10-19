import XCTest
@testable import TCRoofCore

/// Qwen called from the device: the request body and the reply checks (as functions/src/guard.ts makes them).
final class AssistantOpenAITests: XCTestCase {
    typealias O = Assistant.OpenAI

    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testBodyCarriesModelToolsAndLimits() throws {
        let call = Assistant.ToolCall(id: "c1", name: "list_stations", arguments: "{}")
        let r = Assistant.Request(messages: [.system("s"), .user("q"), .init(role: .assistant, content: nil, toolCalls: [call]),
                                             .tool("c1", "{}")], tools: Assistant.Toolbox.definitions)
        let body = try XCTUnwrap(JSONValue.parse(String(decoding: try O.body(r, model: "qwen-max"), as: UTF8.self)))
        XCTAssertEqual(body["model"]?.string, "qwen-max")
        XCTAssertEqual(body["tool_choice"]?.string, "auto")
        XCTAssertEqual(body["max_tokens"]?.number, 1500)
        guard case .array(let messages) = body["messages"] ?? .null else { return XCTFail("messages") }
        XCTAssertEqual(messages[2]["content"], .null)                      // written, as null
        XCTAssertEqual(messages[2]["tool_calls"]?["0"], nil)
        XCTAssertEqual(messages[3]["tool_call_id"]?.string, "c1")
        guard case .array(let tools) = body["tools"] ?? .null else { return XCTFail("tools") }
        XCTAssertEqual(tools.count, Assistant.Toolbox.names.count)
    }

    func testATestWithoutToolsSendsNoToolChoice() throws {
        let body = JSONValue.parse(String(decoding: try O.body(.init(messages: [.user("ok")], tools: []), model: "m"), as: UTF8.self))
        XCTAssertNil(body?["tools"])
        XCTAssertNil(body?["tool_choice"])
    }

    func testURL() {
        XCTAssertEqual(O.url(base: "https://maas.qwencloudapi.com/compatible-mode/v1/")?.absoluteString,
                       "https://maas.qwencloudapi.com/compatible-mode/v1/chat/completions")
        XCTAssertNil(O.url(base: "http://example.com/v1"))                // never the key over plain http
    }

    func testReplyWithWordsOrTools() throws {
        let words = try O.reply(data(#"{"choices":[{"message":{"role":"assistant","content":"สวัสดี","reasoning_content":"x"}}]}"#), status: 200)
        XCTAssertEqual(words, .init(role: .assistant, content: "สวัสดี"))
        let tools = try O.reply(data(#"{"choices":[{"message":{"content":"","tool_calls":[{"id":"c","type":"function","function":{"name":"what_if","arguments":"{\"job\":\"189\"}"}}]}}]}"#), status: 200)
        XCTAssertEqual(tools.toolCalls?.first?.function.name, "what_if")
        XCTAssertEqual(tools.toolCalls?.first?.function.arguments, #"{"job":"189"}"#)
    }

    func testAnUnknownToolBecomesWords() throws {
        let m = try O.reply(data(#"{"choices":[{"message":{"content":null,"tool_calls":[{"id":"c","function":{"name":"delete_job","arguments":"{}"}}]}}]}"#), status: 200)
        XCTAssertNil(m.toolCalls)
        XCTAssertEqual(m.content, "ผู้ช่วยขอใช้เครื่องมือที่ไม่ได้รับอนุญาต")
    }

    func testFailures() {
        XCTAssertThrowsError(try O.reply(data(#"{"error":{"message":"Invalid API-key"}}"#), status: 401)) { XCTAssertEqual($0 as? O.Failure, .badKey) }
        XCTAssertThrowsError(try O.reply(data("{}"), status: 429)) { XCTAssertEqual($0 as? O.Failure, .busy) }
        XCTAssertThrowsError(try O.reply(data(#"{"error":{"message":"model not found"}}"#), status: 404)) {
            XCTAssertEqual($0 as? O.Failure, .server(404, "model not found"))
        }
        XCTAssertThrowsError(try O.reply(data(#"{"choices":[]}"#), status: 200)) { XCTAssertEqual($0 as? O.Failure, .badReply) }
        XCTAssertThrowsError(try O.reply(data(#"{"choices":[{"message":{"content":""}}]}"#), status: 200))
    }

    func testDaysAreBangkokDays() {
        XCTAssertEqual(O.day(ISO8601DateFormatter().date(from: "2026-10-18T17:30:00Z")!), "2026-10-19")
    }
}
