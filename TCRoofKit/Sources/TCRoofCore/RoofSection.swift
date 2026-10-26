import Foundation

/// C1 section A-A: a true-scale cut across the ridge for the seven frame types, drawn as the team's CAD sections draw
/// it (`StructureSection`): members at the depth of the sizes in rows 1–7, C purlins under the sheet, posts with the
/// beam at their heads, the fascia, and level marks with their chain on the right. The members come from the same
/// geometry as the member schedule (`RoofTruss.Geometry`).
///
/// The sketch is 760 × 250, the roof structure only: the posts stop at a break line under the clear height (the level
/// marks give the height). `trueScale` (the DXF) also lists the dimensions (`dimensions`) for the DXF's DIMENSIONs.
/// `callouts` adds the page's numbered member bubbles ①–⑦; the PDF and the DXF leave them out.
/// `tags` names each op's CAD layer (`SECTION`, `POST`, `PURLIN`, `GRID`, `LEVEL`, `DIM`, `CALLOUT`; nil for the
/// background and the dimension texts).
public struct RoofSection: Sendable {
    public static let width = 760.0, height = 250.0

    public var sketch: Sketch
    public var tags: [String?]
    /// Where the eave overhang, clear-height and ridge-height values sit (the page makes them tappable).
    public var overhangLabel = Pt(0, 0), clearLabel = Pt(0, 0), riseLabel = Pt(0, 0)
    /// The numbered callouts' bubble centres (rows a frame doesn't draw are missing).
    public var callouts: [Int: Pt] = [:]
    public let span, half, rise: Double
    public let bays: Int
    /// Sketch points per metre.
    public let scale: Double
    /// The ridge's x in the sketch.
    public let ridgeX: Double
    /// The section in metres.
    public let model: StructureSection
    /// With `trueScale`: the half spans, the span, the overhangs and the level chain, and the indices of the ops that
    /// draw their lines and ticks (the DXF writes DIMENSIONs instead).
    public var dimensions: [SketchDXF.Dimension] = []
    public var dimensionOps: Set<Int> = []

    static let navy = RGBA(hex: 0x16325C), red = RGBA(hex: 0xD9453B), blue = RGBA(hex: 0x1F6FB5)
    /// The posts' break line on screen, and the band of the level marks.
    static let cut = 194.0, marks = 606.0...750.0

    /// - Parameter highlight: member row 1…7 whose callout is filled red.
    public init(_ v: Values, highlight: Int? = nil, trueScale: Bool = false, callouts showCallouts: Bool = true) {
        let f = Roof.frame(v), m = Self.structure(v)
        let span = Roof.span(v), half = span / 2, nH = Roof.bays(v)
        let ang = Roof.slope(v), rise = half * tan(ang * .pi / 180)
        let o = Roof.overhang(v), base = Roof.clearHeight(v)
        // fit the section between x 26 and 586, its posts showing 1.40 m under the clear height before the break
        let ext = m.extent, below = 1.4
        let k = min(560 / max(ext.maxX - ext.minX + 0.2, 1), (Self.cut - 34) / max(ext.maxY - base + below, 0.5))
        let yBase = Self.cut - below * k, cx = 306.0, mid = (ext.minX + ext.maxX) / 2
        func P(_ p: Pt) -> Pt { Pt(cx + (p.x - mid) * k, yBase - (p.y - base) * k) }
        // the roof structure only, as the team's CAD sections show it: the posts end at a break line under the clear height
        let floor = Self.cut, H = Self.height

        var d = StructureSection.Drawn()
        d.add(.rect(Box(0, 0, Self.width, H), stroke: nil, fill: .white), nil)
        m.draw(into: &d, P, scale: k, marks: Self.marks, gridTop: 14, floor: floor, ground: false)

        // the spans and overhangs under it
        let XL = P(Pt(0, 0)).x, XR = P(Pt(span, 0)).x, RX = P(Pt(half, 0)).x, oL = P(Pt(-o, 0)).x, oR = P(Pt(span + o, 0)).x
        let y1 = floor + 14, y2 = floor + 36
        func dim(_ a: Double, _ b: Double, _ c: Double, _ e: Double) { d.dim(.line(Pt(a, b), Pt(c, e), width: 0.8, color: Self.navy)) }
        func tick(_ x: Double, _ y: Double) { dim(x - 4, y + 4, x + 4, y - 4) }
        func text(_ t: String, _ x: Double, _ y: Double, _ size: Double = 11, bold: Bool = false, color: RGBA = Self.navy, align: TextAlign = .center) {
            d.add(.text(t, at: Pt(x, y), size: size, bold: bold, color: color, align: align), nil)
        }
        dim(XL - 6, y1, XR + 6, y1); dim(XL - 6, y2, XR + 6, y2)
        for x in [XL, RX, XR] { tick(x, y1) }
        for x in [XL, XR] { tick(x, y2) }
        dim(RX, y1 - 8, RX, y1 + 4)
        if !f.isRafter { for i in 1..<(2 * nH) where i != nH { let x = P(Pt(Double(i) * half / Double(nH), 0)).x; dim(x, y1 - 3, x, y1 + 3) } }
        let ovT = String(format: "%.2f", o)
        if o > 0.01 {
            dim(oL - 6, y2, XL, y2); dim(XR, y2, oR + 6, y2)
            tick(oL, y2); tick(oR, y2)
            text("ชายคา " + ovT, (oL + XL) / 2, y2 + 11, 10); text(ovT, (XR + oR) / 2, y2 + 11, 10)
        }
        overhangLabel = Pt((oL + XL) / 2, y2 + 11)
        let halfT = f.isRafter ? String(format: "%.2f", half) : "\(nH) × " + String(format: "%.2f", half / Double(nH)) + " = " + String(format: "%.2f", half)
        text(halfT, (XL + RX) / 2, y1 - 7, color: Self.blue); text(halfT, (XR + RX) / 2, y1 - 7, color: Self.blue)
        text(fmt(span) + " (จากแปลน)", RX, floor + 47, 13, bold: true)
        if trueScale {
            typealias D = SketchDXF.Dimension
            let low = floor + 6
            d.dimensions += [D(Pt(XL, low), Pt(RX, low), at: Pt(0, y1), text: halfT, size: 12),
                             D(Pt(RX, low), Pt(XR, low), at: Pt(0, y1), text: halfT, size: 12),
                             D(Pt(XL, low), Pt(XR, low), at: Pt(0, y2), text: String(format: "%.2f", span) + " (จากแปลน)", size: 12)]
            if (XL - oL) > 0.5 {
                d.dimensions += [D(Pt(oL, low), Pt(XL, low), at: Pt(0, y2), text: "ชายคา " + ovT, size: 12),
                                 D(Pt(XR, low), Pt(oR, low), at: Pt(0, y2), text: ovT, size: 12)]
            }
        }

        // the pitch at the left support
        let heel = f.isRafter ? 0 : f.heel, c = P(Pt(0, base + heel))
        d.add(.polyline((0...12).map { s in let t = Double(s) / 12 * ang * .pi / 180; return Pt(c.x + 40 * cos(t), c.y - 40 * sin(t)) },
                        width: 0.8, color: Self.navy), "DIM")
        text(Roof.slopeText(v), c.x + 46, c.y - 6, 11, align: .left)

        // the level values the page makes tappable: the clear height and the ridge
        let baseLevel = m.levels.firstIndex { abs($0.y - base) < 1e-6 }
        if let i = baseLevel, i < d.levelValues.count { clearLabel = d.levelValues[i] }
        if let last = d.levelValues.last { riseLabel = last }

        if showCallouts { callouts = Self.callouts(m, into: &d, P, base: base, below: yBase, half: half, overhang: o) }
        if let n = highlight, let c = callouts[n] {
            d.add(.circle(c, r: 11, stroke: .white, fill: Self.red, width: 2), nil)
            d.add(.text(String(n), at: c, size: 13, bold: true, color: .white, align: .center), nil)
        }
        sketch = Sketch(width: Self.width, height: H, ops: d.ops)
        tags = d.tags
        if trueScale { dimensions = d.dimensions; dimensionOps = d.dimensionOps }
        self.span = span; self.half = half; self.rise = rise; self.bays = nH; self.scale = k; self.ridgeX = RX; self.model = m
    }

    // MARK: the section in metres

    /// C1's frame cut across the ridge, in metres (x from the left support, y up from the ground).
    public static func structure(_ v: Values) -> StructureSection {
        typealias S = StructureSection
        let f = Roof.frame(v), B = Roof.span(v), h = B / 2, n = Roof.bays(v)
        let ang = Roof.slope(v) * .pi / 180, tn = tan(ang), cs = cos(ang), sn = sin(ang)
        let o = Roof.overhang(v), base = Roof.clearHeight(v), heel = f.isRafter ? 0 : f.heel, rise = h * tn
        /// Row `r`'s size as entered (its default until then); nil for "-".
        func size(_ r: Int) -> S.Size? {
            let s = Roof.memberSize(v, r)
            if s == "-" { return nil }
            return S.Size.read(s.isEmpty ? f.members[r - 1].defaultSize : s)
        }
        var m = S()
        let ridge = Roof.ridge(v)
        let gB = ridge == .h ? Roof.gridName(.y, Roof.spans(v, .y).count) : Roof.gridName(.x, Roof.spans(v, .x).count)
        m.grid = [(0, ridge == .h ? "A" : "1"), (B, gB)]
        m.centreLine = h

        /// Purlins at ระยะแป along the slope from 0.15 m off the ridge down to the eave tip, the sheet over them.
        func roofing(_ topFace: (Double) -> Double) {
            let p = size(1), step = Roof.purlinSpacing(v) * cs
            if let p {
                var x = h - 0.15
                while x > -o + 0.06 {
                    m.cuts.append(S.Cut(p.profile, at: Pt(x, topFace(x)), up: Pt(-sn, cs), opens: 1, row: 1))
                    m.cuts.append(S.Cut(p.profile, at: Pt(B - x, topFace(B - x)), up: Pt(sn, cs), opens: -1, row: 1))
                    x -= step
                }
            }
            let lift = (p?.profile.h ?? 0) + 0.01
            m.sheet = [Pt(-o - sn * lift - 0.05 * cs, topFace(-o) + cs * lift - 0.05 * sn), Pt(h, topFace(h) + lift / cs),
                       Pt(B + o + sn * lift + 0.05 * cs, topFace(B + o) + cs * lift - 0.05 * sn)]
            m.ridge = m.sheet[1]
        }
        /// A fascia board standing at each eave tip, its top at the roof's top face.
        func fascia(_ top: Double) {
            guard let fz = size(6) else { return }
            let t = max(0.02, fz.width), hh = max(0.1, fz.depth)
            for x in [-o - t / 2, B + o + t / 2] { m.members.append(S.Member([Pt(x, top), Pt(x, top - hh)], depth: t, row: 6)) }
        }
        func pitched(_ line: (Double) -> Double) -> [Pt] { [Pt(-o, line(-o)), Pt(h, line(h)), Pt(B + o, line(B + o))] }

        switch f {
        case .rafterTie, .eaveCeiling:
            // rafters seated on the post heads at the clear height, a tie between them, the eave beam cut at each head
            let K = f == .eaveCeiling
            let raf = size(2) ?? .c(0.15), tie = size(3) ?? .c(0.1)
            let under: (Double) -> Double = { base + (h - abs($0 - h)) * tn }
            let topFace: (Double) -> Double = { under($0) + raf.depth / cs }
            let mid: (Double) -> Double = { under($0) + raf.depth / (2 * cs) }
            let head = size(4) ?? .rc(0.2, 0.4), post = (K ? size(7) : nil) ?? .rc(0.2, 0.2)
            let pw = post.material == .concrete ? post.width : post.depth
            for (x, s) in [(0.0, 1.0), (B, -1.0)] {
                m.posts.append(S.Post(x: x, width: pw, top: base - head.profile.h, row: K ? 7 : nil))
                m.cuts.append(S.Cut(head.profile, at: Pt(x, base - head.profile.h), opens: s, row: 4))
            }
            let yc = base + (K ? 0.55 : 0.5) * rise, xt = (yc - base) / tn - raf.depth / (2 * cs * tn)
            if !K, let cp = size(7) { m.members.append(S.Member([Pt(h, yc), Pt(h, mid(h))], depth: cp.depth, row: 7)) }
            if !K, let st = size(5) {
                m.members.append(S.Member([Pt(0.72 * h, mid(0.72 * h)), Pt(h, yc)], depth: st.depth, row: 5))
                m.members.append(S.Member([Pt(h, yc), Pt(B - 0.72 * h, mid(B - 0.72 * h))], depth: st.depth, row: 5))
            }
            m.members.append(S.Member([Pt(xt, yc), Pt(B - xt, yc)], depth: tie.depth, row: 3))
            if K && o > 0.25 {
                // the boxed eave: a soffit under the beam out to a fascia raking up to the rafter's tip
                let ys = base - head.profile.h, run = min(0.25, o / 3), sof = size(5) ?? .c(0.075)
                let ft = max(0.025, size(6)?.width ?? 0.025)
                m.members.append(S.Member([Pt(-o + run, ys), Pt(-pw / 2, ys)], depth: sof.depth, face: .top, row: 5))
                m.members.append(S.Member([Pt(B + pw / 2, ys), Pt(B + o - run, ys)], depth: sof.depth, face: .top, row: 5))
                m.members.append(S.Member([Pt(-o, under(-o)), Pt(-o + run, ys - sof.depth)], depth: ft, row: 6))
                m.members.append(S.Member([Pt(B + o - run, ys - sof.depth), Pt(B + o, under(B + o))], depth: ft, row: 6))
            } else {
                fascia(topFace(-o))
            }
            m.members.append(S.Member(pitched(under), depth: raf.depth, face: .bottom, row: 2))
            roofing(topFace)
            m.levels = (K ? [S.Level(base - head.profile.h, head.material == .concrete ? "ระดับใต้คาน ค.ส.ล." : "ระดับใต้คานหัวเสา")] : [])
                + [S.Level(base, "ระดับหัวเสา"), S.Level(topFace(h), "ระดับหลังจันทัน")]

        case .rafterTruss:
            // two tube chords a heel apart from eave to eave, a vertical and a diagonal in each panel, posts under the
            // bottom chord: at the supports and, on a T2 along the ridge, at 0.8 of each half
            let tc = size(2) ?? .tube(0.034), bc = size(3) ?? .tube(0.034), web = size(4) ?? .tube(0.034)
            let topFace: (Double) -> Double = { base + heel + (h - abs($0 - h)) * tn }
            let bottom: (Double) -> Double = { topFace($0) - heel }
            func T(_ x: Double) -> Pt { Pt(x, topFace(x) - tc.depth / (2 * cs)) }
            func Bt(_ x: Double) -> Pt { Pt(x, bottom(x) + bc.depth / (2 * cs)) }
            let panel = h / Double(n), nodes = (0...(2 * n)).map { Double($0) * panel }
            m.members.append(S.Member([Bt(0), T(0)], depth: web.depth, row: 4))
            for i in 0..<(2 * n) {
                let a = nodes[i], b = nodes[i + 1]
                let up = abs(b - h) < 1e-9 || abs(a - h) < 1e-9 || (a < h) == (i % 2 == 0)
                m.members.append(S.Member(up ? [Bt(a), T(b)] : [T(a), Bt(b)], depth: web.depth, row: 4))
                m.members.append(S.Member([Bt(b), T(b)], depth: web.depth, row: 4))
            }
            m.members.append(S.Member(pitched(bottom), depth: bc.depth, face: .bottom, row: 3))
            m.members.append(S.Member(pitched(topFace), depth: tc.depth, face: .top, row: 2))
            let post = size(7) ?? .tube(0.1), pw = post.material == .concrete ? post.width : post.depth
            for x in [0, B] { m.posts.append(S.Post(x: x, width: pw, top: base, row: 7)) }
            let t2 = size(5)
            for x in [0.8 * h, B - 0.8 * h] {
                let d = t2?.profile.h ?? 0
                if let t2 { m.cuts.append(S.Cut(t2.profile, at: Pt(x, bottom(x) - d), row: 5)) }
                m.posts.append(S.Post(x: x, width: pw, top: bottom(x) - d, row: 7))
            }
            fascia(topFace(-o))
            roofing(topFace)
            m.levels = [S.Level(base, "ระดับหัวเสา"), S.Level(topFace(h), "ระดับสันหลังคา")]

        default:
            // a truss with a bottom chord on a concrete beam at each post head; the webs as the schedule counts them
            let tc = size(2) ?? .c(0.15), bc = size(3) ?? .c(0.15), vt = size(4) ?? .c(0.075), dg = size(5) ?? .c(0.075)
            let g = RoofTruss.Geometry(frame: f, span: B, bays: n, slope: Roof.slope(v), overhang: o)
            let topFace: (Double) -> Double = { base + heel + (h - abs($0 - h)) * tn }
            // a web's end on the bottom chord goes to that chord's centre line, one on the top chord to its
            func Y(_ p: Pt) -> Pt { abs(p.y) < 1e-9 ? Pt(p.x, base + bc.depth / 2) : Pt(p.x, base + p.y - tc.depth / (2 * cs)) }
            for s in g.verticals { m.members.append(S.Member([Y(s.a), Y(s.b)], depth: vt.depth, row: 4)) }
            for s in g.diagonals { m.members.append(S.Member(s.a.x < s.b.x ? [Y(s.a), Y(s.b)] : [Y(s.b), Y(s.a)], depth: dg.depth, row: 5)) }
            if let kp = g.kingPost, let ks = size(7) { m.members.append(S.Member([Y(kp.a), Y(kp.b)], depth: ks.depth, row: 7)) }
            m.members.append(S.Member([Pt(0, base), Pt(B, base)], depth: bc.depth, face: .bottom, row: 3))
            m.members.append(S.Member(pitched(topFace), depth: tc.depth, face: .top, row: 2))
            let beam = S.Size.rc(0.2, 0.4)
            for x in [0, B] {
                m.posts.append(S.Post(x: x, width: 0.2, top: base - beam.profile.h))
                m.cuts.append(S.Cut(beam.profile, at: Pt(x, base - beam.profile.h)))
            }
            fascia(topFace(-o))
            roofing(topFace)
            m.levels = [S.Level(base, "ระดับใต้ขื่อ"), S.Level(base + heel, "ระดับหัวโครงถัก"),
                        S.Level(base + heel + rise, "ระดับสันหลังคา", chain: "R " + String(format: "%.2f", rise))]
        }
        return m
    }

    // MARK: callouts

    /// The numbered member bubbles ①–⑦: one per row the section draws, on the member nearest a spot set for each row,
    /// the roof's members (purlin, top chord, fascia) from a band over the roof and the rest from one under the frame.
    static func callouts(_ m: StructureSection, into d: inout StructureSection.Drawn, _ P: (Pt) -> Pt, base: Double, below yBase: Double,
                         half h: Double, overhang o: Double) -> [Int: Pt] {
        let prefer: [Int: Double] = [1: 0.35 * h, 2: 1.4 * h, 3: 0.3 * h, 4: 0.3 * h, 5: 0.5 * h, 6: -o, 7: 1.6 * h]
        var spots: [Int: [Pt]] = [:]
        for mem in m.members {
            guard let r = mem.row else { continue }
            let vertical = abs(mem.path[0].x - mem.path[mem.path.count - 1].x) < 1e-6
            spots[r, default: []].append(mem.path.count > 2 ? mem.centre(piece: 1, at: 0.55) : mem.centre(at: vertical ? 0.5 : 0.3))
        }
        for c in m.cuts { if let r = c.row { spots[r, default: []].append(c.centre) } }
        for p in m.posts { if let r = p.row { spots[r, default: []].append(Pt(p.x, min(p.top - 0.25, base - 0.3))) } }
        var upper: [(Int, Pt)] = [], lower: [(Int, Pt)] = []
        for (r, pts) in spots {
            let want = prefer[r] ?? h
            guard let t = pts.min(by: { abs($0.x - want) < abs($1.x - want) }) else { continue }
            if [1, 2, 6].contains(r) { upper.append((r, P(t))) } else { lower.append((r, P(t))) }
        }
        var bubbles: [Int: Pt] = [:]
        func place(_ list: [(Int, Pt)], y: Double, lean: Double) {
            var xs = list.sorted { $0.1.x < $1.1.x }.map { ($0.0, $0.1, $0.1.x + lean) }
            for i in xs.indices {
                xs[i].2 = max(xs[i].2, 16)
                if i > 0 { xs[i].2 = max(xs[i].2, xs[i - 1].2 + 26) }
            }
            if let last = xs.last, last.2 > 588 { let shift = last.2 - 588; for i in xs.indices { xs[i].2 -= shift } }
            for (r, t, x) in xs { bubbles[r] = Pt(x, y); call(r, Pt(x, y), t) }
        }
        func call(_ n: Int, _ b: Pt, _ t: Pt) {
            let dx = t.x - b.x, dy = t.y - b.y, l = max(hypot(dx, dy), 1), ux = dx / l, uy = dy / l, r = 9.0, al = 7.0, aw = 2.6
            let e = Pt(t.x - ux, t.y - uy)
            d.add(.line(Pt(b.x + ux * r, b.y + uy * r), Pt(e.x - ux * al, e.y - uy * al), width: 1, color: red), "CALLOUT")
            d.add(.polygon([e, Pt(e.x - ux * al - uy * aw, e.y - uy * al + ux * aw), Pt(e.x - ux * al + uy * aw, e.y - uy * al - ux * aw)],
                           stroke: nil, fill: red), "CALLOUT")
            d.add(.circle(b, r: r, stroke: red, fill: .white, width: 1.4), "CALLOUT")
            d.add(.text(String(n), at: b, size: 12, bold: true, color: red, align: .center), "CALLOUT")
        }
        place(upper, y: 40, lean: -22)
        place(lower, y: min(yBase + 28, cut - 12), lean: 18)
        return bubbles
    }
}

/// The few SVG path commands the design's section strings use (M L H V and their relative forms, Z), as polylines.
enum PathD {
    static func parse(_ d: String) -> [(points: [Pt], closed: Bool)] {
        var tokens: [String] = [], cur = ""
        for ch in d {
            if ch.isLetter { if !cur.isEmpty { tokens.append(cur); cur = "" }; tokens.append(String(ch)) }
            else if ch == " " || ch == "," { if !cur.isEmpty { tokens.append(cur); cur = "" } }
            else if ch == "-" && !cur.isEmpty && !cur.hasSuffix("e") { tokens.append(cur); cur = "-" }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { tokens.append(cur) }
        var out: [(points: [Pt], closed: Bool)] = [], pts: [Pt] = [], i = 0, cmd = "", x = 0.0, y = 0.0
        func num() -> Double { defer { i += 1 }; return Double(tokens[safe: i] ?? "") ?? 0 }
        func flush(_ closed: Bool) { if pts.count > 1 { out.append((pts, closed)) }; pts = [] }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = tokens[i]; i += 1 }
            switch cmd {
            case "M", "m":
                flush(false)
                let a = num(), b = num()
                if cmd == "m" { x += a; y += b } else { x = a; y = b }
                pts = [Pt(x, y)]; cmd = cmd == "m" ? "l" : "L"
            case "L": x = num(); y = num(); pts.append(Pt(x, y))
            case "l": x += num(); y += num(); pts.append(Pt(x, y))
            case "H": x = num(); pts.append(Pt(x, y))
            case "h": x += num(); pts.append(Pt(x, y))
            case "V": y = num(); pts.append(Pt(x, y))
            case "v": y += num(); pts.append(Pt(x, y))
            case "Z", "z": if let f = pts.first { x = f.x; y = f.y }; flush(true); cmd = ""
            default: i += 1
            }
        }
        flush(false)
        return out
    }
}
