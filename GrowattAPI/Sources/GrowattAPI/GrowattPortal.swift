import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Growatt's web portal (`server.growatt.com`) for a signed-in account: the calls its own pages make, captured from a
/// browser (docs/specs/growatt-api.md, section 3). Growatt doesn't document them and may change them; the OpenAPI
/// (`GrowattAPI`) is the one to build on, and covers inverter faults with `alarms(deviceSN:)`.
///
/// The portal needs a browser session: the cookies `JSESSIONID` and `assToken` from a signed-in account, given with
/// `useCookies(_:)`; the client sends them itself and keeps the ones the portal renews. Signing in from code (username and password) isn't ported: its request hasn't been captured. A
/// session that is gone answers with the login page, which throws `GrowattAPI.Failure.signedOut`. Treat the cookies as
/// the account's password: they are, until the session ends.
///
/// The answers' row fields aren't confirmed yet, so each row comes back whole as `JSONValue`.
public struct GrowattPortal: Sendable {
    /// One page of a portal list: `{ result: 1, obj: { currPage, pages, pageSize, count, datas: [...] } }` as the
    /// portal's other lists answer (`panel/getDevicesByPlantList`).
    public struct Page: Sendable {
        public var rows: [JSONValue]
        public var page: Int
        /// At least 1.
        public var pages: Int
        public var count: Int?
        /// The whole answer, for what `rows` doesn't cover.
        public var raw: JSONValue
    }

    /// The session's cookies by name: what `useCookies(_:)` gave and what the portal's answers set since.
    final class CookieJar: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]
        private var order: [String] = []

        func set(_ name: String, _ value: String) {
            lock.lock(); defer { lock.unlock() }
            if values[name] == nil { order.append(name) }
            values[name] = value
        }
        var all: [(name: String, value: String)] {
            lock.lock(); defer { lock.unlock() }
            return order.compactMap { n in values[n].map { (n, $0) } }
        }
        /// The `Cookie` header; nil when empty.
        var header: String? { let a = all; return a.isEmpty ? nil : a.map { "\($0.name)=\($0.value)" }.joined(separator: "; ") }
    }

    public var baseURL = URL(string: "https://server.growatt.com/")!
    /// Seconds without an answer before a call fails.
    public var timeout: TimeInterval = 30
    public let session: URLSession
    let jar = CookieJar()

    /// The session sends the cookies itself (`httpShouldSetCookies` off), so one account's stay in this value.
    public init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: config)
    }

    /// Puts a signed-in browser's cookies into this session: the `Cookie` header's text (`JSESSIONID=…; assToken=…`).
    /// Returns the names taken.
    @discardableResult
    public func useCookies(_ header: String) -> [String] {
        var names: [String] = []
        for part in header.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, !pair[0].isEmpty else { continue }
            jar.set(pair[0], pair[1])
            names.append(pair[0])
        }
        return names
    }

    /// Whether the session holds the cookies a signed-in page needs.
    public var hasSession: Bool {
        let names = Set(jar.all.map(\.name))
        return names.contains("JSESSIONID") && names.contains("assToken")
    }

    // MARK: calls

    /// `selectPlant/getPlantList`: the account's plants, a page at a time (the portal's own page size). `name` filters
    /// by plant name; `plantType` -1 is every type; `orderType` 2 is the portal's default order.
    public func plantList(page: Int = 1, name: String = "", plantType: Int = -1, orderType: Int = 2) async throws -> Page {
        try Self.parsePage(try await post("selectPlant/getPlantList", ["currPage": "\(max(page, 1))", "plantType": "\(plantType)",
                                                                        "orderType": "\(orderType)", "plantName": name]))
    }

    /// Every plant of the account, page after page until `pages` (at most `maxPages`).
    public func allPlants(name: String = "", maxPages: Int = 50) async throws -> [JSONValue] {
        var rows: [JSONValue] = []
        var page = 1
        while page <= max(maxPages, 1) {
            let p = try await plantList(page: page, name: name)
            rows += p.rows
            if page >= p.pages || p.rows.isEmpty { break }
            page += 1
        }
        return rows
    }

    /// The fault log's period: the form's `type` and the shape of its `date` (from captured requests: 1 with
    /// `2026-11-09`, 2 with `2026-11`, 3 with `2026`).
    public enum LogPeriod: Int, Sendable, CaseIterable {
        case day = 1, month = 2, year = 3

        /// `yyyy-MM-dd`, `yyyy-MM` or `yyyy` of `date` in `timeZone` (the plant's clock).
        public func dateText(_ date: Date, timeZone: TimeZone) -> String {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let c = cal.dateComponents([.year, .month, .day], from: date)
            let y = c.year ?? 0, m = c.month ?? 0, d = c.day ?? 0
            switch self {
            case .day: return String(format: "%04d-%02d-%02d", y, m, d)
            case .month: return String(format: "%04d-%02d", y, m)
            case .year: return String(format: "%04d", y)
            }
        }
    }

    /// `log/getNewPlantFaultLog`: the faults of a day, a month or a year (`date` written as `period` wants it:
    /// `2026-11-09`, `2026-11`, `2026`), of every plant (`plantID` -1) or one, of every device (`deviceSN` empty) or
    /// one. `deviceFlag` 0 is what the Log page sends; what other values mean isn't known.
    public func faultLog(_ period: LogPeriod = .day, date: String, plantID: String = "-1", deviceSN: String = "",
                         page: Int = 1, deviceFlag: Int = 0) async throws -> Page {
        try Self.parsePage(try await post("log/getNewPlantFaultLog", ["deviceSn": deviceSN, "date": date, "plantId": plantID,
                                                                       "toPageNum": "\(max(page, 1))", "type": "\(period.rawValue)",
                                                                       "deviceFlag": "\(deviceFlag)"]))
    }

    /// The fault log of the period holding `date` (a day, month or year on the plant's clock).
    public func faultLog(_ period: LogPeriod, of date: Date, timeZone: TimeZone, plantID: String = "-1", deviceSN: String = "",
                         page: Int = 1) async throws -> Page {
        try await faultLog(period, date: period.dateText(date, timeZone: timeZone), plantID: plantID, deviceSN: deviceSN, page: page)
    }

    /// `energy/compare/getNewPlantDevices`: the devices of one plant that the portal's Energy › Compare page lists to
    /// pick from (`plantId` only). Its rows' fields aren't confirmed; they are the input of the page's chart calls
    /// (`energy/compare/getDevicesDayChart`).
    public func compareDevices(plantID: String) async throws -> Page {
        try Self.parsePage(try await post("energy/compare/getNewPlantDevices", ["plantId": plantID]))
    }

    /// One line the Compare page charts: a device (`type` as the portal names it: `max`, `tlx`, `mix`, …, or `plant`
    /// with the plant id as `sn`) and the value drawn (`energy`, `pac`, …).
    public struct ChartSeries: Equatable, Sendable {
        public var type: String
        public var sn: String
        public var params: String

        public init(type: String, sn: String, params: String) { self.type = type; self.sn = sn; self.params = params }
    }

    /// One answered line of a chart: its values in order, nil where the portal has none (a day not reached yet).
    public struct ChartLine: Equatable, Sendable {
        public var series: ChartSeries
        /// Every value list the line came with, by name (`energy`, `pac`, …).
        public var values: [String: [Double?]]

        /// The values of the series' own `params`.
        public var points: [Double?] { values[series.params] ?? [] }
    }

    /// `energy/compare/getDevicesDayChart`: the series through one day (`yyyy-MM-dd`), 288 values 5 minutes apart
    /// (`pac` in W, as `GrowattWebDemo` reads it).
    public func dayChart(plantID: String, date: String, series: [ChartSeries]) async throws -> [ChartLine] {
        try await chart("energy/compare/getDevicesDayChart", plantID: plantID, date: date, series: series)
    }

    /// `energy/compare/getDevicesMonthChart`: the series through one month (`yyyy-MM`), a value a day (`energy` in kWh).
    public func monthChart(plantID: String, month: String, series: [ChartSeries]) async throws -> [ChartLine] {
        try await chart("energy/compare/getDevicesMonthChart", plantID: plantID, date: month, series: series)
    }

    private func chart(_ path: String, plantID: String, date: String, series: [ChartSeries]) async throws -> [ChartLine] {
        try Self.parseChart(try await post(path, ["plantId": plantID, "date": date, "jsonData": Self.jsonData(series)]), series: series)
    }

    /// `jsonData` as the page sends it: `[{"type":"max","sn":"…","params":"energy"}]`, keys in that order.
    static func jsonData(_ series: [ChartSeries]) -> String {
        func q(_ s: String) -> String {
            let data = (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8)
            return String(decoding: data, as: UTF8.self)
        }
        return "[" + series.map { #"{"type":\#(q($0.type)),"sn":\#(q($0.sn)),"params":\#(q($0.params))}"# }.joined(separator: ",") + "]"
    }

    /// `{ result: 1, obj: [ { datas: { <param>: [values] } }, … ] }`, one entry per series asked, in the same order.
    public static func parseChart(_ data: Data, series: [ChartSeries]) throws -> [ChartLine] {
        guard let doc = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
            throw head.contains("<html") || head.contains("<!doctype") ? GrowattAPI.Failure.signedOut : GrowattAPI.Failure.badResponse
        }
        if let result = doc["result"]?.int, result != 1 {
            throw GrowattAPI.Failure.api(result, doc["msg"]?.text ?? "")
        }
        guard let entries = doc["obj"]?.array else { throw GrowattAPI.Failure.badResponse }
        return entries.enumerated().compactMap { i, e in
            guard let datas = e["datas"]?.object else { return nil }
            let asked = i < series.count ? series[i] : ChartSeries(type: e["type"]?.text ?? "", sn: e["sn"]?.text ?? "", params: datas.keys.sorted().first ?? "")
            let values = datas.compactMapValues { v in v.array.map { $0.map(\.number) } }
            return ChartLine(series: asked, values: values)
        }
    }

    /// A POST of `path` with `form`, as the portal's pages send it (an XMLHttpRequest from its own origin).
    public func post(_ path: String, _ form: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue(baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
        request.httpBody = Data(GrowattAPI.formBody(form).utf8)
        if let cookies = jar.header { request.setValue(cookies, forHTTPHeaderField: "Cookie") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw GrowattAPI.Failure.offline }
        if let http = response as? HTTPURLResponse {
            // the portal renews its cookies (`SERVERID`, sometimes `JSESSIONID`) as a browser's would be
            let fields = http.allHeaderFields.reduce(into: [String: String]()) { d, kv in
                if let k = kv.key as? String, let v = kv.value as? String { d[k] = v }
            }
            for c in HTTPCookie.cookies(withResponseHeaderFields: fields, for: request.url ?? baseURL) { jar.set(c.name, c.value) }
            if (300..<400).contains(http.statusCode) { throw GrowattAPI.Failure.signedOut }
            if !(200..<300).contains(http.statusCode) { throw GrowattAPI.Failure.http(http.statusCode) }
            if let url = http.url, url.path.lowercased().contains("login") { throw GrowattAPI.Failure.signedOut }
        }
        return data
    }

    // MARK: parsing

    /// `{ result: 1, obj: … }` with its rows in `obj.datas` (or `obj.data`, or `obj` itself as a list). HTML (the login
    /// page) is `signedOut`; a `result` other than 1 is `api(result, msg)`.
    public static func parsePage(_ data: Data) throws -> Page {
        guard let doc = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
            throw head.contains("<html") || head.contains("<!doctype") ? GrowattAPI.Failure.signedOut : GrowattAPI.Failure.badResponse
        }
        if let result = doc["result"]?.int, result != 1 {
            throw GrowattAPI.Failure.api(result, doc["msg"]?.text ?? doc["message"]?.text ?? "")
        }
        let obj = doc["obj"] ?? doc["data"] ?? doc
        let rows = obj.array ?? obj["datas"]?.array ?? obj["data"]?.array ?? obj["list"]?.array ?? []
        let page = obj["currPage"]?.int ?? obj["toPageNum"]?.int ?? 1
        return Page(rows: rows, page: page, pages: max(obj["pages"]?.int ?? obj["totalPage"]?.int ?? 1, 1),
                    count: obj["count"]?.int ?? obj["total"]?.int, raw: doc)
    }
}
