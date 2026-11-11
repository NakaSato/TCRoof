import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Growatt's server OpenAPI v1 (growatt.pl's "Growatt Server Open API protocol standards" and "Growatt Server API Guide",
/// 2016): every call that reads (plants, their energy and power, dataloggers, devices, inverter and storage readings
/// and alarms, end users). Every answer is `{ data, error_code, error_msg }`; every request carries the header `token`.
///
/// Only reads are ported. The guide's calls that change something on Growatt (`user_register`, `user/modify`,
/// `plant/add`, `plant/modify`, `plant/delete`, `datalogger/add`, `datalogger/delete`, `inverterSet`, `storageSet`)
/// are left out on purpose: `inverterSet` and `storageSet` switch equipment on and off. The guide makes some reads
/// POSTs (`plant/user_plant_list`, `device/inverter/invs_data`, `device/storage/*`); those send a form body.
///
/// `demo` is the guide's public test server and token, whose plants are other developers' samples with no inverters. A
/// company's own plants need its own token from Growatt on `openapi.growatt.com`, which refuses the test token (10011).
/// Endpoints and what is confirmed about them: docs/specs/growatt-api.md.
public struct GrowattAPI: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// `error_code` other than 0: 10011 permission denied, 10004 a date range it won't take, and so on.
        case api(Int, String)
        /// 10012 `error_frequently_access`, still after the retries.
        case tooFrequent
        case http(Int), offline, badResponse
        /// The web portal (`GrowattPortal`) answered with its login page: the session's cookies are gone or expired.
        case signedOut

        public var message: String {
            switch self {
            case .api(10011, _): "Growatt ไม่อนุญาต (token ไม่ถูกต้อง)"
            case .api(let c, let m): "Growatt ตอบกลับผิดพลาด (\(c)\(m.isEmpty ? "" : " " + m))"
            case .tooFrequent: "เรียก Growatt ถี่เกินไป | ลองใหม่อีกครั้ง"
            case .http(let c): "Growatt ตอบกลับผิดพลาด (HTTP \(c))"
            case .offline: "ไม่มีสัญญาณอินเทอร์เน็ต | ลองใหม่อีกครั้ง"
            case .badResponse: "อ่านข้อมูลจาก Growatt ไม่ได้"
            case .signedOut: "เซสชัน Growatt หมดอายุ | เข้าสู่ระบบใหม่"
            }
        }
    }

    /// One page of a paged call: the page's rows and the total `count` Growatt reports (nil when it doesn't).
    public struct Page<Item: Sendable>: Sendable {
        public var items: [Item]
        public var count: Int?

        public init(items: [Item], count: Int?) { self.items = items; self.count = count }
    }

    public var baseURL: URL
    public var token: String
    public var session: URLSession = .shared
    public var timeout: TimeInterval = 20
    /// Retries after 10012, waiting `retryDelay` × the attempt (6, 12, 18 s): calls about 6 s apart worked on the test
    /// server, but its token is shared with every developer trying it, so one wait isn't always enough.
    public var retries = 3
    public var retryDelay: TimeInterval = 6
    /// Paces the calls (`GrowattGate`): with one, a call repeated too soon is refused before it is sent and a 10012
    /// isn't retried. Nil (the default) sends every call, with `retries`.
    public var gate: GrowattGate?

    /// `baseURL` ends in `/v1/`; the token is trimmed (a pasted one often brings a newline).
    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The API guide's test server and its published test token.
    public static let demo = GrowattAPI(baseURL: URL(string: "https://test.growatt.com/v1/")!, token: "6eb6f069523055a339d71e5b1f6c88cc")

    /// Growatt's live server, for a company's own token (`openapi-us` and `openapi-au` answer the same way; `openapi-cn`
    /// didn't answer from Thailand).
    public static let openAPIURL = URL(string: "https://openapi.growatt.com/v1/")!

    /// The live server with a company's token.
    public static func live(token: String) -> GrowattAPI { GrowattAPI(baseURL: openAPIURL, token: token) }

    /// True on the test server, whose plants are samples.
    public var isDemo: Bool { baseURL.host == Self.demo.baseURL.host }

    /// The guide's page size limit for most paged calls.
    public static let maxPerPage = 100

    static func perPage(_ n: Int, max: Int = maxPerPage) -> String { "\(min(Swift.max(n, 1), max))" }

    // MARK: transport

    /// A GET of `path` (under `baseURL`) with `query`; the answer's bytes once `error_code` is 0. For a call this SDK
    /// doesn't wrap.
    public func get(_ path: String, _ query: [String: String]) async throws -> Data {
        var c = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: c.url!, timeoutInterval: timeout)
        request.setValue(token, forHTTPHeaderField: "token")
        return try await send(request, call: path + "?" + (c.percentEncodedQuery ?? ""))
    }

    /// A POST of `path` with `form` as `application/x-www-form-urlencoded`, for the reads the guide makes POSTs.
    public func post(_ path: String, _ form: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "token")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let body = Self.formBody(form)
        request.httpBody = Data(body.utf8)
        return try await send(request, call: path + "?" + body)
    }

    /// `a=1&b=x%20y`, keys sorted.
    static func formBody(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        func esc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        return form.sorted { $0.key < $1.key }.map { esc($0.key) + "=" + esc($0.value) }.joined(separator: "&")
    }

    /// `call` names the request for the gate: its path and query or form.
    private func send(_ request: URLRequest, call: String) async throws -> Data {
        if let gate {
            try await gate.admit(token: token, call: call)
            let (data, response): (Data, URLResponse)
            // a call that didn't reach Growatt's API (no network, cancelled, an HTTP error) gives its slot back
            do { (data, response) = try await session.data(for: request) } catch {
                await gate.release(token: token, call: call)
                throw Failure.offline
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                await gate.release(token: token, call: call)
                throw Failure.http(http.statusCode)
            }
            let head = try Self.head(data)
            if head.code == 10012 {
                await gate.refused(token: token, call: call)
                throw Failure.tooFrequent
            }
            guard head.code == 0 else { throw Failure.api(head.code, head.message) }
            return data
        }
        for attempt in 1...(retries + 1) {
            let data: Data, response: URLResponse
            do { (data, response) = try await session.data(for: request) } catch { throw Failure.offline }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.http(http.statusCode) }
            let head = try Self.head(data)
            if head.code == 10012 {
                guard attempt <= retries else { throw Failure.tooFrequent }
                try await Task.sleep(nanoseconds: UInt64(retryDelay * Double(attempt) * 1_000_000_000))
                continue
            }
            guard head.code == 0 else { throw Failure.api(head.code, head.message) }
            return data
        }
        throw Failure.tooFrequent
    }

    // MARK: parsing

    /// An answer's structure with every value hidden, on one line: keys, types, list lengths, and `error_code` /
    /// `error_msg` (Growatt's own words). For showing what Growatt sent without showing the account's data:
    /// `error_code: 0 · data{count: number 0, plants: [] (empty)}`.
    public static func outline(_ data: Data) -> String {
        guard let o = try? JSONSerialization.jsonObject(with: data) else { return "ไม่ใช่ JSON (\(data.count) ไบต์)" }
        func shape(_ v: Any) -> String {
            switch v {
            // a list's total (`count`, `total`) is shown: it tells an empty account from a page that came back empty
            case let o as [String: Any]: return "{" + o.keys.sorted().map { k in
                let total = ["count", "total"].contains(k) ? number(o[k]).map { " \(Int($0))" } : nil
                return "\(k): " + (total.map { "number" + $0 } ?? shape(o[k]!))
            }.joined(separator: ", ") + "}"
            case let a as [Any]: return a.first.map { "[\(a.count)× " + shape($0) + "]" } ?? "[] (empty)"
            case is NSNull: return "null"
            case let n as NSNumber: return Self.isBool(n) ? "bool" : "number"
            case let s as String: return s.isEmpty ? "\"\"" : "text"
            default: return "\(type(of: v))"
            }
        }
        guard let d = o as? [String: Any] else { return shape(o) }
        var parts: [String] = []
        if let c = d["error_code"] { parts.append("error_code: \(c)") }
        if let m = d["error_msg"] as? String, !m.isEmpty { parts.append("error_msg: \(m)") }
        let rest = d.filter { $0.key != "error_code" && $0.key != "error_msg" }
        parts += rest.keys.sorted().map { k in k + (rest[k] is [String: Any] ? "" : ": ") + shape(rest[k]!) }
        return parts.joined(separator: " · ")
    }

    /// Whether JSONSerialization read `n` from `true` / `false`. CoreFoundation's type check isn't public on Linux;
    /// there an NSNumber made from a Bool reports the `c` (char) type.
    static func isBool(_ n: NSNumber) -> Bool {
        #if canImport(Darwin)
        return CFGetTypeID(n) == CFBooleanGetTypeID()
        #else
        return String(cString: n.objCType) == "c"
        #endif
    }

    /// `error_code` (0 when missing) and `error_msg`.
    public static func head(_ data: Data) throws -> (code: Int, message: String) {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.badResponse }
        return (Self.number(o["error_code"]).map { Int($0) } ?? 0, o["error_msg"] as? String ?? "")
    }

    static func body(_ data: Data) throws -> [String: Any] {
        let head = try head(data)
        guard head.code == 0 else { throw Failure.api(head.code, head.message) }
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let body = o["data"] as? [String: Any] else { throw Failure.badResponse }
        return body
    }

    /// The whole answer as `JSONValue`, after checking `error_code`.
    static func document(_ data: Data) throws -> JSONValue {
        let head = try head(data)
        guard head.code == 0 else { throw Failure.api(head.code, head.message) }
        guard let doc = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw Failure.badResponse }
        return doc
    }

    /// `data` of the answer as an object.
    static func dataObject(_ data: Data) throws -> [String: JSONValue] {
        guard let o = try document(data)["data"]?.object else { throw Failure.badResponse }
        return o
    }

    /// Growatt writes booleans as booleans or as text ("true", "false").
    public static func bool(_ v: Any?) -> Bool? {
        switch v {
        case let b as Bool: b
        case let n as NSNumber: n.intValue != 0
        case let s as String:
            switch s.lowercased() {
            case "true", "1": true
            case "false", "0": false
            default: nil
            }
        default: nil
        }
    }

    /// Growatt sends numbers as numbers or as text ("0", "-1.0"); null and "" are nil.
    public static func number(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }
}
