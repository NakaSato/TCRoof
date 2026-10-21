import Foundation

/// C1's answers as the roof PV layout's input, and the choices the แผงบนหลังคา tab keeps on the job
/// (docs/specs/roof-pv-layout.md §2 and §5.1). The pitch comes from the frame type's slope, the purlins from ระยะแป,
/// the obstacles from the plan's skylights, keep-out zones and obstacles, the latitude from A1's GPS.
public enum RoofMount {
    public enum Key {
        /// Compass bearing of the plan's top edge (°).
        public static let bearing = "planBearing"
        /// The tab's choices (`Choice`, JSON).
        public static let choice = "pvMount"
        /// A shed roof's low side: "start" = the plan's top (ridge along x) or left; empty = bottom or right.
        public static let shedLow = "shedLow"
    }

    /// The shed roof's low eave is at the plan's top or left.
    public static func shedLowAtStart(_ v: Values) -> Bool { v.text(Key.shedLow) == "start" }
    public static func setShedLowAtStart(_ v: inout Values, _ on: Bool) { v[Key.shedLow] = on ? .text("start") : nil }

    /// Concrete tiles: tile hooks on the rafters (กระเบื้องลอนคู่ sits on purlins like metal sheet).
    public static func tileRoof(_ v: Values) -> Bool {
        (v.choice(Roof.Key.material) ?? v.text(Roof.Key.material)).contains("ซีแพค")
    }

    /// Latitude when the survey has no GPS: central Thailand (ค่าสมมติ).
    public static let defaultLatitude = 15.0

    /// The shapes the layout handles; nil for a flat, curved or saw-tooth roof (or another typed in).
    public static func shape(_ v: Values) -> RoofMountInput.Shape? {
        let t = v.choice(Roof.Key.shape) ?? v.text(Roof.Key.shape)
        if t.isEmpty || t.contains("จั่ว") { return .gable }
        if t.contains("ปั้นหยา") { return .hip }
        if t.contains("เพิง") { return .shed }
        return nil
    }

    public static func bearing(_ v: Values) -> Double? { v.number(Key.bearing) }
    public static func setBearing(_ v: inout Values, _ b: Double?) {
        v[Key.bearing] = b.map { .text(String(format: "%.0f", ($0.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360))) }
    }

    /// Latitude from A1's `gps` ("lat, lon").
    public static func latitude(gps: String) -> Double? { GPS.parse(gps).map(\.lat) }

    /// The engine's input. `latitude` nil takes the default.
    public static func input(_ v: Values, latitude: Double?) -> RoofMountInput {
        let xs = Roof.spans(v, .x), ys = Roof.spans(v, .y), alongX = Roof.ridge(v) == .h
        let shape = shape(v) ?? .gable
        let across = alongX ? ys.reduce(0, +) : xs.reduce(0, +)
        let run = shape == .shed ? across : across / 2
        let rise = tan(Roof.slope(v) * .pi / 180) * run
        let obstacles: [RoofMountInput.Obstacle] = Roof.areas(v).map { a in
            let kind: RoofObstacleKind = a.kind == Roof.skylightKind ? .skylight : a.kind == Roof.keepOutKind ? .keepOut
                : RoofObstacleKind(rawValue: a.kind) ?? .other
            return .init(kind: kind, x: a.x, y: a.y, w: a.w, h: a.h, height: a.height, label: a.label.isEmpty ? nil : a.label,
                         coverable: kind == .skylight && a.canCover)
        }
        var out = RoofMountInput(spansX: xs, spansY: ys, ridgeAlongX: alongX, shape: shape, eaveHeight: 0, ridgeHeight: rise,
                                 purlinSpacing: Roof.purlinSpacing(v), latitude: latitude ?? defaultLatitude, bearing: bearing(v) ?? 0,
                                 obstacles: obstacles, shedLowAtStart: shape == .shed && shedLowAtStart(v))
        out.tileRoof = tileRoof(v)
        return out
    }

    /// The standard with the catalogue's default module: what a job starts from.
    public static var defaultStandard: RoofMountStandard {
        var s = RoofMountStandard()
        let m = RoofPlan.Module.catalogDefault
        s.moduleLength = m.length; s.moduleWidth = m.width; s.moduleWp = (m.kW * 1000).rounded(); s.moduleKg = m.kg
        (s.clampMin, s.clampMax) = s.clampFromModule
        return s
    }

    // MARK: - Choices

    /// What the tab keeps: the fixing method, the shade switch, the faces in use, each face's placement from the
    /// search (or the slider), the slots removed, the job's standard, and the inputs the placements were found for.
    public struct Choice: Codable, Equatable, Sendable {
        public var ribClamp = false
        public var avoidShade = true
        public var faceUse: [String: Bool] = [:]
        public var placements: [String: RoofMountLayout.Placement] = [:]
        public var removed: [RoofMountLayout.SlotRef] = []
        /// nil = `defaultStandard`.
        public var standard: RoofMountStandard?
        /// `digest` of the inputs the placements belong to; the search runs again when they change.
        public var digest = ""
        /// A walkway after every n columns; 0 = none.
        public var walkwayEvery = 0
        public init() {}

        enum CodingKeys: String, CodingKey { case ribClamp, avoidShade, faceUse, placements, removed, standard, digest, walkwayEvery }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ribClamp = try c.decodeIfPresent(Bool.self, forKey: .ribClamp) ?? false
            avoidShade = try c.decodeIfPresent(Bool.self, forKey: .avoidShade) ?? true
            faceUse = try c.decodeIfPresent([String: Bool].self, forKey: .faceUse) ?? [:]
            placements = try c.decodeIfPresent([String: RoofMountLayout.Placement].self, forKey: .placements) ?? [:]
            removed = try c.decodeIfPresent([RoofMountLayout.SlotRef].self, forKey: .removed) ?? []
            standard = try c.decodeIfPresent(RoofMountStandard.self, forKey: .standard)
            digest = try c.decodeIfPresent(String.self, forKey: .digest) ?? ""
            walkwayEvery = try c.decodeIfPresent(Int.self, forKey: .walkwayEvery) ?? 0
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(ribClamp, forKey: .ribClamp); try c.encode(avoidShade, forKey: .avoidShade)
            try c.encode(faceUse, forKey: .faceUse); try c.encode(placements, forKey: .placements)
            try c.encode(removed, forKey: .removed); try c.encodeIfPresent(standard, forKey: .standard)
            try c.encode(digest, forKey: .digest)
            if walkwayEvery > 0 { try c.encode(walkwayEvery, forKey: .walkwayEvery) }
        }

        /// The layout's options for a roof (tile hooks on concrete tiles).
        public func options(tile: Bool) -> RoofMountLayout.Options {
            .init(ribClamp: ribClamp && !tile, avoidShade: avoidShade, faceUse: faceUse, removed: Set(removed), tileHooks: tile,
                  walkwayEvery: walkwayEvery)
        }
        public var standardOrDefault: RoofMountStandard { standard ?? RoofMount.defaultStandard }
    }

    public static func choice(_ v: Values) -> Choice {
        let t = v.text(Key.choice)
        return t.isEmpty ? Choice() : (try? JSONDecoder().decode(Choice.self, from: Data(t.utf8))) ?? Choice()
    }

    public static func setChoice(_ v: inout Values, _ c: Choice) {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        v[Key.choice] = (try? e.encode(c)).map { .text(String(decoding: $0, as: UTF8.self)) }
    }

    /// A short fingerprint of what the best layout depends on: the roof, its obstacles, the latitude and bearing, the
    /// standard, the fixing method and the shade switch (not the faces in use or the removed slots).
    public static func digest(_ input: RoofMountInput, choice c: Choice) -> String {
        var parts: [String] = [
            input.spansX.map { String(format: "%.3f", $0) }.joined(separator: ","),
            input.spansY.map { String(format: "%.3f", $0) }.joined(separator: ","),
            input.ridgeAlongX ? "x" : "y", input.shape.rawValue,
            String(format: "%.4f|%.3f|%.1f|%.1f", input.ridgeHeight - input.eaveHeight, input.purlinSpacing, input.latitude, input.bearing),
            c.ribClamp ? "rib" : "purlin", c.avoidShade ? "shade" : "noshade",
        ]
        // added later: only when set, so older jobs keep their digest
        if input.tileRoof { parts.append("tile") }
        if input.shedLowAtStart { parts.append("shedStart") }
        if c.walkwayEvery > 0 { parts.append("walk \(c.walkwayEvery)") }
        parts += input.obstacles.map { o in
            String(format: "%@ %.2f %.2f %.2f %.2f %.2f %@", o.kind.rawValue, o.x, o.y, o.w, o.h, o.heightOrDefault, o.coverable ? "c" : "")
        }
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        parts.append((try? e.encode(c.standardOrDefault)).map { String(decoding: $0, as: UTF8.self) } ?? "")
        // FNV-1a, 64 bit
        var h: UInt64 = 0xcbf29ce484222325
        for b in parts.joined(separator: "\n").utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// The layout as the job keeps it: the stored placements while the inputs are the ones they were found for, else
    /// the best layout. `fresh` is true when the search ran (the caller stores its placements with `remember`).
    public static func layout(_ v: Values, latitude: Double?) -> (layout: RoofMountLayout, fresh: Bool) {
        let input = input(v, latitude: latitude), c = choice(v)
        if !c.placements.isEmpty, c.digest == digest(input, choice: c) {
            return (RoofMountLayout.compute(input, standard: c.standardOrDefault, options: c.options(tile: input.tileRoof),
                                            placements: c.placements), false)
        }
        return (RoofMountLayout.best(input, standard: c.standardOrDefault, options: c.options(tile: input.tileRoof)), true)
    }

    /// Keeps a freshly searched layout's placements with the inputs they belong to; removed slots are cleared, since
    /// the slots have moved. Returns true when there were removed slots to clear.
    @discardableResult
    public static func remember(_ layout: RoofMountLayout, in v: inout Values, latitude: Double?) -> Bool {
        var c = choice(v)
        let cleared = !c.removed.isEmpty
        c.placements = layout.placements
        c.removed = []
        c.digest = digest(input(v, latitude: latitude), choice: c)
        setChoice(&v, c)
        return cleared
    }

    // MARK: - Report lines (docs/specs/roof-pv-layout.md §7)

    /// `ผังแผงอัตโนมัติ 216 แผง | 129.6 kWp | 191.1 MWh/ปี | ลาด 15° | แป @1.20 ม. | 4 แถว`
    public static func summaryLine(_ m: RoofMountLayout) -> String {
        let q = m.quantities, rows = m.faces.filter(\.used).map(\.rows.count).max() ?? 0
        let fixing = m.options.tileHooks ? "ขอเกี่ยวกระเบื้อง" : m.options.ribClamp ? "จับสันลอน" : String(format: "แป @%.2f ม.", m.purlins.count > 1 ? m.purlins[1] - m.purlins[0] : 0)
        return "ผังแผงอัตโนมัติ \(q.modules) แผง | " + String(format: "%.1f kWp | %.1f MWh/ปี | ลาด %.0f° | ", q.kWp, q.energy, m.roof.tilt * 180 / .pi)
            + fixing + " | \(rows) แถว"
    }

    /// `BOQ: ราง 502.2 ม. | ต่อราง 80 | L-foot 496 | ตัวจับกลาง 364 | ตัวจับปลาย 136 | 34 ชุดราง`
    public static func boqLine(_ q: RoofMountQuantities) -> String {
        String(format: "BOQ: ราง %.1f ม. | ต่อราง %d | %@ %d | ตัวจับกลาง %d | ตัวจับปลาย %d | %d ชุดราง", q.railLength, q.splices,
               footName(q), q.feet, q.midClamps, q.endClamps, q.runs) + (q.cuts > 0 ? " | ตัดแผง \(q.cuts)" : "")
    }

    /// `L-foot`, or `ขอเกี่ยวกระเบื้อง` on a tile roof.
    public static func footName(_ q: RoofMountQuantities) -> String { q.hooks ? "ขอเกี่ยวกระเบื้อง" : "L-foot" }

    /// `น้ำหนักเพิ่ม 13.4 กก./ม² (เกณฑ์ 15)`, with a warning above the standard's limit.
    public static func loadLine(_ q: RoofMountQuantities) -> String {
        String(format: "น้ำหนักแผงและราง %.1f กก./ม² (เกณฑ์ %.0f)", q.load, q.loadLimit)
            + (q.overLoad ? " | เกินเกณฑ์ ตรวจโครงหลังคากับวิศวกรโครงสร้าง" : "")
    }

    /// Whether the job has a roof PV layout to print: a supported shape and spans.
    public static func printable(_ v: Values) -> Bool {
        shape(v) != nil && !v.text(Roof.Key.spansX).isEmpty && !v.text(Roof.Key.spansY).isEmpty
    }

    /// What the layout assumed (ค่าสมมติ), for the line under the plan and the report.
    public static func assumptions(_ v: Values, latitude: Double?) -> [String] {
        var out: [String] = []
        if latitude == nil { out.append("ละติจูด \(Int(defaultLatitude))° (ยังไม่มีพิกัด A1)") }
        if bearing(v) == nil { out.append("ขอบบนแปลนหันทิศเหนือ (ยังไม่ระบุทิศ)") }
        if v.number(Roof.Key.purlin) == nil && !tileRoof(v) && !choice(v).ribClamp { out.append("ระยะแป 1.00 ม.") }
        let defaulted = Roof.areas(v).filter { a in
            guard a.height == nil, let k = RoofObstacleKind(rawValue: a.kind), k.defaultHeight > 0 else { return false }
            return true
        }
        if !defaulted.isEmpty { out.append("ความสูงสิ่งกีดขวาง \(defaulted.count) จุดตามชนิด") }
        if shape(v) == nil { out.append("หลังคานี้คิดเป็นทรงจั่ว") }
        return out
    }
}
