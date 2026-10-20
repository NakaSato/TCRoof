import Foundation

/// C1 section A-A (docs/ui/survey-c1 `renderVals`, `S.*`): a true-scale cut across the ridge for the six frame types,
/// with dimensions and the callouts ①–⑦ of the member rows. The sketch is the design's 760 × 250 viewBox.
/// `tags` names each op's CAD layer (`SECTION`, `DIM`, `GRID`; nil for fills, labels and the light core strokes).
public struct RoofSection: Sendable {
    public static let width = 760.0, height = 250.0

    public var sketch: Sketch
    public var tags: [String?]
    /// Where the eave overhang, clear-height and rise labels sit (the page makes them tappable).
    public var overhangLabel = Pt(0, 0), clearLabel = Pt(0, 0), riseLabel = Pt(0, 0)
    /// The numbered callouts' bubble centres (rows a frame doesn't draw are missing).
    public var callouts: [Int: Pt] = [:]
    public let span, half, rise: Double
    public let bays: Int
    /// Sketch points per metre.
    public let scale: Double

    static let dark = RGBA(hex: 0x1A1D22), core = RGBA(hex: 0xD5DBE3), webCore = RGBA(hex: 0xF2F4F7), navy = RGBA(hex: 0x16325C)
    static let sheet = RGBA(hex: 0x1F4F78), red = RGBA(hex: 0xD9453B), blue = RGBA(hex: 0x1F6FB5), gridC = RGBA(hex: 0x8A97AA)
    static let concrete = RGBA(hex: 0xC9CED6)

    /// - Parameter highlight: member row 1…7 whose callout is filled red.
    public init(_ v: Values, highlight: Int? = nil) {
        let f = Roof.frame(v), ridge = Roof.ridge(v)
        let span = Roof.span(v), half = span / 2, nH = Roof.bays(v)
        let ang = Roof.slope(v), tn = tan(ang * .pi / 180), rise = half * tn
        let isK = f == .eaveCeiling, isC = f.isRafter, isR = f == .rafterTruss, heelM = f.heel
        let sc = min(540 / span, 118 / (rise + heelM)), HW = half * sc, XL = 380 - HW, XR = 380 + HW, YB = 150.0
        let heel = heelM * sc, YE = YB - heel, YT = YE - rise * sc, pw = half / Double(nH)
        let overhang = Roof.overhang(v), clear = Roof.clearHeight(v)
        var o: [DrawOp] = [], tg: [String?] = []
        func add(_ op: DrawOp, _ tag: String?) { o.append(op); tg.append(tag) }
        var webs: [[Pt]] = [], chords: [[Pt]] = [], cols: [[Pt]] = []
        func pt(_ x: Double, _ y: Double) -> Pt { Pt(x, y) }
        func line(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ w: Double, _ col: RGBA, dash: [Double] = [], _ tag: String? = "SECTION") {
            add(.line(Pt(a, b), Pt(c, d), width: w, color: col, dash: dash), tag)
        }
        func text(_ t: String, _ x: Double, _ y: Double, _ size: Double = 12, bold: Bool = false, color: RGBA = RoofSection.navy, align: TextAlign = .left) {
            // the design's y is the baseline; DrawOp text is anchored at the line's middle
            add(.text(t, at: Pt(x, y - size * 0.35), size: size, bold: bold, color: color, align: align), nil)
        }
        func path(_ d: String, width: Double, color: RGBA = RoofSection.dark, fill: RGBA? = nil, _ tag: String? = "SECTION") {
            for sub in PathD.parse(d) {
                if let fill, sub.closed { add(.polygon(sub.points, stroke: color, fill: fill, width: width), tag) }
                else { add(.polyline(sub.closed ? sub.points + [sub.points[0]] : sub.points, width: width, color: color), tag) }
            }
        }
        func g(_ x: Double) -> String { String(format: "%.1f", x) }
        func topY(_ x: Double) -> Double { x <= 380 ? YE - (x - XL) / HW * (YE - YT) : YE - (XR - x) / HW * (YE - YT) }
        let ov = overhang * sc, rOff = 7.0, slope = (YE - YT) / HW
        var pts: [Double] = []
        if !isC { for i in 1..<(2 * nH) { pts.append(XL + Double(i) * pw * sc) } }

        add(.rect(Box(0, 0, Self.width, Self.height), stroke: nil, fill: .white), nil)
        let gdash: [Double] = [12, 3, 2, 3]
        line(XL, 24, XL, 240, 0.6, Self.gridC, dash: gdash, "GRID"); line(XR, 24, XR, 240, 0.6, Self.gridC, dash: gdash, "GRID")
        line(380, 24, 380, YB, 0.6, Self.gridC, dash: gdash, "GRID")
        let gA = ridge == .h ? "A" : "1"
        let gB = ridge == .h ? Roof.gridName(.y, Roof.spans(v, .y).count) : Roof.gridName(.x, Roof.spans(v, .x).count)
        for (x, t) in [(XL, gA), (XR, gB)] {
            add(.circle(Pt(x, 14), r: 9, stroke: Self.navy, fill: .white, width: 1), "GRID")
            add(.text(t, at: Pt(x, 14), size: 11, bold: true, color: Self.navy, align: .center), nil)
        }

        // the rafter frames' outlines (the owner's ST1 / Type 1 drawings), kept for the callouts
        struct Rafter { var dv = 0.0, hp = 0.0, yc = 0.0, dc = 0.0, w = 0.0, pj = 0.0, yB1 = 0.0, eL = 0.0
            var wc = 0.0, yb1 = 0.0, yb2 = 0.0, bw = 0.0, fx = 0.0 }
        var G = Rafter()
        var hatches: [Box] = []
        if isR {
            let d = heel, eL = XL - ov, eyL = YE + ov * slope
            func ybot(_ x: Double) -> Double { topY(x) + d }
            chords += [[pt(eL, eyL), pt(380, YT), pt(XR + ov, eyL)], [pt(eL, eyL + d), pt(380, YT + d), pt(XR + ov, eyL + d)],
                       [pt(eL, eyL), pt(eL, eyL + d)], [pt(XR + ov, eyL), pt(XR + ov, eyL + d)], [pt(380, YT), pt(380, YT + d)]]
            let nodes = [XL] + pts + [XR]
            for i in 0..<(nodes.count - 1) {
                let a = nodes[i], b = nodes[i + 1]
                if abs(b - 380) < 1 || abs(a - 380) < 1 || (a < 380) == (i % 2 == 0) { webs.append([pt(a, ybot(a)), pt(b, topY(b))]) }
                else { webs.append([pt(a, topY(a)), pt(b, ybot(b))]) }
                webs.append([pt(b, topY(b)), pt(b, ybot(b))])
            }
            let xi1 = XL + HW * 0.8, xi2 = XR - HW * 0.8
            for x in [XL, XR, xi1, xi2] { cols.append([pt(x, ybot(x)), pt(x, 190)]); hatches.append(Box(x - 6, ybot(x), 12, 6)) }
        } else if isC {
            let eL = XL - ov, eR = XR + ov, cs = 1 / hypot(1, slope), sn = slope * cs
            let dv = max(4, 0.17 * sc), hp = max(4.5, 0.1 * sc), fw = hp * 0.55, sh = (hp + 0.6) / cs, sh2 = (hp + 2.2) / cs
            func yb(_ x: Double) -> Double { topY(x) }
            func tp(_ x: Double) -> Double { yb(x) - dv }
            var L = "M\(g(eL)) \(g(yb(eL)))L380 \(g(YT))L\(g(eR)) \(g(yb(eR)))M\(g(eL)) \(g(tp(eL)))L380 \(g(YT - dv))L\(g(eR)) \(g(tp(eR)))"
            L += "M\(g(eL)) \(g(yb(eL)))V\(g(tp(eL)))M\(g(eR)) \(g(yb(eR)))V\(g(tp(eR)))"
            L += "M\(g(eL - 3)) \(g(tp(eL) - sh + 3 * slope))L380 \(g(YT - dv - sh))L\(g(eR + 3)) \(g(tp(eR) - sh + 3 * slope))"
            L += "M\(g(eL - 3)) \(g(tp(eL) - sh2 + 3 * slope))L380 \(g(YT - dv - sh2))L\(g(eR + 3)) \(g(tp(eR) - sh2 + 3 * slope))"
            if !isK { L += "M\(g(eL - 2.4)) \(g(tp(eL) - 1))h2.4v\(g(dv + 5))h-2.4zM\(g(eR)) \(g(tp(eR) - 1))h2.4v\(g(dv + 5))h-2.4z" }
            let yc = YE - (isK ? 0.55 : 0.5) * (YE - YT), dc = max(4, 0.15 * sc)
            func xl(_ y: Double) -> Double { XL + (YE - y) / slope }
            func xr(_ y: Double) -> Double { XR - (YE - y) / slope }
            L += "M\(g(xl(yc))) \(g(yc))H\(g(xr(yc)))M\(g(xl(yc + dc))) \(g(yc + dc))H\(g(xr(yc + dc)))"
            let w = max(7, 0.3 * sc), Hh = 192 - YE, hw = max(10, 0.36 * Hh), yB0 = YE + hw, yB1 = yB0 + max(4, 0.14 * Hh)
            let pj = max(8, 0.3 * sc), ys = yB1 + max(5, 0.2 * Hh)
            var Hd = ""
            G = Rafter(dv: dv, hp: hp, yc: yc, dc: dc, w: w, pj: pj, yB1: yB1, eL: eL)
            if isK {
                let wc = max(7, 0.25 * sc), yo1 = YE + max(3, 0.12 * sc), yo2 = yo1 + max(3.5, 0.15 * sc)
                let yb1 = YE + max(10, 0.45 * sc), yb2 = min(yb1 + max(6, 0.3 * sc), YE + Hh * 0.78), bw = max(6, 0.22 * sc), fx = max(3, 0.15 * sc)
                L += "M\(g(XL + wc / 2)) \(g(yb1))H\(g(XR - wc / 2))M\(g(XL + wc / 2)) \(g(yb2))H\(g(XR - wc / 2))"
                for (x, k, e) in [(XL, 1.0, eL), (XR, -1.0, eR)] {
                    let o = x - k * wc / 2, i = x + k * wc / 2, xf = e + k * fx
                    L += "M\(g(o)) \(g(yb(o)))V192M\(g(i)) \(g(yb(i)))V192"
                    L += "M\(g(x - wc / 2 - 9)) 192H\(g(x - 3))l2 -4l2 8l2 -4H\(g(x + wc / 2 + 9))"
                    Hd += "M\(g(o - k * bw * 0.6)) \(g(yb1))H\(g(o + k * bw * 0.4))V\(g(yb2))H\(g(o - k * bw * 0.6))z"
                    for y in [yo1, yo2] { L += "M\(g(x - k * (y - YE) / slope)) \(g(y))H\(g(o))" }
                    L += "M\(g(e)) \(g(yb(e)))L\(g(xf)) \(g(yb2))M\(g(e + k * 2.2)) \(g(yb(e) + 0.6))L\(g(xf + k * 2.2)) \(g(yb2 - 2.2))"
                    L += "M\(g(xf)) \(g(yb2))H\(g(o - k * bw * 0.6))M\(g(xf + k * 2.2)) \(g(yb2 - 2.2))H\(g(o - k * bw * 0.6))"
                }
                G.wc = wc; G.yb1 = yb1; G.yb2 = yb2; G.bw = bw; G.fx = fx
            } else {
                for (x, k) in [(XL, 1.0), (XR, -1.0)] {
                    let o = x - k * w / 2, i = x + k * w / 2
                    Hd += "M\(g(o)) \(g(yb(o)))L\(g(i)) \(g(yb(i)))V\(g(yB0))H\(g(o))z"
                    L += "M\(g(o)) \(g(yB0))H\(g(i + k * pj))V\(g(yB1))L\(g(i)) \(g(ys))V192M\(g(o)) \(g(yB0))V192"
                    L += "M\(g(x - w / 2 - 9)) 192H\(g(x - 3))l2 -4l2 8l2 -4H\(g(x + w / 2 + 9))"
                }
            }
            // C purlins square to the rafter, at ระยะแป along the slope
            var Pd = ""
            let kk = max(3, Int((((half + overhang) / cos(ang * .pi / 180)) / Roof.purlinSpacing(v)).rounded()))
            let px0 = eL + 0.12 * sc + fw, px1 = 380 - fw - 3
            for q in 0...kk {
                let xx = px0 + (px1 - px0) * Double(q) / Double(kk)
                for (px, ux, uy, nx, ny) in [(xx, cs, -sn, -sn, -cs), (760 - xx, -cs, -sn, sn, -cs)] {
                    let py = tp(px), bx = px + nx * hp, by = py + ny * hp
                    Pd += "M\(g(bx + ux * fw)) \(g(by + uy * fw))L\(g(bx)) \(g(by))L\(g(px)) \(g(py))L\(g(px + ux * fw)) \(g(py + uy * fw))"
                }
            }
            path(Hd, width: 1, fill: Self.concrete)
            path(L, width: 1)
            path(Pd, width: 1.5)
            path("M372 \(g(YT - dv - sh2 + 5))L380 \(g(YT - dv - sh2 - 2))L388 \(g(YT - dv - sh2 + 5))", width: 1.6, color: Self.sheet)
        } else {
            chords += [[pt(XL, YE), pt(380, YT), pt(XR, YE)], [pt(XL, YB), pt(XR, YB)], [pt(XL, YB), pt(XL, YE)], [pt(XR, YB), pt(XR, YE)]]
            cols += [[pt(XL, 150), pt(XL, 192)], [pt(XR, 150), pt(XR, 192)]]
            let nodes = [XL] + pts + [XR]
            switch f {
            case .normal:
                webs.append([pt(380, YB), pt(380, YT)])
                let q1 = XL + HW * 0.5, q2 = XR - HW * 0.5
                webs += [[pt(q1, YB), pt(q1 + HW * 0.22, topY(q1 + HW * 0.22))], [pt(q2, YB), pt(q2 - HW * 0.22, topY(q2 - HW * 0.22))]]
            case .warren:
                for i in 0..<(nodes.count - 1) {
                    let a = nodes[i], b = nodes[i + 1]
                    webs.append(i % 2 == 0 ? [pt(a, YB), pt(b, topY(b))] : [pt(a, topY(a)), pt(b, YB)])
                }
                webs.append([pt(380, YB), pt(380, YT)])
            default:
                for x in pts { webs.append([pt(x, YB), pt(x, topY(x))]) }
                for i in 1..<(nodes.count - 1) {
                    let x = nodes[i]
                    if x < 379 { webs.append([pt(x, topY(x)), pt(nodes[i + 1], YB)]) } else if x > 381 { webs.append([pt(nodes[i - 1], YB), pt(x, topY(x))]) }
                }
            }
        }
        for w in webs { add(.polyline(w, width: 3.2, color: Self.dark), "SECTION") }
        for w in webs { add(.polyline(w, width: 1.3, color: Self.webCore), nil) }
        for c in chords { add(.polyline(c, width: 6, color: Self.dark), "SECTION") }
        for c in chords { add(.polyline(c, width: 3.6, color: Self.core), nil) }
        func gusset(_ x: Double, _ y: Double, _ r: Double) {
            add(.polygon([pt(x - r, y), pt(x, y - r * 0.8), pt(x + r, y), pt(x, y + r * 0.8)], stroke: Self.dark, fill: .white, width: 0.9), "SECTION")
        }
        if !isC && !isR {
            for x in [XL, XR] { gusset(x, YB - 3, 7) }
            for x in pts { gusset(x, YB, 4.5); gusset(x, topY(x), 4.5) }
            gusset(380, YT + 2, 6)
        }
        if isR { for x in pts { gusset(x, topY(x), 3.5); gusset(x, topY(x) + heel, 3.5) } }

        // corrugated sheet along the slope, with the ridge cap (the rafter frames draw theirs as outlines)
        let eY = YE + ov * slope - rOff - (isC ? 7 : 0), rT = YT - rOff - (isC ? 7 : 0)
        if !isC {
            func wave(_ xa: Double, _ ya: Double, _ xb: Double, _ yb: Double) -> [Pt] {
                let L = hypot(xb - xa, yb - ya), n = max(2, Int((L / 5).rounded())), ux = (xb - xa) / L, uy = (yb - ya) / L, nx = -uy, ny = ux
                var p = [pt(xa, ya)]
                for q in 1...n {
                    let t = Double(q) / Double(n), a = q % 2 == 1 ? 1.6 : 0
                    p.append(pt(xa + (xb - xa) * t + nx * -a, ya + (yb - ya) * t + ny * -a))
                }
                return p
            }
            add(.polyline(wave(XL - ov, eY, 380, rT) + wave(380, rT, XR + ov, eY).dropFirst(), width: 1.1, color: Self.sheet), "SECTION")
            add(.polyline([pt(372, rT + 3), pt(380, rT - 3), pt(388, rT + 3)], width: 1.6, color: Self.sheet), "SECTION")
            line(XL - ov, eY, XL - ov, eY + 15, 1.6, RGBA(hex: 0x111111)); line(XR + ov, eY, XR + ov, eY + 15, 1.6, RGBA(hex: 0x111111))
            // purlins (C marks) at ระยะแป along the slope
            let nP = max(3, Int((half / cos(ang * .pi / 180) / Roof.purlinSpacing(v)).rounded()))
            for i in 1...nP {
                for x in [XL + Double(i) * HW / (Double(nP) + 0.5), XR - Double(i) * HW / (Double(nP) + 0.5)] {
                    let py = topY(x) - 5
                    add(.polyline([pt(x + 3, py), pt(x - 3, py), pt(x - 3, py + 5), pt(x + 3, py + 5)], width: 1.4, color: Self.dark), "SECTION")
                }
            }
        }
        for c in cols { add(.polyline(c, width: 7, color: Self.dark), "SECTION") }
        for c in cols { add(.polyline(c, width: 4.4, color: Self.core), nil) }
        let colXs = isC ? [] : isR ? [XL, XR, XL + HW * 0.8, XR - HW * 0.8] : [XL, XR]
        for x in colXs {
            add(.rect(Box(x - 9, 192, 18, 3), stroke: nil, fill: Self.dark), "SECTION")
            add(.polyline([pt(x - 12, 199), pt(x - 6, 196), pt(x - 2, 202), pt(x + 2, 196), pt(x + 8, 199)], width: 0.9, color: Self.dark), "SECTION")
        }
        for b in hatches { add(.hatch(b, color: RGBA(hex: 0x3A3F47), spacing: 5), nil); add(.rect(b, stroke: RGBA(hex: 0x111111), fill: nil, width: 1), "SECTION") }

        // dimensions
        let oL = XL - ov, oR = XR + ov, cX = isK ? XR - 28 : XL - 22, cT = isC ? YE : YB
        func dim(_ a: Double, _ b: Double, _ c: Double, _ d: Double) { line(a, b, c, d, 0.8, Self.navy, "DIM") }
        func tick(_ x: Double, _ y: Double) { dim(x, y, x + 8, y - 8) }
        dim(XL - 6, 208, XR + 6, 208); dim(XL - 6, 230, XR + 6, 230)
        tick(XL - 4, 212); tick(376, 212); tick(XR - 4, 212); tick(XL - 4, 234); tick(XR - 4, 234); dim(380, 200, 380, 212)
        for x in pts { dim(x, 205, x, 211) }
        dim(oL - 6, 230, XL, 230); dim(XR, 230, oR + 6, 230)
        tick(oL - 4, 234); tick(oR - 4, 234); dim(oL, 222, oL, 238); dim(oR, 222, oR, 238)
        dim(cX, cT - 6, cX, 199); tick(cX - 4, cT + 4); tick(cX - 4, 199)
        if isK { dim(XR - 8, cT, cX - 4, cT); dim(XR - 8, 195, cX - 4, 195) } else { dim(cX - 4, cT, XL - 4, cT); dim(cX - 4, 195, XL - 10, 195) }
        let ovT = String(format: "%.2f", overhang)
        text("ชายคา " + ovT, oL - 8, 234, align: .right); text(ovT, oR + 8, 234)
        text(isC ? "สูงถึงหัวเสา" : "สูงใต้ขื่อ", cX - 6, (cT + 195) / 2 - 3, align: .right)
        text(String(format: "%.2f", clear), cX - 6, (cT + 195) / 2 + 11, bold: true, align: .right)
        overhangLabel = Pt(oL - 40, 230); clearLabel = Pt(cX - 30, (cT + 195) / 2 + 2)
        let halfT = isC ? String(format: "%.2f", half) : "\(nH) × " + String(format: "%.2f", half / Double(nH)) + " = " + String(format: "%.2f", half)
        text(halfT, (XL + 380) / 2, 201, color: Self.blue, align: .center); text(halfT, (XR + 380) / 2, 201, color: Self.blue, align: .center)
        text(fmt(span) + " (จากแปลน)", 380, 246, 13, bold: true, align: .center)
        let RX = XR + 46
        dim(RX, YT - 4, RX, YB + 4); dim(386, YT, RX + 4, YT)
        tick(RX - 4, YT + 4); tick(RX - 4, YE + 4); if !isC { tick(RX - 4, 154) }
        text("R " + String(format: "%.2f", rise), RX + 6, (YT + YE) / 2 + 4)
        if !isC { text(String(format: "%.2f", heelM), RX + 6, (YE + YB) / 2 + 4) }
        text(Roof.slopeText(v), XL + 44, YE - 4)
        riseLabel = Pt(RX + 30, (YT + YE) / 2)
        var arc: [Pt] = []
        for s in 0...12 { let t = Double(s) / 12 * ang * .pi / 180; arc.append(pt(XL + 40 * cos(t), YE - 40 * sin(t))) }
        add(.polyline(arc, width: 0.8, color: Self.navy), "DIM")

        // callouts ①–⑦
        var bubbles: [Int: Pt] = [:]
        func call(_ n: Int, _ bx: Double, _ by: Double, _ tx: Double, _ ty: Double) {
            let dx = tx - bx, dy = ty - by, L = max(hypot(dx, dy), 1), ux = dx / L, uy = dy / L, r = 9.0
            let sx = bx + ux * r, sy = by + uy * r, ex = tx - ux, ey = ty - uy, al = 7.0, aw = 2.6
            line(sx, sy, ex - ux * al, ey - uy * al, 1, Self.red, "DIM")
            add(.polygon([pt(ex, ey), pt(ex - ux * al - uy * aw, ey - uy * al + ux * aw), pt(ex - ux * al + uy * aw, ey - uy * al - ux * aw)],
                         stroke: nil, fill: Self.red), nil)
            add(.circle(pt(bx, by), r: r, stroke: Self.red, fill: .white, width: 1.4), "DIM")
            add(.text(String(n), at: pt(bx, by), size: 12, bold: true, color: Self.red, align: .center), nil)
            bubbles[n] = pt(bx, by)
        }
        let x1 = XL + HW * 0.37, x2 = XR - HW * 0.33
        if isC {
            call(1, x1 - 20, 44, x1, topY(x1) - G.dv - G.hp * 0.6); call(2, x2 + 10, 44, x2, topY(x2) - G.dv / 2)
            call(3, 430, 172, 430, G.yc + G.dc)
            if isK {
                let o = XL - G.wc / 2, xf = G.eL + G.fx, ye = topY(G.eL)
                call(4, XL + 60, 196, o + G.bw * 0.4, (G.yb1 + G.yb2) / 2); call(5, G.eL + 8, 196, (xf + o) / 2, G.yb2)
                call(6, G.eL - 26, 96, (G.eL + xf) / 2 - 1, (ye + G.yb2) / 2); call(7, XL + 96, 172, XL + G.wc / 2, (G.yb2 + 192) / 2)
            } else {
                call(4, XL + 44, 196, XL + G.w / 2 + G.pj - 2, G.yB1 - 1); call(6, G.eL - 22, 96, G.eL - 1.5, topY(G.eL) - G.dv / 2 + 2)
            }
        } else if isR {
            call(1, x1 - 20, 44, x1, topY(x1) - 5); call(2, x2 + 10, 44, x2, topY(x2))
            let xa = XL + HW * 0.25, xi1 = XL + HW * 0.8, xq = pts[safe: max(0, Int(Double(pts.count) * 0.15))] ?? XL + 40
            call(3, xa, 172, xa, topY(xa) + heel); call(4, xq + pw * sc * 0.5 + 30, 172, xq + pw * sc * 0.5, topY(xq + pw * sc * 0.5) + heel * 0.5)
            call(5, xi1 + 42, 96, xi1 + 4, topY(xi1) + heel + 2); call(6, XL - 50, 96, XL - ov, eY + 7); call(7, xi1 - 34, 172, xi1, 165)
        } else {
            call(1, x1 - 20, 44, x1, topY(x1) - 5); call(2, x2 + 10, 44, x2, topY(x2))
            let xv = pts[safe: max(0, Int(Double(pts.count) * 0.3))] ?? 300
            call(3, XL + HW * 0.47, 172, XL + HW * 0.47, YB); call(4, xv + 10, 172, xv, (YB + topY(xv)) / 2)
            call(5, xv + 46, 172, xv + pw * sc * 0.5, (YB + topY(xv + pw * sc * 0.5)) / 2 + 4); call(6, XL - 50, 96, XL - ov, eY + 7)
            call(7, 420, 172, 380, (YB + YT) / 2 + 10)
        }
        // the chosen row's callout filled red
        if let n = highlight, let c = bubbles[n] {
            add(.circle(c, r: 11, stroke: .white, fill: Self.red, width: 2), nil)
            add(.text(String(n), at: c, size: 13, bold: true, color: .white, align: .center), nil)
        }
        sketch = Sketch(width: Self.width, height: Self.height, ops: o)
        tags = tg
        callouts = bubbles
        self.span = span; self.half = half; self.rise = rise; self.bays = nH; self.scale = sc
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
