import Foundation
import PVYield

/// C1's shade card `เงาบังแผง | Shade` (docs/ui/survey-c1-ipad-shade, change 2): per roof face in use and for the whole
/// roof, from the same sun track and obstacle shade as `RoofMountYield.estimate` (PVYield only; no SAM), worked out
/// by `RoofMountYield.estimateAndShade`, never stored.
///
/// - Sun Access: the plane's irradiation after the roof's obstacles over the irradiation without them, over the year
///   (the beam each hour loses its shaded share, `RoofObstacleShade`).
/// - TOF: the unshaded irradiation on the face's tilt and azimuth over the site's best fixed plane (`bestPlane`: a
///   coarse search over tilt 0–40° × azimuth 90–270°, refined to `searchStep`).
/// - TSRF = TOF × Sun Access.
/// - The whole roof weighs each face by its modules (POA-weighted).
///
/// Without A1's GPS, or with no hourly weather within 100 km of it, there is no shade report (`Outcome.unavailable`
/// with the reason); SolarModel isn't used for these figures.
public struct RoofShade: Equatable, Sendable {
    public struct Orientation: Equatable, Sendable {
        public var tilt: Double, azimuth: Double
        public init(tilt: Double, azimuth: Double) { self.tilt = tilt; self.azimuth = azimuth }
        /// `S 180°`.
        public var azimuthText: String { "\(Self.letter(azimuth)) \(Int(azimuth.rounded()))°" }
        static func letter(_ az: Double) -> String {
            let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            let a = (az.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            return names[Int((a + 22.5) / 45) % 8]
        }
    }

    public struct Group: Equatable, Sendable, Identifiable {
        /// The face id, or `all`.
        public var id: String
        /// `ด้านใต้` or `รวมทั้งหลังคา`.
        public var title: String
        /// The header's `ด้านใต้ของสันหลังคา` or `ทั้งหลังคา`.
        public var caption: String
        public var modules: Int
        public var dcKWp: Double
        /// One per face in the group.
        public var orientations: [Orientation]
        /// 0–1.
        public var sunAccess: Double, tof: Double
        public var tsrf: Double { tof * sunAccess }
        /// January first, 0–1 of that month's unshaded irradiation; shading = 1 − sun access.
        public var monthlySunAccess: [Double]
        public var monthlyShading: [Double] { monthlySunAccess.map { 1 - $0 } }
        /// Months × `RoofShade.hours`: sun access, nil where the plane gets no light that hour.
        public var hourMonth: [[Double?]]
        /// The obstacles seen from the group's modules (compass azimuth, elevation), for the sun path.
        public var silhouettes: [[Pt]]

        /// `15° | S 180°`, or each face's on the whole roof.
        public var tiltAzimuthText: String {
            let t = Set(orientations.map { Int($0.tilt.rounded()) }).sorted().map { "\($0)°" }.joined(separator: ", ")
            return t + " | " + orientations.map(\.azimuthText).joined(separator: ", ")
        }
    }

    public struct SunPathDay: Equatable, Sendable {
        public enum Kind: Sendable { case june, equinox, december }
        public var kind: Kind
        public var label: String
        /// (compass azimuth, elevation) every 10 minutes with the sun up.
        public var points: [Pt]
        /// The whole hours with the sun up.
        public var hours: [Pt]
    }

    public var groups: [Group]
    public var sunPath: [SunPathDay]
    /// Local hours of the heat map's columns.
    public var hours: [Int]
    /// `ZNSHINE 570 W`.
    public var moduleName: String
    public var bestPlane: Orientation
    /// The best plane's search step: `1° tilt | 2° azimuth`.
    public var searchStep: String
    public var latitude: Double, longitude: Double
    /// `PVGIS-ERA5 TMY กรุงเทพฯ`.
    public var weather: String

    /// `PVYield รายชั่วโมง | PVGIS-ERA5 TMY กรุงเทพฯ | พิกัด A1 13.76° N`.
    public var sourceLine: String {
        "PVYield รายชั่วโมง | " + weather + String(format: " | พิกัด A1 %.2f° %@", abs(latitude), latitude >= 0 ? "N" : "S")
    }

    public enum Outcome: Equatable, Sendable {
        case ready(RoofShade)
        /// Why there is none: no layout, no GPS, no hourly weather near the site.
        case unavailable(String)
        public var shade: RoofShade? { if case .ready(let s) = self { return s }; return nil }
    }

    public static let noLayout = "ยังไม่มีผังแผง"
    public static let noGPS = "ยังไม่มีพิกัด A1 จึงยังคำนวณเงาไม่ได้"
    public static let noWeather = "ยังไม่มีข้อมูลอากาศรายชั่วโมงใกล้พิกัด A1 (ภายใน 100 กม.) จึงยังคำนวณเงาไม่ได้"

    // MARK: - Compute

    /// The report from a sun track and the obstacles' hourly shade per face id (`RoofObstacleShade.hourly`).
    static func make(_ i: RoofMountYield.Inputs, track: SunTrack, shade: [String: [Double]], weather: String) -> RoofShade {
        let albedo = YieldLosses().albedo, n = track.hours.count, offset = Int(track.utcOffsetHours * 3600)
        let lit = (0..<n).filter { track.hours[$0].ghi > 0 }
        let local = track.hours.map { (($0.unix + offset) / 3600 % 24 + 24) % 24 }
        let best = bestPlane(track, lit: lit, albedo: albedo)
        let bestPOA = poaSum(track, lit: lit, tilt: best.tilt, azimuth: best.azimuth, albedo: albedo)

        struct Sums { var free = 0.0, shaded = 0.0; var month = [Double](repeating: 0, count: 12), monthShaded = [Double](repeating: 0, count: 12)
            var cell = [[Double]](repeating: [Double](repeating: 0, count: 24), count: 12), cellShaded = [[Double]](repeating: [Double](repeating: 0, count: 24), count: 12) }
        func add(_ a: inout Sums, _ b: Sums, weight w: Double) {
            a.free += w * b.free; a.shaded += w * b.shaded
            for m in 0..<12 {
                a.month[m] += w * b.month[m]; a.monthShaded[m] += w * b.monthShaded[m]
                for h in 0..<24 { a.cell[m][h] += w * b.cell[m][h]; a.cellShaded[m][h] += w * b.cellShaded[m][h] }
            }
        }
        let sums: [Sums] = i.faces.map { f in
            var s = Sums()
            let frac = shade[f.id]
            for k in lit {
                let h = track.hours[k]
                let poa = Irradiance.planeOfArray(tilt: f.tiltDeg, azimuth: f.azimuthDeg, albedo: albedo, hour: h)
                let x = frac.map { k < $0.count ? min(1, max(0, $0[k])) : 0 } ?? 0
                let free = poa.global, shaded = free - poa.direct * x
                let m = h.month - 1, hr = local[k]
                s.free += free; s.shaded += shaded
                s.month[m] += free; s.monthShaded[m] += shaded
                s.cell[m][hr] += free; s.cellShaded[m][hr] += shaded
            }
            return s
        }
        // the heat map's hours: those with at least 0.5 % of the brightest hour's light over the year, on any face
        var byHour = [Double](repeating: 0, count: 24)
        for s in sums { for m in 0..<12 { for h in 0..<24 { byHour[h] += s.cell[m][h] } } }
        let top = byHour.max() ?? 0
        let hours = (0..<24).filter { top > 0 && byHour[$0] >= 0.005 * top }

        let scene = i.shade
        func group(id: String, title: String, caption: String, faces: [RoofMountYield.Inputs.Face], sums s: Sums) -> Group {
            let mods = faces.reduce(0) { $0 + $1.modules }
            let ratio = { (a: Double, b: Double) -> Double in b > 0 ? min(1, a / b) : 1 }
            let monthly = (0..<12).map { ratio(s.monthShaded[$0], s.month[$0]) }
            let cells: [[Double?]] = (0..<12).map { m in
                hours.map { h in s.cell[m][h] > 1e-6 * max(1, Double(mods)) ? ratio(s.cellShaded[m][h], s.cell[m][h]) : nil }
            }
            let free = mods > 0 ? s.free / Double(mods) : 0
            let centre = scene?.centre(faces: Set(faces.map(\.id)))
            return Group(id: id, title: title, caption: caption, modules: mods, dcKWp: Double(mods) * i.moduleWp / 1000,
                         orientations: faces.map { Orientation(tilt: $0.tiltDeg, azimuth: $0.azimuthDeg) },
                         sunAccess: ratio(s.shaded, s.free), tof: bestPOA > 0 ? free / bestPOA : 0,
                         monthlySunAccess: monthly, hourMonth: cells,
                         silhouettes: centre.map { scene?.silhouettes(from: $0) ?? [] } ?? [])
        }
        var groups: [Group] = []
        let several = i.faces.count > 1
        for (f, s) in zip(i.faces, sums) {
            // one face's sums per module (the face's POA × its modules, so the whole roof weighs them by modules)
            var per = Sums()
            add(&per, s, weight: Double(f.modules))
            let title = "ด้าน" + RoofFace.direction(f.azimuthDeg)
            groups.append(group(id: f.id, title: title, caption: several ? title + "ของสันหลังคา" : title, faces: [f], sums: per))
        }
        if several {
            var all = Sums()
            for (f, s) in zip(i.faces, sums) { add(&all, s, weight: Double(f.modules)) }
            groups.append(group(id: "all", title: "รวมทั้งหลังคา", caption: "ทั้งหลังคา", faces: i.faces, sums: all))
        }
        let cat = RoofMountYield.catalogModule(wp: i.moduleWp, length: i.moduleLength, width: i.moduleWidth)
        let maker = cat.map { String($0.model.split(separator: " ").first ?? "").uppercased() } ?? "แผง"
        return RoofShade(groups: groups, sunPath: sunPath(track.site, utcOffsetHours: track.utcOffsetHours), hours: hours,
                         moduleName: String(format: "%@ %.0f W", maker, i.moduleWp), bestPlane: best, searchStep: "1° tilt | 2° azimuth",
                         latitude: track.site.latitude, longitude: track.site.longitude, weather: weather)
    }

    static func poaSum(_ track: SunTrack, lit: [Int], tilt: Double, azimuth: Double, albedo: Double) -> Double {
        var s = 0.0
        for k in lit { s += Irradiance.planeOfArray(tilt: tilt, azimuth: azimuth, albedo: albedo, hour: track.hours[k]).global }
        return s
    }

    /// The site's best fixed plane on its weather: tilt 0–40° every 5° × azimuth 90–270° every 15°, then 1° of tilt and
    /// 2° of azimuth around the best. Kept per site.
    static func bestPlane(_ track: SunTrack, lit: [Int], albedo: Double) -> Orientation {
        let key = "\(track.weatherSource) \((track.site.latitude * 100).rounded()) \((track.site.longitude * 100).rounded())"
        if let hit = bestCache.get(key) { return hit }
        func sum(_ t: Double, _ a: Double) -> Double { poaSum(track, lit: lit, tilt: t, azimuth: a, albedo: albedo) }
        var best = (t: 0.0, a: 180.0, s: -1.0)
        for t in stride(from: 0.0, through: 40, by: 5) {
            for a in stride(from: 90.0, through: 270, by: 15) {
                // a flat plane has no azimuth
                if t == 0 && a != 180 { continue }
                let s = sum(t, a)
                if s > best.s { best = (t, a, s) }
            }
        }
        for t in stride(from: max(0, best.t - 4), through: min(40, best.t + 4), by: 1) where t != best.t {
            let s = sum(t, best.a)
            if s > best.s { best = (t, best.a, s) }
        }
        for a in stride(from: max(90, best.a - 14), through: min(270, best.a + 14), by: 2) where a != best.a {
            let s = sum(best.t, a)
            if s > best.s { best = (best.t, a, s) }
        }
        let out = Orientation(tilt: best.t, azimuth: best.a)
        bestCache.set(key, out)
        return out
    }

    /// The sun on 21 June, 21 March (≈ 21 September) and 21 December at the site, every 10 minutes, local time.
    public static func sunPath(_ site: SolarPosition.Site, utcOffsetHours: Double = 7) -> [SunPathDay] {
        let days: [(SunPathDay.Kind, String, Double)] = [(.june, "มิ.ย.", 1_782_000_000), (.equinox, "มี.ค./ก.ย.", 1_774_051_200),
                                                         (.december, "ธ.ค.", 1_797_811_200)]
        return days.map { kind, label, midnightUTC in
            // `midnightUTC` is 00:00 UTC of 21 June / 21 March / 21 December 2026
            let start = (midnightUTC / 86400).rounded(.down) * 86400 - utcOffsetHours * 3600
            var pts: [Pt] = [], hours: [Pt] = []
            for m in stride(from: 0, through: 24 * 60, by: 10) {
                let p = SolarPosition.position(unix: start + Double(m) * 60, site: site)
                guard p.apparentElevation > 0 else { continue }
                let at = Pt(p.azimuth, p.apparentElevation)
                pts.append(at)
                if m % 60 == 0 { hours.append(at) }
            }
            return SunPathDay(kind: kind, label: label, points: pts, hours: hours)
        }
    }

    final class Cache: @unchecked Sendable {
        private var items: [String: Orientation] = [:]
        private let lock = NSLock()
        func get(_ k: String) -> Orientation? { lock.lock(); defer { lock.unlock() }; return items[k] }
        func set(_ k: String, _ v: Orientation) { lock.lock(); items[k] = v; lock.unlock() }
    }
    static let bestCache = Cache()
}
