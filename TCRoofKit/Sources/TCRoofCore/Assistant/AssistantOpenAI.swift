import Foundation

public extension Assistant {

    /// Talking to Qwen's OpenAI-compatible endpoint straight from the device (the key kept in its Keychain), the same
    /// checks the Cloud Function makes (functions/src/guard.ts): the reply keeps only the fields the app reads, and a
    /// call to a tool the app doesn't have becomes words.
    enum OpenAI {
        public static let defaultBaseURL = "https://maas.qwencloudapi.com/compatible-mode/v1"
        public static let defaultModel = "qwen-plus"
        public static let maxTokens = 1_500
        /// Requests a device may send per Bangkok day.
        public static let dailyLimit = 50

        public enum Failure: Error, Equatable, LocalizedError {
            case noKey
            case badKey
            case limit(Int)
            case busy
            case server(Int, String)
            case badReply

            public var errorDescription: String? {
                switch self {
                case .noKey: "ยังไม่ได้ใส่คีย์ Qwen ในเครื่องนี้ ให้ผู้จัดการใส่ที่ ตั้งค่า › ผู้ช่วยโครงการ (AI)"
                case .badKey: "คีย์ Qwen ใช้ไม่ได้หรือหมดอายุ ให้ผู้จัดการตรวจที่ ตั้งค่า › ผู้ช่วยโครงการ (AI)"
                case .limit(let n): "เครื่องนี้ใช้ผู้ช่วยครบ \(n) ครั้งของวันนี้แล้ว"
                case .busy: "ผู้ช่วยมีคนใช้มาก ลองอีกครั้งในอีกสักครู่"
                case .server(let status, let message): "ผู้ช่วยขัดข้อง (\(status))" + (message.isEmpty ? "" : ": \(message)")
                case .badReply: "ผู้ช่วยไม่ได้ตอบ ลองอีกครั้ง"
                }
            }
        }

        private struct Body: Encodable {
            let model: String
            let messages: [Message]
            let tools: [JSONValue]?
            let tool_choice: String?
            let max_tokens: Int
            let temperature: Double
        }

        /// The chat completion request. A request without tools (the connection test) sends no `tool_choice`.
        public static func body(_ request: Request, model: String) throws -> Data {
            let tools = request.tools.isEmpty ? nil : request.tools
            return try JSONEncoder().encode(Body(model: model, messages: request.messages, tools: tools,
                                                 tool_choice: tools == nil ? nil : "auto", max_tokens: maxTokens, temperature: 0.2))
        }

        public static func url(base: String) -> URL? {
            var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
            while b.hasSuffix("/") { b.removeLast() }
            guard b.hasPrefix("https://") else { return nil }
            return URL(string: b + "/chat/completions")
        }

        /// The model's message from a response, or why there is none. `status` is the HTTP status.
        public static func reply(_ data: Data, status: Int) throws -> Message {
            let json = JSONValue.parse(String(decoding: data, as: UTF8.self))
            guard (200..<300).contains(status) else {
                let message = String((json?["error"]?["message"]?.string ?? "").prefix(200))
                switch status {
                case 401, 403: throw Failure.badKey
                case 429: throw Failure.busy
                default: throw Failure.server(status, message)
                }
            }
            guard case .array(let choices) = json?["choices"] ?? .null, let m = choices.first?["message"] else { throw Failure.badReply }
            let content = m["content"]?.string
            var calls: [ToolCall] = []
            if case .array(let raw) = m["tool_calls"] ?? .null {
                for c in raw {
                    guard let id = c["id"]?.string, let name = c["function"]?["name"]?.string,
                          Toolbox.names.contains(name) else {
                        return Message(role: .assistant, content: content ?? "ผู้ช่วยขอใช้เครื่องมือที่ไม่ได้รับอนุญาต")
                    }
                    calls.append(ToolCall(id: id, name: name, arguments: c["function"]?["arguments"]?.string ?? "{}"))
                }
            }
            guard !calls.isEmpty || content?.isEmpty == false else { throw Failure.badReply }
            return Message(role: .assistant, content: content, toolCalls: calls.isEmpty ? nil : calls)
        }

        /// The Bangkok day a request counts against, as `yyyy-MM-dd`.
        public static func day(_ now: Date) -> String { ScheduleBrief.day(now, calendar: MasterSchedule.calendar) }
    }
}
