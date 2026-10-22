import Foundation

/// The project assistant's messages, in the OpenAI-compatible chat format the Qwen endpoint takes. The app sends them
/// through the `assistant` Cloud Function (functions/), which holds the API key.
public enum Assistant {

    public struct ToolCall: Codable, Equatable, Sendable {
        public struct Function: Codable, Equatable, Sendable {
            public var name: String
            /// JSON text, as the model wrote it.
            public var arguments: String
            public init(name: String, arguments: String) { self.name = name; self.arguments = arguments }
        }
        public var id: String
        public var type = "function"
        public var function: Function

        public init(id: String, name: String, arguments: String) {
            self.id = id
            function = Function(name: name, arguments: arguments)
        }
    }

    public struct Message: Codable, Equatable, Sendable {
        public enum Role: String, Codable, Sendable { case system, user, assistant, tool }
        public var role: Role
        public var content: String?
        public var toolCalls: [ToolCall]?
        public var toolCallID: String?
        /// The provider's own content blocks of an assistant reply, sent back as they came (Claude's `thinking` blocks
        /// must be). Kept on the device only: never encoded, so OpenAI-style bodies and the function never see it.
        public var providerBlocks: JSONValue? = nil

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }

        public init(role: Role, content: String?, toolCalls: [ToolCall]? = nil, toolCallID: String? = nil) {
            self.role = role; self.content = content; self.toolCalls = toolCalls; self.toolCallID = toolCallID
        }

        /// `content` is always written (null with only tool calls), as OpenAI-style endpoints expect.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(role, forKey: .role)
            try c.encode(content, forKey: .content)
            try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
            try c.encodeIfPresent(toolCallID, forKey: .toolCallID)
        }

        public static func system(_ text: String) -> Message { Message(role: .system, content: text) }
        public static func user(_ text: String) -> Message { Message(role: .user, content: text) }
        public static func tool(_ id: String, _ text: String) -> Message { Message(role: .tool, content: text, toolCallID: id) }
    }

    /// What the app sends to the function.
    public struct Request: Codable, Equatable, Sendable {
        public var messages: [Message]
        public var tools: [JSONValue]
        public init(messages: [Message], tools: [JSONValue]) { self.messages = messages; self.tools = tools }

        /// It starts a new question (ends with the person's message), not a tool round of one: what the daily limit
        /// counts.
        public var isNewQuestion: Bool { messages.last?.role == .user }
    }

    /// What the function returns: the model's message and the person's requests left today.
    public struct Reply: Codable, Equatable, Sendable {
        public var message: Message
        public var remainingToday: Int?
        public init(message: Message, remainingToday: Int? = nil) { self.message = message; self.remainingToday = remainingToday }
    }

    /// Sends one request; the app's is the Cloud Function, tests stub it.
    public protocol Transport: Sendable {
        func complete(_ request: Request) async throws -> Reply
    }

    public enum Failure: Error, Equatable, LocalizedError {
        /// The model kept calling tools past the round limit.
        case tooManyRounds
        case emptyReply

        public var errorDescription: String? {
            switch self {
            case .tooManyRounds: "ผู้ช่วยใช้ข้อมูลหลายรอบเกินไป ลองถามให้แคบลง"
            case .emptyReply: "ผู้ช่วยไม่ได้ตอบ ลองอีกครั้ง"
            }
        }
    }
}

/// Any JSON value, for tool schemas and tool arguments.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var string: String? {
        switch self {
        case .string(let s): s
        case .number(let n): n == n.rounded() ? String(Int(n)) : String(n)
        default: nil
        }
    }

    public var number: Double? {
        switch self {
        case .number(let n): n
        case .string(let s): Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: ""))
        default: nil
        }
    }

    public static func parse(_ text: String) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
}
