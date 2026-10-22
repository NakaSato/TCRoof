import Foundation

public extension Assistant {

    /// The AI services a device can be given a key for (ตั้งค่า › ผู้ช่วยโครงการ (AI)). Most take the OpenAI-style chat
    /// format (`Assistant.OpenAI`); Claude takes Anthropic's Messages API (`Assistant.Anthropic`). Each keeps its own
    /// key, model and endpoint on the device; one of them is the one in use.
    enum Provider: String, CaseIterable, Codable, Identifiable, Sendable {
        case qwen, openai, anthropic, gemini, deepseek, groq, openrouter, mistral, xai, custom

        public var id: String { rawValue }

        public enum API: Sendable { case openAI, anthropic }

        public var api: API { self == .anthropic ? .anthropic : .openAI }

        public var title: String {
            switch self {
            case .qwen: "Qwen (Alibaba)"
            case .openai: "OpenAI (ChatGPT)"
            case .anthropic: "Claude (Anthropic)"
            case .gemini: "Gemini (Google)"
            case .deepseek: "DeepSeek"
            case .groq: "Groq"
            case .openrouter: "OpenRouter"
            case .mistral: "Mistral"
            case .xai: "Grok (xAI)"
            case .custom: "อื่น ๆ (OpenAI-compatible)"
            }
        }

        /// The endpoint the key is used with; the custom one has none until the person types it.
        public var defaultBaseURL: String {
            switch self {
            case .qwen: OpenAI.defaultBaseURL
            case .openai: "https://api.openai.com/v1"
            case .anthropic: Anthropic.defaultBaseURL
            case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
            case .deepseek: "https://api.deepseek.com/v1"
            case .groq: "https://api.groq.com/openai/v1"
            case .openrouter: "https://openrouter.ai/api/v1"
            case .mistral: "https://api.mistral.ai/v1"
            case .xai: "https://api.x.ai/v1"
            case .custom: ""
            }
        }

        /// A starting model the person can change; providers rename their models often, so the field stays editable.
        public var defaultModel: String {
            switch self {
            case .qwen: OpenAI.defaultModel
            case .openai: "gpt-4.1-mini"
            case .anthropic: Anthropic.defaultModel
            case .gemini: "gemini-2.5-flash"
            case .deepseek: "deepseek-chat"
            case .groq: "llama-3.3-70b-versatile"
            case .openrouter: "openrouter/auto"
            case .mistral: "mistral-small-latest"
            case .xai: "grok-3-mini"
            case .custom: ""
            }
        }

        /// How a key of this service starts, for the field's placeholder.
        public var keyHint: String {
            switch self {
            case .anthropic: "sk-ant-…"
            case .gemini: "AIza…"
            case .groq: "gsk_…"
            case .openrouter: "sk-or-…"
            case .xai: "xai-…"
            default: "sk-…"
            }
        }

        /// Where the person gets a key.
        public var keyPage: String? {
            switch self {
            case .qwen: "https://modelstudio.console.alibabacloud.com"
            case .openai: "https://platform.openai.com/api-keys"
            case .anthropic: "https://platform.claude.com/settings/keys"
            case .gemini: "https://aistudio.google.com/apikey"
            case .deepseek: "https://platform.deepseek.com/api_keys"
            case .groq: "https://console.groq.com/keys"
            case .openrouter: "https://openrouter.ai/keys"
            case .mistral: "https://console.mistral.ai/api-keys"
            case .xai: "https://console.x.ai"
            case .custom: nil
            }
        }

        /// OpenAI's newer models take `max_completion_tokens` and only their default temperature.
        var usesCompletionTokens: Bool { self == .openai }
    }

    /// Claude through Anthropic's Messages API (`POST /v1/messages`), called straight from the device with the key in
    /// its Keychain. The conversation stays in the app's OpenAI-style `Message`s; this turns them into Messages API
    /// bodies and the reply back. Claude's own content blocks ride on the reply's `providerBlocks` and go back as they
    /// came within the question they belong to (its thinking blocks are bound to the conversation before them); from
    /// earlier questions only their text and tool calls go back, since the session trims and shortens old turns.
    enum Anthropic {
        public static let defaultBaseURL = "https://api.anthropic.com/v1"
        public static let defaultModel = "claude-opus-5-5"
        public static let version = "2026-10-21"
        /// Adaptive thinking counts toward it, so it is larger than the OpenAI-style limit.
        public static let maxTokens = 16_000
        static let bindingBeta = "thinking-binding-controls-2026-08-01"
        static let fallbackBeta = "server-side-fallback-2026-07-01"

        public static func url(base: String) -> URL? {
            var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
            while b.hasSuffix("/") { b.removeLast() }
            guard b.hasPrefix("https://") else { return nil }
            return URL(string: b + "/messages")
        }

        /// Models with adaptive thinking (the 4.6 generation and later); older ones get no `thinking` field.
        static func thinks(_ model: String) -> Bool {
            ["claude-fable", "claude-mythos", "claude-opus-5", "claude-sonnet-5", "claude-haiku-5",
             "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8", "claude-sonnet-4-6"].contains { model.hasPrefix($0) }
        }

        /// Models with a server-side fallback when a safety classifier declines (`fallbacks: "default"`).
        static func fallsBack(_ model: String) -> Bool {
            ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"].contains(model)
        }

        /// The `anthropic-beta` header the body needs, nil for none.
        public static func betas(model: String) -> String? {
            var b: [String] = []
            if thinks(model) { b.append(bindingBeta) }
            if fallsBack(model) { b.append(fallbackBeta) }
            return b.isEmpty ? nil : b.joined(separator: ",")
        }

        public static func headers(key: String, model: String) -> [String: String] {
            var h = ["Content-Type": "application/json", "x-api-key": key, "anthropic-version": version]
            if let b = betas(model: model) { h["anthropic-beta"] = b }
            return h
        }

        // MARK: Request

        public static func body(_ request: Request, model: String) throws -> Data {
            var o: [String: JSONValue] = ["model": .string(model), "max_tokens": .number(Double(maxTokens)),
                                          "messages": .array(messages(request.messages))]
            let system = request.messages.filter { $0.role == .system }.compactMap(\.content).joined(separator: "\n\n")
            if !system.isEmpty { o["system"] = .string(system) }
            if !request.tools.isEmpty { o["tools"] = .array(request.tools.compactMap(tool)) }
            if thinks(model) {
                // a block whose conversation changed is dropped, not refused (the session trims old turns)
                o["thinking"] = .object(["type": .string("adaptive"),
                                         "block_binding": .object(["prefix_mismatch_behavior": .string("drop_block")])])
            }
            if fallsBack(model) { o["fallbacks"] = .string("default") }
            return try JSONEncoder().encode(JSONValue.object(o))
        }

        /// An OpenAI-style tool definition as a Messages API tool.
        static func tool(_ t: JSONValue) -> JSONValue? {
            guard let f = t["function"], let name = f["name"]?.string else { return nil }
            var o: [String: JSONValue] = ["name": .string(name),
                                          "input_schema": f["parameters"] ?? .object(["type": .string("object")])]
            if let d = f["description"]?.string { o["description"] = .string(d) }
            return .object(o)
        }

        /// The conversation as Messages API turns: the system prompt goes to `system`, tool results into the user turn
        /// after the call, and turns of one role in a row into one.
        static func messages(_ list: [Message]) -> [JSONValue] {
            let current = list.lastIndex { $0.role == .user } ?? list.endIndex
            var turns: [(role: String, blocks: [JSONValue])] = []
            func add(_ role: String, _ blocks: [JSONValue]) {
                guard !blocks.isEmpty else { return }
                if turns.last?.role == role { turns[turns.count - 1].blocks += blocks } else { turns.append((role, blocks)) }
            }
            for (i, m) in list.enumerated() {
                switch m.role {
                case .system: continue
                case .user: add("user", text(m.content))
                case .tool:
                    add("user", [.object(["type": .string("tool_result"), "tool_use_id": .string(m.toolCallID ?? ""),
                                          "content": .string(m.content ?? "")])])
                case .assistant:
                    add("assistant", assistantBlocks(m, keepThinking: i > current))
                }
            }
            return turns.map { .object(["role": .string($0.role), "content": .array($0.blocks)]) }
        }

        static func text(_ s: String?) -> [JSONValue] {
            guard let s, !s.isEmpty else { return [] }
            return [.object(["type": .string("text"), "text": .string(s)])]
        }

        /// The reply's own blocks when it has them (thinking only within the current question), else its text and
        /// tool calls.
        static func assistantBlocks(_ m: Message, keepThinking: Bool) -> [JSONValue] {
            if case .array(let raw) = m.providerBlocks ?? .null {
                let kept = raw.filter { b in
                    let t = b["type"]?.string ?? ""
                    return t == "text" || t == "tool_use" || (keepThinking && (t == "thinking" || t == "redacted_thinking"))
                }
                if !kept.isEmpty { return kept }
            }
            let calls: [JSONValue] = (m.toolCalls ?? []).map { c in
                .object(["type": .string("tool_use"), "id": .string(c.id), "name": .string(c.function.name),
                         "input": JSONValue.parse(c.function.arguments) ?? .object([:])])
            }
            return text(m.content) + calls
        }

        // MARK: Reply

        /// The model's message from a Messages API response, or why there is none.
        public static func reply(_ data: Data, status: Int) throws -> Message {
            let json = JSONValue.parse(String(decoding: data, as: UTF8.self))
            guard (200..<300).contains(status) else {
                let message = String((json?["error"]?["message"]?.string ?? "").prefix(200))
                switch status {
                case 401, 403: throw OpenAI.Failure.badKey
                case 429, 529: throw OpenAI.Failure.busy
                default: throw OpenAI.Failure.server(status, message)
                }
            }
            if json?["stop_reason"]?.string == "refusal" {
                return Message(role: .assistant, content: "ผู้ช่วยไม่ตอบคำถามนี้ (ระบบความปลอดภัยของผู้ให้บริการ) ลองถามใหม่ด้วยถ้อยคำอื่น")
            }
            guard case .array(var blocks) = json?["content"] ?? .null else { throw OpenAI.Failure.badReply }
            // after a fallback, what came before its marker is the declined model's: only its text stays
            if let cut = blocks.lastIndex(where: { $0["type"]?.string == "fallback" }) {
                blocks = blocks[..<cut].filter { $0["type"]?.string == "text" } + blocks[(cut + 1)...]
            }
            var words: [String] = [], calls: [ToolCall] = []
            for b in blocks {
                switch b["type"]?.string {
                case "text": if let t = b["text"]?.string, !t.isEmpty { words.append(t) }
                case "tool_use":
                    guard let id = b["id"]?.string, let name = b["name"]?.string, Toolbox.names.contains(name) else {
                        return Message(role: .assistant, content: words.isEmpty ? "ผู้ช่วยขอใช้เครื่องมือที่ไม่ได้รับอนุญาต" : words.joined(separator: "\n"))
                    }
                    calls.append(ToolCall(id: id, name: name, arguments: Toolbox.encode(b["input"] ?? .object([:]))))
                default: continue
                }
            }
            let content = words.isEmpty ? nil : words.joined(separator: "\n")
            guard !calls.isEmpty || content != nil else { throw OpenAI.Failure.badReply }
            var m = Message(role: .assistant, content: content, toolCalls: calls.isEmpty ? nil : calls)
            m.providerBlocks = .array(blocks.filter { ["text", "tool_use", "thinking", "redacted_thinking"].contains($0["type"]?.string ?? "") })
            return m
        }
    }
}
