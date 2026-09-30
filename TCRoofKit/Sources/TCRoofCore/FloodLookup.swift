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
            case .offline: return "ไม่มีสัญญาณอินเทอร์เน็ต · ลองใหม่อีกครั้ง"
            case .timeout: return "GISTDA ตอบช้าเกินไป · ลองใหม่อีกครั้ง"
            case .http(let c): return "GISTDA ตอบกลับผิดพลาด (\(c)) · ลองใหม่อีกครั้ง"
            case .badResponse: return "อ่านข้อมูลจาก GISTDA ไม่ได้ · ลองใหม่อีกครั้ง"
            }
        }
    }

    public var apiKey: String
    public var baseURL = URL(string: "https://api-gateway.gistda.or.th/api/2.0/resources/features")!
    /// Half-side of the box around the point.
    public var radiusMeters = 25.0
    /// The service needs ~50 s per call; its gateway gives up at 60 s (HTTP 504).
    public var timeout: TimeInterval = 65
    public var session: URLSession = .shared
    public init(apiKey: String) { self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Key from the git-ignored xcconfig (Info.plist `GISTDAAPIKey`); empty when none is built in.
    public static var bundledKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "GISTDAAPIKey") as? String).map { $0.hasPrefix("$(") ? "" : $0 } ?? ""
    }

    /// Is the point in a repeat-flood plot (within `radiusMeters`), and how often did it flood since 2011.
    /// One request with `limit=1`: the service takes ~50 s whatever the box and the gateway gives up at 60 s, and it answers 504 for
    /// `limit` above about 5, so `numberMatched` carries the answer. A timeout or 504 is retried up to `attempts` times; `progress` gets the attempt.
    public func fetch(lat: Double, lon: Double, now: Date = Date(), attempts: Int = 3, progress: (@Sendable (Int) -> Void)? = nil) async throws -> FloodGistda {
        guard !apiKey.isEmpty else { throw Failure.noKey }
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { throw Failure.badCoordinates }
        var last: Failure = .timeout
        for n in 1...max(1, attempts) {
            progress?(n)
            do {
                let data = try await get("flood-freq", Self.bbox(lat: lat, lon: lon, meters: radiusMeters))
                var g = try Self.parsePoint(data)
                g.lat = lat; g.lon = lon; g.fetchedAt = now
                return g
            } catch let e as Failure where e == .timeout || e == .http(504) || e == .http(502) || e == .http(503) {
                last = e
            }
        }
        throw last
    }

    /// "minLon,minLat,maxLon,maxLat" of a square `meters` from the point on each side.
    static func bbox(lat: Double, lon: Double, meters: Double) -> String {
        let dLat = meters / 111_320, dLon = meters / (111_320 * cos(lat * .pi / 180))
        return [lon - dLon, lat - dLat, lon + dLon, lat + dLat].map { String(format: "%.5f", $0) }.joined(separator: ",")
    }

    func get(_ path: String, _ bbox: String) async throws -> Data {
        var c = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "bbox", value: bbox), URLQueryItem(name: "limit", value: "1")]
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

    /// Buddhist-era years flagged `y_2011` … on a repeat-flood plot.
    static func years(_ p: [String: Any]) -> [Int] {
        p.compactMap { k, v in
            guard k.hasPrefix("y_"), let y = Int(k.dropFirst(2)), (int(v) ?? 0) > 0 else { return nil }
            return y + 543
        }.sorted()
    }
    static func place(_ p: [String: Any]) -> String {
        ["tb_tn", "ap_tn", "pv_tn"].compactMap { p[$0] as? String }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// `flood-freq` for a tiny box round the point with `limit=1`: `numberMatched` plots touch it; the one returned carries `freq`
    /// (times flooded), the `y_YYYY` flags (2011 = พ.ศ. 2554 onwards) and the tambon / amphoe / province.
    public static func parsePoint(_ data: Data) throws -> FloodGistda {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["features"] is [Any] else { throw Failure.badResponse }
        let matched = int(root["numberMatched"]) ?? 0
        var g = FloodGistda()
        g.plots = matched
        g.insideRepeatArea = matched > 0
        if let f = try features(data).first {
            g.maxTimes = int(f.props["freq"]) ?? 0
            g.pointYears = years(f.props)
            g.place = place(f.props)
            g.nearestMeters = 0; g.nearestTimes = int(f.props["freq"]); g.nearestYears = g.pointYears
        }
        return g
    }
}
