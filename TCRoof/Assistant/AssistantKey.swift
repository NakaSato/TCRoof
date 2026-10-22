import Foundation
import Security
import TCRoofCore

/// The Qwen key on this device (docs/specs/project-assistant-qwen.md §7): in the Keychain, this device only (never
/// synced, never in a backup), entered by a manager in ตั้งค่า › ผู้ช่วยโครงการ (AI). The model and the endpoint are
/// plain defaults.
enum AssistantKey {
    private static let service = "com.tcroof.assistant.qwen"
    private static let account = "apiKey"

    static var key: String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s = String(decoding: d, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    static var hasKey: Bool { key != nil }

    @discardableResult
    static func save(_ key: String) -> Bool {
        remove()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: Data(key.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func remove() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: "assistant.model").flatMap { $0.isEmpty ? nil : $0 } ?? Assistant.OpenAI.defaultModel }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "assistant.model") }
    }

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: "assistant.baseURL").flatMap { $0.isEmpty ? nil : $0 } ?? Assistant.OpenAI.defaultBaseURL }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "assistant.baseURL") }
    }

    /// Questions this device asked today (Bangkok day); kept per day, so it resets at midnight.
    static func used(_ now: Date = .now) -> Int { UserDefaults.standard.integer(forKey: "assistant.used." + Assistant.OpenAI.day(now)) }
    /// Requests sent today, tool rounds included.
    static func requests(_ now: Date = .now) -> Int { UserDefaults.standard.integer(forKey: "assistant.requests." + Assistant.OpenAI.day(now)) }
    /// Counts a request, and a question when it starts one; returns the questions asked today.
    static func count(question: Bool, _ now: Date = .now) -> Int {
        let day = Assistant.OpenAI.day(now), d = UserDefaults.standard
        d.set(requests(now) + 1, forKey: "assistant.requests." + day)
        let n = used(now) + (question ? 1 : 0)
        d.set(n, forKey: "assistant.used." + day)
        return n
    }
}

/// Qwen straight from the device with the key in its Keychain, at most `dailyLimit` questions a day on this device
/// (their tool rounds free, up to `dailyRequestLimit` requests in all).
struct QwenDirectClient: Assistant.Transport {
    var key: String
    var model: String
    var baseURL: String

    func complete(_ request: Assistant.Request) async throws -> Assistant.Reply {
        typealias O = Assistant.OpenAI
        guard let url = O.url(base: baseURL) else { throw O.Failure.server(0, "ที่อยู่ต้องขึ้นต้นด้วย https://") }
        let limit = O.dailyLimit
        let question = request.isNewQuestion
        guard !question || AssistantKey.used() < limit, AssistantKey.requests() < O.dailyRequestLimit else {
            throw O.Failure.limit(limit)
        }
        // counted before the call, as the function does, so a failing loop still stops
        let used = AssistantKey.count(question: question)
        var r = URLRequest(url: url, timeoutInterval: 90)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.httpBody = try O.body(request, model: model)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: r) } catch let e as URLError {
            throw O.Failure.server(0, e.code == .timedOut ? "ตอบช้าเกินไป ลองอีกครั้ง" : "ติดต่อไม่ได้ ตรวจสอบอินเทอร์เน็ต")
        }
        let message = try O.reply(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        return Assistant.Reply(message: message, remainingToday: max(limit - used, 0))
    }
}

/// Picks the way to Qwen at each request, so a key entered while the chat is open counts: the key on this device,
/// else the `assistant` Cloud Function.
struct AssistantRouter: Assistant.Transport {
    func complete(_ request: Assistant.Request) async throws -> Assistant.Reply {
        if let key = AssistantKey.key {
            return try await QwenDirectClient(key: key, model: AssistantKey.model, baseURL: AssistantKey.baseURL).complete(request)
        }
        // the function isn't deployed (or nobody is signed in): what this device lacks is a key
        do { return try await AssistantClient().complete(request) } catch let e as AssistantClient.Failure where e == .unavailable || e == .signedOut {
            throw Assistant.OpenAI.Failure.noKey
        }
    }
}
