import Foundation

/// The C1 roof plan (docs/ui/survey-c1 `renderVals`, `P.*`): grid and dimension chains, ridge, frame lines, purlins,
/// posts, slope arrows, section mark A-A, skylights and obstacles, and the PV layout. The sketch is 580 × 446 (the
/// design's viewBox moved to the origin); the page draws it and lays its buttons over the points in `Layout`.
/// Every op carries the design's path key in `tags` (`grid`, `purl`, `tbd`, `post`, …), which the CAD export maps to
/// DXF layers and the member highlight redraws in red.
public struct RoofPlan: Sendable {
    public enum Mode: Sendable { case structure, pv }
    public static let width = 580.0, height = 446.0

    public struct Chip: Sendable { public let axis: Roof.Axis; public let index: Int; public let value: Double; public let at: Pt }
    public struct Layout: Sendable {
        public var chips: [Chip] = []
        public var addX = Pt(0, 0), addY = Pt(0, 0)
        /// Grid intersections (i along x, j along y).
        public var nodes: [(i: Int, j: Int, at: Pt, post: Bool)] = []
        /// Skylights and obstacles / keep-out zones on the sketch, with their `obst` index.
        public var areas: [(area: Roof.Area, box: Box)] = []
        /// Metres → sketch point, and back.
        public var origin = Pt(0, 0), k = 1.0, lx = 0.0, ly = 0.0
        public func point(x: Double, y: Double) -> Pt { Pt(origin.x + x * k, origin.y + y * k) }
        public func metres(_ p: Pt) -> (x: Double, y: Double) {
            (min(lx, max(0, (p.x - origin.x) / k)), min(ly, max(0, (p.y - origin.y) / k)))
        }
    }

    public struct PV: Sendable {
        public var count = 0
        public var kWp = 0.0
        /// Tables (ชุด) holding at least one module; 0 when the field is continuous.
        public var tables = 0
        public var placed: [Box] = [], blocked: [Box] = []
    }

    /// Module size (m) and power (kW) for the layout: the catalogue's default module.
    public struct Module: Sendable {
        public var length, width, kW: Double
        public init(length: Double, width: Double, kW: Double) { self.length = length; self.width = width; self.kW = kW }
        public static var catalogDefault: Module {
            let c = EquipmentCatalog.bundled, m = c.pv.first { $0.def == true } ?? c.pv.first
            return m.map { Module(length: Double($0.l) / 1000, width: Double($0.wd) / 1000, kW: Double($0.w) / 1000) }
                ?? Module(length: 2.278, width: 1.134, kW: 0.57)
        }
    }

    public var sketch: Sketch
    /// The design's path key of each op in `sketch.ops` (nil: labels, arrows, backgrounds).
    public var tags: [String?]
    public var layout: Layout
    public var pv: PV

    static let navy = RGBA(hex: 0x16325C), gridC = RGBA(hex: 0x8A97AA), red = RGBA(hex: 0xD9453B)
    /// Ink the page's legend draws with too.
    public static let ink = RGBA(hex: 0x111111), purlC = RGBA(hex: 0x6B7280), postInk = RGBA(hex: 0x111827)
    public static let skyFill = RGBA(hex: 0xCFE8F7), skyLine = RGBA(hex: 0x2E8FDB), pvFill = RGBA(hex: 0x1F4F8F), pvLine = RGBA(hex: 0xDCE6F2)
    static let redText = RGBA(hex: 0xB42318), amber = RGBA(hex: 0xB45309)

    /// The plan's path keys drawn for member row n (1…7) of this frame (the design's `HLK`).
    public static func highlightKeys(_ f: RoofFrame, member n: Int) -> [String] {
        let rafter = f.isRafter, r = f == .rafterTruss
        switch n {
        case 1: return ["purl"]
        case 2: return [rafter ? "raft" : r ? "truss" : "tbd"]
        case 3: return rafter ? [] : [r ? "truss" : "tbd"]
        case 4: return [rafter ? "eave" : r ? "truss" : "tbd"]
        case 5: return rafter ? [] : [r ? "t2" : "tbd"]
        case 6: return ["out"]
        case 7: return ["post"]
        default: return []
        }
    }

    /// - Parameters:
    ///   - chips: false draws the span values as text (report, CAD); true leaves them to the page's buttons.
    ///   - dragging: an unfinished skylight / keep-out zone being dragged (metres, two corners).
    ///   - highlight: member row 1…7 whose lines are redrawn in red.
    public init(_ v: Values, mode: Mode = .structure, portrait: Bool? = nil, module: Module = .catalogDefault,
                chips: Bool = false, dragging: (Double, Double, Double, Double)? = nil, highlight: Int? = nil) {
        var d = Drawer(v, pv: mode == .pv)
        d.background()
        if !d.pvMode { d.purlins() }
        d.grid()
        if !d.pvMode { d.frameLines() }
        d.posts()
        d.outlineAndRidge()
        d.bubbles()
        d.dimensions(chips: chips)
        if !d.pvMode { d.purlinCallout(); d.slopeArrows() }
        d.areas()
        if d.pvMode {
            d.pvLayout(RoofPV(v, portrait: portrait, module: module))
            if let r = dragging { d.dragged(r, fill: RGBA(0.851, 0.271, 0.231, 0.12), line: Self.red, width: 1.4) }
            d.keepOutLabels()
        } else if let r = dragging {
            d.dragged(r, fill: Self.skyFill, line: Self.skyLine, width: 1.2)
        }
        d.obstacleLabels()
        d.sectionMark()
        d.labels()
        if let n = highlight, !d.pvMode { d.highlight(Self.highlightKeys(d.frame, member: n)) }

        sketch = Sketch(width: Self.width, height: Self.height, ops: d.o)
        tags = d.tg
        layout = d.L
        pv = d.pv
    }

    /// The PV preview count alone (tests, hints).
    public static func pvCount(_ v: Values, portrait: Bool = true, module: Module = .catalogDefault) -> Int {
        RoofPV(v, portrait: portrait, module: module).count
    }
}

// MARK: - drawing

/// Draws the plan in the design's viewBox (origin (100, -6)), one method per layer, in the design's order.
private struct Drawer {
    let v: Values
    let pvMode: Bool
    let xs: [Double], ys: [Double]
    let frame: RoofFrame
    /// Ridge along x.
    let hor: Bool
    /// Roof slope (°).
    let ang: Double
    let Lx: Double, Ly: Double, k: Double, W: Double, H: Double, x0: Double, y0: Double
    /// Grid lines along x and y (design units).
    let gx: [Double], gy: [Double]
    var o: [DrawOp] = [], tg: [String?] = []
    var L = RoofPlan.Layout()
    var pv = RoofPlan.PV()
    /// Frame and slope labels, drawn last over everything (structure mode).
    var notes: [(String, Double, Double)] = []

    init(_ v: Values, pv: Bool) {
        self.v = v; pvMode = pv
        xs = Roof.spans(v, .x); ys = Roof.spans(v, .y); frame = Roof.frame(v)
        hor = Roof.ridge(v) == .h; ang = frame.slope
        Lx = xs.reduce(0, +); Ly = ys.reduce(0, +)
        k = min(380 / Lx, 320 / Ly); W = Lx * k; H = Ly * k; x0 = 400 - W / 2; y0 = 252 - H / 2
        var gx = [x0]; for s in xs { gx.append(gx.last! + s * k) }
        var gy = [y0]; for s in ys { gy.append(gy.last! + s * k) }
        self.gx = gx; self.gy = gy
        L.origin = P(x0, y0); L.k = k; L.lx = Lx; L.ly = Ly
    }

    // MARK: primitives

    mutating func add(_ op: DrawOp, _ tag: String?) { o.append(op); tg.append(tag) }
    func P(_ x: Double, _ y: Double) -> Pt { Pt(x - 100, y + 6) }
    mutating func line(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ w: Double, _ col: RGBA, dash: [Double] = [], _ tag: String? = nil) {
        add(.line(P(a, b), P(c, d), width: w, color: col, dash: dash), tag)
    }
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Box { let p = P(x, y); return Box(p.x, p.y, w, h) }
    mutating func text(_ t: String, _ x: Double, _ y: Double, _ size: Double, bold: Bool = false, color: RGBA = RoofPlan.navy, bg: Bool = false,
                       angle: Double = 0, align: TextAlign = .center, _ tag: String? = nil) {
        let p = P(x, y)
        if bg {
            let w = ApproxText.width(t, size: size, bold: bold) + 6, h = size + 3
            let x0 = align == .left ? p.x - 3 : p.x - w / 2
            add(.rect(angle == 0 ? Box(x0, p.y - h / 2, w, h) : Box(p.x - h / 2, p.y - w / 2, h, w), stroke: nil, fill: .white), nil)
        }
        add(.text(t, at: p, size: size, bold: bold, color: color, align: align, angle: angle), tag)
    }
    mutating func dashedBox(_ b: Box, _ col: RGBA, _ w: Double, _ dash: [Double], _ tag: String? = nil) {
        let c = [Pt(b.x, b.y), Pt(b.maxX, b.y), Pt(b.maxX, b.maxY), Pt(b.x, b.maxY)]
        for i in 0..<4 { add(.line(c[i], c[(i + 1) % 4], width: w, color: col, dash: dash), tag) }
    }
    /// A box in metres from the plan's top-left on the sketch.
    func sketchBox(_ m: Box) -> Box { Box(L.origin.x + m.x * k, L.origin.y + m.y * k, m.w * k, m.h * k) }
    /// A 45° dimension tick.
    mutating func tick(_ x: Double, _ y: Double, _ w: Double, _ col: RGBA, _ tag: String? = nil) { line(x - 4, y + 4, x + 4, y - 4, w, col, tag) }

    // MARK: layers

    mutating func background() { add(.rect(Box(0, 0, RoofPlan.width, RoofPlan.height), stroke: nil, fill: .white), nil) }

    /// Purlins parallel to the ridge at ระยะแป along the slope.
    mutating func purlins() {
        for m in Roof.purlinLines(v) {
            if hor { line(gx[0], y0 + m * k, gx.last!, y0 + m * k, 0.5, RoofPlan.purlC, "purl") }
            else { line(x0 + m * k, gy[0], x0 + m * k, gy.last!, 0.5, RoofPlan.purlC, "purl") }
        }
    }

    mutating func grid() {
        let gdash: [Double] = [14, 3, 2, 3]
        for x in gx { line(x, y0 - 22, x, y0 + H + 14, 0.6, RoofPlan.gridC, dash: gdash, "grid") }
        for y in gy { line(x0 - 22, y, x0 + W + 14, y, 0.6, RoofPlan.gridC, dash: gdash, "grid") }
    }

    /// Rafters and eaves, or the trusses (T1 across the ridge, T2 along it for a rafter truss).
    mutating func frameLines() {
        let AL = hor ? gx : gy, CR = hor ? gy : gx, aMin = AL.first!, aMax = AL.last!, cMin = CR.first!, cMax = CR.last!
        func across(_ a: Double, _ w: Double, dash: [Double] = [], _ tag: String) {
            if hor { line(a, cMin, a, cMax, w, RoofPlan.ink, dash: dash, tag) } else { line(cMin, a, cMax, a, w, RoofPlan.ink, dash: dash, tag) }
        }
        func along(_ c: Double, _ ext: Double, _ w: Double, dash: [Double] = [], _ tag: String) {
            if hor { line(aMin - ext, c, aMax + ext, c, w, RoofPlan.ink, dash: dash, tag) } else { line(c, aMin - ext, c, aMax + ext, w, RoofPlan.ink, dash: dash, tag) }
        }
        func lab(_ a: Double, _ c: Double, _ t: String) { notes.append((t, hor ? a : c, hor ? c : a)) }
        let inA = Array(AL.dropFirst().dropLast()), inC = Array(CR.dropFirst().dropLast())
        if frame.isRafter {
            var a = aMin + k / 2
            while a < aMax { across(a, 0.7, "raft"); a += k }
            let eaves = [CR[min(1, CR.count - 1)], CR[max(0, CR.count - 2)]]
            for c in eaves { along(c, 6, 1.8, "eave") }
            lab(aMin + (aMax - aMin) * 0.3, eaves[0] - 10, "อเส"); lab(aMin + (aMax - aMin) * 0.3, eaves[1] + 12, "อเส")
            lab(aMin + (aMax - aMin) * 0.62, cMin + (cMax - cMin) * 0.3, "จันทัน @1.00")
        } else if frame == .rafterTruss {
            for a in inA { across(a, 1.8, "truss"); lab(a, cMin + 12, "T1") }
            for c in inC where AL.count > 2 { along(c, 6, 1.5, dash: [12, 3], "t2"); lab((AL[1] + AL[2]) / 2, c - 9, "T2") }
        } else {
            for a in inA { across(a - 2.5, 1.1, "tbd"); across(a + 2.5, 1.1, "tbd"); lab(a, cMin + 12, "T1") }
        }
    }

    /// Every grid node for the page's post buttons; the chosen posts drawn in the structure mode.
    mutating func posts() {
        let posts = Roof.posts(v)
        for (i, x) in gx.enumerated() {
            for (j, y) in gy.enumerated() {
                let on = posts.contains("\(i),\(j)")
                L.nodes.append((i, j, P(x, y), on))
                if on && !pvMode { add(.rect(rect(x - 4, y - 4, 8, 8), stroke: nil, fill: RoofPlan.postInk), "post") }
            }
        }
    }

    mutating func outlineAndRidge() {
        add(.rect(rect(x0, y0, W, H), stroke: RoofPlan.ink, fill: nil, width: 1.5), "out")
        let rdash: [Double] = [18, 4, 3, 4]
        if hor { line(x0 - 10, y0 + H / 2, x0 + W + 10, y0 + H / 2, 1.2, RoofPlan.ink, dash: rdash, "ridge") }
        else { line(x0 + W / 2, y0 - 10, x0 + W / 2, y0 + H + 10, 1.2, RoofPlan.ink, dash: rdash, "ridge") }
    }

    /// Grid bubbles A, B, C… along x and 1, 2, 3… along y.
    mutating func bubbles() {
        for (i, x) in gx.enumerated() {
            add(.circle(P(x, 58), r: 10, stroke: RoofPlan.navy, fill: .white, width: 0.9), "bub"); text(Roof.gridName(.x, i), x, 58, 13, bold: true, "txt")
        }
        for (j, y) in gy.enumerated() {
            add(.circle(P(176, y), r: 10, stroke: RoofPlan.navy, fill: .white, width: 0.9), "bub"); text(Roof.gridName(.y, j), 176, y, 13, bold: true, "txt")
        }
    }

    /// Dimension chains with 45° ticks, the totals, and each span as text or as a chip point for the page.
    mutating func dimensions(chips: Bool) {
        line(gx.first! - 6, 32, gx.last! + 6, 32, 0.8, RoofPlan.navy, "dim"); line(gx.first! - 6, 10, gx.last! + 6, 10, 0.8, RoofPlan.navy, "dim")
        for (i, x) in gx.enumerated() { line(x, i == 0 || i == gx.count - 1 ? 6 : 28, x, 47, 0.8, RoofPlan.navy, "dim"); tick(x, 32, 0.9, RoofPlan.navy, "dim") }
        tick(gx.first!, 10, 0.9, RoofPlan.navy, "dim"); tick(gx.last!, 10, 0.9, RoofPlan.navy, "dim")
        line(150, gy.first! - 6, 150, gy.last! + 6, 0.8, RoofPlan.navy, "dim"); line(128, gy.first! - 6, 128, gy.last! + 6, 0.8, RoofPlan.navy, "dim")
        for (j, y) in gy.enumerated() { line(j == 0 || j == gy.count - 1 ? 124 : 146, y, 165, y, 0.8, RoofPlan.navy, "dim"); tick(150, y, 0.9, RoofPlan.navy, "dim") }
        tick(128, gy.first!, 0.9, RoofPlan.navy, "dim"); tick(128, gy.last!, 0.9, RoofPlan.navy, "dim")
        text(String(format: "%.2f", Lx), 400, 4, 13, bold: true, bg: true, "dimtxt")
        text(String(format: "%.2f", Ly), 118, 252, 13, bold: true, bg: true, angle: -90, "dimtxt")
        for (i, s) in xs.enumerated() {
            L.chips.append(RoofPlan.Chip(axis: .x, index: i, value: s, at: P((gx[i] + gx[i + 1]) / 2, 21)))
            if !chips { text(fmt(s), (gx[i] + gx[i + 1]) / 2, 21, 12, "dimtxt") }
        }
        for (j, s) in ys.enumerated() {
            L.chips.append(RoofPlan.Chip(axis: .y, index: j, value: s, at: P(139, (gy[j] + gy[j + 1]) / 2)))
            if !chips { text(fmt(s), 139, (gy[j] + gy[j + 1]) / 2, 12, angle: -90, "dimtxt") }
        }
        L.addX = P(gx.last! + 22, 21); L.addY = P(139, gy.last! + 22)
    }

    /// `แป @1.00` on one bay of the lower face.
    mutating func purlinCallout() {
        let Lcr = hor ? Ly : Lx, ppH = Roof.purlinSpacing(v) * cos(ang * .pi / 180)
        let m1 = Lcr / 2 + 0.15 + ppH * 2, m2 = m1 + ppH, t = "แป @" + String(format: "%.2f", Roof.purlinSpacing(v))
        guard m2 < Lcr - 0.1 else { return }
        if hor {
            let xd = x0 + W * 0.72, ya = y0 + m1 * k, yb = y0 + m2 * k
            line(xd, ya, xd, yb, 1, RoofPlan.amber); tick(xd, ya, 1, RoofPlan.amber); tick(xd, yb, 1, RoofPlan.amber)
            text(t, xd + 6, (ya + yb) / 2, 12.5, bold: true, color: RoofPlan.amber, bg: true, align: .left)
        } else {
            let yd = y0 + H * 0.74, xa = x0 + m1 * k, xb = x0 + m2 * k
            line(xa, yd, xb, yd, 1, RoofPlan.amber); tick(xa, yd, 1, RoofPlan.amber); tick(xb, yd, 1, RoofPlan.amber)
            text(t, (xa + xb) / 2, yd - 10, 12.5, bold: true, color: RoofPlan.amber, bg: true)
        }
    }

    /// Slope arrows down both faces, labelled on the first pair.
    mutating func slopeArrows() {
        func head(_ tip: Pt, _ dx: Double, _ dy: Double) -> DrawOp {
            // a 10-wide, 10-long triangle pointing from (tip - d) to tip
            let b = Pt(tip.x - dx * 10, tip.y - dy * 10), n = Pt(-dy * 5, dx * 5)
            return .polygon([tip, Pt(b.x + n.x, b.y + n.y), Pt(b.x - n.x, b.y - n.y)], stroke: nil, fill: RoofPlan.navy)
        }
        let slope = "ลาด \(fmt(ang))°"
        if hor {
            for (n, x) in [x0 + W * 0.18, x0 + W * 0.82].enumerated() {
                let m = y0 + H / 2
                line(x, m - 12, x, y0 + 30, 1.2, RoofPlan.navy); add(head(P(x, y0 + 22), 0, -1), nil)
                line(x, m + 12, x, y0 + H - 30, 1.2, RoofPlan.navy); add(head(P(x, y0 + H - 22), 0, 1), nil)
                if n == 0 { notes.append((slope, x, m - 36)); notes.append((slope, x, m + 36)) }
            }
        } else {
            for (n, y) in [y0 + H * 0.2, y0 + H * 0.8].enumerated() {
                let m = x0 + W / 2
                line(m - 12, y, x0 + 30, y, 1.2, RoofPlan.navy); add(head(P(x0 + 22, y), -1, 0), nil)
                line(m + 12, y, x0 + W - 30, y, 1.2, RoofPlan.navy); add(head(P(x0 + W - 22, y), 1, 0), nil)
                if n == 0 { notes.append((slope, m - 44, y - 12)); notes.append((slope, m + 44, y - 12)) }
            }
        }
    }

    /// Skylights, obstacles and (PV mode only) keep-out zones.
    mutating func areas() {
        for a in Roof.areas(v) {
            let b = Box(L.origin.x + a.x * k, L.origin.y + a.y * k, a.w * k, a.h * k)
            if a.kind == Roof.keepOutKind && !pvMode { continue }
            L.areas.append((a, b))
            switch a.kind {
            case Roof.skylightKind:
                add(.rect(b, stroke: nil, fill: RoofPlan.skyFill), nil)
                if a.canCover { add(.rect(b, stroke: RoofPlan.skyLine, fill: nil, width: 1), "sky") } else { dashedBox(b, RoofPlan.red, 1.2, [4, 2], "sky") }
            case Roof.keepOutKind:
                add(.rect(b, stroke: nil, fill: RGBA(0.851, 0.271, 0.231, 0.10)), nil); add(.hatch(b, color: RoofPlan.red, spacing: 7), nil)
                add(.rect(b, stroke: RoofPlan.red, fill: nil, width: 1.4), "kz")
            default:
                add(.rect(b, stroke: nil, fill: .white), nil); add(.hatch(b, color: RoofPlan.red), nil); add(.rect(b, stroke: RoofPlan.red, fill: nil, width: 1), "obst")
            }
        }
    }

    /// The modules, dropped modules, table outlines and the gaps between tables.
    mutating func pvLayout(_ lay: RoofPV) {
        pv.placed = lay.placed.map(sketchBox); pv.blocked = lay.blocked.map(sketchBox)
        for b in pv.placed { add(.rect(b, stroke: RoofPlan.pvLine, fill: RGBA(0.122, 0.31, 0.561, 0.85), width: 0.6), "pv") }
        for b in pv.blocked { dashedBox(b, RoofPlan.pvFill, 0.6, [3, 2]) }
        pv.count = pv.placed.count
        pv.kWp = lay.kWp
        pv.tables = lay.tables
        for b in lay.outlines { add(.rect(sketchBox(b), stroke: RoofPlan.navy, fill: nil, width: 1.6), "tbl") }
        // the gap between tables, dimensioned once each way
        let gl = "ห่าง " + String(format: "%.2f", Roof.pvGap(v))
        if let g = lay.alongGap {
            if hor {
                let xa = x0 + g.a1 * k, xb = x0 + g.a2 * k, yd = y0 + g.c * k
                line(xa - 8, yd, xb + 8, yd, 1, RoofPlan.amber); tick(xa, yd, 1, RoofPlan.amber); tick(xb, yd, 1, RoofPlan.amber)
                text(gl, (xa + xb) / 2 + 30, yd + 1, 12, bold: true, color: RoofPlan.amber, bg: true, align: .left)
            } else {
                let ya = y0 + g.a1 * k, yb = y0 + g.a2 * k, xd = x0 + g.c * k
                line(xd, ya - 8, xd, yb + 8, 1, RoofPlan.amber); tick(xd, ya, 1, RoofPlan.amber); tick(xd, yb, 1, RoofPlan.amber)
                text(gl, xd + 6, (ya + yb) / 2 + 26, 12, bold: true, color: RoofPlan.amber, bg: true, align: .left)
            }
        }
        if let g = lay.acrossGap {
            if hor {
                let xd = x0 + g.a * k, ya = y0 + g.c2 * k, yb = y0 + g.c1 * k
                line(xd, ya, xd, yb, 1, RoofPlan.amber); tick(xd, ya, 1, RoofPlan.amber); tick(xd, yb, 1, RoofPlan.amber)
                text(gl, xd + 6, (ya + yb) / 2, 12, bold: true, color: RoofPlan.amber, bg: true, align: .left)
            } else {
                let yd = y0 + g.a * k, xa = x0 + g.c2 * k, xb = x0 + g.c1 * k
                line(xa, yd, xb, yd, 1, RoofPlan.amber); tick(xa, yd, 1, RoofPlan.amber); tick(xb, yd, 1, RoofPlan.amber)
                text(gl, (xa + xb) / 2, yd + 12, 12, bold: true, color: RoofPlan.amber, bg: true)
            }
        }
    }

    /// An unfinished skylight / keep-out zone being dragged (metres, two corners).
    mutating func dragged(_ d: (Double, Double, Double, Double), fill: RGBA, line col: RGBA, width: Double) {
        let b = Box(L.origin.x + min(d.0, d.2) * k, L.origin.y + min(d.1, d.3) * k, abs(d.2 - d.0) * k, abs(d.3 - d.1) * k)
        add(.rect(b, stroke: nil, fill: fill), nil); dashedBox(b, col, width, [5, 3])
    }

    /// `ห้ามติด 4.0×3.0` in each keep-out zone.
    mutating func keepOutLabels() {
        for (a, b) in L.areas where a.kind == Roof.keepOutKind {
            let t = "ห้ามติด " + String(format: "%.1f×%.1f", a.w, a.h)
            let c = Pt(b.x + b.w / 2, b.y + b.h / 2), w = ApproxText.width(t, size: 10.5, bold: true) + 6
            add(.rect(Box(c.x - w / 2, c.y - 7, w, 14), stroke: nil, fill: RGBA(1, 1, 1, 0.85)), nil)
            add(.text(t, at: c, size: 10.5, bold: true, color: RoofPlan.redText, align: .center), nil)
        }
    }

    /// Obstacle labels as on the old plan.
    mutating func obstacleLabels() {
        for (a, b) in L.areas where a.kind == "" && !a.label.isEmpty {
            add(.text("\(a.label) \(fmt(a.w))x\(fmt(a.h))", at: Pt(b.maxX + 3, b.maxY - 3), size: 8, color: .dark), nil)
        }
    }

    /// Section mark A-A across the roof.
    mutating func sectionMark() {
        let sdash: [Double] = [16, 4, 3, 4], sc = RoofPlan.postInk
        func bubble(_ c: Pt) -> [DrawOp] {
            [.circle(c, r: 10.5, stroke: sc, fill: .white, width: 1.4), .text("A", at: c, size: 14, bold: true, color: sc, align: .center)]
        }
        func ends(_ arrow: DrawOp, _ at: Pt) {
            add(arrow, nil)
            let b = bubble(at); add(b[0], "sec"); add(b[1], nil)
        }
        if hor {
            let sx = x0 + W * 0.42
            line(sx, y0 - 2, sx, y0 + H + 2, 0.9, sc, dash: sdash, "sec")
            for (a, b) in [(y0 - 17, y0 - 2), (y0 + H + 2, y0 + H + 17)] {
                line(sx, a, sx, b, 3, sc, "sec"); let m = (a + b) / 2
                ends(.polygon([P(sx - 1.5, m - 6), P(sx - 14, m), P(sx - 1.5, m + 6)], stroke: nil, fill: sc), P(sx - 23, m))
            }
        } else {
            let sy = y0 + H * 0.42
            line(x0 - 2, sy, x0 + W + 2, sy, 0.9, sc, dash: sdash, "sec")
            for (a, b) in [(x0 - 17, x0 - 2), (x0 + W + 2, x0 + W + 17)] {
                line(a, sy, b, sy, 3, sc, "sec"); let m = (a + b) / 2
                ends(.polygon([P(m - 6, sy - 1.5), P(m, sy - 14), P(m + 6, sy - 1.5)], stroke: nil, fill: sc), P(m, sy - 23))
            }
        }
    }

    /// The frame and slope labels (structure mode), then `สันหลังคา`.
    mutating func labels() {
        if !pvMode {
            for (t, x, y) in notes { let s = t.hasPrefix("ลาด"); text(t, x, y, s ? 13 : 11, bold: !s, bg: true) }
        }
        text("สันหลังคา", hor ? x0 + W + 34 : x0 + W / 2, hor ? y0 + H / 2 : y0 - 30, 13, bold: true, bg: true)
    }

    /// The chosen member's lines redrawn in red, over everything.
    mutating func highlight(_ keys: [String]) {
        let keys = Set(keys)
        for (op, t) in zip(o, tg) {
            guard let t, keys.contains(t) else { continue }
            switch op {
            case let .line(a, b, w, _, dash): o.append(.line(a, b, width: w + 1.6, color: RoofPlan.red, dash: dash))
            case let .rect(b, _, fill, w): o.append(fill != nil ? .rect(b, stroke: nil, fill: RoofPlan.red) : .rect(b, stroke: RoofPlan.red, fill: nil, width: w + 1.5))
            default: continue
            }
            tg.append(nil)
        }
    }
}
