import Foundation

/// D1 sub-step 4 "ภาพถ่าย" on iPad (docs/ui/survey-d1-photo-ipad): the board's photo tiles over the fields of the tank's
/// `ภาพถ่าย` group. Nothing new is stored: each tile reads and writes one field (or one slot of a list), and "required"
/// is the field's own (`FieldSpec.optional`), so `Tank.photoCompletion`, `Progress`, the PDF and Excel are unchanged.
/// The two roof tiles share `roofPhotos` and are told apart by the photo's tag.
public enum TankPhotos {
    public struct Tile: Hashable, Sendable, Identifiable {
        public let id: String
        public let field: String
        /// The obstacle photo's index in `obstPhotos`; nil for the other tiles.
        public let slot: Int?
        public let name: String
        public let subtitle: String
        /// `วิธีถ่าย`.
        public let tip: String
        public let required: Bool
    }

    public static let roofOverview = "ภาพรวม", roofSurface = "ผิวหลังคา"
    /// The four wall slots of `sidePhotos`, in order.
    public static let walls = ["เหนือ", "ใต้", "ตะวันออก", "ตะวันตก"]
    public static let obstacleMax = 5

    /// The board's tiles (`SHOT`), with their field: id, field, name, subtitle, tip.
    static let shots: [(id: String, field: String, name: String, subtitle: String, tip: String)] = [
        ("aerial", "aerialPhoto", "ภาพมุมสูง", "โดรน หรือ Google Maps", "ถ่ายตรงลงจากด้านบนให้เห็นถังทั้งใบและทางเข้า"),
        ("walls", "sidePhotos", "ผนังถัง", "ใช้วางแนวรางสายไฟ · เหนือ ใต้ ตะวันออก ตะวันตก",
         "ยืนห่างผนัง ~10 ม. ให้เห็นผนังทั้งด้าน ทั้งขอบบนและฐาน (ด้านที่จะเดินรางสายไฟ)"),
        ("roof", Tank.Key.roofPhotos, "หลังคาถัง · ภาพรวม", "หลังคาถัง", "ถ่ายจากมุมหลังคาให้เห็นพื้นที่วางแผงทั้งหมด"),
        ("surface", Tank.Key.roofPhotos, "ผิวหลังคาใกล้", "หลังคาถัง · สภาพผิว รอยร้าว น้ำขัง", "ถ่ายใกล้ ~1 ม. ให้เห็นผิวคอนกรีต รอยร้าว หรือคราบน้ำขัง"),
        ("cable", Tank.Key.cablePhoto, "แนวเดินสายไฟ", "จากถังถึงห้อง Inverter", "เดินตามแนวสายจากถังไปห้อง Inverter ถ่ายให้เห็นทางเดินสายทั้งแนว"),
        ("shade", Tank.Key.shadePhoto, "สิ่งบังแดด", "เฉพาะเมื่อมีต้นไม้ / อาคารบัง", "ยืนกลางหลังคา หันไปทางสิ่งที่บังแดด ให้เห็นความสูงเทียบกับขอบถัง"),
    ]
    static let obstacleTip = "ถ่ายให้เห็นสิ่งกีดขวางทั้งชิ้นและระยะจากขอบถัง แล้วผูกกับจุดบนแปลน (V1, H1 …)"

    static var group: GroupSpec? { Schema.spec(.tank).groups.first { $0.title == "ภาพถ่าย" } }
    static func required(_ field: String) -> Bool { !(group?.fields.first { $0.id == field }?.optional ?? true) }

    /// The six tiles, then one per obstacle photo (named after its tag, else `สิ่งกีดขวาง n`); while there is none, one
    /// empty obstacle tile, since the field is required.
    public static func tiles(_ v: Values) -> [Tile] {
        var out = shots.map { Tile(id: $0.id, field: $0.field, slot: nil, name: $0.name, subtitle: $0.subtitle, tip: $0.tip, required: required($0.field)) }
        let ob = v.photos("obstPhotos"), req = required("obstPhotos")
        if ob.isEmpty {
            out.append(Tile(id: "obst.0", field: "obstPhotos", slot: 0, name: "สิ่งกีดขวาง", subtitle: "ภาพแรกลงกรอบใหญ่ในรายงาน", tip: obstacleTip, required: req))
        }
        for (i, p) in ob.enumerated() {
            let name = p.tag.flatMap { $0.isEmpty ? nil : $0 } ?? "สิ่งกีดขวาง \(i + 1)"
            out.append(Tile(id: "obst.\(i)", field: "obstPhotos", slot: i, name: name,
                            subtitle: i == 0 ? "ภาพแรกลงกรอบใหญ่ในรายงาน" : (p.note ?? "สิ่งกีดขวาง"), tip: obstacleTip, required: req))
        }
        return out
    }

    // MARK: reading and writing a tile's photo

    /// The tile's photo (the walls tile: the first wall).
    public static func photo(_ v: Values, _ t: Tile) -> Photo? {
        switch t.id {
        case "walls": return v.photos("sidePhotos").first
        case "roof", "surface": return roof(v, t.id)
        default:
            if let i = t.slot { return v.photos("obstPhotos")[safe: i] }
            return v.photo(t.field)
        }
    }

    /// The roof photo of a tile: tagged for it, else by position among the untagged ones.
    static func roof(_ v: Values, _ id: String) -> Photo? {
        let list = v.photos(Tank.Key.roofPhotos), tag = id == "roof" ? roofOverview : roofSurface
        if let hit = list.first(where: { $0.tag == tag }) { return hit }
        let free = list.filter { $0.tag != roofOverview && $0.tag != roofSurface }
        let taken = list.contains { $0.tag == (id == "roof" ? roofSurface : roofOverview) }
        // the overview takes the first untagged photo; the surface the second (or the first when the overview is tagged)
        return id == "roof" ? free.first : free[safe: taken ? 0 : 1]
    }

    public static func taken(_ v: Values, _ t: Tile) -> Bool { photo(v, t) != nil }

    /// The photos in the walls tile, in slot order (up to 4).
    public static func walls(_ v: Values) -> [Photo] { v.photos("sidePhotos") }

    /// Puts `p` in the tile (replacing what was there), or removes the tile's photo when nil. `wall` picks the slot of
    /// the walls tile; `slot` past the end of a list appends.
    public static func set(_ v: inout Values, _ t: Tile, _ p: Photo?, wall: Int? = nil) {
        switch t.id {
        case "walls": v["sidePhotos"] = .photos(replace(v.photos("sidePhotos"), at: wall ?? 0, with: p, max: walls.count))
        case "roof", "surface":
            var list = v.photos(Tank.Key.roofPhotos)
            if let old = roof(v, t.id) { list.removeAll { $0.id == old.id } }
            if var p { p.tag = t.id == "roof" ? roofOverview : roofSurface; list.insert(p, at: t.id == "roof" ? 0 : list.count) }
            v[Tank.Key.roofPhotos] = list.isEmpty ? nil : .photos(list)
        default:
            if let i = t.slot {
                v["obstPhotos"] = .photos(replace(v.photos("obstPhotos"), at: i, with: p, max: obstacleMax))
            } else {
                v[t.field] = p.map { .photo($0) }
            }
        }
    }

    static func replace(_ list: [Photo], at i: Int, with p: Photo?, max: Int) -> [Photo] {
        var list = list
        if let p {
            if list.indices.contains(i) { list[i] = p } else if list.count < max { list.append(p) }
        } else if list.indices.contains(i) {
            list.remove(at: i)
        }
        return list
    }

    /// Edits the tile's photo in place (its note or tag).
    public static func edit(_ v: inout Values, _ t: Tile, wall: Int? = nil, _ f: (inout Photo) -> Void) {
        let current = t.id == "walls" ? walls(v)[safe: wall ?? 0] : photo(v, t)
        guard var p = current else { return }
        f(&p)
        set(&v, t, p, wall: wall)
    }

    /// Appends an obstacle photo (the add bar); false at the maximum.
    @discardableResult
    public static func addObstacle(_ v: inout Values, _ p: Photo) -> Bool {
        var list = v.photos("obstPhotos")
        guard list.count < obstacleMax else { return false }
        list.append(p)
        v["obstPhotos"] = .photos(list)
        return true
    }

    // MARK: the filter and the next missing tile

    public enum Filter: String, CaseIterable, Sendable { case all, missing, done }

    public static func filtered(_ v: Values, _ f: Filter) -> [Tile] {
        tiles(v).filter { f == .all || (f == .missing) != taken(v, $0) }
    }

    /// The next required tile without a photo after `current`, wrapping round; nil when none is missing.
    public static func nextMissing(_ v: Values, after current: String?) -> Tile? {
        let all = tiles(v), start = all.firstIndex { $0.id == current } ?? -1
        let order = all.indices.map { all[(start + 1 + $0 + all.count) % all.count] }
        return order.first { $0.required && !taken(v, $0) && $0.id != current }
    }

    /// `ภาพบังคับยังขาด 2 ภาพ · ไม่บังคับ 1 ภาพ`: the required count from `Tank.photoCompletion`, the optional tiles taken.
    public static func summary(_ v: Values) -> String {
        let c = Tank.photoCompletion(v), left = c.total - c.filled
        let optional = tiles(v).filter { !$0.required && taken(v, $0) }.count
        return (left > 0 ? "ภาพบังคับยังขาด \(left) ภาพ" : "ภาพบังคับครบแล้ว") + " · ไม่บังคับ \(optional) ภาพ"
    }

    // MARK: the shot point

    /// Where a photo was taken on the tank's plan (metres from the top-left corner), from its GPS against A1's (taken as
    /// the tank's centre, ค่าสมมติ) and the tank's azimuth; nil without both positions.
    public static func shotPoint(_ p: Photo, tank v: Values, site gps: String) -> Pt? {
        guard let lat = p.lat, let lon = p.lon, let c = GPS.parse(gps), let t = TankPoints.tankSize(v) else { return nil }
        let east = (lon - c.lon) * 111_320 * cos(c.lat * .pi / 180), north = (lat - c.lat) * 110_540
        let az = Double(Tank.azimuth(v) ?? 0) * .pi / 180
        // the plan's top faces `az`: east and north on the plan
        let x = east * cos(az) - north * sin(az), y = -east * sin(az) - north * cos(az)
        return Pt(t.w / 2 + x, t.h / 2 + y)
    }
}

extension TankPhotos {
    /// The inspector's `จุดถ่าย · GPS` (230 × 230): the tank, its tables when laid out, and a numbered dot where each
    /// tile's photo was taken (the selected one filled, the others outlined); points off the drawing sit on its edge.
    /// nil when the selected photo has no position (or the site no GPS).
    public static func shotPlan(_ v: Values, site gps: String, selected: String?) -> Sketch? {
        let all = tiles(v)
        guard let t = TankPoints.tankSize(v), let sel = all.first(where: { $0.id == selected }), let sp = photo(v, sel),
              shotPoint(sp, tank: v, site: gps) != nil else { return nil }
        let S = 230.0, pad = 22.0, k = min((S - 2 * pad) / t.w, (S - 2 * pad) / t.h)
        let ox = (S - t.w * k) / 2, oy = (S - t.h * k) / 2
        let blue = RGBA(hex: 0x1F6FB5), line = RGBA(hex: 0x111111)
        var o: [DrawOp] = [.rect(Box(0, 0, S, S), stroke: nil, fill: .white),
                           .rect(Box(ox, oy, t.w * k, t.h * k), stroke: line, fill: RGBA(hex: 0xF3F6FA), width: 1.6)]
        if let l = TankLayout.current(v) {
            for tb in l.builtTables { o.append(.rect(Box(ox + tb.x * k, oy + tb.y * k, tb.w * k, tb.h * k), stroke: nil, fill: RGBA(hex: 0xE1E8F2))) }
        }
        for (i, tile) in all.enumerated() {
            guard let p = photo(v, tile), let q = shotPoint(p, tank: v, site: gps) else { continue }
            let x = min(S - 10, max(10, ox + q.x * k)), y = min(S - 10, max(10, oy + q.y * k)), on = tile.id == sel.id
            o.append(.circle(Pt(x, y), r: 8, stroke: .white, fill: on ? blue : RGBA(hex: 0x8FB3D9), width: 1.5))
            o.append(.text("\(i + 1)", at: Pt(x, y), size: 9.5, bold: true, color: .white, align: .center))
        }
        return Sketch(width: S, height: S, ops: o)
    }
}
