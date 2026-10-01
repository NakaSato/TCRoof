import Foundation

/// C1 section A-A (docs/ui/survey-c1 `renderVals`, `S.*`): a true-scale cut across the ridge for the five frame types,
/// with dimensions and the callouts ①–⑦ of the member rows. The sketch is the design's 760 × 250 viewBox.
public struct RoofSection: Sendable {
    public static let width = 760.0, height = 250.0

    public var sketch: Sketch
    /// Where the eave overhang and clear-height labels sit (the page makes them tappable).
    public var overhangLabel = Pt(0, 0), clearLabel = Pt(0, 0)
    public let span, half, rise: Double
    public let bays: Int

    static let dark = RGBA(hex: 0x1A1D22), core = RGBA(hex: 0xD5DBE3), webCore = RGBA(hex: 0xF2F4F7), navy = RGBA(hex: 0x16325C)
    static let sheet = RGBA(hex: 0x1F4F78), red = RGBA(hex: 0xD9453B), blue = RGBA(hex: 0x1F6FB5), gridC = RGBA(hex: 0x8A97AA)

    public init(_ v: Values) {
        let f = Roof.frame(v), ridge = Roof.ridge(v)
        let span = Roof.span(v), half = span / 2, nH = Roof.bays(v)
        let ang = f.slope, tn = tan(ang * .pi / 180), rise = half * tn
        let isC = f == .rafterTie, isR = f == .rafterTruss, heelM = f.heel
        let sc = min(540 / span, 118 / (rise + heelM)), HW = half * sc, XL = 380 - HW, XR = 380 + HW, YB = 150.0
        let heel = heelM * sc, YE = YB - heel, YT = YE - rise * sc, pw = half / Double(nH)
        let overhang = Roof.overhang(v), clear = Roof.clearHeight(v)
        var o: [DrawOp] = []
        var webs: [[Pt]] = [], chords: [[Pt]] = [], cols: [[Pt]] = []
        func pt(_ x: Double, _ y: Double) -> Pt { Pt(x, y) }
        func line(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ w: Double, _ col: RGBA, dash: [Double] = []) {
            o.append(.line(Pt(a, b), Pt(c, d), width: w, color: col, dash: dash))
        }
        func text(_ t: String, _ x: Double, _ y: Double, _ size: Double = 12, bold: Bool = false, color: RGBA = RoofSection.navy, align: TextAlign = .left) {
            // the design's y is the baseline; DrawOp text is anchored at the line's middle
            o.append(.text(t, at: Pt(x, y - size * 0.35), size: size, bold: bold, color: color, align: align))
        }
        func topY(_ x: Double) -> Double { x <= 380 ? YE - (x - XL) / HW * (YE - YT) : YE - (XR - x) / HW * (YE - YT) }
        let ov = overhang * sc, rOff = 7.0, slope = (YE - YT) / HW
        var pts: [Double] = []
        if !isC { for i in 1..<(2 * nH) { pts.append(XL + Double(i) * pw * sc) } }

        o.append(.rect(Box(0, 0, Self.width, Self.height), stroke: nil, fill: .white))
        let gdash: [Double] = [12, 3, 2, 3]
        line(XL, 24, XL, 240, 0.6, Self.gridC, dash: gdash); line(XR, 24, XR, 240, 0.6, Self.gridC, dash: gdash); line(380, 24, 380, YB, 0.6, Self.gridC, dash: gdash)
        let gA = ridge == .h ? "A" : "1"
        let gB = ridge == .h ? Roof.gridName(.y, Roof.spans(v, .y).count) : Roof.gridName(.x, Roof.spans(v, .x).count)
        for (x, t) in [(XL, gA), (XR, gB)] {
            o.append(.circle(Pt(x, 14), r: 9, stroke: Self.navy, fill: .white, width: 1))
            o.append(.text(t, at: Pt(x, 14), size: 11, bold: true, color: Self.navy, align: .center))
        }

        var hatches: [Box] = [], supports: [[Pt]] = []
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
            let t = 7.0, eL = XL - ov, eyL = YE + ov * slope
            chords.append([pt(eL, eyL), pt(380, YT), pt(XR + ov, eyL)])
            webs += [[pt(eL, eyL - t), pt(380, YT - t), pt(XR + ov, eyL - t)], [pt(eL, eyL), pt(eL, eyL - t)], [pt(XR + ov, eyL), pt(XR + ov, eyL - t)]]
            let yc = YE - 0.62 * (YE - YT), xc1 = XL + (YE - yc) / slope, xc2 = XR - (YE - yc) / slope
            webs += [[pt(xc1, yc), pt(xc2, yc)], [pt(xc1 + 3, yc + 6), pt(xc2 - 3, yc + 6)]]
            hatches += [Box(XL - 8, YE, 16, 28), Box(XR - 8, YE, 16, 28)]
            supports += [[pt(XL - 8, YE + 28), pt(XL + 18, YE + 28), pt(XL + 10, YE + 38), pt(XL + 10, YE + 80)], [pt(XL - 8, YE + 28), pt(XL - 8, 190)],
                         [pt(XR + 8, YE + 28), pt(XR - 18, YE + 28), pt(XR - 10, YE + 38), pt(XR - 10, YE + 80)], [pt(XR + 8, YE + 28), pt(XR + 8, 190)]]
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
        for w in webs { o.append(.polyline(w, width: 3.2, color: Self.dark)) }
        for w in webs { o.append(.polyline(w, width: 1.3, color: Self.webCore)) }
        for c in chords { o.append(.polyline(c, width: 6, color: Self.dark)) }
        for c in chords { o.append(.polyline(c, width: 3.6, color: Self.core)) }
        func gusset(_ x: Double, _ y: Double, _ r: Double) {
            o.append(.polygon([pt(x - r, y), pt(x, y - r * 0.8), pt(x + r, y), pt(x, y + r * 0.8)], stroke: Self.dark, fill: .white, width: 0.9))
        }
        if !isC && !isR {
            for x in [XL, XR] { gusset(x, YB - 3, 7) }
            for x in pts { gusset(x, YB, 4.5); gusset(x, topY(x), 4.5) }
            gusset(380, YT + 2, 6)
        }
        if isR { for x in pts { gusset(x, topY(x), 3.5); gusset(x, topY(x) + heel, 3.5) } }

        // corrugated sheet along the slope, with the ridge cap
        let eY = YE + ov * slope - rOff - (isC ? 7 : 0), rT = YT - rOff - (isC ? 7 : 0)
        func wave(_ xa: Double, _ ya: Double, _ xb: Double, _ yb: Double) -> [Pt] {
            let L = hypot(xb - xa, yb - ya), n = max(2, Int((L / 5).rounded())), ux = (xb - xa) / L, uy = (yb - ya) / L, nx = -uy, ny = ux
            var p = [pt(xa, ya)]
            for q in 1...n {
                let t = Double(q) / Double(n), a = q % 2 == 1 ? 1.6 : 0
                p.append(pt(xa + (xb - xa) * t + nx * -a, ya + (yb - ya) * t + ny * -a))
            }
            return p
        }
        o.append(.polyline(wave(XL - ov, eY, 380, rT) + wave(380, rT, XR + ov, eY).dropFirst(), width: 1.1, color: Self.sheet))
        o.append(.polyline([pt(372, rT + 3), pt(380, rT - 3), pt(388, rT + 3)], width: 1.6, color: Self.sheet))
        if !isC { line(XL - ov, eY, XL - ov, eY + 15, 1.6, RGBA(hex: 0x111111)); line(XR + ov, eY, XR + ov, eY + 15, 1.6, RGBA(hex: 0x111111)) }
        // purlins (C marks)
        let nP = max(4, Int((half / 1.1).rounded()))
        for i in 1...nP {
            for x in [XL + Double(i) * HW / (Double(nP) + 0.5), XR - Double(i) * HW / (Double(nP) + 0.5)] {
                let py = topY(x) - 5 - (isC ? 7 : 0)
                o.append(.polyline([pt(x + 3, py), pt(x - 3, py), pt(x - 3, py + 5), pt(x + 3, py + 5)], width: 1.4, color: Self.dark))
            }
        }
        for c in cols { o.append(.polyline(c, width: 7, color: Self.dark)) }
        for c in cols { o.append(.polyline(c, width: 4.4, color: Self.core)) }
        let colXs = isC ? [] : isR ? [XL, XR, XL + HW * 0.8, XR - HW * 0.8] : [XL, XR]
        for x in colXs {
            o.append(.rect(Box(x - 9, 192, 18, 3), stroke: nil, fill: Self.dark))
            o.append(.polyline([pt(x - 12, 199), pt(x - 6, 196), pt(x - 2, 202), pt(x + 2, 196), pt(x + 8, 199)], width: 0.9, color: Self.dark))
        }
        for b in hatches { o.append(.hatch(b, color: RGBA(hex: 0x3A3F47), spacing: 5)); o.append(.rect(b, stroke: RGBA(hex: 0x111111), fill: nil, width: 1)) }
        for s in supports { o.append(.polyline(s, width: 1.2, color: RGBA(hex: 0x111111))) }

        // dimensions
        let oL = XL - ov, oR = XR + ov, cX = XL - 22, cT = isC ? YE : YB
        func tick(_ x: Double, _ y: Double) { line(x, y, x + 8, y - 8, 0.8, Self.navy) }
        line(XL - 6, 208, XR + 6, 208, 0.8, Self.navy); line(XL - 6, 230, XR + 6, 230, 0.8, Self.navy)
        tick(XL - 4, 212); tick(376, 212); tick(XR - 4, 212); tick(XL - 4, 234); tick(XR - 4, 234); line(380, 200, 380, 212, 0.8, Self.navy)
        for x in pts { line(x, 205, x, 211, 0.8, Self.navy) }
        line(oL - 6, 230, XL, 230, 0.8, Self.navy); line(XR, 230, oR + 6, 230, 0.8, Self.navy)
        tick(oL - 4, 234); tick(oR - 4, 234); line(oL, 222, oL, 238, 0.8, Self.navy); line(oR, 222, oR, 238, 0.8, Self.navy)
        line(cX, cT - 6, cX, 199, 0.8, Self.navy); tick(cX - 4, cT + 4); tick(cX - 4, 199)
        line(cX - 4, cT, XL - 4, cT, 0.8, Self.navy); line(cX - 4, 195, XL - 10, 195, 0.8, Self.navy)
        let ovT = String(format: "%.2f", overhang)
        text("ชายคา " + ovT, oL - 8, 234, align: .right); text(ovT, oR + 8, 234)
        text(isC ? "สูงถึงหัวเสา" : "สูงใต้ขื่อ", cX - 6, (cT + 195) / 2 - 3, align: .right)
        text(String(format: "%.2f", clear), cX - 6, (cT + 195) / 2 + 11, bold: true, align: .right)
        overhangLabel = Pt(oL - 40, 230); clearLabel = Pt(cX - 30, (cT + 195) / 2 + 2)
        let halfT = isC ? String(format: "%.2f", half) : "\(nH) × " + String(format: "%.2f", half / Double(nH)) + " = " + String(format: "%.2f", half)
        text(halfT, (XL + 380) / 2, 201, color: Self.blue, align: .center); text(halfT, (XR + 380) / 2, 201, color: Self.blue, align: .center)
        text(fmt(span) + " (จากแปลน)", 380, 246, 13, bold: true, align: .center)
        let RX = XR + 46
        line(RX, YT - 4, RX, YB + 4, 0.8, Self.navy); line(386, YT, RX + 4, YT, 0.8, Self.navy)
        tick(RX - 4, YT + 4); tick(RX - 4, YE + 4); if !isC { tick(RX - 4, 154) }
        text("R " + String(format: "%.2f", rise), RX + 6, (YT + YE) / 2 + 4)
        if !isC { text(String(format: "%.2f", heelM), RX + 6, (YE + YB) / 2 + 4) }
        text(fmt(ang) + "°", XL + 44, YE - 4)
        var arc: [Pt] = []
        for s in 0...12 { let t = Double(s) / 12 * ang * .pi / 180; arc.append(pt(XL + 40 * cos(t), YE - 40 * sin(t))) }
        o.append(.polyline(arc, width: 0.8, color: Self.navy))

        // callouts ①–⑦
        func call(_ n: Int, _ bx: Double, _ by: Double, _ tx: Double, _ ty: Double) {
            let dx = tx - bx, dy = ty - by, L = max(hypot(dx, dy), 1), ux = dx / L, uy = dy / L, r = 9.0
            let sx = bx + ux * r, sy = by + uy * r, ex = tx - ux, ey = ty - uy, al = 7.0, aw = 2.6
            line(sx, sy, ex - ux * al, ey - uy * al, 1, Self.red)
            o.append(.polygon([pt(ex, ey), pt(ex - ux * al - uy * aw, ey - uy * al + ux * aw), pt(ex - ux * al + uy * aw, ey - uy * al - ux * aw)],
                              stroke: nil, fill: Self.red))
            o.append(.circle(pt(bx, by), r: r, stroke: Self.red, fill: .white, width: 1.4))
            o.append(.text(String(n), at: pt(bx, by), size: 12, bold: true, color: Self.red, align: .center))
        }
        let x1 = XL + HW * 0.37, x2 = XR - HW * 0.33
        call(1, x1 - 20, 44, x1, topY(x1) - 5 - (isC ? 7 : 0)); call(2, x2 + 10, 44, x2, topY(x2))
        if isC {
            let yc = YE - 0.62 * (YE - YT)
            call(3, 430, 172, 430, yc + 3); call(4, XL + 40, 196, XL + 8, YE + 10); call(6, XL - ov - 22, 96, XL - ov, YE + ov * slope - 3)
        } else if isR {
            let xa = XL + HW * 0.25, xi1 = XL + HW * 0.8, xq = pts[safe: max(0, Int(Double(pts.count) * 0.15))] ?? XL + 40
            call(3, xa, 172, xa, topY(xa) + heel); call(4, xq + pw * sc * 0.5 + 30, 172, xq + pw * sc * 0.5, topY(xq + pw * sc * 0.5) + heel * 0.5)
            call(5, xi1 + 42, 96, xi1 + 4, topY(xi1) + heel + 2); call(6, XL - 50, 96, XL - ov, eY + 7); call(7, xi1 - 34, 172, xi1, 165)
        } else {
            let xv = pts[safe: max(0, Int(Double(pts.count) * 0.3))] ?? 300
            call(3, XL + HW * 0.47, 172, XL + HW * 0.47, YB); call(4, xv + 10, 172, xv, (YB + topY(xv)) / 2)
            call(5, xv + 46, 172, xv + pw * sc * 0.5, (YB + topY(xv + pw * sc * 0.5)) / 2 + 4); call(6, XL - 50, 96, XL - ov, eY + 7)
            call(7, 420, 172, 380, (YB + YT) / 2 + 10)
        }
        sketch = Sketch(width: Self.width, height: Self.height, ops: o)
        self.span = span; self.half = half; self.rise = rise; self.bays = nH
    }
}
