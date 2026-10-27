import Foundation

public extension Assistant {

    /// A conversation kept on this device, so the chat carries on where it was left: the messages after the system
    /// prompt (written fresh with today's date when it opens again).
    struct SavedChat: Codable, Equatable, Sendable {
        public var messages: [Message]
        public var savedAt: Date
        public init(messages: [Message], savedAt: Date) { self.messages = messages; self.savedAt = savedAt }
    }

    /// The saved conversations, one file per account and per station the chat was opened from (`focus`, nil for
    /// the all-stations chat): `<folder>/<account>/<focus or all>.json`. Nothing leaves the device.
    struct History: Sendable {
        public let folder: URL
        /// A conversation untouched this long starts over.
        public static let keepDays = 30
        /// Messages kept; older turns are dropped whole.
        public static let maxMessages = 200

        public init(folder: URL) { self.folder = folder }

        public func url(account: String, focus: String?) -> URL {
            folder.appendingPathComponent(Self.safe(account.isEmpty ? "local" : account), isDirectory: true)
                .appendingPathComponent(Self.safe(focus ?? "all") + ".json")
        }

        /// The conversation saved for `account` and `focus`, nil when there is none or it is older than `keepDays`.
        public func load(account: String, focus: String?, now: Date = .now) -> SavedChat? {
            guard let data = try? Data(contentsOf: url(account: account, focus: focus)),
                  let chat = try? Self.decoder.decode(SavedChat.self, from: data), !chat.messages.isEmpty,
                  now.timeIntervalSince(chat.savedAt) < Double(Self.keepDays) * 86_400 else { return nil }
            return chat
        }

        /// Writes `messages` (a session's `history`); an empty list removes the file.
        public func save(_ messages: [Message], account: String, focus: String?, now: Date = .now) {
            let u = url(account: account, focus: focus)
            guard !messages.isEmpty else { try? FileManager.default.removeItem(at: u); return }
            guard let data = try? Self.encoder.encode(SavedChat(messages: messages, savedAt: now)) else { return }
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: u, options: .atomic)
        }

        public func clear(account: String, focus: String?) { save([], account: account, focus: focus) }

        /// Every account's conversations.
        public func removeAll() { try? FileManager.default.removeItem(at: folder) }

        private static func safe(_ s: String) -> String {
            let ok = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@.-_"))
            let out = String(String.UnicodeScalarView(s.lowercased().unicodeScalars.map { ok.contains($0) ? $0 : "_" }))
            return out.hasPrefix(".") ? "_" + out : out
        }

        private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
        private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    }
}

public extension Assistant.Session {

    /// What is kept on the device: the messages after the system prompt, tool results shortened as every later
    /// question sends them anyway, at most `History.maxMessages` starting at a person's message, and a note for each
    /// card still open (it is not restored: the plan may have moved on by the time the chat opens again).
    var history: [Assistant.Message] {
        var rest = messages.dropFirst().map(Self.compacted)
        rest += proposals.map { .user("[ระบบ] \($0.station) | \($0.title): \($0.after) — ปิดแชตก่อนยืนยัน ไม่ได้บันทึก") }
        guard rest.count > Assistant.History.maxMessages else { return rest }
        var start = rest.count - Assistant.History.maxMessages
        while start < rest.count, rest[start].role != .user { start += 1 }
        return Array(rest[start...])
    }
}
