import Foundation

/// The C1 roof plan (docs/ui/survey-c1 `renderVals`, `P.*`): grid and dimension chains, ridge, frame lines, purlins,
/// posts, slope arrows, section mark A-A, skylights and obstacles, and the PV layout preview. The sketch is 580 × 446
/// (the design's viewBox moved to the origin); the page draws it and lays its buttons over the points in `Layout`.
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
    public var layout: Layout
    public var pv: PV

    static let navy = RGBA(hex: 0x16325C), gridC = RGBA(hex: 0x8A97AA), ink = RGBA(hex: 0x111111), purlC = RGBA(hex: 0x6B7280)
    static let red = RGBA(hex: 0xD9453B), skyFill = RGBA(hex: 0xCFE8F7), skyLine = RGBA(hex: 0x2E8FDB), pvFill = RGBA(hex: 0x1F4F8F)
    static let pvLine = RGBA(hex: 0xDCE6F2), redText = RGBA(hex: 0xB42318)

    /// - Parameters:
    ///   - chips: false draws the span values as text (report); true leaves them to the page's buttons.
    ///   - keepOut: an unfinished keep-out zone being dragged (metres, two corners).
    public init(_ v: Values, mode: Mode = .structure, portrait: Bool? = nil, module: Module = .catalogDefault,
                chips: Bool = false, dragging: (Double, Double, Double, Double)? = nil) {
        let xs = Roof.spans(v, .x), ys = Roof.spans(v, .y), frame = Roof.frame(v), ridge = Roof.ridge(v)
        let portrait = portrait ?? (v.text(Roof.Key.pvOrientation) != "l")
        var o: [DrawOp] = [], L = Layout(), pv = PV()
        // design viewBox origin (100, -6)
        func P(_ x: Double, _ y: Double) -> Pt { Pt(x - 100, y + 6) }
        func line(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ w: Double, _ col: RGBA, dash: [Double] = []) {
            o.append(.line(P(a, b), P(c, d), width: w, color: col, dash: dash))
        }
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Box { let p = P(x, y); return Box(p.x, p.y, w, h) }
        func text(_ t: String, _ x: Double, _ y: Double, _ size: Double, bold: Bool = false, color: RGBA = RoofPlan.navy, bg: Bool = false, angle: Double = 0) {
            let p = P(x, y)
            if bg {
                let w = ApproxText.width(t, size: size, bold: bold) + 6, h = size + 3
                o.append(.rect(angle == 0 ? Box(p.x - w / 2, p.y - h / 2, w, h) : Box(p.x - h / 2, p.y - w / 2, h, w), stroke: nil, fill: .white))
            }
            o.append(.text(t, at: p, size: size, bold: bold, color: color, align: .center, angle: angle))
        }
        func dashedBox(_ b: Box, _ col: RGBA, _ w: Double, _ dash: [Double]) {
            let c = [Pt(b.x, b.y), Pt(b.maxX, b.y), Pt(b.maxX, b.maxY), Pt(b.x, b.maxY)]
            for i in 0..<4 { o.append(.line(c[i], c[(i + 1) % 4], width: w, color: col, dash: dash)) }
        }

        let Lx = xs.reduce(0, +), Ly = ys.reduce(0, +)
        let k = min(380 / Lx, 320 / Ly), W = Lx * k, H = Ly * k, x0 = 400 - W / 2, y0 = 252 - H / 2
        var gx = [x0]; for s in xs { gx.append(gx.last! + s * k) }
        var gy = [y0]; for s in ys { gy.append(gy.last! + s * k) }
        L.origin = P(x0, y0); L.k = k; L.lx = Lx; L.ly = Ly
        let hor = ridge == .h, ang = frame.slope, pvMode = mode == .pv
        o.append(.rect(Box(0, 0, Self.width, Self.height), stroke: nil, fill: .white))

        // purlins along the ridge every 1 m
        if !pvMode {
            var m = 0.5
            while m < (hor ? Ly : Lx) {
                if hor { line(gx[0], y0 + m * k, gx.last!, y0 + m * k, 0.5, Self.purlC) } else { line(x0 + m * k, gy[0], x0 + m * k, gy.last!, 0.5, Self.purlC) }
                m += 1
            }
        }
        let gdash: [Double] = [14, 3, 2, 3]
        for x in gx { line(x, y0 - 22, x, y0 + H + 14, 0.6, Self.gridC, dash: gdash) }
        for y in gy { line(x0 - 22, y, x0 + W + 14, y, 0.6, Self.gridC, dash: gdash) }

        // frame lines
        let AL = hor ? gx : gy, CR = hor ? gy : gx, aMin = AL.first!, aMax = AL.last!, cMin = CR.first!, cMax = CR.last!
        func across(_ a: Double, _ w: Double, dash: [Double] = []) {
            if hor { line(a, cMin, a, cMax, w, Self.ink, dash: dash) } else { line(cMin, a, cMax, a, w, Self.ink, dash: dash) }
        }
        func along(_ c: Double, _ ext: Double, _ w: Double, dash: [Double] = []) {
            if hor { line(aMin - ext, c, aMax + ext, c, w, Self.ink, dash: dash) } else { line(c, aMin - ext, c, aMax + ext, w, Self.ink, dash: dash) }
        }
        var labels: [(String, Double, Double)] = []
        func lab(_ a: Double, _ c: Double, _ t: String) { labels.append((t, hor ? a : c, hor ? c : a)) }
        let inA = Array(AL.dropFirst().dropLast()), inC = Array(CR.dropFirst().dropLast())
        if !pvMode {
            switch frame {
            case .rafterTie:
                var a = aMin + k / 2
                while a < aMax { across(a, 0.7); a += k }
                let eaves = [CR[min(1, CR.count - 1)], CR[max(0, CR.count - 2)]]
                for c in eaves { along(c, 6, 1.8) }
                lab(aMin + (aMax - aMin) * 0.3, eaves[0] - 10, "อเส"); lab(aMin + (aMax - aMin) * 0.3, eaves[1] + 12, "อเส")
                lab(aMin + (aMax - aMin) * 0.62, cMin + (cMax - cMin) * 0.3, "จันทัน @1.00")
            case .rafterTruss:
                for a in inA { across(a, 1.8); lab(a, cMin + 12, "T1") }
                for c in inC where AL.count > 2 { along(c, 6, 1.5, dash: [12, 3]); lab((AL[1] + AL[2]) / 2, c - 9, "T2") }
            default:
                for a in inA { across(a - 2.5, 1.1); across(a + 2.5, 1.1); lab(a, cMin + 12, "T1") }
            }
        }
        // posts
        let posts = Roof.posts(v)
        for (i, x) in gx.enumerated() {
            for (j, y) in gy.enumerated() {
                let on = posts.contains("\(i),\(j)")
                L.nodes.append((i, j, P(x, y), on))
                if on && !pvMode { o.append(.rect(rect(x - 5, y - 5, 10, 10), stroke: nil, fill: RGBA(hex: 0x111827))) }
            }
        }
        o.append(.rect(rect(x0, y0, W, H), stroke: Self.ink, fill: nil, width: 1.5))
        // ridge
        let rdash: [Double] = [18, 4, 3, 4]
        if hor { line(x0 - 10, y0 + H / 2, x0 + W + 10, y0 + H / 2, 1.2, Self.ink, dash: rdash) }
        else { line(x0 + W / 2, y0 - 10, x0 + W / 2, y0 + H + 10, 1.2, Self.ink, dash: rdash) }
        // grid bubbles
        for (i, x) in gx.enumerated() {
            o.append(.circle(P(x, 58), r: 9, stroke: Self.navy, fill: .white, width: 0.9)); text(Roof.gridName(.x, i), x, 58, 11, bold: true)
        }
        for (j, y) in gy.enumerated() {
            o.append(.circle(P(176, y), r: 9, stroke: Self.navy, fill: .white, width: 0.9)); text(Roof.gridName(.y, j), 176, y, 11, bold: true)
        }
        // dimension chains, 45° ticks
        func tick(_ x: Double, _ y: Double) { line(x - 4, y + 4, x + 4, y - 4, 0.9, Self.navy) }
        line(gx.first! - 6, 32, gx.last! + 6, 32, 0.8, Self.navy); line(gx.first! - 6, 10, gx.last! + 6, 10, 0.8, Self.navy)
        for (i, x) in gx.enumerated() { line(x, i == 0 || i == gx.count - 1 ? 6 : 28, x, 47, 0.8, Self.navy); tick(x, 32) }
        tick(gx.first!, 10); tick(gx.last!, 10)
        line(150, gy.first! - 6, 150, gy.last! + 6, 0.8, Self.navy); line(128, gy.first! - 6, 128, gy.last! + 6, 0.8, Self.navy)
        for (j, y) in gy.enumerated() { line(j == 0 || j == gy.count - 1 ? 124 : 146, y, 165, y, 0.8, Self.navy); tick(150, y) }
        tick(128, gy.first!); tick(128, gy.last!)
        text(String(format: "%.2f", Lx), 400, 4, 13, bold: true, bg: true)
        text(String(format: "%.2f", Ly), 118, 252, 13, bold: true, bg: true, angle: -90)
        for (i, s) in xs.enumerated() {
            let c = P((gx[i] + gx[i + 1]) / 2, 21)
            L.chips.append(Chip(axis: .x, index: i, value: s, at: c))
            if !chips { text(fmt(s), (gx[i] + gx[i + 1]) / 2, 21, 12) }
        }
        for (j, s) in ys.enumerated() {
            let c = P(139, (gy[j] + gy[j + 1]) / 2)
            L.chips.append(Chip(axis: .y, index: j, value: s, at: c))
            if !chips { text(fmt(s), 139, (gy[j] + gy[j + 1]) / 2, 12, angle: -90) }
        }
        L.addX = P(gx.last! + 22, 21); L.addY = P(139, gy.last! + 22)

        // slope arrows
        if !pvMode {
            func head(_ tip: Pt, _ dx: Double, _ dy: Double) {
                // a 10-wide, 10-long triangle pointing from (tip - d) to tip
                let b = Pt(tip.x - dx * 10, tip.y - dy * 10), n = Pt(-dy * 5, dx * 5)
                o.append(.polygon([tip, Pt(b.x + n.x, b.y + n.y), Pt(b.x - n.x, b.y - n.y)], stroke: nil, fill: Self.navy))
            }
            let slope = "ลาด \(fmt(ang))°"
            if hor {
                for x in [x0 + W * 0.18, x0 + W * 0.82] {
                    let m = y0 + H / 2
                    line(x, m - 12, x, y0 + 30, 1.2, Self.navy); head(P(x, y0 + 22), 0, -1)
                    line(x, m + 12, x, y0 + H - 30, 1.2, Self.navy); head(P(x, y0 + H - 22), 0, 1)
                    labels.append((slope, x, m - 36)); labels.append((slope, x, m + 36))
                }
            } else {
                for y in [y0 + H * 0.2, y0 + H * 0.8] {
                    let m = x0 + W / 2
                    line(m - 12, y, x0 + 30, y, 1.2, Self.navy); head(P(x0 + 22, y), -1, 0)
                    line(m + 12, y, x0 + W - 30, y, 1.2, Self.navy); head(P(x0 + W - 22, y), 1, 0)
                    labels.append((slope, m - 44, y - 12)); labels.append((slope, m + 44, y - 12))
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
                o.append(.rect(b, stroke: nil, fill: Self.skyFill))
                if a.canCover { o.append(.rect(b, stroke: Self.skyLine, fill: nil, width: 1)) } else { dashedBox(b, Self.red, 1.2, [4, 2]) }
            case Roof.keepOutKind:
                o.append(.rect(b, stroke: nil, fill: RGBA(0.851, 0.271, 0.231, 0.10))); o.append(.hatch(b, color: Self.red, spacing: 7))
                o.append(.rect(b, stroke: Self.red, fill: nil, width: 1.4))
            default:
                o.append(.rect(b, stroke: nil, fill: .white)); o.append(.hatch(b, color: Self.red)); o.append(.rect(b, stroke: Self.red, fill: nil, width: 1))
            }
        }

        // PV layout: rows down each face from the eave, columns along the ridge
        if pvMode {
            let La = hor ? Lx : Ly, Lc = hor ? Ly : Lx, cs = cos(ang * .pi / 180), gp = 0.02, seE = 0.5, seR = 0.3, seG = 0.5
            let msl = portrait ? module.length : module.width, mwd = portrait ? module.width : module.length
            let us = (Lc / 2) / cs - seE - seR
            let rows = max(0, Int(floor((us + gp) / (msl + gp)))), cols = max(0, Int(floor((La - 2 * seG + gp) / (mwd + gp))))
            let off = (La - (Double(cols) * (mwd + gp) - gp)) / 2
            // blocked areas as (a1, a2, c1, c2) along / across the ridge
            var obs: [(Double, Double, Double, Double)] = []
            for a in areas where !(a.kind == Roof.skylightKind && a.canCover) {
                let e = a.kind == Roof.skylightKind ? 0.1 : 0
                obs.append(hor ? (a.x - e, a.x + a.w + e, a.y, a.y + a.h) : (a.y - e, a.y + a.h + e, a.x, a.x + a.w))
            }
            for face in 0..<2 {
                for r in 0..<rows {
                    for c in 0..<cols {
                        let a1 = off + Double(c) * (mwd + gp), a2 = a1 + mwd, s1 = seE + Double(r) * (msl + gp), s2 = s1 + msl
                        var c1 = s1 * cs, c3 = s2 * cs
                        if face == 1 { (c1, c3) = (Lc - c3, Lc - c1) }
                        let hit = obs.contains { a2 > $0.0 && a1 < $0.1 && c3 > $0.2 && c1 < $0.3 }
                        let b = hor ? Box(L.origin.x + a1 * k, L.origin.y + c1 * k, (a2 - a1) * k, (c3 - c1) * k)
                                    : Box(L.origin.x + c1 * k, L.origin.y + a1 * k, (c3 - c1) * k, (a2 - a1) * k)
                        if hit { pv.blocked.append(b) } else { pv.placed.append(b) }
                    }
                }
            }
            for b in pv.placed { o.append(.rect(b, stroke: Self.pvLine, fill: RGBA(0.122, 0.31, 0.561, 0.85), width: 0.6)) }
            for b in pv.blocked { dashedBox(b, Self.pvFill, 0.6, [3, 2]) }
            pv.count = pv.placed.count
            pv.kWp = Double(pv.count) * module.kW
            if let d = dragging {
                let b = Box(L.origin.x + min(d.0, d.2) * k, L.origin.y + min(d.1, d.3) * k, abs(d.2 - d.0) * k, abs(d.3 - d.1) * k)
                o.append(.rect(b, stroke: nil, fill: RGBA(0.851, 0.271, 0.231, 0.12))); dashedBox(b, Self.red, 1.4, [5, 3])
            }
            for (a, b) in L.areas where a.kind == Roof.keepOutKind {
                let t = "ห้ามติด " + String(format: "%.1f×%.1f", a.w, a.h)
                let c = Pt(b.x + b.w / 2, b.y + b.h / 2), w = ApproxText.width(t, size: 10.5, bold: true) + 6
                o.append(.rect(Box(c.x - w / 2, c.y - 7, w, 14), stroke: nil, fill: RGBA(1, 1, 1, 0.85)))
                o.append(.text(t, at: c, size: 10.5, bold: true, color: Self.redText, align: .center))
            }
        } else if let d = dragging {
            let b = Box(L.origin.x + min(d.0, d.2) * k, L.origin.y + min(d.1, d.3) * k, abs(d.2 - d.0) * k, abs(d.3 - d.1) * k)
            o.append(.rect(b, stroke: nil, fill: Self.skyFill)); dashedBox(b, Self.skyLine, 1.2, [5, 3])
        }
        // obstacle labels as on the old plan
        for (a, b) in L.areas where a.kind == "" && !a.label.isEmpty {
            o.append(.text("\(a.label) \(fmt(a.w))x\(fmt(a.h))", at: Pt(b.maxX + 3, b.maxY - 3), size: 8, color: .dark))
        }

        // section mark A-A
        func secBubble(_ c: Pt) {
            o.append(.circle(c, r: 9, stroke: RGBA(hex: 0x111827), fill: .white, width: 1.4))
            o.append(.text("A", at: c, size: 12, bold: true, color: RGBA(hex: 0x111827), align: .center))
        }
        let sdash: [Double] = [16, 4, 3, 4], sc = RGBA(hex: 0x111827)
        if hor {
            let sx = x0 + W * 0.42
            line(sx, y0 - 2, sx, y0 + H + 2, 0.9, sc, dash: sdash)
            for (a, b) in [(y0 - 17, y0 - 2), (y0 + H + 2, y0 + H + 17)] {
                line(sx, a, sx, b, 3, sc); let m = (a + b) / 2
                o.append(.polygon([P(sx - 1.5, m - 6), P(sx - 14, m), P(sx - 1.5, m + 6)], stroke: nil, fill: sc))
                secBubble(P(sx - 23, m))
            }
        } else {
            let sy = y0 + H * 0.42
            line(x0 - 2, sy, x0 + W + 2, sy, 0.9, sc, dash: sdash)
            for (a, b) in [(x0 - 17, x0 - 2), (x0 + W + 2, x0 + W + 17)] {
                line(a, sy, b, sy, 3, sc); let m = (a + b) / 2
                o.append(.polygon([P(m - 6, sy - 1.5), P(m, sy - 14), P(m + 6, sy - 1.5)], stroke: nil, fill: sc))
                secBubble(P(m, sy - 23))
            }
        }
        if !pvMode { for (t, x, y) in labels { text(t, x, y, t.hasPrefix("ลาด") ? 11 : 10.5, bold: !t.hasPrefix("ลาด"), bg: true) } }
        text("สันหลังคา", hor ? x0 + W + 34 : x0 + W / 2, hor ? y0 + H / 2 : y0 - 30, 12, bold: true, bg: true)

        sketch = Sketch(width: Self.width, height: Self.height, ops: o)
        layout = L
        self.pv = pv
    }

    /// The PV preview count alone (tests, hints).
    public static func pvCount(_ v: Values, portrait: Bool = true, module: Module = .catalogDefault) -> Int {
        RoofPlan(v, mode: .pv, portrait: portrait, module: module).pv.count
    }
}
