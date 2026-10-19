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
        let rise = tan(Roof.frame(v).slope * .pi / 180) * run
        let obstacles: [RoofMountInput.Obstacle] = Roof.areas(v).map { a in
            let kind: RoofObstacleKind = a.kind == Roof.skylightKind ? .skylight : a.kind == Roof.keepOutKind ? .keepOut
                : RoofObstacleKind(rawValue: a.kind) ?? .other
            return .init(kind: kind, x: a.x, y: a.y, w: a.w, h: a.h, height: a.height, label: a.label.isEmpty ? nil : a.label,
                         coverable: kind == .skylight && a.canCover)
        }
        return RoofMountInput(spansX: xs, spansY: ys, ridgeAlongX: alongX, shape: shape, eaveHeight: 0, ridgeHeight: rise,
                              purlinSpacing: Roof.purlinSpacing(v), latitude: latitude ?? defaultLatitude, bearing: bearing(v) ?? 0,
                              obstacles: obstacles)
    }

    /// The standard with the catalogue's default module: what a job starts from.
    public static var defaultStandard: RoofMountStandard {
        var s = RoofMountStandard()
        let m = RoofPlan.Module.catalogDefault
        s.moduleLength = m.length; s.moduleWidth = m.width; s.moduleWp = (m.kW * 1000).rounded()
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
        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ribClamp = try c.decodeIfPresent(Bool.self, forKey: .ribClamp) ?? false
            avoidShade = try c.decodeIfPresent(Bool.self, forKey: .avoidShade) ?? true
            faceUse = try c.decodeIfPresent([String: Bool].self, forKey: .faceUse) ?? [:]
            placements = try c.decodeIfPresent([String: RoofMountLayout.Placement].self, forKey: .placements) ?? [:]
            removed = try c.decodeIfPresent([RoofMountLayout.SlotRef].self, forKey: .removed) ?? []
            standard = try c.decodeIfPresent(RoofMountStandard.self, forKey: .standard)
            digest = try c.decodeIfPresent(String.self, forKey: .digest) ?? ""
        }

        public var options: RoofMountLayout.Options {
            .init(ribClamp: ribClamp, avoidShade: avoidShade, faceUse: faceUse, removed: Set(removed))
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
            return (RoofMountLayout.compute(input, standard: c.standardOrDefault, options: c.options, placements: c.placements), false)
        }
        return (RoofMountLayout.best(input, standard: c.standardOrDefault, options: c.options), true)
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

    /// What the layout assumed (ค่าสมมติ), for the line under the plan and the report.
    public static func assumptions(_ v: Values, latitude: Double?) -> [String] {
        var out: [String] = []
        if latitude == nil { out.append("ละติจูด \(Int(defaultLatitude))° (ยังไม่มีพิกัด A1)") }
        if bearing(v) == nil { out.append("ขอบบนแปลนหันทิศเหนือ (ยังไม่ระบุทิศ)") }
        if v.number(Roof.Key.purlin) == nil { out.append("ระยะแป 1.00 ม.") }
        let defaulted = Roof.areas(v).filter { a in
            guard a.height == nil, let k = RoofObstacleKind(rawValue: a.kind), k.defaultHeight > 0 else { return false }
            return true
        }
        if !defaulted.isEmpty { out.append("ความสูงสิ่งกีดขวาง \(defaulted.count) จุดตามชนิด") }
        if shape(v) == nil { out.append("หลังคานี้คิดเป็นทรงจั่ว") }
        return out
    }
}
