import Foundation

/// The roof framing section of C2 หลังคาอาคาร and C3 บ้าน (docs/specs/auto-drawing.md §4.4), drawn from the measured
/// sizes and heights rather than a chosen frame type: a rafter frame (rafter, tie beam, king post and struts) on a
/// gable or hip, a shed, a flat slab or a curved roof, with the purlins, columns, ground, dimensions, the members
/// entered and the assumed values. C1 has its own section (`RoofSection`).
public enum MeasuredRoofSection {
    public enum Shape: Sendable, Equatable { case gable, hip, shed, flat, curved }

    public struct Input: Sendable, Equatable {
        public var title: String
        public var shape: Shape
        /// Across the ridge (m).
        public var span: Double
        /// Ground to the tie beam at the column (m); nil when not measured.
        public var eave: Double?
        /// Tie beam to the roof at the ridge (m); 0 for a flat roof.
        public var rise: Double
        /// Horizontal, from the column to the rafter's tip (m).
        public var overhang: Double
        /// Along the slope (m).
        public var purlinSpacing: Double
        /// The members as entered: name and size.
        public var members: [Member]
        public var assumed: [String] = []
        public var warnings: [String] = []

        /// The horizontal run of one slope.
        public var run: Double { shape == .shed ? span : span / 2 }
        /// Degrees.
        public var pitch: Double { atan2(rise, run) * 180 / .pi }
        public var slopeLength: Double { hypot(run, rise) }
    }
    public struct Member: Sendable, Equatable {
        public let name: String, size: String
    }

    /// The drawing's input, or why it can't be drawn. Only C2 (`roofForm`) and C3 (`house`) have one.
    public static func input(_ m: SurveyModule) -> (input: Input?, missing: [String]) {
        switch m.type {
        case .house: return house(m.values)
        case .roofForm: return roofForm(m.values)
        default: return (nil, [])
        }
    }

    /// The section's `Sketch`, or why it can't be drawn.
    public static func draw(_ m: SurveyModule, width: Double = 690) -> (sketch: Sketch?, missing: [String]) {
        let r = input(m)
        return (r.input.map { sketch($0, width: width) }, r.missing)
    }

    /// The field ids C2 adds to its group "อาคาร" (optional, so completion is unchanged).
    public enum Key {
        public static let eaveHeight = "eaveHeight", ridgeHeight = "ridgeHeight"
    }

    // MARK: input

    static func shape(_ v: Values) -> Shape {
        switch v.choice("roofShape") {
        case "หลังคาทรงปั้นหยา"?: return .hip
        case "หลังคาเพิงหมาแหงน"?: return .shed
        case "หลังคาคอนกรีต (ดาดฟ้า)"?: return .flat
        case "หลังคาทรงโค้ง"?: return .curved
        default: return .gable
        }
    }
    static func cm(_ v: Values, _ id: String) -> Double? { v.number(id).flatMap { $0 > 0 ? $0 / 100 : nil } }

    /// Applies the pitch checks: ridge ≤ eave, pitch outside 3–45°, over 60° refused.
    static func checked(_ i: Input) -> (input: Input?, missing: [String]) {
        var i = i
        guard i.span > 0, i.span.isFinite, i.rise.isFinite, i.rise >= 0 else { return (nil, ["ความกว้างอาคาร"]) }
        if i.rise < 0.05 && i.shape != .flat { i.shape = .flat; i.rise = 0; i.warnings.append("ความสูงสันเท่าชายคา วาดเป็นหลังคาแบน") }
        if i.shape != .flat {
            guard i.pitch <= 60 else { return (nil, [String(format: "ความสูงที่ให้มุมไม่เกิน 60° (ได้ %.1f°)", i.pitch)]) }
            if i.pitch < 3 || i.pitch > 45 { i.warnings.append(String(format: "ตรวจความสูงอีกครั้ง (มุมประมาณ %.1f°)", i.pitch)) }
        } else { i.rise = 0 }
        return (i, [])
    }

    /// C3: the width (ซม.) across the ridge, i1 ground → ridge, i2 ground → the eave's tip (ซม.), h the rafter's tip
    /// to the column, c the purlin spacing; `roofAngle` only when the heights are missing or disagree by > 10 %.
    static func house(_ v: Values) -> (input: Input?, missing: [String]) {
        guard let B = cm(v, "buildingWidth") else { return (nil, ["ความกว้างอาคาร (ข้อ 1)"]) }
        let sh = shape(v), o = cm(v, "measH") ?? 0
        let i1 = cm(v, "measI1"), i2 = cm(v, "measI2"), angle = v.number("roofAngle").flatMap { $0 > 0 && $0 < 90 ? $0 : nil }
        var assumed: [String] = [], warnings: [String] = []
        let run = sh == .shed ? B : B / 2
        var theta: Double?   // radians
        if let i1, let i2 {
            if i1 > i2 {
                theta = atan((i1 - i2) / (run + o))
                if let angle, let t = theta, abs(t * 180 / .pi - angle) > 0.1 * angle {
                    warnings.append(String(format: "มุมจากความสูง %.1f° ต่างจากข้อ 12 (%@°) ใช้ค่าจากความสูง", t * 180 / .pi, fmt(angle)))
                }
            } else if sh != .flat {
                warnings.append("ความสูงสันต้องมากกว่าชายคา")
            }
        }
        if theta == nil, let angle, sh != .flat {
            theta = angle * .pi / 180
            assumed.append("มุมเอียงจากข้อ 12 (" + fmt(angle) + "°)")
        }
        if theta == nil && sh != .flat { return (nil, ["ความสูง i1 / i2 (ข้อ 10–11) หรือมุมเอียง (ข้อ 12)"]) }
        let t = theta ?? 0
        let eave = i2.map { $0 + o * tan(t) }
        if eave == nil { assumed.append("ไม่ทราบความสูงชายคา") }
        let s = cm(v, "measC")
        if s == nil && sh != .flat { assumed.append("ระยะแป 1.00 ม.") }
        var members: [Member] = []
        let steel = v.choice("structMaterial") == "โครงสร้างเหล็ก"
        for (name, wood, steelKey) in [("แป", "woodPurlin", "steelPurlin"), ("จันทัน", "woodRafter", "steelRafter")] {
            let size: String
            if steel {
                let dims = ["F", "G", "H"].compactMap { v.number(steelKey + $0).map { fmt($0) } }
                let type = v.text(steelKey + "Type").trimmingCharacters(in: .whitespaces)
                size = dims.isEmpty ? "" : (type.isEmpty ? "" : type + " ") + dims.joined(separator: "x") + " ซม."
            } else {
                let dims = ["F", "G"].compactMap { v.number(wood + $0).map { fmt($0) } }
                size = dims.isEmpty ? "" : "ไม้ " + dims.joined(separator: "x") + " ซม."
            }
            let at = name == "แป" ? v.number("measC") : v.number("measA")
            members.append(Member(name: name, size: size.isEmpty ? "" : size + (at.map { " @" + fmt($0) + " ซม." } ?? "")))
        }
        return checked(Input(title: "บ้าน / อาคาร", shape: sh, span: B, eave: eave, rise: run * tan(t), overhang: o,
                             purlinSpacing: s.map { min(3, max(0.2, $0)) } ?? 1.0, members: members, assumed: assumed, warnings: warnings))
    }

    /// C2: the width (ซม.) across the ridge, the eave and ridge heights (ม., the two optional fields of group อาคาร), and
    /// the purlin spacing `space1` (ซม.).
    static func roofForm(_ v: Values) -> (input: Input?, missing: [String]) {
        guard let B = cm(v, "buildingWidth") else { return (nil, ["ความกว้างอาคาร"]) }
        let sh = shape(v), E = v.number(Key.eaveHeight).flatMap { $0 > 0 ? $0 : nil }, R = v.number(Key.ridgeHeight)
        var assumed: [String] = [], warnings: [String] = []
        var rise = 0.0
        if sh != .flat {
            guard let E, let R else {
                return (nil, [E == nil ? "ความสูงชายคา" : nil, R == nil ? "ความสูงสันหลังคา" : nil].compactMap { $0 })
            }
            guard R > E else { return (nil, ["ความสูงสันหลังคา (ต้องมากกว่าชายคา)"]) }
            rise = R - E
        }
        if E == nil { assumed.append("ไม่ทราบความสูงชายคา") }
        let s = v.number("space1").flatMap { $0 > 0 ? $0 / 100 : nil }
        if s == nil && sh != .flat { assumed.append("ระยะแป 1.00 ม.") }
        var members: [Member] = []
        for (i, name) in Options.components.enumerated() {
            let size = v.text("size\(i + 1)").trimmingCharacters(in: .whitespaces), at = v.text("space\(i + 1)").trimmingCharacters(in: .whitespaces)
            guard !size.isEmpty else { continue }
            members.append(Member(name: name, size: size + " ซม." + (at.isEmpty ? "" : " @" + at + " ซม.")))
        }
        if members.isEmpty { warnings.append("ยังไม่ได้ระบุขนาดชิ้นส่วน") }
        return checked(Input(title: "หลังคาอาคาร", shape: sh, span: B, eave: E, rise: rise, overhang: 0,
                             purlinSpacing: s.map { min(3, max(0.2, $0)) } ?? 1.0, members: members, assumed: assumed, warnings: warnings))
    }

    // MARK: geometry

    /// The roof line, eave tip to eave tip, in metres (y up, tie beam at `e`).
    static func roofLine(_ i: Input, eave e: Double) -> [(x: Double, y: Double)] {
        let t = i.rise / max(i.run, 1e-9), o = i.overhang, B = i.span
        switch i.shape {
        case .gable, .hip: return [(-o, e - o * t), (B / 2, e + i.rise), (B + o, e - o * t)]
        case .shed: return [(-o, e - o * t), (B + o, e + i.rise + o * t)]
        case .flat: return [(-o, e), (B + o, e)]
        case .curved:
            // the arc through both eaves and the ridge
            let h = B / 2, r = (h * h + i.rise * i.rise) / (2 * i.rise), cy = e + i.rise - r
            let a0 = asin(min(1, h / r))
            return (0...24).map { k in
                let a = -a0 + 2 * a0 * Double(k) / 24
                return (h + r * sin(a), cy + r * cos(a))
            }
        }
    }

    /// Purlins along each slope from the eave, every `purlinSpacing`, plus one at the ridge when the last gap is over
    /// a quarter spacing (cap 200 a slope). Points in metres, with the slope's direction.
    static func purlins(_ i: Input, eave e: Double) -> [(x: Double, y: Double)] {
        guard i.shape != .flat else { return [] }
        let L = i.slopeLength, s = i.purlinSpacing, ux = i.run / L, uy = i.rise / L
        var ts: [Double] = []
        var t = 0.0
        while t <= L + 1e-9 && ts.count < 200 { ts.append(t); t += s }
        if let last = ts.last, L - last > 0.25 * s { ts.append(L) }
        if i.shape == .curved {
            let line = roofLine(Input(title: "", shape: .curved, span: i.span, eave: nil, rise: i.rise, overhang: 0, purlinSpacing: s, members: []), eave: e)
            let n = max(2, ts.count - 1)
            return (0...(2 * n)).map { k in line[min(line.count - 1, Int((Double(k) / Double(2 * n) * 24).rounded()))] }
        }
        var out = ts.map { (x: $0 * ux, y: e + $0 * uy) }
        if i.shape != .shed { out += ts.filter { $0 < L - 1e-6 }.map { (x: i.span - $0 * ux, y: e + $0 * uy) } }
        return out
    }

    // MARK: the section in metres

    /// The frame as the team's CAD sections draw it (`StructureSection`): the rafter seated on the posts at the eave
    /// height, the tie beam under it, a king post and struts on a gable or hip, C purlins on the rafter's top face under
    /// the sheet, a fascia at each tip, and the levels. Sizes come from the members entered (centimetres), else the usual.
    public static func structure(_ i: Input, eave e: Double, known: Bool) -> StructureSection {
        typealias S = StructureSection
        func size(_ name: String) -> S.Size? { i.members.first { $0.name == name }.flatMap { S.Size.read($0.size) } }
        let raf = size("จันทัน") ?? .c(0.15), tie = size("ขื่อ") ?? .c(0.1), purlin = size("แป") ?? .c(0.1)
        let B = i.span, h = B / 2, o = i.overhang, t = i.rise / max(i.run, 1e-9), cs = 1 / (1 + t * t).squareRoot()
        let pw = 0.2
        var m = S()
        m.datum = known ? 0 : e
        let line = roofLine(i, eave: e).map { Pt($0.x, $0.y) }
        func posts(_ tops: [(Double, Double)]) { for (x, top) in tops { m.posts.append(S.Post(x: x, width: pw, top: top)) } }
        let ground = known ? [S.Level(0, "ระดับพื้น")] : []

        if i.shape == .flat {
            let slab = S.Size.rc(B + 2 * o, 0.15)
            posts([(0, e), (B, e)])
            m.cuts.append(S.Cut(slab.profile, at: Pt(h, e)))
            m.levels = ground + [S.Level(e, "ระดับใต้พื้นดาดฟ้า"), S.Level(e + 0.15, "ระดับหลังพื้นดาดฟ้า")]
            return m
        }
        // the posts under the tie beam, the high side of a shed straight up to its rafter
        posts(i.shape == .shed ? [(0, e - tie.depth), (B, e + i.rise)] : [(0, e - tie.depth), (B, e - tie.depth)])
        m.members.append(S.Member([Pt(-pw / 2, e), Pt(i.shape == .shed ? B - pw / 2 : B + pw / 2, e)], depth: tie.depth, face: .top))
        let mid = raf.depth / (2 * cs)
        if i.shape == .gable || i.shape == .hip || i.shape == .curved {
            let king = size("ดั้ง") ?? .c(0.1)
            m.members.append(S.Member([Pt(h, e), Pt(h, e + i.rise + mid)], depth: king.depth))
            if i.shape != .curved {
                let st = size("ค้ำยัน") ?? .c(0.075)
                m.members.append(S.Member([Pt(h / 2, e + i.rise / 2 + mid), Pt(h, e)], depth: st.depth))
                m.members.append(S.Member([Pt(h, e), Pt(3 * h / 2, e + i.rise / 2 + mid)], depth: st.depth))
            }
            m.centreLine = h
        }
        let rafter = S.Member(line, depth: raf.depth, face: .bottom)
        // the rafter's top face: the first half of its outline
        let top = Array(rafter.outline.prefix(line.count))
        let fz = size("เชิงชาย") ?? S.Size.box(0.2, 0.025, .wood), th = max(0.02, fz.width), hh = max(0.1, fz.depth)
        for (p, s) in [(top[0], -1.0), (top[top.count - 1], 1.0)] {
            m.members.append(S.Member([Pt(p.x + s * th / 2, p.y), Pt(p.x + s * th / 2, p.y - hh)], depth: th))
        }
        m.members.append(rafter)
        // purlins square to the rafter on its top face, flanges toward the ridge
        func normal(_ x: Double) -> Pt {
            for k in 0..<(line.count - 1) where x >= line[k].x - 1e-9 && x <= line[k + 1].x + 1e-9 {
                return S.Member.leftNormal(line[k], line[k + 1])
            }
            return Pt(0, 1)
        }
        for p in purlins(i, eave: e) {
            let up = abs(p.x - h) < 1e-6 && i.shape != .shed ? Pt(0, 1) : normal(p.x)
            let lift = abs(up.x) < 1e-9 ? raf.depth / cs : raf.depth
            m.cuts.append(S.Cut(purlin.profile, at: Pt(p.x + up.x * lift, p.y + up.y * lift), up: up,
                                opens: i.shape == .shed || p.x < h ? 1 : -1))
        }
        let sheet = S.Member(line, depth: raf.depth + purlin.profile.h + 0.01, face: .bottom)
        m.sheet = Array(sheet.outline.prefix(line.count))
        if i.shape != .shed { m.ridge = m.sheet[m.sheet.count / 2] }
        m.levels = ground + [S.Level(e, "ระดับหัวเสา"), S.Level(top.map(\.y).max() ?? e, "ระดับหลังจันทัน")]
        return m
    }

    // MARK: member marks

    /// Where the member named `name` is drawn (metres), and whether its mark goes over the roof (the roof's members) or
    /// under the tie beam; nil for a member the section doesn't draw (อเส, a flat roof's frame) or a name it doesn't know.
    static func target(_ name: String, _ i: Input, eave e: Double, base: Double) -> (at: Pt, over: Bool)? {
        typealias S = StructureSection
        func size(_ n: String) -> S.Size? { i.members.first { $0.name == n }.flatMap { S.Size.read($0.size) } }
        let B = i.span, h = B / 2, t = i.rise / max(i.run, 1e-9), cs = 1 / (1 + t * t).squareRoot()
        let raf = size("จันทัน") ?? .c(0.15), tie = size("ขื่อ") ?? .c(0.1), purlin = size("แป") ?? .c(0.1)
        let line = roofLine(i, eave: e)
        /// The rafter's underside at x (the roof line).
        func under(_ x: Double) -> Double {
            for k in 0..<(line.count - 1) where x >= line[k].x - 1e-9 && x <= line[k + 1].x + 1e-9 {
                let a = line[k], b = line[k + 1], f = (x - a.x) / max(b.x - a.x, 1e-9)
                return a.y + f * (b.y - a.y)
            }
            return e
        }
        let gableLike = i.shape == .gable || i.shape == .hip
        switch (name, i.shape) {
        case (_, .flat): return nil
        case ("จันทัน", _):
            let x = i.shape == .shed ? 0.3 * B : 0.25 * h
            return (Pt(x, under(x) + raf.depth / (2 * cs)), true)
        case ("แป", _):
            let want = i.shape == .shed ? 0.78 * B : 0.8 * h
            guard let p = purlins(i, eave: e).min(by: { abs($0.x - want) < abs($1.x - want) }) else { return nil }
            return (Pt(p.x, p.y + raf.depth / cs + purlin.profile.h / 2), true)
        case ("เชิงชาย", _):
            return (Pt(-i.overhang, under(-i.overhang) - 0.05), true)
        case ("ขื่อ", _):
            return (Pt(0.72 * B, e - tie.depth / 2), false)
        case ("ดั้ง", _) where gableLike || i.shape == .curved:
            return (Pt(h, e + 0.3 * i.rise), false)
        case ("ค้ำยัน", _) where gableLike:
            return (Pt(1.25 * h, e + i.rise / 4), false)
        default:
            return nil
        }
    }

    /// The listed members' numbers: a circle with the member's number, its leader and arrowhead to the member; the
    /// roof's members from a band over the roof, the rest from one under the tie beam, spread so no two circles touch.
    static func callouts(_ i: Input, eave e: Double, base: Double, into d: inout StructureSection.Drawn, _ P: (Pt) -> Pt,
                         top: Double, floor: Double) {
        var over: [(Int, Pt)] = [], under: [(Int, Pt)] = []
        for (n, m) in i.members.enumerated() {
            guard let t = target(m.name, i, eave: e, base: base) else { continue }
            if t.over { over.append((n + 1, P(t.at))) } else { under.append((n + 1, P(t.at))) }
        }
        let r = 8.0, gap = 2 * r + 6, low = min(P(Pt(0, e)).y + 34, floor - r - 4)
        func place(_ list: [(Int, Pt)], y: Double, lean: Double) {
            var x = -Double.infinity
            for (n, t) in list.sorted(by: { $0.1.x < $1.1.x }) {
                x = max(t.x + lean, x + gap, r + 4)
                let b = Pt(x, y), dx = t.x - b.x, dy = t.y - b.y, l = max(hypot(dx, dy), 1), ux = dx / l, uy = dy / l, al = 6.0, aw = 2.2
                d.add(.line(Pt(b.x + ux * r, b.y + uy * r), Pt(t.x - ux * al, t.y - uy * al), width: 0.8, color: dimC), "CALLOUT")
                d.add(.polygon([t, Pt(t.x - ux * al - uy * aw, t.y - uy * al + ux * aw), Pt(t.x - ux * al + uy * aw, t.y - uy * al - ux * aw)],
                               stroke: nil, fill: dimC), "CALLOUT")
                d.add(.circle(b, r: r, stroke: dimC, fill: .white, width: 1), "CALLOUT")
                d.add(.text(String(n), at: b, size: 9.5, bold: true, color: dimC, align: .center), "CALLOUT")
            }
        }
        place(over, y: top, lean: -18)
        place(under, y: low, lean: 16)
    }

    // MARK: drawing

    static let ink = RGBA(hex: 0x1A1D22), dimC = RGBA(hex: 0x16325C), red = RGBA(hex: 0xD9453B)

    /// docs/specs/auto-drawing.md §6: 690 pt wide, title strip, the section fitted beside its level marks, the dimension
    /// chain under it, the members, the assumed values and warnings, and the note that it is not a construction drawing.
    public static func sketch(_ i: Input, width W: Double = 690) -> Sketch {
        let known = i.eave != nil, e = i.eave ?? 3.0, o = i.overhang, B = i.span
        let model = structure(i, eave: e, known: known)
        // the frame and its overhang dimensions (a curved roof's tips stop at the posts)
        let ext = model.extent, base = known ? 0 : e - 0.8, minX = min(ext.minX, -o), maxX = max(ext.maxX, B + o)
        let marks = (W - 150)...(W - 12), areaL = 24.0, areaR = marks.lowerBound - 20, areaH = 200.0
        // the drawing comes down a row when members are marked over the roof, so their circles clear the title
        let marksOver = i.members.contains { target($0.name, i, eave: e, base: base)?.over == true }, y0 = marksOver ? 56.0 : 40.0
        let k = min((areaR - areaL) / max(maxX - minX, 1e-6), areaH / max(ext.maxY - base, 1e-6))
        let x0 = areaL + ((areaR - areaL) - (maxX - minX) * k) / 2
        func P(_ p: Pt) -> Pt { Pt(x0 + (p.x - minX) * k, y0 + (ext.maxY - p.y) * k) }
        func X(_ x: Double) -> Double { P(Pt(x, 0)).x }
        var d = StructureSection.Drawn()
        d.add(.rect(Box(0, 0, W, 0), stroke: nil, fill: .white), nil)
        d.add(.text("รูปตัดโครงหลังคา — " + i.title, at: Pt(16, 14), size: 10, bold: true, color: ink), nil)
        d.add(.text("หน่วย: ม. | มาตราส่วนโดยประมาณ", at: Pt(W - 16, 14), size: 8.5, color: .ink2, align: .right), nil)
        let floor = P(Pt(0, base)).y
        model.draw(into: &d, P, scale: k, marks: marks, gridTop: nil, floor: floor, ground: known, text: 8.5)
        if !known { d.add(.text("ไม่ทราบความสูงชายคา", at: Pt(X(B / 2), floor - 10), size: 8.5, color: red, align: .center), nil) }
        // each listed member's number, on the member it names (the list under the drawing reads the same numbers)
        callouts(i, eave: e, base: base, into: &d, P, top: y0 - 18, floor: floor)

        // the spans under it
        func dimH(_ a: Double, _ b: Double, _ y: Double, _ label: String) {
            let pa = X(a), pb = X(b)
            d.add(.line(Pt(pa, y), Pt(pb, y), width: 0.6, color: dimC), nil)
            for x in [pa, pb] { d.add(.line(Pt(x - 3, y + 3), Pt(x + 3, y - 3), width: 0.8, color: dimC), nil) }
            if pb - pa > 14 { d.add(.text(label, at: Pt((pa + pb) / 2, y - 7), size: 8.5, color: dimC, align: .center), nil) }
        }
        let chainY = floor + 22
        if o > 0 { dimH(-o, 0, chainY, String(format: "%.2f", o)); dimH(B, B + o, chainY, String(format: "%.2f", o)) }
        dimH(0, B, chainY, String(format: "%.2f", B))
        d.add(.text("ช่วงกว้าง " + String(format: "%.2f", B), at: Pt(X(B / 2), chainY + 12), size: 9, bold: true, color: dimC, align: .center), nil)
        if i.rise > 0 {
            // the pitch: an arc at the left post head, and the slope length along the first slope
            let c = P(Pt(0, e)), deg = i.pitch
            let arc = (0...12).map { s -> Pt in let a = Double(s) / 12 * deg * .pi / 180; return Pt(c.x + 30 * cos(a), c.y - 30 * sin(a)) }
            d.add(.polyline(arc, width: 0.6, color: dimC), nil)
            d.add(.text(fmt((deg * 10).rounded() / 10) + "°", at: Pt(c.x + 50, c.y - 5), size: 8, color: dimC), nil)
            if i.shape != .curved {
                let m = P(Pt(i.run / 2, e + i.rise / 2))
                d.add(.text("L = " + String(format: "%.2f", i.slopeLength) + " ม.", at: Pt(m.x, m.y - 16), size: 8.5, color: dimC,
                            align: .center, angle: -deg), nil)
            }
        }

        // members, assumed values, warnings and the note
        var y = chainY + 30
        let rows = i.members.enumerated().map { n, m in "\(n + 1) " + m.name + " | " + (m.size.isEmpty ? "— ไม่ได้ระบุ —" : m.size) }
        let colWd = (W - 32) / 2
        for (n, t) in rows.enumerated() {
            d.add(.text(t, at: Pt(16 + Double(n % 2) * colWd, y + Double(n / 2) * 12), size: 8.5, color: ink), nil)
        }
        y += Double((rows.count + 1) / 2) * 12 + (rows.isEmpty ? 0 : 4)
        if !i.assumed.isEmpty { d.add(.text("ค่าสมมติ: " + i.assumed.joined(separator: " | "), at: Pt(16, y), size: 8, color: .ink2), nil); y += 12 }
        for w in i.warnings { d.add(.text(w, at: Pt(16, y), size: 8, bold: true, color: red), nil); y += 12 }
        d.add(.text(TankDrawings.note, at: Pt(16, y), size: 7.5, color: .ink2), nil)
        let H = y + 10
        d.ops[0] = .rect(Box(0, 0, W, H), stroke: nil, fill: .white)
        return Sketch(width: W, height: H, ops: d.ops)
    }
}
