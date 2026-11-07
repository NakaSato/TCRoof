import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Growatt's server OpenAPI v1 (growatt.pl's "Growatt Server Open API protocol standards" and "Growatt Server API Guide",
/// 2016): plants and their energy, for the `บำรุงรักษา` overview. Every call is a GET with the header `token`, and every
/// answer is `{ data, error_code, error_msg }`.
///
/// `demo` is the guide's public test server and token, whose plants are other developers' samples with no inverters. A
/// company's own plants need its own token from Growatt on `openapi.growatt.com`, which refuses the test token (10011).
public struct GrowattAPI: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// `error_code` other than 0: 10011 permission denied, 10004 a date range it won't take, and so on.
        case api(Int, String)
        /// 10012 `error_frequently_access`, still after the retries.
        case tooFrequent
        case http(Int), offline, badResponse

        public var message: String {
            switch self {
            case .api(10011, _): "Growatt ไม่อนุญาต (token ไม่ถูกต้อง)"
            case .api(let c, let m): "Growatt ตอบกลับผิดพลาด (\(c)\(m.isEmpty ? "" : " " + m))"
            case .tooFrequent: "เรียก Growatt ถี่เกินไป | ลองใหม่อีกครั้ง"
            case .http(let c): "Growatt ตอบกลับผิดพลาด (HTTP \(c))"
            case .offline: "ไม่มีสัญญาณอินเทอร์เน็ต | ลองใหม่อีกครั้ง"
            case .badResponse: "อ่านข้อมูลจาก Growatt ไม่ได้"
            }
        }
    }

    /// One plant of `plant/list`. `currentPower` is -1 when the plant has never reported.
    public struct Plant: Equatable, Sendable {
        public var id: Int
        public var name: String
        /// kWp.
        public var peakPower: Double
        /// kW.
        public var currentPower: Double
        /// kWh.
        public var totalEnergy: Double
        /// `status` isn't described in either PDF; kept as given.
        public var status: Int?
        public var city: String
        public var country: String
        public var latitude: Double?
        public var longitude: Double?
    }

    /// `plant/data`: the plant's energy so far, kWh, and its power now, kW.
    public struct PlantData: Equatable, Sendable {
        public var todayEnergy: Double
        public var monthlyEnergy: Double
        public var yearlyEnergy: Double
        public var totalEnergy: Double
        public var currentPower: Double
        /// The plant's own clock (`timezone`, e.g. GMT+8), as Growatt writes it: `yyyy-MM-dd HH:mm:ss`.
        public var lastUpdate: String
    }

    public var baseURL: URL
    public var token: String
    public var session: URLSession = .shared
    public var timeout: TimeInterval = 20
    /// Retries after 10012, waiting `retryDelay` × the attempt (6, 12, 18 s): calls about 6 s apart worked on the test
    /// server, but its token is shared with every developer trying it, so one wait isn't always enough.
    public var retries = 3
    public var retryDelay: TimeInterval = 6

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

    // MARK: calls

    /// `plant/list`: the token's plants, at most 100 a page.
    public func plants(page: Int = 1, perPage: Int = 100) async throws -> [Plant] {
        try Self.parsePlants(try await get("plant/list", ["page": "\(page)", "perpage": "\(min(max(perPage, 1), 100))"]))
    }

    /// `plant/data`: one plant's energy today, this month, this year and in all.
    public func data(plantID: Int) async throws -> PlantData {
        try Self.parseData(try await get("plant/data", ["plant_id": "\(plantID)"]))
    }

    func get(_ path: String, _ query: [String: String]) async throws -> Data {
        var c = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: c.url!, timeoutInterval: timeout)
        request.setValue(token, forHTTPHeaderField: "token")
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

    static func head(_ data: Data) throws -> (code: Int, message: String) {
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

    static func parsePlants(_ data: Data) throws -> [Plant] {
        guard let rows = try body(data)["plants"] as? [[String: Any]] else { throw Failure.badResponse }
        return rows.compactMap { r in
            guard let id = number(r["plant_id"]) else { return nil }
            return Plant(id: Int(id), name: (r["name"] as? String) ?? "Plant \(Int(id))",
                         peakPower: number(r["peak_power"]) ?? 0, currentPower: number(r["current_power"]) ?? -1,
                         totalEnergy: number(r["total_energy"]) ?? 0, status: number(r["status"]).map { Int($0) },
                         city: (r["city"] as? String) ?? "", country: (r["country"] as? String) ?? "",
                         latitude: number(r["latitude"]), longitude: number(r["longitude"]))
        }
    }

    static func parseData(_ data: Data) throws -> PlantData {
        let b = try body(data)
        return PlantData(todayEnergy: number(b["today_energy"]) ?? 0, monthlyEnergy: number(b["monthly_energy"]) ?? 0,
                         yearlyEnergy: number(b["yearly_energy"]) ?? 0, totalEnergy: number(b["total_energy"]) ?? 0,
                         currentPower: number(b["current_power"]) ?? -1, lastUpdate: (b["last_update_time"] as? String) ?? "")
    }

    /// Growatt sends numbers as numbers or as text ("0", "-1.0"); null and "" are nil.
    static func number(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    // MARK: overview

    /// A plant as a row of the `บำรุงรักษา` overview. Growatt gives no expected energy or PR, so both stay 0 (shown as a
    /// dash); a plant that has never reported is offline. `plant/list` says so with power -1, while `plant/data` gives
    /// the same plant 0, so -1 from either call wins.
    public static func summary(_ plant: Plant, data: PlantData? = nil) -> MaintenanceStationSummary {
        let offline = plant.currentPower < 0 || (data?.currentPower ?? 0) < 0
        let power = max(data?.currentPower ?? plant.currentPower, 0)
        let updated = data.map { String($0.lastUpdate.prefix(16)) } ?? ""
        let note = offline ? "Growatt | ไม่มีข้อมูล" + (updated.isEmpty ? "" : " ตั้งแต่ " + updated)
                           : "Growatt | " + String(format: power.rounded() == power ? "%.0f" : "%.1f", power) + " kW"
        return MaintenanceStationSummary(id: "growatt-\(plant.id)", name: plant.name, kWp: plant.peakPower,
                                         energy: data?.todayEnergy ?? 0, status: offline ? .offline : .normal, note: note)
    }
}
