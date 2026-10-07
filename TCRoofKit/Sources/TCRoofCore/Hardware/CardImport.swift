import Foundation

/// นำเข้ารูปจากการ์ด / USB (docs/specs/hardware-assist-swift.md §H6): what a card or drone photo is offered for.
/// The highest one is offered as the A2 site picture, one taken within 15 m of a site symbol is offered for that
/// symbol's section, and the rest wait in a tray for the surveyor to put into a slot.
public enum CardImport {
    /// A photo's EXIF, read when it is imported.
    public struct Shot: Identifiable, Hashable, Sendable {
        public let id: UUID
        public var lat: Double?, lon: Double?
        /// GPS altitude, metres above sea level.
        public var altitude: Double?
        /// Compass direction the camera faced, degrees.
        public var heading: Double?
        public var date: Date?
        /// "FC3582" (a DJI drone), "iPhone 15 Pro".
        public var camera: String?
        public init(id: UUID = UUID(), lat: Double? = nil, lon: Double? = nil, altitude: Double? = nil, heading: Double? = nil,
                    date: Date? = nil, camera: String? = nil) {
            self.id = id; self.lat = lat; self.lon = lon; self.altitude = altitude; self.heading = heading; self.date = date; self.camera = camera
        }

        /// The capture fields kept on the stored `Photo`.
        public var stamp: PhotoStamp { PhotoStamp(lat: lat, lon: lon, heading: heading, device: camera) }
    }

    /// A photo taken this close to a symbol, in metres, is offered for its section.
    public static let nearMeters = 15.0
    /// An aerial photo is at least this much higher than the lowest imported one, unless it is the only one with an altitude.
    public static let aerialRise = 15.0

    /// The photo to offer as the A2 site picture: the highest one, clearly above the others.
    public static func aerial(_ shots: [Shot]) -> Shot? {
        let high = shots.filter { $0.altitude != nil }
        guard let top = high.max(by: { $0.altitude! < $1.altitude! }) else { return nil }
        guard high.count > 1, let low = high.map({ $0.altitude! }).min() else { return top }
        return top.altitude! - low >= aerialRise ? top : nil
    }

    /// The site symbol a photo was taken next to, and how far, when the site picture is a map.
    public static func nearest(_ shot: Shot, marks: [MapMark], geo: SiteGeo) -> (mark: MapMark, meters: Double)? {
        guard let lat = shot.lat, let lon = shot.lon else { return nil }
        return marks.map { m -> (MapMark, Double) in
            let c = geo.coordinate(x: m.x, y: m.y)
            return (m, distance(lat, lon, c.lat, c.lon))
        }
        .filter { $0.1 <= nearMeters }
        .min { $0.1 < $1.1 }
    }

    /// Metres between two points, flat-earth (fine across a site).
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let k = 111_320.0
        let dy = (lat2 - lat1) * k, dx = (lon2 - lon1) * k * cos((lat1 + lat2) / 2 * .pi / 180)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Where the A2 site picture lies on the ground, when it is a satellite map fetched for the job's GPS.
public struct SiteGeo: Equatable, Sendable {
    public var lat: Double, lon: Double
    /// Metres across the whole fetched map (before the report frame cut it).
    public var mapMeters: Double
    public var crop: MapCrop
    /// The fetched map is 640 × 400.
    public static let mapAspect = 400.0 / 640

    public init(lat: Double, lon: Double, mapMeters: Double, crop: MapCrop) {
        self.lat = lat; self.lon = lon; self.mapMeters = mapMeters; self.crop = crop
    }

    /// From the job's answers and its GPS: only a "google" picture with a scale is a map.
    public init?(values v: Values, lat: Double, lon: Double) {
        guard v.text(SiteShapes.sourceKey) == "google", let scale = v.number(SiteShapes.scaleKey), scale > 0 else { return nil }
        let crop = MapCrop(v.text(MapCrop.key)) ?? .full
        self.init(lat: lat, lon: lon, mapMeters: scale / (crop.w / 100), crop: crop)
    }

    /// Ground position of a point on the picture (0…1 across and down).
    public func coordinate(x: Double, y: Double) -> (lat: Double, lon: Double) {
        let u = (crop.x + x * crop.w) / 100, v = (crop.y + y * crop.h) / 100
        let east = (u - 0.5) * mapMeters, north = (0.5 - v) * mapMeters * Self.mapAspect
        return (lat + north / 111_320, lon + east / (111_320 * cos(lat * .pi / 180)))
    }
}

/// One photo field a card photo can go into.
public struct PhotoTarget: Hashable, Identifiable, Sendable {
    /// nil for the cover pages (A1–A4, E1).
    public let module: UUID?
    public let field: String
    public let label: String
    /// "A3 มิเตอร์ หม้อแปลง และตู้ MDB", "B1 ตู้ไฟฟ้า 1".
    public let section: String
    public var id: String { (module?.uuidString ?? "job") + "/" + field }
}

public extension Job {
    /// Empty single-photo fields shown on the form, in app order.
    var emptyPhotoTargets: [PhotoTarget] {
        func empty(_ fields: [FieldSpec], _ v: Values, module: UUID?, section: String) -> [PhotoTarget] {
            fields.filter { f in
                if case .photo = f.kind { return f.isVisible(v) && v.photo(f.id) == nil }
                return false
            }
            .map { PhotoTarget(module: module, field: $0.id, label: $0.label, section: section) }
        }
        var out = empty(Schema.site.fields, values, module: nil, section: "A2 ภาพสถานที่ติดตั้ง")
            + empty(Schema.electrical.fields, values, module: nil, section: "A3 มิเตอร์ หม้อแปลง และตู้ MDB")
            + empty(Schema.flood.fields, values, module: nil, section: "A4 ประวัติน้ำท่วม")
        for s in sectionsByCategory.flatMap(\.sections) {
            out += empty(s.module.spec.fields, s.module.values, module: s.module.id, section: s.title)
        }
        return out.filter { $0.field != "siteMap" }
    }

    /// The empty slots of the section a site symbol stands for: a transformer's or MDB's photos in A3, the meter's,
    /// or the section a water point or FTS button belongs to.
    func photoTargets(for mark: MapMark) -> [PhotoTarget] {
        let all = emptyPhotoTargets
        if let m = mark.module { return all.filter { $0.module == m } }
        let trafos = values.transformers("trafos")
        func transformer(_ i: Int, _ keys: [String]) -> [PhotoTarget] {
            all.filter { t in t.module == nil && keys.contains { t.field == "tr\(i)_\($0)" } }
        }
        switch mark.kind {
        case .meter:
            return all.filter { $0.module == nil && $0.field == "meterPic" }
        case .trafo:
            guard let id = mark.link?.split(separator: ":").last, let i = trafos.firstIndex(where: { $0.id.uuidString == id }) else { return [] }
            return transformer(i, Schema.transformerAngles.map(\.key))
        case .mdb:
            guard let id = mark.link?.split(separator: ":").last,
                  let i = trafos.firstIndex(where: { $0.boards.contains { $0.id.uuidString == id } }) else { return [] }
            return transformer(i, ["feedPhoto", "mdbOpen", "mdbBreaker", "mdbSpace"])
        case .inv:
            return all.filter { t in modules.contains { $0.id == t.module && $0.type == .inverter } }
        default:
            return []
        }
    }
}
