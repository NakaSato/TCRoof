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

    static let navy = RGBA(hex: 0x16325C), gridC = RGBA(hex: 0x8A97AA), ink = RGBA(hex: 0x111111), purlC = RGBA(hex: 0x6B7280)
    static let red = RGBA(hex: 0xD9453B), skyFill = RGBA(hex: 0xCFE8F7), skyLine = RGBA(hex: 0x2E8FDB), pvFill = RGBA(hex: 0x1F4F8F)
    static let pvLine = RGBA(hex: 0xDCE6F2), redText = RGBA(hex: 0xB42318), amber = RGBA(hex: 0xB45309)

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
        let xs = Roof.spans(v, .x), ys = Roof.spans(v, .y), frame = Roof.frame(v), ridge = Roof.ridge(v)
        let portrait = portrait ?? Roof.pvPortrait(v)
        var o: [DrawOp] = [], tg: [String?] = [], L = Layout(), pv = PV()
        func add(_ op: DrawOp, _ tag: String?) { o.append(op); tg.append(tag) }
        // design viewBox origin (100, -6)
        func P(_ x: Double, _ y: Double) -> Pt { Pt(x - 100, y + 6) }
        func line(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ w: Double, _ col: RGBA, dash: [Double] = [], _ tag: String? = nil) {
            add(.line(P(a, b), P(c, d), width: w, color: col, dash: dash), tag)
        }
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Box { let p = P(x, y); return Box(p.x, p.y, w, h) }
        func text(_ t: String, _ x: Double, _ y: Double, _ size: Double, bold: Bool = false, color: RGBA = RoofPlan.navy, bg: Bool = false,
                  angle: Double = 0, align: TextAlign = .center, _ tag: String? = nil) {
            let p = P(x, y)
            if bg {
                let w = ApproxText.width(t, size: size, bold: bold) + 6, h = size + 3
                let x0 = align == .left ? p.x - 3 : p.x - w / 2
                add(.rect(angle == 0 ? Box(x0, p.y - h / 2, w, h) : Box(p.x - h / 2, p.y - w / 2, h, w), stroke: nil, fill: .white), nil)
            }
            add(.text(t, at: p, size: size, bold: bold, color: color, align: align, angle: angle), tag)
        }
        func dashedBox(_ b: Box, _ col: RGBA, _ w: Double, _ dash: [Double], _ tag: String? = nil) {
            let c = [Pt(b.x, b.y), Pt(b.maxX, b.y), Pt(b.maxX, b.maxY), Pt(b.x, b.maxY)]
            for i in 0..<4 { add(.line(c[i], c[(i + 1) % 4], width: w, color: col, dash: dash), tag) }
        }

        let Lx = xs.reduce(0, +), Ly = ys.reduce(0, +)
        let k = min(380 / Lx, 320 / Ly), W = Lx * k, H = Ly * k, x0 = 400 - W / 2, y0 = 252 - H / 2
        var gx = [x0]; for s in xs { gx.append(gx.last! + s * k) }
        var gy = [y0]; for s in ys { gy.append(gy.last! + s * k) }
        L.origin = P(x0, y0); L.k = k; L.lx = Lx; L.ly = Ly
        let hor = ridge == .h, ang = frame.slope, pvMode = mode == .pv
        add(.rect(Box(0, 0, Self.width, Self.height), stroke: nil, fill: .white), nil)

        // purlins parallel to the ridge at ระยะแป along the slope
        let Lcr = hor ? Ly : Lx, ppH = Roof.purlinSpacing(v) * cos(ang * .pi / 180)
        if !pvMode {
            for m in Roof.purlinLines(v) {
                if hor { line(gx[0], y0 + m * k, gx.last!, y0 + m * k, 0.5, Self.purlC, "purl") }
                else { line(x0 + m * k, gy[0], x0 + m * k, gy.last!, 0.5, Self.purlC, "purl") }
            }
        }
        let gdash: [Double] = [14, 3, 2, 3]
        for x in gx { line(x, y0 - 22, x, y0 + H + 14, 0.6, Self.gridC, dash: gdash, "grid") }
        for y in gy { line(x0 - 22, y, x0 + W + 14, y, 0.6, Self.gridC, dash: gdash, "grid") }

        // frame lines
        let AL = hor ? gx : gy, CR = hor ? gy : gx, aMin = AL.first!, aMax = AL.last!, cMin = CR.first!, cMax = CR.last!
        func across(_ a: Double, _ w: Double, dash: [Double] = [], _ tag: String) {
            if hor { line(a, cMin, a, cMax, w, Self.ink, dash: dash, tag) } else { line(cMin, a, cMax, a, w, Self.ink, dash: dash, tag) }
        }
        func along(_ c: Double, _ ext: Double, _ w: Double, dash: [Double] = [], _ tag: String) {
            if hor { line(aMin - ext, c, aMax + ext, c, w, Self.ink, dash: dash, tag) } else { line(c, aMin - ext, c, aMax + ext, w, Self.ink, dash: dash, tag) }
        }
        var labels: [(String, Double, Double)] = []
        func lab(_ a: Double, _ c: Double, _ t: String) { labels.append((t, hor ? a : c, hor ? c : a)) }
        let inA = Array(AL.dropFirst().dropLast()), inC = Array(CR.dropFirst().dropLast())
        if !pvMode {
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
        // posts
        let posts = Roof.posts(v)
        for (i, x) in gx.enumerated() {
            for (j, y) in gy.enumerated() {
                let on = posts.contains("\(i),\(j)")
                L.nodes.append((i, j, P(x, y), on))
                if on && !pvMode { add(.rect(rect(x - 4, y - 4, 8, 8), stroke: nil, fill: RGBA(hex: 0x111827)), "post") }
            }
        }
        add(.rect(rect(x0, y0, W, H), stroke: Self.ink, fill: nil, width: 1.5), "out")
        // ridge
        let rdash: [Double] = [18, 4, 3, 4]
        if hor { line(x0 - 10, y0 + H / 2, x0 + W + 10, y0 + H / 2, 1.2, Self.ink, dash: rdash, "ridge") }
        else { line(x0 + W / 2, y0 - 10, x0 + W / 2, y0 + H + 10, 1.2, Self.ink, dash: rdash, "ridge") }
        // grid bubbles
        for (i, x) in gx.enumerated() {
            add(.circle(P(x, 58), r: 10, stroke: Self.navy, fill: .white, width: 0.9), "bub"); text(Roof.gridName(.x, i), x, 58, 13, bold: true, "txt")
        }
        for (j, y) in gy.enumerated() {
            add(.circle(P(176, y), r: 10, stroke: Self.navy, fill: .white, width: 0.9), "bub"); text(Roof.gridName(.y, j), 176, y, 13, bold: true, "txt")
        }
        // dimension chains, 45° ticks
        func tick(_ x: Double, _ y: Double) { line(x - 4, y + 4, x + 4, y - 4, 0.9, Self.navy, "dim") }
        line(gx.first! - 6, 32, gx.last! + 6, 32, 0.8, Self.navy, "dim"); line(gx.first! - 6, 10, gx.last! + 6, 10, 0.8, Self.navy, "dim")
        for (i, x) in gx.enumerated() { line(x, i == 0 || i == gx.count - 1 ? 6 : 28, x, 47, 0.8, Self.navy, "dim"); tick(x, 32) }
        tick(gx.first!, 10); tick(gx.last!, 10)
        line(150, gy.first! - 6, 150, gy.last! + 6, 0.8, Self.navy, "dim"); line(128, gy.first! - 6, 128, gy.last! + 6, 0.8, Self.navy, "dim")
        for (j, y) in gy.enumerated() { line(j == 0 || j == gy.count - 1 ? 124 : 146, y, 165, y, 0.8, Self.navy, "dim"); tick(150, y) }
        tick(128, gy.first!); tick(128, gy.last!)
        text(String(format: "%.2f", Lx), 400, 4, 13, bold: true, bg: true, "dimtxt")
        text(String(format: "%.2f", Ly), 118, 252, 13, bold: true, bg: true, angle: -90, "dimtxt")
        for (i, s) in xs.enumerated() {
            let c = P((gx[i] + gx[i + 1]) / 2, 21)
            L.chips.append(Chip(axis: .x, index: i, value: s, at: c))
            if !chips { text(fmt(s), (gx[i] + gx[i + 1]) / 2, 21, 12, "dimtxt") }
        }
        for (j, s) in ys.enumerated() {
            let c = P(139, (gy[j] + gy[j + 1]) / 2)
            L.chips.append(Chip(axis: .y, index: j, value: s, at: c))
            if !chips { text(fmt(s), 139, (gy[j] + gy[j + 1]) / 2, 12, angle: -90, "dimtxt") }
        }
        L.addX = P(gx.last! + 22, 21); L.addY = P(139, gy.last! + 22)

        // purlin spacing callout on one bay of the lower face
        if !pvMode {
            let m1 = Lcr / 2 + 0.15 + ppH * 2, m2 = m1 + ppH, t = "แป @" + String(format: "%.2f", Roof.purlinSpacing(v))
            if m2 < Lcr - 0.1 {
                if hor {
                    let xd = x0 + W * 0.72, ya = y0 + m1 * k, yb = y0 + m2 * k
                    line(xd, ya, xd, yb, 1, Self.amber); line(xd - 4, ya + 4, xd + 4, ya - 4, 1, Self.amber); line(xd - 4, yb + 4, xd + 4, yb - 4, 1, Self.amber)
                    text(t, xd + 6, (ya + yb) / 2, 12.5, bold: true, color: Self.amber, bg: true, align: .left)
                } else {
                    let yd = y0 + H * 0.74, xa = x0 + m1 * k, xb = x0 + m2 * k
                    line(xa, yd, xb, yd, 1, Self.amber); line(xa - 4, yd + 4, xa + 4, yd - 4, 1, Self.amber); line(xb - 4, yd + 4, xb + 4, yd - 4, 1, Self.amber)
                    text(t, (xa + xb) / 2, yd - 10, 12.5, bold: true, color: Self.amber, bg: true)
                }
            }
        }

        // slope arrows, labelled on the first one
        if !pvMode {
            func head(_ tip: Pt, _ dx: Double, _ dy: Double) {
                // a 10-wide, 10-long triangle pointing from (tip - d) to tip
                let b = Pt(tip.x - dx * 10, tip.y - dy * 10), n = Pt(-dy * 5, dx * 5)
                add(.polygon([tip, Pt(b.x + n.x, b.y + n.y), Pt(b.x - n.x, b.y - n.y)], stroke: nil, fill: Self.navy), nil)
            }
            let slope = "ลาด \(fmt(ang))°"
            if hor {
                for (n, x) in [x0 + W * 0.18, x0 + W * 0.82].enumerated() {
                    let m = y0 + H / 2
                    line(x, m - 12, x, y0 + 30, 1.2, Self.navy); head(P(x, y0 + 22), 0, -1)
                    line(x, m + 12, x, y0 + H - 30, 1.2, Self.navy); head(P(x, y0 + H - 22), 0, 1)
                    if n == 0 { labels.append((slope, x, m - 36)); labels.append((slope, x, m + 36)) }
                }
            } else {
                for (n, y) in [y0 + H * 0.2, y0 + H * 0.8].enumerated() {
                    let m = x0 + W / 2
                    line(m - 12, y, x0 + 30, y, 1.2, Self.navy); head(P(x0 + 22, y), -1, 0)
                    line(m + 12, y, x0 + W - 30, y, 1.2, Self.navy); head(P(x0 + W - 22, y), 1, 0)
                    if n == 0 { labels.append((slope, m - 44, y - 12)); labels.append((slope, m + 44, y - 12)) }
                }
            }
        }

        // skylights, obstacles and keep-out zones
        let areas = Roof.areas(v)
        for a in areas {
            let b = Box(L.origin.x + a.x * k, L.origin.y + a.y * k, a.w * k, a.h * k)
            if a.kind == Roof.keepOutKind && !pvMode { continue }
            L.areas.append((a, b))
            switch a.kind {
            case Roof.skylightKind:
                add(.rect(b, stroke: nil, fill: Self.skyFill), nil)
                if a.canCover { add(.rect(b, stroke: Self.skyLine, fill: nil, width: 1), "sky") } else { dashedBox(b, Self.red, 1.2, [4, 2], "sky") }
            case Roof.keepOutKind:
                add(.rect(b, stroke: nil, fill: RGBA(0.851, 0.271, 0.231, 0.10)), nil); add(.hatch(b, color: Self.red, spacing: 7), nil)
                add(.rect(b, stroke: Self.red, fill: nil, width: 1.4), "kz")
            default:
                add(.rect(b, stroke: nil, fill: .white), nil); add(.hatch(b, color: Self.red), nil); add(.rect(b, stroke: Self.red, fill: nil, width: 1), "obst")
            }
        }

        // PV layout: tables of `nS` rows down each face from the eave and `nR` modules along the ridge, `gap` apart
        if pvMode {
            let La = hor ? Lx : Ly, Lc = hor ? Ly : Lx, cs = cos(ang * .pi / 180), gp = 0.02, seE = 0.5, seR = 0.3, seG = 0.5
            let msl = portrait ? module.length : module.width, mwd = portrait ? module.width : module.length
            let nS = Roof.pvRows(v), nR = Roof.pvPerTable(v, portrait: portrait), gap = Roof.pvGap(v)
            let us = (Lc / 2) / cs - seE - seR
            let pS = nS > 0 ? Double(nS) * (msl + gp) - gp + gap : 0, pR = nR > 0 ? Double(nR) * (mwd + gp) - gp + gap : 0
            let GS = nS > 0 ? max(0, Int(floor((us + gap) / pS))) : 0, GR = nR > 0 ? max(0, Int(floor((La - 2 * seG + gap) / pR))) : 0
            let rows = nS > 0 ? GS * nS : max(0, Int(floor((us + gp) / (msl + gp))))
            let cols = nR > 0 ? GR * nR : max(0, Int(floor((La - 2 * seG + gp) / (mwd + gp))))
            let rowW = nR > 0 ? Double(GR) * (pR - gap) + Double(max(0, GR - 1)) * gap : Double(cols) * (mwd + gp) - gp
            let off = (La - rowW) / 2
            func aOf(_ c: Int) -> Double { nR > 0 ? off + Double(c / nR) * pR + Double(c % nR) * (mwd + gp) : off + Double(c) * (mwd + gp) }
            func sOf(_ r: Int) -> Double { nS > 0 ? seE + Double(r / nS) * pS + Double(r % nS) * (msl + gp) : seE + Double(r) * (msl + gp) }
            // blocked areas as (a1, a2, c1, c2) along / across the ridge
            var obs: [(Double, Double, Double, Double)] = []
            for a in areas where !(a.kind == Roof.skylightKind && a.canCover) {
                let e = a.kind == Roof.skylightKind ? 0.1 : 0
                obs.append(hor ? (a.x - e, a.x + a.w + e, a.y, a.y + a.h) : (a.y - e, a.y + a.h + e, a.x, a.x + a.w))
            }
            func box(_ a1: Double, _ a2: Double, _ s1: Double, _ s2: Double, _ face: Int) -> (Double, Double, Double, Double) {
                var c1 = s1 * cs, c3 = s2 * cs
                if face == 1 { (c1, c3) = (Lc - c3, Lc - c1) }
                return (a1, a2, c1, c3)
            }
            func sk(_ b: (Double, Double, Double, Double)) -> Box {
                hor ? Box(L.origin.x + b.0 * k, L.origin.y + b.2 * k, (b.1 - b.0) * k, (b.3 - b.2) * k)
                    : Box(L.origin.x + b.2 * k, L.origin.y + b.0 * k, (b.3 - b.2) * k, (b.1 - b.0) * k)
            }
            var used = Set<String>()
            for face in 0..<2 {
                for r in 0..<rows {
                    for c in 0..<cols {
                        let a1 = aOf(c), s1 = sOf(r), b = box(a1, a1 + mwd, s1, s1 + msl, face)
                        if obs.contains(where: { b.1 > $0.0 && b.0 < $0.1 && b.3 > $0.2 && b.2 < $0.3 }) { pv.blocked.append(sk(b)); continue }
                        pv.placed.append(sk(b))
                        used.insert("\(face)-\(nS > 0 ? r / nS : r)-\(nR > 0 ? c / nR : 0)")
                    }
                }
            }
            for b in pv.placed { add(.rect(b, stroke: Self.pvLine, fill: RGBA(0.122, 0.31, 0.561, 0.85), width: 0.6), "pv") }
            for b in pv.blocked { dashedBox(b, Self.pvFill, 0.6, [3, 2]) }
            pv.count = pv.placed.count
            pv.kWp = Double(pv.count) * module.kW
            if nS > 0 || nR > 0 {
                pv.tables = used.count
                // table outlines
                let rgN = nS > 0 ? GS : rows, cgN = nR > 0 ? GR : 1
                if cols > 0 && rows > 0 {
                    for face in 0..<2 {
                        for g in 0..<rgN {
                            for h in 0..<cgN where used.contains("\(face)-\(g)-\(h)") {
                                let s1 = nS > 0 ? seE + Double(g) * pS : sOf(g), s2 = s1 + (nS > 0 ? Double(nS) * (msl + gp) - gp : msl)
                                let a1 = nR > 0 ? off + Double(h) * pR : off, a2 = a1 + (nR > 0 ? Double(nR) * (mwd + gp) - gp : rowW)
                                add(.rect(sk(box(a1 - 0.04, a2 + 0.04, s1 - 0.04, s2 + 0.04, face)), stroke: Self.navy, fill: nil, width: 1.6), "tbl")
                            }
                        }
                    }
                }
                // the gap between tables, dimensioned once each way
                let gl = "ห่าง " + String(format: "%.2f", gap)
                func tick2(_ x: Double, _ y: Double) { line(x - 4, y + 4, x + 4, y - 4, 1, Self.amber) }
                if nR > 0 && GR > 1 && rows > 0 {
                    let ga = off + Double(nR) * (mwd + gp) - gp, gb = off + pR, cm = Lc - (sOf(rows - 1) + msl) * cs - 0.3
                    if hor {
                        let xa = x0 + ga * k, xb = x0 + gb * k, yd = y0 + cm * k
                        line(xa - 8, yd, xb + 8, yd, 1, Self.amber); tick2(xa, yd); tick2(xb, yd)
                        text(gl, (xa + xb) / 2 + 30, yd + 1, 12, bold: true, color: Self.amber, bg: true, align: .left)
                    } else {
                        let ya = y0 + ga * k, yb = y0 + gb * k, xd = x0 + cm * k
                        line(xd, ya - 8, xd, yb + 8, 1, Self.amber); tick2(xd, ya); tick2(xd, yb)
                        text(gl, xd + 6, (ya + yb) / 2 + 26, 12, bold: true, color: Self.amber, bg: true, align: .left)
                    }
                }
                if nS > 0 && GS > 1 {
                    let g1 = Lc - (seE + Double(nS) * (msl + gp) - gp) * cs, g2 = Lc - (seE + pS) * cs, ax = off + rowW + 0.3
                    if hor {
                        let xd = x0 + ax * k, ya = y0 + g2 * k, yb = y0 + g1 * k
                        line(xd, ya, xd, yb, 1, Self.amber); tick2(xd, ya); tick2(xd, yb)
                        text(gl, xd + 6, (ya + yb) / 2, 12, bold: true, color: Self.amber, bg: true, align: .left)
                    } else {
                        let yd = y0 + ax * k, xa = x0 + g2 * k, xb = x0 + g1 * k
                        line(xa, yd, xb, yd, 1, Self.amber); tick2(xa, yd); tick2(xb, yd)
                        text(gl, (xa + xb) / 2, yd + 12, 12, bold: true, color: Self.amber, bg: true)
                    }
                }
            }
            if let d = dragging {
                let b = Box(L.origin.x + min(d.0, d.2) * k, L.origin.y + min(d.1, d.3) * k, abs(d.2 - d.0) * k, abs(d.3 - d.1) * k)
                add(.rect(b, stroke: nil, fill: RGBA(0.851, 0.271, 0.231, 0.12)), nil); dashedBox(b, Self.red, 1.4, [5, 3])
            }
            for (a, b) in L.areas where a.kind == Roof.keepOutKind {
                let t = "ห้ามติด " + String(format: "%.1f×%.1f", a.w, a.h)
                let c = Pt(b.x + b.w / 2, b.y + b.h / 2), w = ApproxText.width(t, size: 10.5, bold: true) + 6
                add(.rect(Box(c.x - w / 2, c.y - 7, w, 14), stroke: nil, fill: RGBA(1, 1, 1, 0.85)), nil)
                add(.text(t, at: c, size: 10.5, bold: true, color: Self.redText, align: .center), nil)
            }
        } else if let d = dragging {
            let b = Box(L.origin.x + min(d.0, d.2) * k, L.origin.y + min(d.1, d.3) * k, abs(d.2 - d.0) * k, abs(d.3 - d.1) * k)
            add(.rect(b, stroke: nil, fill: Self.skyFill), nil); dashedBox(b, Self.skyLine, 1.2, [5, 3])
        }
        // obstacle labels as on the old plan
        for (a, b) in L.areas where a.kind == "" && !a.label.isEmpty {
            add(.text("\(a.label) \(fmt(a.w))x\(fmt(a.h))", at: Pt(b.maxX + 3, b.maxY - 3), size: 8, color: .dark), nil)
        }

        // section mark A-A
        func secBubble(_ c: Pt) {
            add(.circle(c, r: 10.5, stroke: RGBA(hex: 0x111827), fill: .white, width: 1.4), "sec")
            add(.text("A", at: c, size: 14, bold: true, color: RGBA(hex: 0x111827), align: .center), nil)
        }
        let sdash: [Double] = [16, 4, 3, 4], sc = RGBA(hex: 0x111827)
        if hor {
            let sx = x0 + W * 0.42
            line(sx, y0 - 2, sx, y0 + H + 2, 0.9, sc, dash: sdash, "sec")
            for (a, b) in [(y0 - 17, y0 - 2), (y0 + H + 2, y0 + H + 17)] {
                line(sx, a, sx, b, 3, sc, "sec"); let m = (a + b) / 2
                add(.polygon([P(sx - 1.5, m - 6), P(sx - 14, m), P(sx - 1.5, m + 6)], stroke: nil, fill: sc), nil)
                secBubble(P(sx - 23, m))
            }
        } else {
            let sy = y0 + H * 0.42
            line(x0 - 2, sy, x0 + W + 2, sy, 0.9, sc, dash: sdash, "sec")
            for (a, b) in [(x0 - 17, x0 - 2), (x0 + W + 2, x0 + W + 17)] {
                line(a, sy, b, sy, 3, sc, "sec"); let m = (a + b) / 2
                add(.polygon([P(m - 6, sy - 1.5), P(m, sy - 14), P(m + 6, sy - 1.5)], stroke: nil, fill: sc), nil)
                secBubble(P(m, sy - 23))
            }
        }
        if !pvMode {
            for (t, x, y) in labels { let s = t.hasPrefix("ลาด"); text(t, x, y, s ? 13 : 11, bold: !s, bg: true) }
        }
        text("สันหลังคา", hor ? x0 + W + 34 : x0 + W / 2, hor ? y0 + H / 2 : y0 - 30, 13, bold: true, bg: true)

        // the chosen member's lines in red, over everything
        if let n = highlight, !pvMode {
            let keys = Set(Self.highlightKeys(frame, member: n))
            for (op, t) in zip(o, tg) {
                guard let t, keys.contains(t) else { continue }
                switch op {
                case let .line(a, b, w, _, dash): o.append(.line(a, b, width: w + 1.6, color: Self.red, dash: dash))
                case let .rect(b, _, fill, w): o.append(fill != nil ? .rect(b, stroke: nil, fill: Self.red) : .rect(b, stroke: Self.red, fill: nil, width: w + 1.5))
                default: continue
                }
                tg.append(nil)
            }
        }

        sketch = Sketch(width: Self.width, height: Self.height, ops: o)
        tags = tg
        layout = L
        self.pv = pv
    }

    /// The PV preview count alone (tests, hints).
    public static func pvCount(_ v: Values, portrait: Bool = true, module: Module = .catalogDefault) -> Int {
        RoofPlan(v, mode: .pv, portrait: portrait, module: module).pv.count
    }
}
