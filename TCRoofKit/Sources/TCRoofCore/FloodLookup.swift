import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// GISTDA flood lookup for the A4 "ไม่ทราบ" answer: repeat-flood frequency at and around the point (1 km) and floods in the last 30 days.
///
/// The API key is never in the repository: the app passes it from Settings (`SurveySettings.gistdaKey`) or from the
/// `GISTDAAPIKey` Info.plist entry filled by the git-ignored `Secrets.xcconfig`. Both endpoints take a `bbox` and return GeoJSON;
/// distances and inside/outside are worked out here from the polygons.
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
    public var radiusMeters = 1000.0
    /// The service often needs 50–60 s for a 1 km box; its gateway gives up at 60 s (HTTP 504).
    public var timeout: TimeInterval = 75
    public var session: URLSession = .shared
    public init(apiKey: String) { self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Key from the git-ignored xcconfig (Info.plist `GISTDAAPIKey`); empty when none is built in.
    public static var bundledKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "GISTDAAPIKey") as? String).map { $0.hasPrefix("$(") ? "" : $0 } ?? ""
    }

    /// Repeat-flood plots within `radiusMeters` (falling back to 300 m when the gateway times out) and satellite floods of the last 30 days.
    public func fetch(lat: Double, lon: Double, now: Date = Date()) async throws -> FloodGistda {
        guard !apiKey.isEmpty else { throw Failure.noKey }
        guard (-90...90).contains(lat), (-180...180).contains(lon) else { throw Failure.badCoordinates }
        let freq: Data
        do { freq = try await get("flood-freq", Self.bbox(lat: lat, lon: lon, meters: radiusMeters)) }
        catch Failure.http(504), Failure.timeout { freq = try await get("flood-freq", Self.bbox(lat: lat, lon: lon, meters: 300)) }
        var g = try Self.parseFreq(freq, lat: lat, lon: lon, radius: radiusMeters)
        g.lat = lat; g.lon = lon; g.fetchedAt = now
        return g
    }

    /// "minLon,minLat,maxLon,maxLat" of a square `meters` from the point on each side.
    static func bbox(lat: Double, lon: Double, meters: Double) -> String {
        let dLat = meters / 111_320, dLon = meters / (111_320 * cos(lat * .pi / 180))
        return [lon - dLon, lat - dLat, lon + dLon, lat + dLat].map { String(format: "%.5f", $0) }.joined(separator: ",")
    }

    func get(_ path: String, _ bbox: String) async throws -> Data {
        var c = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "bbox", value: bbox), URLQueryItem(name: "limit", value: "1000")]
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

    struct Feature { let props: [String: Any]; let rings: [[(lon: Double, lat: Double)]] }

    static func features(_ data: Data) throws -> [Feature] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = root["features"] as? [[String: Any]] else {
            throw Failure.badResponse
        }
        return list.map { f in
            let g = f["geometry"] as? [String: Any]
            var rings: [[(Double, Double)]] = []
            func ring(_ a: Any?) -> [(Double, Double)] { (a as? [[Double]])?.compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil } ?? [] }
            switch g?["type"] as? String {
            case "Polygon"?: rings = (g?["coordinates"] as? [Any])?.map(ring) ?? []
            case "MultiPolygon"?: rings = (g?["coordinates"] as? [[Any]])?.flatMap { $0.map(ring) } ?? []
            default: break
            }
            return Feature(props: (f["properties"] as? [String: Any]) ?? [:], rings: rings.map { $0.map { (lon: $0.0, lat: $0.1) } })
        }
    }
    static func int(_ x: Any?) -> Int? {
        if let i = x as? Int { return i }
        if let d = x as? Double { return Int(d.rounded()) }
        if let s = x as? String { return Int(s) }
        return nil
    }

    /// Metres from the point to the nearest edge of a feature; 0 when the point is inside it.
    static func distance(_ f: Feature, lat: Double, lon: Double) -> Double {
        let mx = 111_320 * cos(lat * .pi / 180), my = 110_574.0
        var best = Double.infinity, inside = false
        for r in f.rings where r.count >= 3 {
            let p = r.map { (x: ($0.lon - lon) * mx, y: ($0.lat - lat) * my) }
            var j = p.count - 1
            for i in p.indices {
                let a = p[j], b = p[i]
                if (a.y > 0) != (b.y > 0), 0 < (b.x - a.x) * (0 - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                let dx = b.x - a.x, dy = b.y - a.y, len = dx * dx + dy * dy
                let t = len > 0 ? max(0, min(1, -(a.x * dx + a.y * dy) / len)) : 0
                best = min(best, hypot(a.x + t * dx, a.y + t * dy))
                j = i
            }
        }
        return inside ? 0 : best
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

    /// `flood-freq`: repeat-flood plots with `freq` (times flooded 2011–2024) and `y_YYYY` flags.
    public static func parseFreq(_ data: Data, lat: Double, lon: Double, radius: Double = 1000) throws -> FloodGistda {
        var g = FloodGistda()
        var plotYears = Set<Int>()
        var nearest: (d: Double, f: Feature)?
        for f in try features(data) {
            let d = distance(f, lat: lat, lon: lon)
            guard d <= radius else { continue }
            if nearest == nil || d < nearest!.d { nearest = (d, f) }
            g.plots += 1
            g.maxTimes = max(g.maxTimes, int(f.props["freq"]) ?? 0)
            plotYears.formUnion(years(f.props))
            if d == 0 { g.insideRepeatArea = true; g.pointYears = Array(Set(g.pointYears + years(f.props))).sorted() }
            if g.place.isEmpty { g.place = place(f.props) }
        }
        g.plotYears = plotYears.sorted()
        if let n = nearest {
            g.nearestMeters = Int((n.d / 10).rounded() * 10)
            g.nearestTimes = int(n.f.props["freq"])
            g.nearestYears = years(n.f.props)
        }
        return g
    }

    /// `flood/30days`: flood polygons from recent satellite images; `file_name` lists the images ("S1D_20260910_0551, …").
    public static func parseRecent(_ data: Data, lat: Double, lon: Double, into g: inout FloodGistda) {
        guard let list = try? features(data) else { return }
        g.recentFound = !list.isEmpty
        let d = list.map { distance($0, lat: lat, lon: lon) }.min()
        g.recentMeters = d.map { Int(($0 / 10).rounded() * 10) }
        var dates = Set<String>()
        for f in list {
            for part in ((f.props["file_name"] as? String) ?? "").split(separator: ",") {
                if let m = part.split(separator: "_").first(where: { $0.count == 8 && $0.allSatisfy(\.isNumber) }) { dates.insert(String(m)) }
            }
        }
        let s = dates.sorted()
        g.recentFrom = s.first.map(thaiDate); g.recentTo = s.last.map(thaiDate)
        if g.place.isEmpty, let f = list.first { g.place = place(f.props) }
    }
    /// "20260910" → "10/9/2569"
    static func thaiDate(_ s: String) -> String {
        guard s.count == 8, let y = Int(s.prefix(4)), let m = Int(s.dropFirst(4).prefix(2)), let d = Int(s.suffix(2)) else { return s }
        return "\(d)/\(m)/\(y + 543)"
    }
}
