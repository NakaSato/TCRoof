import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// GISTDA flood lookup for the A4 "ไม่ทราบ" answer: repeat-flood frequency at and around the point (1 km) and floods in the last 30 days.
///
/// The API key is never in the repository: the app passes it from Settings (`SurveySettings.gistdaKey`) or from the
/// `GISTDAAPIKey` Info.plist entry filled by the git-ignored `Secrets.xcconfig`. The endpoint takes a `bbox` and returns GeoJSON.
public struct FloodLookup: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case noKey, badCoordinates, offline, timeout, http(Int), badResponse
        /// Thai message for the retry hint. Saving is never blocked by a failed lookup.
        public var message: String {
            switch self {
            case .noKey: return "ยังไม่ได้ตั้งค่า GISTDA API key"
            case .badCoordinates: return "พิกัด A1 ไม่ถูกต้อง"
            case .offline: return "ไม่มีสัญญาณอินเทอร์เน็ต | ลองใหม่อีกครั้ง"
            case .timeout: return "GISTDA ตอบช้าเกินไป | ลองใหม่อีกครั้ง"
            case .http(let c): return "GISTDA ตอบกลับผิดพลาด (\(c)) | ลองใหม่อีกครั้ง"
            case .badResponse: return "อ่านข้อมูลจาก GISTDA ไม่ได้ | ลองใหม่อีกครั้ง"
            }
        }
    }

    public var apiKey: String
    public var baseURL = URL(string: "https://api-gateway.gistda.or.th/api/2.0/resources/features")!
    /// Half-side of the box around the point: the area round the installation, not the point itself.
    public var radiusMeters = 1000.0
    /// The service needs ~50 s per call; its gateway gives up at 60 s (HTTP 504).
    public var timeout: TimeInterval = 65
    public var session: URLSession = .shared
    public init(apiKey: String) { self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Key from the git-ignored xcconfig (Info.plist `GISTDAAPIKey`); empty when none is built in.
    public static var bundledKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "GISTDAAPIKey") as? String).map { $0.hasPrefix("$(") ? "" : $0 } ?? ""
    }

    /// Which years flooded round the point, from พ.ศ. 2554 to the last year GISTDA holds: one `limit=1` request per year with the
    /// filter `y_YYYY=1`, whose `numberMatched` is the number of repeat-flood plots in the box that flooded that year. The requests
    /// run together. A timeout or 5xx is retried up to `attempts` times; `progress` gets the number of years answered.
    public func fetch(lat: Double, lon: Double, now: Date = Date(), attempts: Int = 3, progress: (@Sendable (Int) -> Void)? = nil) async throws -> FloodGistda {
        guard !apiKey.isEmpty else { throw Failure.noKey }
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { throw Failure.badCoordinates }
        let box = Self.bbox(lat: lat, lon: lon, meters: radiusMeters)
        let answers = try await withThrowingTaskGroup(of: (Int, Int, String).self) { group -> [(Int, Int, String)] in
            for ad in Self.gregorianYears { group.addTask { let (n, place) = try await self.plots(box: box, year: ad, attempts: attempts); return (ad + 543, n, place) } }
            var out: [(Int, Int, String)] = []
            for try await a in group { out.append(a); progress?(out.count) }
            return out
        }
        var g = FloodGistda()
        g.lat = lat; g.lon = lon; g.fetchedAt = now; g.radiusMeters = Int(radiusMeters)
        g.years = answers.sorted { $0.0 < $1.0 }.map { FloodGistda.YearPlots(year: $0.0, plots: $0.1) }
        g.place = answers.first { !$0.2.isEmpty }?.2 ?? ""
        return g
    }

    /// Years the service holds (ค.ศ.): 2011 … 2024.
    public static let gregorianYears = Array(2011...2024)

    func plots(box: String, year: Int, attempts: Int) async throws -> (Int, String) {
        var last: Failure = .timeout
        for _ in 1...max(1, attempts) {
            do { return try Self.parseYear(try await get("flood-freq", box, extra: [URLQueryItem(name: "y_\(year)", value: "1")])) }
            catch let e as Failure where e == .timeout || e == .http(504) || e == .http(502) || e == .http(503) { last = e }
        }
        throw last
    }

    /// "minLon,minLat,maxLon,maxLat" of a square `meters` from the point on each side.
    static func bbox(lat: Double, lon: Double, meters: Double) -> String {
        let dLat = meters / 111_320, dLon = meters / (111_320 * cos(lat * .pi / 180))
        return [lon - dLon, lat - dLat, lon + dLon, lat + dLat].map { String(format: "%.5f", $0) }.joined(separator: ",")
    }

    func get(_ path: String, _ bbox: String, extra: [URLQueryItem] = []) async throws -> Data {
        var c = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "bbox", value: bbox), URLQueryItem(name: "limit", value: "1")] + extra
        var req = URLRequest(url: c.url!, timeoutInterval: timeout)
        req.setValue(apiKey, forHTTPHeaderField: "API-Key")
        do {
            let (data, resp) = try await session.data(for: req)
            if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw Failure.http(h.statusCode) }
            return data
        } catch let e as Failure { throw e }
        catch let e as URLError { throw e.code == .timedOut ? Failure.timeout : Failure.offline }
        catch { throw Failure.badResponse }
    }

    // MARK: parsing (GeoJSON FeatureCollection)

    struct Feature { let props: [String: Any] }

    static func features(_ data: Data) throws -> [Feature] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = root["features"] as? [[String: Any]] else {
            throw Failure.badResponse
        }
        return list.map { Feature(props: ($0["properties"] as? [String: Any]) ?? [:]) }
    }
    static func int(_ x: Any?) -> Int? {
        if let i = x as? Int { return i }
        if let d = x as? Double { return Int(d.rounded()) }
        if let s = x as? String { return Int(s) }
        return nil
    }

    static func place(_ p: [String: Any]) -> String {
        ["tb_tn", "ap_tn", "pv_tn"].compactMap { p[$0] as? String }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// `flood-freq` filtered to one year, `limit=1`: `numberMatched` plots flooded that year; the one returned names the tambon / amphoe / province.
    public static func parseYear(_ data: Data) throws -> (plots: Int, place: String) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["features"] is [Any] else { throw Failure.badResponse }
        return (int(root["numberMatched"]) ?? 0, try features(data).first.map { place($0.props) } ?? "")
    }
}
