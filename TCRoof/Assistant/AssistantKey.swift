import Foundation
import Security
import TCRoofCore

/// The AI keys on this device (docs/specs/project-assistant-qwen.md §7): one per provider (`Assistant.Provider`), in
/// the Keychain, this device only (never synced, never in a backup), entered by a manager in ตั้งค่า › ผู้ช่วยโครงการ
/// (AI). The provider in use, and each provider's model and endpoint, are plain defaults. Qwen keeps the Keychain item
/// and defaults it had before there were others, so a key saved then still works.
enum AssistantKey {
    private static let account = "apiKey"
    private static func service(_ p: Assistant.Provider) -> String { "com.tcroof.assistant." + p.rawValue }

    /// The provider the assistant uses on this device.
    static var provider: Assistant.Provider {
        get { UserDefaults.standard.string(forKey: "assistant.provider").flatMap(Assistant.Provider.init(rawValue:)) ?? .qwen }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "assistant.provider") }
    }

    static func key(_ p: Assistant.Provider) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service(p),
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s = String(decoding: d, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    /// Whether the provider in use has a key on this device.
    static var hasActiveKey: Bool { key(provider) != nil }
    static func hasKey(_ p: Assistant.Provider) -> Bool { key(p) != nil }

    @discardableResult
    static func save(_ key: String, for p: Assistant.Provider) -> Bool {
        remove(p)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service(p),
                                kSecAttrAccount as String: account, kSecValueData as String: Data(key.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func remove(_ p: Assistant.Provider) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service(p),
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }

    /// Qwen's settings keep their names from before (`assistant.model`); the others are `assistant.model.<id>`.
    private static func defaultsKey(_ name: String, _ p: Assistant.Provider) -> String {
        p == .qwen ? "assistant." + name : "assistant.\(name).\(p.rawValue)"
    }

    static func model(_ p: Assistant.Provider) -> String {
        UserDefaults.standard.string(forKey: defaultsKey("model", p)).flatMap { $0.isEmpty ? nil : $0 } ?? p.defaultModel
    }
    static func setModel(_ m: String, for p: Assistant.Provider) {
        UserDefaults.standard.set(m.trimmingCharacters(in: .whitespacesAndNewlines), forKey: defaultsKey("model", p))
    }

    static func baseURL(_ p: Assistant.Provider) -> String {
        UserDefaults.standard.string(forKey: defaultsKey("baseURL", p)).flatMap { $0.isEmpty ? nil : $0 } ?? p.defaultBaseURL
    }
    static func setBaseURL(_ u: String, for p: Assistant.Provider) {
        UserDefaults.standard.set(u.trimmingCharacters(in: .whitespacesAndNewlines), forKey: defaultsKey("baseURL", p))
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

/// An AI provider straight from the device with the key in its Keychain, at most `dailyLimit` questions a day on this
/// device (their tool rounds free, up to `dailyRequestLimit` requests in all): the OpenAI-style chat format, or
/// Anthropic's Messages API for Claude.
struct DirectAIClient: Assistant.Transport {
    var provider: Assistant.Provider
    var key: String
    var model: String
    var baseURL: String

    /// The provider in use with its saved settings, nil without a key.
    static var saved: DirectAIClient? {
        let p = AssistantKey.provider
        return AssistantKey.key(p).map { DirectAIClient(provider: p, key: $0, model: AssistantKey.model(p), baseURL: AssistantKey.baseURL(p)) }
    }

    func complete(_ request: Assistant.Request) async throws -> Assistant.Reply {
        typealias O = Assistant.OpenAI
        typealias A = Assistant.Anthropic
        let claude = provider.api == .anthropic
        guard let url = claude ? A.url(base: baseURL) : O.url(base: baseURL) else {
            throw O.Failure.server(0, "ที่อยู่ API ต้องขึ้นต้นด้วย https://")
        }
        let limit = O.dailyLimit
        let question = request.isNewQuestion
        guard !question || AssistantKey.used() < limit, AssistantKey.requests() < O.dailyRequestLimit else {
            throw O.Failure.limit(limit)
        }
        // counted before the call, as the function does, so a failing loop still stops
        let used = AssistantKey.count(question: question)
        var r = URLRequest(url: url, timeoutInterval: claude ? 180 : 90)
        r.httpMethod = "POST"
        if claude {
            for (k, v) in A.headers(key: key, model: model) { r.setValue(v, forHTTPHeaderField: k) }
            r.httpBody = try A.body(request, model: model)
        } else {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            r.httpBody = try O.body(request, model: model, provider: provider)
        }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: r) } catch let e as URLError {
            throw O.Failure.server(0, e.code == .timedOut ? "ตอบช้าเกินไป ลองอีกครั้ง" : "ติดต่อไม่ได้ ตรวจสอบอินเทอร์เน็ต")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let message = claude ? try A.reply(data, status: status) : try O.reply(data, status: status)
        return Assistant.Reply(message: message, remainingToday: max(limit - used, 0))
    }
}

/// Picks the way to the AI at each request, so a key entered while the chat is open counts: the key of the provider in
/// use on this device, else the `assistant` Cloud Function (Qwen with the function's key).
struct AssistantRouter: Assistant.Transport {
    func complete(_ request: Assistant.Request) async throws -> Assistant.Reply {
        if let client = DirectAIClient.saved {
            return try await client.complete(request)
        }
        // the function isn't deployed (or nobody is signed in): what this device lacks is a key
        do { return try await AssistantClient().complete(request) } catch let e as AssistantClient.Failure where e == .unavailable || e == .signedOut {
            throw Assistant.OpenAI.Failure.noKey
        }
    }
}
