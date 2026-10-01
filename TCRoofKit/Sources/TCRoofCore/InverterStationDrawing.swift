import Foundation

/// Dimensioned plan of a B2 inverter station, outdoor (covered station with columns) or indoor (wall-mounted),
/// with the section through the AC cable ladder. Drawn in a 1470 × 752 frame as on the canvas page `iPadB2`;
/// the same sketch goes to the page, the PDF and the Excel picture. Symbols follow `docs/ui/survey-b2/icons/svg/b2-*.svg`.
public enum InverterStationDrawing {
    public static let size = (w: 1470.0, h: 752.0)
    static let ink = RGBA(hex: 0x111111), warn = RGBA(hex: 0xD9453B)

    /// Layers in the design's paint order; each draws with one style.
    private struct Layers {
        var wall: [DrawOp] = [], white: [DrawOp] = [], over: [DrawOp] = [], door: [DrawOp] = [], arc: [DrawOp] = []
        var post: [DrawOp] = [], box: [DrawOp] = [], thin: [DrawOp] = [], tick: [DrawOp] = [], bub: [DrawOp] = []
        var core: [DrawOp] = [], hatch: [DrawOp] = [], text: [DrawOp] = []
        var all: [DrawOp] { wall + white + over + door + arc + post + box + thin + tick + bub + core + hatch + text }

        /// Dash-dot line: available area and walls.
        mutating func wall(_ a: Pt, _ b: Pt) { wall.append(.line(a, b, width: 1, color: ink, dash: [22, 5, 3, 5])) }
        mutating func thin(_ a: Pt, _ b: Pt) { thin.append(.line(a, b, width: 1, color: ink)) }
        mutating func thinRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { thin.append(.rect(Box(x, y, w, h), stroke: ink, fill: nil, width: 1)) }
        mutating func boxRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { box.append(.rect(Box(x, y, w, h), stroke: ink, fill: .white, width: 1.2)) }
        mutating func postRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { post.append(.rect(Box(x, y, w, h), stroke: ink, fill: .white, width: 1)) }
        /// 45° tick of a dimension end.
        mutating func tick(_ x: Double, _ y: Double) { tick.append(.line(Pt(x - 5, y + 5), Pt(x + 5, y - 5), width: 1.4, color: ink)) }
        /// Text whose baseline sits at `y` (as in the design); rotated text reads bottom to top, left of `x`.
        mutating func text(_ x: Double, _ y: Double, _ t: String, _ fs: Double = 20, align: TextAlign = .center, angle: Double = 0, bold: Bool = false, color: RGBA = ink) {
            let at = angle == 0 ? Pt(x, y - fs * 0.35) : Pt(x - fs * 0.35, y)
            text.append(.text(t, at: at, size: fs, bold: bold, color: color, align: align, angle: angle))
        }
        mutating func hdim(_ x1: Double, _ x2: Double, _ y: Double, _ label: String, color: RGBA = ink, fs: Double = 20) {
            thin(Pt(x1, y), Pt(x2, y)); tick(x1, y); tick(x2, y); text((x1 + x2) / 2, y - 7, label, fs, color: color)
        }
        mutating func vdim(_ x: Double, _ y1: Double, _ y2: Double, _ label: String, color: RGBA = ink) {
            thin(Pt(x, y1), Pt(x, y2)); tick(x, y1); tick(x, y2); text(x - 8, (y1 + y2) / 2, label, 20, angle: -90, color: color)
        }
        /// Red dashed area past the available length.
        mutating func overflow(_ r: Box, label: String, at: Pt) {
            over.append(.rect(r, stroke: nil, fill: RGBA(217 / 255, 69 / 255, 59 / 255, 0.10)))
            let c = [Pt(r.x, r.y), Pt(r.maxX, r.y), Pt(r.maxX, r.maxY), Pt(r.x, r.maxY)]
            for i in 0..<4 { over.append(.line(c[i], c[(i + 1) % 4], width: 2, color: warn, dash: [8, 5])) }
            text(at.x, at.y, label, 22, bold: true, color: warn)
        }
        /// Equipment box: cabinets labelled SOLAR / name; inverters split 55 % / 35 % with a base line and the model.
        mutating func equipment(_ it: InverterStation.Item, x: Double, y: Double, k: Double, model: String?) {
            let w = it.w * k, h = it.d * k
            if it.kind == .inverter {
                boxRect(x, y, w, h * 0.55); boxRect(x, y + h * 0.55, w, h * 0.35)
                box.append(.line(Pt(x, y + h * 0.9 + 4), Pt(x + w, y + h * 0.9 + 4), width: 1.2, color: ink))
                if let model { text(x + w / 2, y + h * 0.55 + 14, model, 11, bold: true) }
                text(x + w / 2, y + h + 20, it.name, 17)
            } else {
                boxRect(x, y, w, h); text(x + w / 2, y + 22, "SOLAR", 17); text(x + w / 2, y + 40, it.name, 15)
            }
        }
        /// Chain of every width and gap under the row.
        mutating func chain(_ pts: [(Double, Double, Double)], y: Double, fs: Double) {
            guard let first = pts.first, let last = pts.last else { return }
            thin(Pt(first.0, y), Pt(last.1, y))
            for (a, b, v) in pts { thin(Pt(a, y - 10), Pt(a, y + 10)); text((a + b) / 2, y + 22, String(format: "%.2f", v), fs) }
            thin(Pt(last.1, y - 10), Pt(last.1, y + 10))
        }
    }

    public static func sketch(_ s: InverterStation) -> Sketch {
        var p = Layers()
        if s.site == .outdoor { outdoor(s, &p) } else { indoor(s, &p) }
        // the design's view box starts at y = 8
        let ops = Sketch(width: size.w, height: size.h, ops: p.all).translated(0, -8)
        return Sketch(width: size.w, height: size.h, ops: [.rect(Box(0, 0, size.w, size.h), stroke: nil, fill: .white)] + ops)
    }

    /// Model label of an inverter item.
    static func model(_ s: InverterStation, _ it: InverterStation.Item, brand: Bool) -> String? {
        guard let kw = it.kw else { return nil }
        let inv = s.catalog.inverter(kw: kw)
        return brand && !inv.brand.isEmpty ? inv.brand.uppercased() + " " + inv.model : inv.model
    }

    private static func outdoor(_ s: InverterStation, _ p: inout Layers) {
        let L = s.planLength, W = s.planWidth, need = s.minLength, Ld = max(L, need)
        let (items, gaps) = s.row
        let S = min(150, 1330 / Ld), OX = 70.0, OY = 175.0
        func X(_ m: Double) -> Double { ((OX + m * S) * 10).rounded() / 10 }
        func Y(_ m: Double) -> Double { ((OY + m * S) * 10).rounded() / 10 }
        let spans = s.planSpans
        var gx = [0.0]; for sp in spans { gx.append(gx[gx.count - 1] + sp) }
        // grid bubbles, overall and span dimensions
        for (i, g) in gx.enumerated() {
            let x = X(g)
            p.bub.append(.circle(Pt(x, 34), r: 20, stroke: ink, fill: .white, width: 1.4))
            p.text(x, 43, String(i + 1), 22); p.thin(Pt(x, 51), Pt(x, 70))
        }
        p.hdim(X(0), X(L), 92, String(format: "%.2f", L))
        for i in 1..<gx.count { p.hdim(X(gx[i - 1]), X(gx[i]), 120, String(format: "%.2f", gx[i] - gx[i - 1])) }
        p.thin(Pt(X(0), 70), Pt(X(0), Y(0) - 12)); p.thin(Pt(X(L), 70), Pt(X(L), Y(0) - 12))
        // double walls
        for yy in [0, W] { p.wall(Pt(X(0), Y(yy) - 2), Pt(X(L), Y(yy) - 2)); p.wall(Pt(X(0), Y(yy) + 2), Pt(X(L), Y(yy) + 2)) }
        for xx in [0, L] { p.wall(Pt(X(xx) - 2, Y(0)), Pt(X(xx) - 2, Y(W))); p.wall(Pt(X(xx) + 2, Y(0)), Pt(X(xx) + 2, Y(W))) }
        // door 1.30 m with its swing
        let door = 1.30, dr = door * S
        p.white.append(.rect(Box(X(0) + 12, Y(W) - 6, dr - 18, 12), stroke: nil, fill: .white))
        p.door.append(.line(Pt(X(0), Y(W)), Pt(X(0), Y(W) + dr), width: 3, color: ink))
        p.thin(Pt(X(0) + 5, Y(W)), Pt(X(0) + 5, Y(W) + dr))
        p.arc += arc(center: Pt(X(0) + 5, Y(W)), r: dr, from: .pi / 2, to: 0)
        // columns
        for g in gx { for yy in [0, W] {
            let x = X(g), y = Y(yy)
            p.postRect(x - 11, y - 11, 22, 22); p.thinRect(x - 6, y - 6, 12, 12)
        } }
        // frame and tray band
        let tw = Double(s.trayWidth) / 1000, bandH = s.bandDepth
        let r0 = InverterStation.bandX, r1 = r0 + s.bandLength, ry0 = InverterStation.bandY, ry1 = ry0 + bandH, ty0 = ry0 + (bandH - tw) / 2
        p.boxRect(X(r0), Y(ry0), (r1 - r0) * S, (ry1 - ry0) * S); p.thinRect(X(r0) + 6, Y(ry0) + 6, (r1 - r0) * S - 12, (ry1 - ry0) * S - 12)
        let np = max(3, Int(((r1 - r0) / 1.2).rounded()) + 1)
        for i in 0..<np {
            let px = X(r0 + 0.05 + Double(i) * (r1 - r0 - 0.1) / Double(np - 1))
            for yy in [ry0, ry1] { framePost(&p, px, Y(yy), w: 18) }
        }
        p.thinRect(X(r0 + 0.5), Y(ty0), (r1 - r0 - 0.9) * S, tw * S)
        let tLab = "AC PERFORATED TRAY \(s.trayWidth)x100 WITH COVER"
        if tw >= 0.2 { p.text(X(r0 + (r1 - r0) * 0.5), Y(ty0 + tw / 2) + 6, tLab, 17) } else { p.text(X(r0 + (r1 - r0) * 0.5), Y(ty0) - 5, tLab, 15) }
        p.vdim(X(r0) - 30, Y(ry0), Y(ry1), String(format: "%.2f", bandH))
        p.thin(Pt(X(r0) - 38, Y(ry0)), Pt(X(r0), Y(ry0))); p.thin(Pt(X(r0) - 38, Y(ry1)), Pt(X(r0), Y(ry1)))
        // equipment directly below the band
        var x = r0 + 0.10
        var pts: [(Double, Double, Double)] = []
        for (i, it) in items.enumerated() {
            p.equipment(it, x: X(x), y: Y(ry1), k: S, model: model(s, it, brand: false))
            pts.append((X(x), X(x + it.w), it.w))
            if i < gaps.count { pts.append((X(x + it.w), X(x + it.w + gaps[i]), gaps[i])) }
            x += it.w + (i < gaps.count ? gaps[i] : 0)
        }
        p.chain(pts, y: Y(1.45), fs: 20)
        // walkway and room width
        let walk = s.walkway
        if walk > 0.05 { p.vdim(X(r0 + 0.10) + 14, Y(ry1 + 0.45), Y(W), String(format: "%.2f", walk), color: s.walkwayOK ? ink : warn) }
        p.thin(Pt(X(0) - 52, Y(0)), Pt(X(0) - 8, Y(0))); p.thin(Pt(X(0) - 52, Y(W)), Pt(X(0) - 8, Y(W)))
        p.vdim(X(0) - 46, Y(0), Y(W), String(format: "%.2f", W))
        let over = need - L
        if over > 0.001 { p.overflow(Box(X(L), Y(0), (Ld - L) * S, W * S), label: "เกินพื้นที่ \(String(format: "%.2f", over)) ม.", at: Pt(X((L + Ld) / 2), Y(W) + 34)) }
        ladder(s, &p, cx: 1085, yTop: Y(W) + (over > 0.001 ? 48 : 22))
    }

    private static func indoor(_ s: InverterStation, _ p: inout Layers) {
        let L = s.planLength, W = s.planWidth, need = s.minLength, Ld = max(L, need)
        let (items, gaps) = s.row, used = s.used
        let S = min(150, 1330 / Ld), OX = 70.0, OY = 130.0
        func X(_ m: Double) -> Double { ((OX + m * S) * 10).rounded() / 10 }
        func Y(_ m: Double) -> Double { ((OY + m * S) * 10).rounded() / 10 }
        // existing wall, hatched, along the top
        p.boxRect(X(0), Y(-0.12), L * S, 0.12 * S)
        var m = 0.04
        while m < L { p.hatch.append(.line(Pt(X(m), Y(-0.12) + 1), Pt(X(m), Y(0) - 1), width: 0.8, color: ink)); m += 0.08 }
        p.text(X(0), Y(-0.12) - 8, "EXISTING WALL", 15, align: .left)
        // available area and its dimensions
        p.wall(Pt(X(0), Y(0)), Pt(X(0), Y(W))); p.wall(Pt(X(0), Y(W)), Pt(X(L), Y(W))); p.wall(Pt(X(L), Y(W)), Pt(X(L), Y(0)))
        p.hdim(X(0), X(L), Y(-0.12) - 34, String(format: "%.2f", L) + " (ความยาวผนังที่ใช้ได้)", fs: 18)
        p.thin(Pt(X(0) - 52, Y(0)), Pt(X(0) - 8, Y(0))); p.thin(Pt(X(0) - 52, Y(W)), Pt(X(0) - 8, Y(W)))
        p.vdim(X(0) - 46, Y(0), Y(W), String(format: "%.2f", W))
        // steel frame 0.20 deep, 0.05–0.25 off the wall, AC tray inside
        let f0 = 0.30, f1 = f0 + used, fy0 = 0.05, fy1 = 0.25
        p.boxRect(X(f0 - 0.05), Y(fy0), (used + 0.10) * S, (fy1 - fy0) * S)
        let tw = min(0.14, Double(s.trayWidth) / 1000)
        p.thinRect(X(f0 + 0.45), Y(0.15 - tw / 2), (used - 0.45) * S, tw * S)
        p.text(X(f0 + used * 0.55), Y(0.15) + 6, "AC PERFORATED TRAY \(s.trayWidth)x100 WITH COVER", 13)
        p.vdim(X(f0 - 0.05) - 18, Y(fy0), Y(fy1), "0.20")
        // posts at the gaps between groups
        var posts = [f0 - 0.05]
        var x = f0
        for (i, it) in items.enumerated() {
            x += it.w
            if i < gaps.count { if it.kind != .inverter { posts.append(x + gaps[i] / 2) }; x += gaps[i] }
        }
        posts.append(f1 + 0.05)
        for px in posts { for yy in [fy0, fy1] { framePost(&p, X(px), Y(yy), w: 16) } }
        // equipment
        x = f0
        let ey = fy1 + 0.03
        var pts: [(Double, Double, Double)] = []
        var maxD = 0.0
        for (i, it) in items.enumerated() {
            maxD = max(maxD, it.d)
            p.equipment(it, x: X(x), y: Y(ey), k: S, model: model(s, it, brand: true))
            pts.append((X(x), X(x + it.w), it.w))
            if i < gaps.count { pts.append((X(x + it.w), X(x + it.w + gaps[i]), gaps[i])) }
            x += it.w + (i < gaps.count ? gaps[i] : 0)
        }
        // ladder riser from AC-DB-01
        let lx = X(f0 + 0.45)
        p.boxRect(lx - 10, Y(0.02), 20, (fy1 - 0.02) * S)
        var yy = 0.06
        while yy < fy1 { p.thin(Pt(lx - 10, Y(yy)), Pt(lx + 10, Y(yy))); yy += 0.06 }
        p.thin(Pt(lx + 10, Y(0.1)), Pt(X(f0 + 1.3), Y(-0.12) - 60))
        p.text(X(f0 + 1.3) + 6, Y(-0.12) - 62, "TO INJECTION POINT · AC CABLE LADDER \(s.ladderWidth)x100 (NON COVER)", 14, align: .left)
        p.chain(pts, y: Y(ey + maxD) + 60, fs: 18)
        // equipment depth 0.85 and the walkway
        let depth = 0.85, walk = s.walkway, cx2 = X(f1) + 40
        p.vdim(cx2, Y(0), Y(depth), "0.85"); p.thin(Pt(X(f1) + 20, Y(depth)), Pt(cx2 + 8, Y(depth)))
        if walk > 0.05 { p.vdim(cx2, Y(depth), Y(W), String(format: "%.2f", walk), color: s.walkwayOK ? ink : warn) }
        let over = need - L
        if over > 0.001 { p.overflow(Box(X(L), Y(0), (Ld - L) * S, W * S), label: "เกินพื้นที่ \(String(format: "%.2f", over)) ม.", at: Pt(X((L + Ld) / 2), Y(W) + 34)) }
        ladder(s, &p, cx: 1085, yTop: Y(W) + (over > 0.001 ? 48 : 22))
    }

    /// Steel frame post (b2-frame-post): box with two inner verticals.
    private static func framePost(_ p: inout Layers, _ x: Double, _ y: Double, w: Double) {
        let inner = w == 18 ? 4.0 : 3.0
        p.postRect(x - w / 2, y - 7, w, 14)
        p.thin(Pt(x - inner, y - 7), Pt(x - inner, y + 7)); p.thin(Pt(x + inner, y - 7), Pt(x + inner, y + 7))
    }

    /// Dashed swing arc as short straight pieces, one dash period each so the dashes run on.
    static func arc(center c: Pt, r: Double, from a0: Double, to a1: Double) -> [DrawOp] {
        let n = max(4, Int((abs(a1 - a0) * r / 20).rounded()))
        return (0..<n).map { i in
            let t0 = a0 + (a1 - a0) * Double(i) / Double(n), t1 = a0 + (a1 - a0) * Double(i + 1) / Double(n)
            return .line(Pt(c.x + r * cos(t0), c.y + r * sin(t0)), Pt(c.x + r * cos(t1), c.y + r * sin(t1)), width: 1, color: ink, dash: [12, 8])
        }
    }

    /// Section through the AC cable ladder leaving AC-DB-01 (b2-cable-ladder-section), bottom right; skipped below 35 % scale.
    private static func ladder(_ s: InverterStation, _ p: inout Layers, cx: Double, yTop: Double) {
        let fd = s.feeder, lw = Double(s.ladderWidth)
        let y0 = yTop + 18, k = min(1.1, 460 / lw, (748 - y0 - 72) / 100)
        guard k >= 0.35 else { return }
        let Wp = lw * k, Hp = 100 * k, x0 = cx - Wp / 2, yb = y0 + 44 + Hp
        p.text(cx, y0, "รูปตัดราง AC ออกจาก SOLAR AC-DB-01", 17, bold: true)
        for d in [0.0, 3.0] {
            p.thin(Pt(x0 - d, y0 + 44), Pt(x0 - d, yb + d)); p.thin(Pt(x0 - d, yb + d), Pt(x0 + Wp + d, yb + d)); p.thin(Pt(x0 + Wp + d, yb + d), Pt(x0 + Wp + d, y0 + 44))
        }
        let r = fd.diameter / 2 * k, nC = fd.runs * 4, names = ["L1", "L2", "L3", "N"]
        let span = Double(2 * nC - 1) * fd.diameter * k
        var x = cx - span / 2 + r
        for i in 0..<nC {
            let cy = yb - r - 1
            p.box.append(.circle(Pt(x, cy), r: r, stroke: ink, fill: .white, width: 1.2))
            p.core.append(.circle(Pt(x, cy), r: r * 0.5, stroke: nil, fill: ink))
            if r >= 7 { p.text(x, cy - r - 5, names[i % 4], 13) }
            if i < nC - 1, r >= 7, i < 3 {
                let dy = cy - r - 24
                p.thin(Pt(x + r, dy), Pt(x + 3 * r, dy)); p.thin(Pt(x + r, dy - 4), Pt(x + r, dy + 4)); p.thin(Pt(x + 3 * r, dy - 4), Pt(x + 3 * r, dy + 4))
                p.text(x + 2 * r, dy - 4, "D", 13)
            }
            x += 4 * r
        }
        p.text(cx, yb + 22, "CABLE LADDER \(s.ladderWidth)x100 (NON COVER) · \(fd.label) · เว้นระยะ D = Ø สาย", 14)
    }
}
