import Foundation

/// Standard designs of กปภ. clear-water tanks (docs/specs/standard-designs.md §2): only the two sheets the team supplied,
/// as docs/specs/img/tank_plan.py draws them. Picking one in D1 sub-step 2 writes the tank's bays and the design's
/// vents, hatches, ladders and pipes as standard points (`TankPoints`), in place of the generic layout; the surveyor then
/// checks each one on site as before, and `summary` lists where the site differs from the design.
public struct TankDesign: Hashable, Sendable, Identifiable, Codable {
    /// A vent in the middle of a bay: row from the top, column from the left.
    public struct Cell: Hashable, Sendable, Codable {
        public let row, col: Int
        public init(row: Int, col: Int) { self.row = row; self.col = col }
    }
    /// A hatch, ladder or pipe on a wall, `along` metres from the wall's start (top-left corner).
    public struct OnWall: Hashable, Sendable, Codable {
        public let wall: TankPoints.Wall
        public let along: Double
        public var note = ""
        public init(wall: TankPoints.Wall, along: Double, note: String = "") { self.wall = wall; self.along = along; self.note = note }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            wall = try c.decode(TankPoints.Wall.self, forKey: .wall); along = try c.decode(Double.self, forKey: .along)
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        }
    }

    public let id: String
    public var name: String
    public let source: String
    public let nx, ny: Int
    public let span: Double
    /// "box" (ช่องระบายแบบกล่อง) or "cross" (แบบเห็ด on a column head).
    public let ventStyle: String
    public let vents: [Cell]
    public let hatches, ladders, pipes: [OnWall]
    /// Bays that aren't all `span` (a design saved from a job); nil = `nx` / `ny` bays of `span`.
    public var spansX: [Double]? = nil
    public var spansY: [Double]? = nil
    /// The library's bookkeeping (docs/specs/standard-designs.md §2): raised on every edit; the design it was saved
    /// from; who saved it and when; archived designs stay in the library but aren't offered.
    public var revision = 1
    public var basedOn: String? = nil
    public var savedBy: String? = nil
    public var savedAt: Date? = nil
    public var archived = false
    /// The scanned drawing's pages (docs/specs/standard-designs.md §3.4).
    public var sheet: [Photo] = []

    /// One of the sheets the team supplied (built in, never edited).
    public var isSeed: Bool { Self.seeds.contains { $0.id == id } }
    public var xs: [Double] { spansX ?? Array(repeating: span, count: nx) }
    public var ys: [Double] { spansY ?? Array(repeating: span, count: ny) }
    public var width: Double { xs.reduce(0, +) }
    public var height: Double { ys.reduce(0, +) }
    /// "64 × 40 ม."
    public var size: String { "\(fmt(width)) × \(fmt(height)) ม." }
    /// What the design holds, for its card: `ระบาย 12 | ลงถัง 6 | บันได 3 | ท่อ 0`.
    public var contents: String {
        "ระบาย \(vents.count) | ลงถัง \(hatches.count) | บันได \(ladders.count) | ท่อ \(pipes.count)"
    }
    /// The design's plan for its card (as D1 would draw it once picked), turned like the match.
    public func thumbnail(turned: Bool = false) -> Sketch? {
        DesignThumbnail.sketch(xs: turned ? Array(ys.reversed()) : xs, ys: turned ? xs : ys,
                               marks: DesignThumbnail.marks(points(turned: turned)))
    }

    /// The measured size matches a design within this, |ΔW| + |ΔL| in metres (§3.1; decided 2026-10-19).
    public static let tolerance = 1.0
    /// A point within this of its design position still matches the design (m; decided 2026-10-19).
    public static let pointTolerance = 0.2
    /// A hatch's distance in from its wall (m), as on the sheets.
    static let hatchInset = 0.15

    public static let pwa64x40 = TankDesign(
        id: "pwa-64x40", name: "ถังน้ำใส 64×40 (ช่องระบายแบบกล่อง)", source: "แบบ กปภ. แปลนฝาถังน้ำใส",
        nx: 16, ny: 10, span: 4, ventStyle: "box",
        vents: [0, 3, 6, 9].flatMap { r in [0, 4, 8, 12, 15].map { Cell(row: r, col: $0) } },
        hatches: [OnWall(wall: .top, along: 14.3), OnWall(wall: .top, along: 46), OnWall(wall: .bottom, along: 14.1),
                  OnWall(wall: .bottom, along: 45.7), OnWall(wall: .left, along: 18), OnWall(wall: .left, along: 22),
                  OnWall(wall: .right, along: 18.2), OnWall(wall: .right, along: 22.2)],
        ladders: [OnWall(wall: .top, along: 14.3), OnWall(wall: .top, along: 46), OnWall(wall: .bottom, along: 14.1),
                  OnWall(wall: .bottom, along: 45.7), OnWall(wall: .left, along: 22), OnWall(wall: .right, along: 22.2)],
        pipes: [OnWall(wall: .left, along: 14, note: "ท่อเชื่อมถังน้ำใส Ø600 มม."), OnWall(wall: .left, along: 26, note: "ท่อเชื่อมถังน้ำใส Ø600 มม."),
                OnWall(wall: .right, along: 14, note: "ท่อน้ำใส Ø700 มม."), OnWall(wall: .right, along: 26, note: "ท่อน้ำใส Ø700 มม."),
                OnWall(wall: .right, along: 17, note: "ท่อน้ำล้น Ø500 มม."), OnWall(wall: .right, along: 23, note: "ท่อน้ำล้น Ø500 มม.")])

    public static let pwa40x40 = TankDesign(
        id: "pwa-40x40", name: "ถังน้ำใส 40×40 (ช่องระบายแบบเห็ด)", source: "แบบ กปภ. แปลนพื้น เสา ค.ส.ล. ที่ฝาถัง",
        nx: 10, ny: 10, span: 4, ventStyle: "cross",
        vents: [0, 4, 9].flatMap { r in [0, 4, 5, 9].map { Cell(row: r, col: $0) } },
        hatches: [OnWall(wall: .top, along: 10.2), OnWall(wall: .top, along: 29.6), OnWall(wall: .bottom, along: 10.2),
                  OnWall(wall: .bottom, along: 29.6), OnWall(wall: .left, along: 21.7), OnWall(wall: .right, along: 21.7)],
        ladders: [OnWall(wall: .left, along: 6.4), OnWall(wall: .left, along: 33.4), OnWall(wall: .right, along: 33.4)],
        pipes: [])

    /// The two sheets the team supplied.
    public static let seeds = [pwa64x40, pwa40x40]
    /// The designs offered: the sheets and the library's saved designs not archived.
    public static var all: [TankDesign] { seeds + DesignLibrary.shared.tanks.filter { !$0.archived } }

    public init(id: String, name: String, source: String, nx: Int, ny: Int, span: Double, ventStyle: String, vents: [Cell],
                hatches: [OnWall], ladders: [OnWall], pipes: [OnWall]) {
        self.id = id; self.name = name; self.source = source; self.nx = nx; self.ny = ny; self.span = span
        self.ventStyle = ventStyle; self.vents = vents; self.hatches = hatches; self.ladders = ladders; self.pipes = pipes
    }

    enum CodingKeys: String, CodingKey {
        case id, name, source, nx, ny, span, ventStyle, vents, hatches, ladders, pipes, spansX, spansY, revision, basedOn, savedBy, savedAt
        case archived, sheet
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        nx = try c.decode(Int.self, forKey: .nx); ny = try c.decode(Int.self, forKey: .ny); span = try c.decode(Double.self, forKey: .span)
        ventStyle = try c.decodeIfPresent(String.self, forKey: .ventStyle) ?? "box"
        vents = try c.decodeIfPresent([Cell].self, forKey: .vents) ?? []
        hatches = try c.decodeIfPresent([OnWall].self, forKey: .hatches) ?? []
        ladders = try c.decodeIfPresent([OnWall].self, forKey: .ladders) ?? []
        pipes = try c.decodeIfPresent([OnWall].self, forKey: .pipes) ?? []
        spansX = try c.decodeIfPresent([Double].self, forKey: .spansX); spansY = try c.decodeIfPresent([Double].self, forKey: .spansY)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        basedOn = try c.decodeIfPresent(String.self, forKey: .basedOn)
        savedBy = try c.decodeIfPresent(String.self, forKey: .savedBy); savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        sheet = try c.decodeIfPresent([Photo].self, forKey: .sheet) ?? []
    }

    // MARK: matching the measured size

    /// A design for a measured tank: `turned` when it fits a quarter turn (a 40 × 64 tank and the 64 × 40 design);
    /// `difference` is |ΔW| + |ΔL| in the better orientation, nil without a measured size.
    public struct Match: Hashable, Sendable, Identifiable {
        public let design: TankDesign
        public let turned: Bool
        public let difference: Double?
        public var id: String { design.id }
        public var matches: Bool { (difference ?? .infinity) <= TankDesign.tolerance }
        /// "ตรงกับขนาดที่วัด" / "ต่างจากที่วัด 24 ม." / nil without a size.
        public var line: String? {
            guard let difference else { return nil }
            return matches ? "ตรงกับขนาดที่วัด" : "ต่างจากที่วัด \(fmt((difference * 100).rounded() / 100)) ม."
        }
    }

    /// Every design, the closest to the tank's size first.
    public static func ranked(_ v: Values) -> [Match] {
        // the designs are rectangular: none for a round tank
        guard !Tank.isRound(v) else { return [] }
        let all = Self.all
        guard let t = TankPoints.tankSize(v) else { return all.map { Match(design: $0, turned: false, difference: nil) } }
        return all.map { d in
            let straight = abs(t.w - d.width) + abs(t.h - d.height), turned = abs(t.w - d.height) + abs(t.h - d.width)
            return turned < straight - 1e-9 ? Match(design: d, turned: true, difference: turned) : Match(design: d, turned: false, difference: straight)
        }
        .enumerated()
        .sorted { ($0.element.difference ?? 0, $0.offset) < ($1.element.difference ?? 0, $1.offset) }
        .map(\.element)
    }

    // MARK: writing it into D1

    /// The design's points, unchecked, at their positions; `turned` turns the plan a quarter clockwise (the design's
    /// top wall becomes the right one).
    public func points(turned: Bool = false) -> [Obstacle] {
        let W = width, H = height
        var out: [Obstacle] = []
        func put(_ kind: String, cx: Double, cy: Double, note: String = "") {
            let s = TankPoints.size(kind)
            let (x, y) = turned ? (H - cy, cx) : (cx, cy)
            let px = TankPoints.text(x - s / 2), py = TankPoints.text(y - s / 2)
            let label = TankPoints.nextLabel(out, kind: kind)
            out.append(Obstacle(label: label, x: px, y: py, w: fmt(s), h: fmt(s), kind: kind, origin: TankPoints.standard,
                                stdX: px, stdY: py, note: note))
        }
        func centre(_ p: OnWall, size s: Double, inset: Double) -> (Double, Double) {
            switch p.wall {
            case .top: return (p.along, inset + s / 2)
            case .bottom: return (p.along, H - inset - s / 2)
            case .left: return (inset + s / 2, p.along)
            case .right: return (W - inset - s / 2, p.along)
            }
        }
        // bay centres from the bays (a saved design's may differ)
        let gx = xs, gy = ys
        func mid(_ s: [Double], _ i: Int) -> Double { s.prefix(max(0, i)).reduce(0, +) + (s[safe: i] ?? span) / 2 }
        for c in vents { put(TankPoints.vent, cx: mid(gx, c.col), cy: mid(gy, c.row)) }
        for h in hatches { let c = centre(h, size: TankPoints.hatchSize, inset: Self.hatchInset); put(TankPoints.hatch, cx: c.0, cy: c.1) }
        for l in ladders { let c = centre(l, size: TankPoints.size(TankPoints.ladder), inset: 0); put(TankPoints.ladder, cx: c.0, cy: c.1) }
        for p in pipes { let c = centre(p, size: TankPoints.size(TankPoints.pipe), inset: 0); put(TankPoints.pipe, cx: c.0, cy: c.1, note: p.note) }
        return out
    }

    /// Replaces the tank's bays and points with the design's (every check starts again) and remembers the design.
    /// Replaces the tank's bays and points with the design's (every check starts again), remembers the design and
    /// keeps a snapshot of it, so a later edit of the library never changes this job (§2).
    public static func apply(_ v: inout Values, _ d: TankDesign, turned: Bool = false) {
        // turned a quarter clockwise: the design's rows become columns, read from the bottom
        let sx = turned ? Array(d.ys.reversed()) : d.xs, sy = turned ? d.xs : d.ys
        // a design is rectangular
        v[Tank.Key.shape] = nil
        Roof.setSpans(&v, .x, sx)
        Roof.setSpans(&v, .y, sy)
        TankPoints.write(&v, d.points(turned: turned))
        v[Tank.Key.design] = .text(d.id + (turned ? "@r" : ""))
        var snapshot = d
        snapshot.sheet = []
        v[Tank.Key.designSnapshot] = (try? JSONEncoder().encode(snapshot)).map { .text(String(decoding: $0, as: UTF8.self)) }
    }

    /// The design the tank's points came from: the job's snapshot, else (older jobs) the library's design by id.
    public static func current(_ v: Values) -> (design: TankDesign, turned: Bool)? {
        let key = v.text(Tank.Key.design)
        guard !key.isEmpty else { return nil }
        let turned = key.hasSuffix("@r"), id = turned ? String(key.dropLast(2)) : key
        let snap = v.text(Tank.Key.designSnapshot)
        if !snap.isEmpty, let d = try? JSONDecoder().decode(TankDesign.self, from: Data(snap.utf8)), d.id == id { return (d, turned) }
        return (seeds + DesignLibrary.shared.tanks).first { $0.id == id }.map { ($0, turned) }
    }

    // MARK: saving a checked tank as a design (§2)

    /// The checked tank as a new design: its bays, its vents by bay, its hatches, ladders and pipes along their walls
    /// (points marked absent left out), based on the design it started from.
    public static func from(_ v: Values, name: String, job: String, by email: String?, now: Date = Date()) -> TankDesign? {
        let s = Tank.spans(v)
        guard !Tank.isRound(v), !s.x.isEmpty, !s.y.isEmpty, let t = TankPoints.tankSize(v) else { return nil }
        func index(_ spans: [Double], _ at: Double) -> Int {
            var edge = 0.0
            for (i, w) in spans.enumerated() { edge += w; if at < edge { return i } }
            return spans.count - 1
        }
        var vents: [Cell] = [], hatches: [OnWall] = [], ladders: [OnWall] = [], pipes: [OnWall] = []
        for o in TankPoints.points(v) where !o.isAbsent {
            guard let r = TankPoints.rect(o) else { continue }
            if o.kind == TankPoints.vent {
                vents.append(Cell(row: index(s.y, r.cy), col: index(s.x, r.cx)))
                continue
            }
            let wall = TankPoints.wall(r, w: t.w, h: t.h)
            let along = ((wall == .top || wall == .bottom ? r.cx : r.cy) * 100).rounded() / 100
            let w = OnWall(wall: wall, along: along, note: o.note)
            switch o.kind {
            case TankPoints.hatch: hatches.append(w)
            case TankPoints.ladder: ladders.append(w)
            case TankPoints.pipe: pipes.append(w)
            default: continue
            }
        }
        let base = current(v)
        let uniformX = Set(s.x).count == 1, uniformY = Set(s.y).count == 1, span = s.x.first ?? 4
        var d = TankDesign(id: "team-" + UUID().uuidString.lowercased(), name: name, source: "บันทึกจากงาน \(job)" + (base.map { " อ้างอิง " + $0.design.name } ?? ""),
                           nx: s.x.count, ny: s.y.count, span: span, ventStyle: base?.design.ventStyle ?? "box", vents: vents,
                           hatches: hatches, ladders: ladders, pipes: pipes)
        if !(uniformX && uniformY && s.x.first == s.y.first) { d.spansX = s.x; d.spansY = s.y }
        d.basedOn = base?.design.id
        d.savedBy = email
        d.savedAt = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))   // whole seconds, as files keep them
        return d
    }

    /// `.tcdesign`: one design as JSON, to send by LINE or e-mail and import on another iPad.
    public func exported() -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        var d = self
        d.sheet = []
        return (try? e.encode(d)) ?? Data()
    }
    public static func imported(_ data: Data) throws -> TankDesign {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(TankDesign.self, from: data)
    }

    // MARK: where the site differs (§6)

    /// The check's result for the report: counts by state and one line per difference.
    public struct Summary: Hashable, Sendable {
        /// "ถังน้ำใส 40×40 (ช่องระบายแบบเห็ด)", or the generic layout's name.
        public var design: String
        public var matches = 0, moved = 0, absent = 0, added = 0, open = 0
        /// Confirmed together (`TankPoints.confirmRest`), not one by one.
        public var bulk = 0
        /// What `moved` counts: a point moved on a tank, an answer changed on a roof (`RoofDesign`).
        public var movedLabel = "ย้าย"
        /// A difference is expected to have a photo (a tank's points; a roof's items have none).
        public var photosExpected = true
        /// "V5 ย้าย 4.00 ม. (16.70, 18.70 → 12.70, 18.70)", "H3 ไม่มีจริง", "V13 เพิ่มหน้างาน (20.00, 21.70)"
        public var differences: [String] = []
        /// Each difference's photo, in the same order (nil when it has none).
        public var photos: [Photo?] = []
        /// "ตรงแบบ 9 | ย้าย 1 | ไม่มีจริง 1 | เพิ่มหน้างาน 1 | ยืนยันแบบรวม 4 | ยังไม่ตรวจ 8"
        public var counts: String {
            var parts = ["ตรงแบบ \(matches)", "\(movedLabel) \(moved)", "ไม่มีจริง \(absent)", "เพิ่มหน้างาน \(added)"]
            if bulk > 0 { parts.append("ยืนยันแบบรวม \(bulk)") }
            if open > 0 { parts.append("ยังไม่ตรวจ \(open)") }
            return parts.joined(separator: " | ")
        }
    }

    /// Nil when the tank has no standard points (an older job's obstacles, or none yet).
    public static func summary(_ v: Values) -> Summary? {
        let list = TankPoints.points(v)
        guard list.contains(where: TankPoints.isStandard) else { return nil }
        var s = Summary(design: current(v).map { $0.design.name + ($0.turned ? " (หมุน 90°)" : "") } ?? "ผังมาตรฐานทั่วไป")
        func at(_ x: String, _ y: String) -> String {
            String(format: "%.2f, %.2f", NumberInput.value(x) ?? 0, NumberInput.value(y) ?? 0)
        }
        for o in list {
            let name = o.label + (o.note.isEmpty ? "" : " " + o.note)
            if o.isAbsent {
                s.absent += 1; s.differences.append("\(name) ไม่มีจริง"); s.photos.append(o.photo)
            } else if !TankPoints.isStandard(o) {
                s.added += 1; s.differences.append("\(name) เพิ่มหน้างาน (\(at(o.x, o.y)))"); s.photos.append(o.photo)
            } else if o.status.isEmpty {
                s.open += 1
            } else if o.bulk {
                s.bulk += 1
            } else if TankPoints.moved(o) {
                s.moved += 1
                let dx = (NumberInput.value(o.x) ?? 0) - (NumberInput.value(o.stdX) ?? 0)
                let dy = (NumberInput.value(o.y) ?? 0) - (NumberInput.value(o.stdY) ?? 0)
                s.differences.append(String(format: "%@ ย้าย %.2f ม. (%@ → %@)", name, hypot(dx, dy), at(o.stdX, o.stdY), at(o.x, o.y)))
                s.photos.append(o.photo)
            } else {
                s.matches += 1
            }
        }
        return s
    }
}
