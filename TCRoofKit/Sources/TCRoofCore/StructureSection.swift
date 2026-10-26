import Foundation

/// A roof cut across the ridge as the team's CAD sections draw it: members at their true depth, C purlins standing on
/// the rafters under the sheet, posts with the beam they carry cut (concrete hatched), the fascia (and a boxed eave's
/// soffit), and level marks on the right (`ระดับหัวเสา +4.00`) with a dimension chain between them.
///
/// Everything is in metres: x from the left support, y up from the ground. C1's section A-A (`RoofSection`) and the
/// measured sections of C2 / C3 (`MeasuredRoofSection`) build one, then `draw` turns it into sketch ops for the page,
/// the PDF and the DXF.
public struct StructureSection: Sendable {
    public enum Material: Sendable, Equatable { case steel, wood, concrete }

    /// A cross-section as the cut shows it: a lipped C, a box (tube, H, wood), or solid concrete (hatched).
    public struct Profile: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case channel(lip: Double), box, concrete }
        public var kind: Kind
        /// Height and width (m).
        public var h, b: Double
        public init(_ kind: Kind, h: Double, b: Double) { self.kind = kind; self.h = h; self.b = b }
    }

    /// A member size read from what was entered ("C-100x50x20x3.2", "ไม้ 1\"x8\"", "ค.ส.ล 0.20x0.40", C2's "C 10x5x2").
    public struct Size: Sendable, Equatable {
        /// How deep it draws in the section's plane, and how wide across it (m).
        public var depth, width: Double
        public var material: Material
        /// The member as a cut shows it.
        public var profile: Profile

        /// A C's lip (m), for its line along the member; nil for anything else.
        public var lip: Double? { if case let .channel(l) = profile.kind { return l }; return nil }

        public static func c(_ h: Double, _ b: Double = 0.05, lip: Double = 0.02) -> Size {
            Size(depth: h, width: b, material: .steel, profile: Profile(.channel(lip: lip), h: h, b: b))
        }
        public static func tube(_ h: Double) -> Size { Size(depth: h, width: h, material: .steel, profile: Profile(.box, h: h, b: h)) }
        /// Reinforced concrete `w` wide, `h` deep.
        public static func rc(_ w: Double, _ h: Double) -> Size { Size(depth: h, width: w, material: .concrete, profile: Profile(.concrete, h: h, b: w)) }

        /// The size, or nil for "-", an empty field or anything without a size in it.
        ///
        /// Steel shapes go through `SteelSection` (millimetres). Otherwise the numbers decide the unit: inches with `"`,
        /// metres for concrete under 3 ("0.20x0.40"), and for the rest millimetres from 30 up, else centimetres (C2 and
        /// C3 enter centimetres). A T2 truss reads its depth from "ลึก 1.00".
        public static func read(_ raw: String?) -> Size? {
            guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty, s != "-" else { return nil }
            if let r = s.range(of: "@") { s = String(s[..<r.lowerBound]) }
            s = s.replacingOccurrences(of: "ซม.", with: "").trimmingCharacters(in: .whitespaces)
            if let r = s.range(of: "ลึก") {
                let d = numbers(String(s[r.upperBound...])).first ?? 0.8
                return Size(depth: d, width: 0.3, material: .steel, profile: Profile(.box, h: d, b: 0.3))
            }
            if s.contains("ค.ส.ล") || s.contains("คสล") || s.contains("คอนกรีต") {
                let n = numbers(s)
                guard n.count >= 2 else { return .rc(0.2, 0.4) }
                let k = n[0] > 3 ? 0.01 : 1
                return .rc(n[0] * k, n[1] * k)
            }
            if let st = SteelSection.parse(s) {
                switch st.shape {
                case let .lippedC(h, b, lip, _, double):
                    return Size(depth: h / 1000, width: (double ? 2 * b : b) / 1000, material: .steel,
                                profile: Profile(.channel(lip: lip / 1000), h: h / 1000, b: b / 1000))
                case let .tube(h, b, _): return box(h / 1000, b / 1000, .steel)
                case let .pipe(d, _): return box(d / 1000, d / 1000, .steel)
                case let .h(h, b, _, _, _): return box(h / 1000, b / 1000, .steel)
                case let .angle(a, b, _): return box(a / 1000, b / 1000, .steel)
                }
            }
            let inch = s.contains("\"") || s.contains("”")
            let wood = inch || s.contains("ไม้") || s.contains("ไฟเบอร์")
            let double = s.hasPrefix("2C")
            if double { s.removeFirst(2) }
            let n = numbers(s)
            guard let first = n.first, first > 0 else { return nil }
            let unit = inch ? 0.0254 : (n.max() ?? 0) >= 30 ? 0.001 : 0.01
            if wood {
                let a = n.prefix(2).map { $0 * unit }
                return box(a.max() ?? first * unit, a.min() ?? first * unit, .wood)
            }
            let h = first * unit, b = n.count > 1 ? n[1] * unit : h
            if s.trimmingCharacters(in: .whitespaces).hasPrefix("C") {
                let lip = n.count > 2 ? n[2] * unit : b * 0.4
                return Size(depth: h, width: double ? 2 * b : b, material: .steel, profile: Profile(.channel(lip: lip), h: h, b: b))
            }
            return box(h, b, .steel)
        }
        static func box(_ h: Double, _ b: Double, _ m: Material) -> Size { Size(depth: h, width: b, material: m, profile: Profile(.box, h: h, b: b)) }

        /// The numbers in a size, with ½ ¼ ¾ read ("1½" → 1.5).
        static func numbers(_ s: String) -> [Double] {
            var out: [Double] = [], cur = ""
            func flush() { if let d = Double(cur) { out.append(d) }; cur = "" }
            for ch in s {
                switch ch {
                case "0"..."9", ".": cur.append(ch)
                case "½", "¼", "¾":
                    let f = ch == "½" ? 0.5 : ch == "¼" ? 0.25 : 0.75
                    let whole = Double(cur) ?? 0; cur = ""; out.append(whole + f)
                default: flush()
                }
            }
            flush()
            return out
        }
    }

    /// A member along `path` (one straight piece, a pitched rafter, a curve), `depth` deep. `face` says where the path
    /// runs: through the middle, along the top face (the member hangs under it) or along the bottom face (it sits on it).
    /// Paths run left to right, so "top" is the side up.
    public struct Member: Sendable {
        public enum Face: Sendable { case centre, top, bottom }
        public var path: [Pt]
        public var depth: Double
        public var face: Face
        /// Member row 1…7 of C1's table (nil when it isn't one).
        public var row: Int?
        /// A steel C's lip, drawn as a line that far inside its top face (nil: none).
        public var lip: Double?
        /// A line (two points) the member's start is cut along, as where a strut meets a sloping rafter (nil: square).
        public var trimStart: (Pt, Pt)?
        public init(_ path: [Pt], depth: Double, face: Face = .centre, row: Int? = nil, lip: Double? = nil, trimStart: (Pt, Pt)? = nil) {
            self.path = path; self.depth = depth; self.face = face; self.row = row; self.lip = lip; self.trimStart = trimStart
        }
        /// `p` with its first point moved along its first piece to `trimStart`.
        func trimmed(_ p: [Pt]) -> [Pt] {
            guard let (a, b) = trimStart, p.count >= 2 else { return p }
            let d = Pt(p[1].x - p[0].x, p[1].y - p[0].y), e = Pt(b.x - a.x, b.y - a.y), den = d.x * e.y - d.y * e.x
            guard abs(den) > 1e-12 else { return p }
            let t = ((a.x - p[0].x) * e.y - (a.y - p[0].y) * e.x) / den
            return [Pt(p[0].x + d.x * t, p[0].y + d.y * t)] + p.dropFirst()
        }

        /// How far the top and bottom faces are from the path, along its left normal.
        var faces: (top: Double, bottom: Double) { face == .centre ? (depth / 2, -depth / 2) : face == .top ? (0, -depth) : (depth, 0) }
        /// The outline, mitred at every bend.
        public var outline: [Pt] {
            guard path.count >= 2 else { return [] }
            return trimmed(StructureSection.offset(path, faces.top)) + trimmed(StructureSection.offset(path, faces.bottom)).reversed()
        }
        /// The lip lines, that far inside each face, as the team draws a C seen from its side.
        public var lipLines: [[Pt]] {
            guard let lip, lip > 0, 2 * lip < depth, path.count >= 2 else { return [] }
            return [trimmed(StructureSection.offset(path, faces.top - lip)), trimmed(StructureSection.offset(path, faces.bottom + lip))]
        }

        /// A point on the member's centre line `t` of the way along its piece `i`.
        public func centre(piece i: Int = 0, at t: Double) -> Pt {
            let a = path[min(i, path.count - 2)], b = path[min(i, path.count - 2) + 1], n = Self.leftNormal(a, b)
            let off = face == .centre ? 0 : face == .top ? -depth / 2 : depth / 2
            return Pt(a.x + (b.x - a.x) * t + n.x * off, a.y + (b.y - a.y) * t + n.y * off)
        }

        static func leftNormal(_ a: Pt, _ b: Pt) -> Pt {
            let l = max(hypot(b.x - a.x, b.y - a.y), 1e-12)
            return Pt(-(b.y - a.y) / l, (b.x - a.x) / l)
        }
    }

    /// `p` moved `d` along its left normal (up for a path left to right), mitred at every bend.
    public static func offset(_ p: [Pt], _ d: Double) -> [Pt] {
        guard p.count >= 2 else { return p }
        let normals = (0..<(p.count - 1)).map { Member.leftNormal(p[$0], p[$0 + 1]) }
        return p.indices.map { i in
            var n = normals[min(i, normals.count - 1)]
            if i > 0 && i < p.count - 1 {
                let a = normals[i - 1], b = normals[i], m = Pt(a.x + b.x, a.y + b.y), l = hypot(m.x, m.y)
                if l > 1e-9 {
                    let u = Pt(m.x / l, m.y / l), c = max(0.2, u.x * a.x + u.y * a.y)
                    n = Pt(u.x / c, u.y / c)
                }
            }
            return Pt(p[i].x + n.x * d, p[i].y + n.y * d)
        }
    }

    /// A member running along the ridge, cut by the section (a purlin, an eave beam, a T2), standing on the face at `at`
    /// with its height along `up` (a unit vector). A C's flanges point along +`opens` across `up`.
    public struct Cut: Sendable {
        public var profile: Profile
        public var at: Pt
        public var up: Pt
        public var opens: Double
        public var row: Int?
        public init(_ profile: Profile, at: Pt, up: Pt = Pt(0, 1), opens: Double = 1, row: Int? = nil) {
            self.profile = profile; self.at = at; self.up = up; self.opens = opens; self.row = row
        }

        /// A C as its open line (lip, flange, web, flange, lip), a box or a concrete block as a closed loop.
        public var outline: [Pt] {
            let u = Pt(up.y, -up.x), h = profile.h, b = profile.b
            func P(_ s: Double, _ t: Double) -> Pt { Pt(at.x + s * u.x + t * up.x, at.y + s * u.y + t * up.y) }
            switch profile.kind {
            case let .channel(lip):
                let s0 = -opens * b / 2, s1 = opens * b / 2
                return [P(s1, lip), P(s1, 0), P(s0, 0), P(s0, h), P(s1, h), P(s1, h - lip)]
            case .box, .concrete:
                return [P(-b / 2, 0), P(b / 2, 0), P(b / 2, h), P(-b / 2, h)]
            }
        }
        public var centre: Pt { Pt(at.x + up.x * profile.h / 2, at.y + up.y * profile.h / 2) }
    }

    /// A post seen in elevation, centred on `x`, from the ground (or the cut) up to `top`.
    public struct Post: Sendable {
        public var x, width, top: Double
        public var row: Int?
        public init(x: Double, width: Double, top: Double, row: Int? = nil) { self.x = x; self.width = width; self.top = top; self.row = row }
    }

    /// A level mark. `chain` labels the dimension from the level below to this one (nil: its length).
    public struct Level: Sendable, Equatable {
        public var y: Double
        public var label: String
        public var chain: String?
        public init(_ y: Double, _ label: String, chain: String? = nil) { self.y = y; self.label = label; self.chain = chain }
        /// "+4.00", "±0.00" above `datum`.
        public func value(from datum: Double = 0) -> String { abs(y - datum) < 0.005 ? "±0.00" : String(format: "%+.2f", y - datum) }
    }

    /// In drawing order: a later member covers the ends of an earlier one, as the CAD trims them.
    public var members: [Member] = []
    public var posts: [Post] = []
    /// Drawn after the members (beams under them, purlins on them).
    public var cuts: [Cut] = []
    /// The roof sheet's line, eave to eave.
    public var sheet: [Pt] = []
    /// The ridge cap's apex on the sheet.
    public var ridge: Pt?
    /// From the lowest up.
    public var levels: [Level] = []
    public var grid: [(x: Double, name: String)] = []
    /// The ridge's centre line.
    public var centreLine: Double?
    /// The height the level values count from: the ground, or the eave when its height isn't known.
    public var datum = 0.0

    public init() {}

    /// What the section covers (m): left, right and top.
    public var extent: (minX: Double, maxX: Double, maxY: Double) {
        var pts = members.flatMap(\.outline) + cuts.flatMap(\.outline) + sheet
        pts += posts.flatMap { [Pt($0.x - $0.width / 2, $0.top), Pt($0.x + $0.width / 2, $0.top)] }
        guard let f = pts.first else { return (0, 1, 1) }
        return pts.reduce((f.x, f.x, f.y)) { (min($0.0, $1.x), max($0.1, $1.x), max($0.2, $1.y)) }
    }

    // MARK: drawing

    static let ink = RGBA(hex: 0x1A1D22), sheetC = RGBA(hex: 0x1F4F78), navy = RGBA(hex: 0x16325C), gridC = RGBA(hex: 0x8A97AA)
    static let hatchC = RGBA(hex: 0x3A3F47), soil = RGBA(hex: 0x8B6F47)
    /// A metal sheet's thickness as the team draws it (m).
    public static let sheetThickness = 0.005

    /// Sketch ops with each one's CAD layer key (`SECTION`, `POST`, `PURLIN`, `GRID`, `LEVEL`, `DIM`; nil for what the DXF
    /// leaves out: the background, dimension texts, the soil hatch), the level chain as DIMENSIONs, and the ops that draw
    /// those dimensions' lines (the DXF writes the DIMENSIONs instead).
    public struct Drawn: Sendable {
        public var ops: [DrawOp] = []
        public var tags: [String?] = []
        public var dimensions: [SketchDXF.Dimension] = []
        public var dimensionOps: Set<Int> = []
        /// Each level's value text, in `levels` order (the page puts its tappable chips there).
        public var levelValues: [Pt] = []
        public init() {}
        public mutating func add(_ op: DrawOp, _ tag: String?) { ops.append(op); tags.append(tag) }
        mutating func dim(_ op: DrawOp) { dimensionOps.insert(ops.count); add(op, "DIM") }
    }

    /// Draws the section into `d`. `P` maps metres to sketch points at `k` points per metre; posts end at the sketch's
    /// `floor` (the ground line when `ground`, else a break line); grid bubbles sit at `gridTop` when given; the level
    /// marks run across `marks` (sketch x), their dimension chain at its start.
    public func draw(into d: inout Drawn, _ P: (Pt) -> Pt, scale k: Double, marks: ClosedRange<Double>, gridTop: Double?,
                     floor: Double, ground: Bool, text ts: Double = 9.5) {
        let ext = extent
        // grid and the ridge's centre line
        let dash: [Double] = [12, 3, 2, 3]
        for g in grid {
            let x = P(Pt(g.x, 0)).x
            d.add(.line(Pt(x, (gridTop ?? P(Pt(0, ext.maxY)).y) + 9), Pt(x, floor + 8), width: 0.6, color: Self.gridC, dash: dash), "GRID")
            if let gy = gridTop {
                d.add(.circle(Pt(x, gy), r: 9, stroke: Self.navy, fill: .white, width: 1), "GRID")
                d.add(.text(g.name, at: Pt(x, gy), size: 11, bold: true, color: Self.navy, align: .center), "GRID")
            }
        }
        if let c = centreLine {
            let x = P(Pt(c, 0)).x, low = levels.first.map { P(Pt(0, $0.y)).y } ?? floor
            d.add(.line(Pt(x, (gridTop ?? P(Pt(0, ext.maxY)).y) + 4), Pt(x, low), width: 0.6, color: Self.gridC, dash: dash), "GRID")
        }

        // posts in elevation, then the members, then what is cut (beams under them, purlins on them)
        for p in posts {
            let a = P(Pt(p.x - p.width / 2, p.top)), b = P(Pt(p.x + p.width / 2, p.top))
            d.add(.polygon([a, b, Pt(b.x, floor), Pt(a.x, floor)], stroke: Self.ink, fill: .white, width: 0.9), "POST")
            if !ground {
                let w = b.x - a.x
                d.add(.polyline([Pt(a.x - 6, floor), Pt(a.x + w * 0.3, floor), Pt(a.x + w * 0.4, floor - 4), Pt(a.x + w * 0.6, floor + 4),
                                 Pt(a.x + w * 0.7, floor), Pt(b.x + 6, floor)], width: 0.8, color: Self.ink), "POST")
            }
        }
        if ground {
            let x0 = P(Pt(ext.minX, 0)).x - 16, x1 = P(Pt(ext.maxX, 0)).x + 16
            d.add(.line(Pt(x0, floor), Pt(x1, floor), width: 1.4, color: Self.soil), "SECTION")
            d.add(.hatch(Box(x0, floor, x1 - x0, 5), color: Self.soil.withAlpha(0.6), spacing: 6), nil)
        }
        for m in members {
            d.add(.polygon(m.outline.map(P), stroke: Self.ink, fill: .white, width: 0.9), "SECTION")
            for l in m.lipLines { d.add(.polyline(l.map(P), width: 0.5, color: Self.ink), "SECTION") }
        }
        for c in cuts {
            let o = c.outline.map(P), tag = c.row == 1 ? "PURLIN" : "SECTION"
            switch c.profile.kind {
            case .channel:
                d.add(.polyline(o, width: 0.9, color: Self.ink), tag)
            case .box:
                d.add(.polygon(o, stroke: Self.ink, fill: .white, width: 0.9), tag)
            case .concrete:
                d.add(.polygon(o, stroke: Self.ink, fill: .white, width: 0.9), tag)
                let xs = o.map(\.x), ys = o.map(\.y)
                if let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() {
                    d.add(.hatch(Box(x0, y0, x1 - x0, y1 - y0), color: Self.hatchC, spacing: max(3, 0.08 * k)), tag)
                }
            }
        }
        if sheet.count > 1 {
            // the sheet's top, and its underside 5 mm down resting on the purlins, as the team draws a metal sheet cut
            d.add(.polyline(sheet.map(P), width: 1.2, color: Self.sheetC), "SECTION")
            d.add(.polyline(Self.offset(sheet, -Self.sheetThickness).map(P), width: 0.5, color: Self.sheetC), "SECTION")
        }
        if let r = ridge, let i = sheet.firstIndex(where: { abs($0.x - r.x) < 1e-9 && abs($0.y - r.y) < 1e-9 }), i > 0, i < sheet.count - 1 {
            // the ridge cap: a flashing 0.30 m down each slope, 15 mm over the sheet, folded up 40 mm at the apex
            func along(_ to: Pt, _ len: Double) -> Pt {
                let l = max(hypot(to.x - r.x, to.y - r.y), 1e-9)
                return Pt(r.x + (to.x - r.x) / l * len, r.y + (to.y - r.y) / l * len + 0.015)
            }
            let a = along(sheet[i - 1], 0.3), b = along(sheet[i + 1], 0.3)
            let cap = [Pt(a.x, a.y - 0.02), a, Pt(r.x, r.y + 0.055), b, Pt(b.x, b.y - 0.02)]
            d.add(.polyline(cap.map(P), width: 1.2, color: Self.sheetC), "CAP")
        }

        // level marks on the right, a dashed line from the section to each, with the chain between them
        let right = P(Pt(ext.maxX, 0)).x + 8, x0 = marks.lowerBound, x1 = marks.upperBound, chainX = x0 + 4
        var prev: (y: Double, sy: Double)?
        let ys = levels.map { P(Pt(0, $0.y)).y }
        for (i, l) in levels.enumerated() {
            let y = ys[i]
            // its text over the line, or under it when the next level up leaves no room
            let ty = i + 1 < ys.count && y - ys[i + 1] < ts + 5 ? y + 7 : y - 7
            d.add(.line(Pt(right, y), Pt(x0 + 12, y), width: 0.6, color: Self.gridC, dash: [6, 3]), "LEVEL")
            d.add(.line(Pt(x0 + 12, y), Pt(x1, y), width: 0.8, color: Self.ink), "LEVEL")
            d.add(.text(l.label, at: Pt(x0 + 15, ty), size: ts, color: Self.ink), "LEVEL")
            d.add(.text(l.value(from: datum), at: Pt(x1, ty), size: ts, bold: true, color: Self.ink, align: .right), "LEVEL")
            d.levelValues.append(Pt(x1 - 18, ty))
            if let p = prev {
                d.dim(.line(Pt(chainX, p.sy + 4), Pt(chainX, y - 4), width: 0.7, color: Self.navy))
                for sy in [p.sy, y] { d.dim(.line(Pt(chainX - 3, sy + 3), Pt(chainX + 3, sy - 3), width: 0.8, color: Self.navy)) }
                let t = l.chain ?? String(format: "%.2f", l.y - p.y)
                d.add(.text(t, at: Pt(chainX - 4, (p.sy + y) / 2), size: ts - 0.5, color: Self.navy, align: .right), nil)
                d.dimensions.append(SketchDXF.Dimension(Pt(right, p.sy), Pt(right, y), at: Pt(chainX, 0), vertical: true, text: t, size: 12))
            }
            prev = (l.y, y)
        }
    }
}
