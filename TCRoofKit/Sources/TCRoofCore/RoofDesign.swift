import Foundation

/// A standard building roof for C1 (docs/specs/standard-designs.md §7): the C1 answers the roof drawings and the roof
/// PV layout read (spans, shape, frame, purlins, heights, member sizes and the plan's obstacles), saved from a checked
/// roof. None is seeded: the first station of each building type saves one. Picking one fills C1; each item is then
/// confirmed on site (`ตรงแบบ`) or, once its values change, counts as differing from the design.
public struct RoofDesign: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var source: String
    /// The C1 answers of `keys`.
    public var values: Values
    public var revision = 1
    public var basedOn: String? = nil
    public var savedBy: String? = nil
    public var savedAt: Date? = nil
    public var archived = false

    public enum Key {
        /// The design the roof was filled from ("<id>"), its snapshot (JSON) and the items confirmed on site.
        public static let design = "roofDesign", snapshot = "roofDesignSnapshot", checked = "roofDesignChecked"
    }

    /// The C1 answers a design carries.
    public static let keys: [String] = [Roof.Key.spansX, Roof.Key.spansY, Roof.Key.sheetDir, Roof.Key.ridge, Roof.Key.frame, Roof.Key.bays,
                                        Roof.Key.posts, Roof.Key.overhang, Roof.Key.clearHeight, Roof.Key.purlin, Roof.Key.standard,
                                        Roof.Key.shape, Roof.Key.material, Roof.Key.structure, Roof.Key.obstacles]
        + (1...7).map(Roof.Key.member)

    public init(id: String, name: String, source: String, values: Values) {
        self.id = id; self.name = name; self.source = source; self.values = values
    }
    enum CodingKeys: String, CodingKey { case id, name, source, values, revision, basedOn, savedBy, savedAt, archived }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        values = try c.decodeIfPresent(Values.self, forKey: .values) ?? Values()
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        basedOn = try c.decodeIfPresent(String.self, forKey: .basedOn)
        savedBy = try c.decodeIfPresent(String.self, forKey: .savedBy); savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }

    public var width: Double { Roof.spans(values, .x).reduce(0, +) }
    public var length: Double { Roof.spans(values, .y).reduce(0, +) }
    /// "32 × 24 ม."
    public var size: String { "\(fmt(width)) × \(fmt(length)) ม." }

    // MARK: saving and picking

    /// The roof's C1 answers as a new design.
    public static func from(_ v: Values, name: String, job: String, by email: String?, now: Date = Date()) -> RoofDesign {
        var kept = Values()
        for k in keys { kept[k] = v[k] }
        let base = current(v)
        var d = RoofDesign(id: "roof-" + UUID().uuidString.lowercased(), name: name,
                           source: "บันทึกจากงาน \(job)" + (base.map { " อ้างอิง " + $0.name } ?? ""), values: kept)
        d.basedOn = base?.id
        d.savedBy = email
        d.savedAt = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        return d
    }

    /// Fills C1 with the design (every check starts again) and keeps a snapshot of it.
    public static func apply(_ v: inout Values, _ d: RoofDesign) {
        for k in keys { v[k] = d.values[k] }
        v[Key.design] = .text(d.id)
        v[Key.snapshot] = (try? JSONEncoder().encode(d)).map { .text(String(decoding: $0, as: UTF8.self)) }
        v[Key.checked] = nil
    }

    /// The design C1 was filled from (its snapshot).
    public static func current(_ v: Values) -> RoofDesign? {
        let s = v.text(Key.snapshot)
        guard !v.text(Key.design).isEmpty, !s.isEmpty else { return nil }
        return try? JSONDecoder().decode(RoofDesign.self, from: Data(s.utf8))
    }

    /// The designs offered for a roof, the closest to its spans first; `matches` within `TankDesign.tolerance`.
    public static func ranked(_ v: Values) -> [(design: RoofDesign, difference: Double?, matches: Bool)] {
        let w = parseSpans(v.text(Roof.Key.spansX)).reduce(0, +), l = parseSpans(v.text(Roof.Key.spansY)).reduce(0, +)
        let list = DesignLibrary.shared.roofs.filter { !$0.archived }
        guard w > 0, l > 0 else { return list.map { ($0, nil, false) } }
        return list.map { d -> (RoofDesign, Double?, Bool) in
            let diff = min(abs(w - d.width) + abs(l - d.length), abs(w - d.length) + abs(l - d.width))
            return (d, diff, diff <= TankDesign.tolerance)
        }
        .sorted { ($0.1 ?? 0) < ($1.1 ?? 0) }
        .map { (design: $0.0, difference: $0.1, matches: $0.2) }
    }

    // MARK: checking on site

    public enum State: String, Sendable { case open, matches, differs, missing, added }
    public struct Item: Hashable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let state: State
        public var done: Bool { state != .open }
    }

    /// The groups of answers checked as one item.
    static let groups: [(id: String, title: String, keys: [String])] = [
        ("size", "ขนาดและช่วงเสา", [Roof.Key.spansX, Roof.Key.spansY]),
        ("frame", "รูปทรงและโครงหลังคา", [Roof.Key.shape, Roof.Key.material, Roof.Key.structure, Roof.Key.frame, Roof.Key.ridge,
                                          Roof.Key.sheetDir, Roof.Key.bays, Roof.Key.posts, Roof.Key.standard]),
        ("purlin", "ระยะแป", [Roof.Key.purlin]),
        ("heights", "ชายคาและความสูงใต้โครง", [Roof.Key.overhang, Roof.Key.clearHeight]),
        ("members", "ขนาดชิ้นส่วน 1–7", (1...7).map(Roof.Key.member)),
    ]

    static func same(_ a: Obstacle, _ b: Obstacle) -> Bool {
        a.kind == b.kind && a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h && a.canCover == b.canCover && a.height == b.height
    }
    static func title(_ o: Obstacle, _ n: Int) -> String {
        let kind = o.kind == Roof.skylightKind ? "แผ่นใส" : o.kind == Roof.keepOutKind ? "เขตห้ามติด"
            : (RoofObstacleKind(rawValue: o.kind)?.title ?? (o.label.isEmpty ? "สิ่งกีดขวาง" : o.label))
        return "\(kind) \(n)"
    }

    public static func checked(_ v: Values) -> Set<String> { Set(v.text(Key.checked).split(separator: " ").map(String.init)) }

    /// Every item of the design against the roof now: answers changed since the design differ (they were checked),
    /// unchanged ones match once confirmed; an obstacle gone from the plan is missing, a new one added.
    public static func items(_ v: Values) -> [Item] {
        guard let d = current(v) else { return [] }
        let ok = checked(v)
        var out: [Item] = groups.map { g in
            let changed = g.keys.contains { v[$0] != d.values[$0] }
            return Item(id: g.id, title: g.title, state: changed ? .differs : ok.contains(g.id) ? .matches : .open)
        }
        let now = v.obstacles(Roof.Key.obstacles), was = d.values.obstacles(Roof.Key.obstacles)
        for (i, o) in was.enumerated() {
            let id = "o:" + o.id.uuidString, t = title(o, i + 1)
            guard let here = now.first(where: { $0.id == o.id }) else { out.append(Item(id: id, title: t, state: .missing)); continue }
            out.append(Item(id: id, title: t, state: !same(here, o) ? .differs : ok.contains(id) ? .matches : .open))
        }
        for (i, o) in now.enumerated() where !was.contains(where: { $0.id == o.id }) {
            out.append(Item(id: "o:" + o.id.uuidString, title: title(o, i + 1), state: .added))
        }
        return out
    }

    /// `ตรงแบบ` on an item (again: unconfirmed).
    public static func toggle(_ v: inout Values, _ id: String) {
        var c = checked(v)
        if c.contains(id) { c.remove(id) } else { c.insert(id) }
        v[Key.checked] = c.isEmpty ? nil : .text(c.sorted().joined(separator: " "))
    }
    /// Every item still open confirmed together.
    public static func confirmRest(_ v: inout Values) {
        var c = checked(v)
        for i in items(v) where i.state == .open { c.insert(i.id) }
        v[Key.checked] = c.isEmpty ? nil : .text(c.sorted().joined(separator: " "))
    }

    /// Every item checked (confirmed, or found different).
    public static func done(_ v: Values) -> Bool { let i = items(v); return !i.isEmpty && i.allSatisfy(\.done) }

    /// For the report: the design, the counts and one line per difference (the tank's `Summary`).
    public static func summary(_ v: Values) -> TankDesign.Summary? {
        guard let d = current(v) else { return nil }
        var s = TankDesign.Summary(design: d.name + " rev \(d.revision)")
        s.movedLabel = "ต่างจากแบบ"
        s.photosExpected = false
        for i in items(v) {
            switch i.state {
            case .open: s.open += 1
            case .matches: s.matches += 1
            case .differs: s.moved += 1; s.differences.append(i.title + " ต่างจากแบบ"); s.photos.append(nil)
            case .missing: s.absent += 1; s.differences.append(i.title + " ไม่มีจริง"); s.photos.append(nil)
            case .added: s.added += 1; s.differences.append(i.title + " เพิ่มหน้างาน"); s.photos.append(nil)
            }
        }
        return s
    }

    public func exported() -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return (try? e.encode(self)) ?? Data()
    }
    public static func imported(_ data: Data) throws -> RoofDesign {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(RoofDesign.self, from: data)
    }
}
