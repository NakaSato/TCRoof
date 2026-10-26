import XCTest
@testable import TCRoofCore

/// The AI providers a device can be given a key for, and Claude through Anthropic's Messages API.
final class AssistantProvidersTests: XCTestCase {
    typealias A = Assistant.Anthropic

    private func json(_ d: Data) throws -> JSONValue { try XCTUnwrap(JSONValue.parse(String(decoding: d, as: UTF8.self))) }
    private func array(_ v: JSONValue?) -> [JSONValue] { if case .array(let a) = v ?? .null { return a }; return [] }

    func testEveryProviderHasWhatTheSettingsPageNeeds() {
        for p in Assistant.Provider.allCases where p != .custom {
            XCTAssertFalse(p.title.isEmpty)
            XCTAssertTrue(p.defaultBaseURL.hasPrefix("https://"), "\(p)")
            XCTAssertFalse(p.defaultModel.isEmpty, "\(p)")
            switch p.api {
            case .openAI: XCTAssertNotNil(Assistant.OpenAI.url(base: p.defaultBaseURL), "\(p)")
            case .anthropic: XCTAssertEqual(A.url(base: p.defaultBaseURL)?.absoluteString, "https://api.anthropic.com/v1/messages")
            }
        }
        XCTAssertEqual(Assistant.Provider.custom.defaultBaseURL, "")
        XCTAssertEqual(Assistant.Provider.anthropic.api, .anthropic)
        XCTAssertEqual(Assistant.Provider.qwen.defaultModel, Assistant.OpenAI.defaultModel)
        XCTAssertNil(A.url(base: "http://api.anthropic.com/v1"))           // never the key over plain http
    }

    func testOpenAIGetsCompletionTokensAndNoTemperature() throws {
        let r = Assistant.Request(messages: [.user("q")], tools: [])
        let openai = try json(Assistant.OpenAI.body(r, model: "gpt-4.1-mini", provider: .openai))
        XCTAssertEqual(openai["max_completion_tokens"]?.number, 1500)
        XCTAssertNil(openai["max_tokens"])
        XCTAssertNil(openai["temperature"])
        let gemini = try json(Assistant.OpenAI.body(r, model: "gemini-2.5-flash", provider: .gemini))
        XCTAssertEqual(gemini["max_tokens"]?.number, 1500)
        XCTAssertNil(gemini["max_completion_tokens"])
    }

    // MARK: Claude

    func testClaudeBodyTurnsTheConversationIntoMessagesAPITurns() throws {
        let call = Assistant.ToolCall(id: "toolu_1", name: "get_schedule", arguments: #"{"job":"189"}"#)
        let r = Assistant.Request(messages: [.system("sys"), .user("[ระบบ] ยืนยันแล้ว"), .user("MP 189 ช้าไหม"),
                                             .init(role: .assistant, content: "ขอดูแผนก่อน", toolCalls: [call]),
                                             .tool("toolu_1", #"{"actualPercent":24}"#)],
                                  tools: Assistant.Toolbox.definitions)
        let body = try json(A.body(r, model: "claude-opus-5-5"))
        XCTAssertEqual(body["model"]?.string, "claude-opus-5-5")
        XCTAssertEqual(body["system"]?.string, "sys")
        XCTAssertEqual(body["max_tokens"]?.number, Double(A.maxTokens))
        XCTAssertNil(body["temperature"])                                  // removed from the 2026-10-21 API
        XCTAssertEqual(body["thinking"]?["type"]?.string, "adaptive")
        XCTAssertEqual(body["thinking"]?["block_binding"]?["prefix_mismatch_behavior"]?.string, "drop_block")
        XCTAssertEqual(body["fallbacks"]?.string, "default")

        let turns = array(body["messages"])
        XCTAssertEqual(turns.map { $0["role"]?.string }, ["user", "assistant", "user"])   // the two person turns as one
        XCTAssertEqual(array(turns[0]["content"]).count, 2)
        let assistant = array(turns[1]["content"])
        XCTAssertEqual(assistant.map { $0["type"]?.string }, ["text", "tool_use"])
        XCTAssertEqual(assistant[1]["input"]?["job"]?.string, "189")
        let result = array(turns[2]["content"])[0]
        XCTAssertEqual(result["type"]?.string, "tool_result")
        XCTAssertEqual(result["tool_use_id"]?.string, "toolu_1")

        let tools = array(body["tools"])
        XCTAssertEqual(tools.count, Assistant.Toolbox.names.count)
        XCTAssertNotNil(tools[0]["input_schema"])
        XCTAssertNil(tools[0]["function"])
    }

    func testHeadersAndModelsWithoutThinkingOrFallbacks() throws {
        let h = A.headers(key: "sk-ant-x", model: "claude-opus-5-5")
        XCTAssertEqual(h["x-api-key"], "sk-ant-x")
        XCTAssertEqual(h["anthropic-version"], "2026-10-21")
        XCTAssertEqual(h["anthropic-beta"], "thinking-binding-controls-2026-08-01,server-side-fallback-2026-07-01")
        // Haiku 5.5 thinks but has no server-side fallback; Haiku 4.5 has neither
        XCTAssertEqual(A.betas(model: "claude-haiku-5-5"), "thinking-binding-controls-2026-08-01")
        XCTAssertNil(A.betas(model: "claude-haiku-4-5"))
        let old = try json(A.body(.init(messages: [.user("q")], tools: []), model: "claude-haiku-4-5"))
        XCTAssertNil(old["thinking"])
        XCTAssertNil(old["fallbacks"])
        XCTAssertNil(old["tools"])
        XCTAssertNil(old["system"])
    }

    func testReplyKeepsClaudesBlocksAndThinkingGoesBackOnlyWithinTheQuestion() throws {
        let raw = #"{"stop_reason":"tool_use","content":[{"type":"thinking","thinking":"","signature":"sig"},{"type":"text","text":"ขอดูแผน"},{"type":"tool_use","id":"toolu_9","name":"get_schedule","input":{"job":"189"}}]}"#
        let m = try A.reply(Data(raw.utf8), status: 200)
        XCTAssertEqual(m.content, "ขอดูแผน")
        XCTAssertEqual(m.toolCalls?.first?.id, "toolu_9")
        XCTAssertEqual(JSONValue.parse(m.toolCalls?.first?.function.arguments ?? "")?["job"]?.string, "189")
        XCTAssertEqual(array(m.providerBlocks).count, 3)

        // this question's rounds: the thinking block goes back as it came
        let now = try json(A.body(.init(messages: [.user("q"), m, .tool("toolu_9", "{}")], tools: []), model: "claude-opus-5-5"))
        XCTAssertEqual(array(array(now["messages"])[1]["content"]).map { $0["type"]?.string }, ["thinking", "text", "tool_use"])
        XCTAssertEqual(array(array(now["messages"])[1]["content"])[0]["signature"]?.string, "sig")
        // a later question: only its text and tool call
        let later = try json(A.body(.init(messages: [.user("q"), m, .tool("toolu_9", "{}"), .init(role: .assistant, content: "ตอบ"), .user("q2")],
                                          tools: []), model: "claude-opus-5-5"))
        XCTAssertEqual(array(array(later["messages"])[1]["content"]).map { $0["type"]?.string }, ["text", "tool_use"])
        // never encoded for OpenAI-style bodies
        let openai = String(decoding: try Assistant.OpenAI.body(.init(messages: [m], tools: []), model: "x"), as: UTF8.self)
        XCTAssertFalse(openai.contains("signature"))
    }

    func testReplyFailuresRefusalsAndUnknownTools() throws {
        typealias F = Assistant.OpenAI.Failure
        XCTAssertThrowsError(try A.reply(Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8), status: 401)) {
            XCTAssertEqual($0 as? F, .badKey)
        }
        XCTAssertThrowsError(try A.reply(Data("{}".utf8), status: 529)) { XCTAssertEqual($0 as? F, .busy) }
        XCTAssertThrowsError(try A.reply(Data(#"{"type":"error","error":{"message":"model: not found"}}"#.utf8), status: 404)) {
            XCTAssertEqual($0 as? F, .server(404, "model: not found"))
        }
        XCTAssertThrowsError(try A.reply(Data(#"{"content":[]}"#.utf8), status: 200)) { XCTAssertEqual($0 as? F, .badReply) }

        let refused = try A.reply(Data(#"{"stop_reason":"refusal","content":[]}"#.utf8), status: 200)
        XCTAssertNil(refused.toolCalls)
        XCTAssertTrue(refused.content?.contains("ไม่ตอบคำถามนี้") == true)

        let unknown = try A.reply(Data(#"{"content":[{"type":"tool_use","id":"t","name":"delete_job","input":{}}]}"#.utf8), status: 200)
        XCTAssertNil(unknown.toolCalls)
        XCTAssertEqual(unknown.content, "ผู้ช่วยขอใช้เครื่องมือที่ไม่ได้รับอนุญาต")

        // after a fallback marker, only the declined model's text stays
        let fell = try A.reply(Data(#"{"content":[{"type":"thinking","thinking":"","signature":"a"},{"type":"text","text":"เริ่ม"},{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-5"}},{"type":"text","text":"ต่อ"}]}"#.utf8), status: 200)
        XCTAssertEqual(fell.content, "เริ่ม\nต่อ")
        XCTAssertEqual(array(fell.providerBlocks).map { $0["type"]?.string }, ["text", "text"])
    }
}
