import Foundation

/// A round tank's roof plan (`Tank.isRound`): the double rim, the two centre lines, the diameter dimension under the
/// circle, the level tags, the openings (ladders and pipes as small boxes outside the rim on their radius), the north
/// arrow and the caption; `details` adds the section marks 1–1 / 2–2 on the centre lines and the size and volume
/// summary. The frame is the circle's bounding square, so the D1 page, the panel layout and the DXF place everything
/// in the same tank metres as a rectangle's.
extension TankPlan {
    static func round(_ v: Values, width W: Double, hints: Bool, details: Bool)
        -> (sketch: Sketch, tags: [String?], frame: (ox: Double, oy: Double, k: Double), dimensions: [SketchDXF.Dimension])? {
        guard let D = Tank.diameter(v) else { return nil }
        let padL = 52.0, padT = 66.0, padR = 78.0, padB = 82.0, maxH = (W * 0.78).rounded()
        let k = min((W - padL - padR) / D, (maxH - padT - padB) / D), w = D * k, h = w
        let ox = padL + ((W - padL - padR) - w) / 2, oy = padT, H = (oy + h + padB).rounded()
        let c = Pt(ox + w / 2, oy + h / 2), R = w / 2
        var o: [DrawOp] = [.rect(Box(0, 0, W, H), stroke: nil, fill: .white)]
        var tags: [String?] = [nil]
        func tag(_ t: String, text: String? = nil) {
            for op in o[tags.count...] { if case .text = op { tags.append(text ?? t) } else { tags.append(t) } }
        }
        let grid = RGBA(hex: 0xB9C6D6), ink = RGBA(hex: 0x111111), navy = RGBA(hex: 0x16325C)

        // centre lines, past the rim
        let dash: [Double] = [6, 3, 1.5, 3]
        o.append(.line(Pt(c.x, oy - 18), Pt(c.x, oy + h + 8), width: 0.5, color: grid, dash: dash))
        o.append(.line(Pt(ox - 18, c.y), Pt(ox + w + 8, c.y), width: 0.5, color: grid, dash: dash))
        tag("grid")
        // the wall: a double rim
        o.append(.circle(c, r: R, stroke: ink, fill: nil, width: 1.4))
        o.append(.circle(c, r: max(0, R - 3), stroke: ink, fill: nil, width: 0.8))
        tag("out")
        if details {
            o += sectionMarks(ox: ox, oy: oy, w: w, h: h)
            tag("sect")
        }
        // level tags in the four quadrants (inside the circle)
        if let e = v.number(Tank.Key.exposed) {
            let t = "ระดับหลังถัง +" + String(format: "%.2f", e)
            for (fx, fy) in [(0.3, 0.32), (0.7, 0.32), (0.3, 0.72), (0.7, 0.72)] {
                let p = Pt(ox + w * fx, oy + h * fy)
                o.append(.line(Pt(p.x - 30, p.y + 5), Pt(p.x + 30, p.y + 5), width: 0.5, color: .ink2))
                o.append(.text(t, at: p, size: 6.5, color: .ink2, align: .center))
            }
        }
        tag("txt")
        // openings; ladders and pipes stand outside the rim on their radius
        let circle = TankPoints.Circle(diameter: D)
        for ob in v.obstacles(Roof.Key.obstacles) where !ob.isAbsent {
            guard let x = NumberInput.value(ob.x), let y = NumberInput.value(ob.y), let ow = NumberInput.value(ob.w), let oh = NumberInput.value(ob.h), ow > 0, oh > 0 else { continue }
            if TankPoints.onWall(ob.kind) {
                let r = TankPoints.Rect(x: x, y: y, w: ow, h: oh), u = circle.outward(r), at = Pt(c.x + u.x * (R + 9), c.y + u.y * (R + 9))
                let flat = abs(u.y) >= abs(u.x)
                let b = Box(at.x - (flat ? 3 : 5), at.y - (flat ? 5 : 3), flat ? 6 : 10, flat ? 10 : 6)
                o.append(.rect(b, stroke: .red, fill: .white, width: 0.8))
                if ob.kind == TankPoints.pipe { o.append(.line(Pt(b.x, b.y), Pt(b.maxX, b.maxY), width: 0.6, color: .red)) }
                continue
            }
            let b = Box(ox + x * k, oy + y * k, ow * k, oh * k)
            o.append(.rect(b, stroke: nil, fill: .white)); o.append(.hatch(b, color: .red)); o.append(.rect(b, stroke: .red, fill: nil, width: 1))
            if !ob.label.isEmpty { o.append(.text("\(ob.label) \(fmt(ow))x\(fmt(oh))", at: Pt(b.maxX + 3, b.maxY - 3), size: 8, color: .dark)) }
        }
        tag("obst", text: "txt")
        // the diameter under the circle, from its leftmost and rightmost points
        func tick(_ p: Pt) -> DrawOp { .line(Pt(p.x - 3, p.y + 3), Pt(p.x + 3, p.y - 3), width: 0.9, color: ink) }
        let cy = oy + h + 22
        o.append(.line(Pt(ox, c.y), Pt(ox, cy + 4), width: 0.4, color: .ink2))
        o.append(.line(Pt(ox + w, c.y), Pt(ox + w, cy + 4), width: 0.4, color: .ink2))
        o.append(.line(Pt(ox - 4, cy), Pt(ox + w + 4, cy), width: 0.6, color: ink))
        o.append(tick(Pt(ox, cy))); o.append(tick(Pt(ox + w, cy)))
        o.append(.text("Ø " + String(format: "%.2f", D), at: Pt(ox + w / 2, cy - 7), size: 9, bold: true, color: ink, align: .center))
        let dims = [SketchDXF.Dimension(Pt(ox, c.y), Pt(ox + w, c.y), at: Pt(0, cy), text: "Ø " + String(format: "%.2f", D), size: 9)]
        tag("dim", text: "dimtxt")
        // note, north arrow, caption
        let wall = Tank.typeName(v).map { "ผนัง " + $0 }
        let note = ([wall] + [hints ? "สิ่งกีดขวางระบุในขั้นที่ 2" : nil]).compactMap { $0 }.joined(separator: " | ")
        if !note.isEmpty { o.append(.text(note, at: Pt(W - 50, 14), size: 8, color: .ink2, align: .right)) }
        tag("txt")
        if let az = Tank.azimuth(v) { o += northArrow(at: Pt(W - 24, 36), azimuth: az) }
        tag("north")
        let caption = "แปลนหลังคาถังน้ำใสทรงกลม Ø \(fmt(D)) ม."
        let capY = cy + 30
        o.append(.text(caption, at: Pt(ox, capY), size: 10.5, bold: true, color: navy))
        o.append(.line(Pt(ox, capY + 8), Pt(ox + Double(caption.count) * 5.6, capY + 8), width: 0.9, color: navy))
        o.append(.text("หน่วย: เมตร", at: Pt(W - 16, capY), size: 8, color: .ink2, align: .right))
        var bottom = capY + 14
        if details {
            if let sum = Tank.summary(v) {
                o.append(.text(sum.text, at: Pt(ox, capY + 20), size: 8.5, color: ink)); bottom = capY + 28
            }
            o.append(.text(TankDrawings.note, at: Pt(ox, bottom + 4), size: 7.5, color: .ink2)); bottom += 12
        }
        tag("txt")
        return (Sketch(width: W, height: max(H, bottom), ops: o), tags, (ox, oy, k), dims)
    }

    /// The iPhone's 330 × 300 plan of a round tank: the rim, the centre lines, the diameter and the north arrow.
    static func compactRound(_ v: Values) -> Sketch? {
        guard let D = Tank.diameter(v), let f = compactFrame(v) else { return nil }
        let k = f.k, w = D * k, c = Pt(f.ox + w / 2, f.oy + w / 2)
        let navy = RGBA(hex: 0x16325C), grid = RGBA(hex: 0xC9D3DF)
        var o: [DrawOp] = [.rect(Box(0, 0, 330, 300), stroke: nil, fill: .white), .circle(c, r: w / 2, stroke: nil, fill: .white)]
        o.append(.line(Pt(c.x, f.oy - 6), Pt(c.x, f.oy + w + 6), width: 1, color: grid, dash: [3, 3]))
        o.append(.line(Pt(f.ox - 6, c.y), Pt(f.ox + w + 6, c.y), width: 1, color: grid, dash: [3, 3]))
        o.append(.circle(c, r: w / 2, stroke: navy, fill: nil, width: 2))
        o.append(.text("Ø " + String(format: "%.2f", D), at: Pt(c.x, f.oy + w + 16), size: 9, bold: true, color: navy, align: .center))
        if let az = Tank.azimuth(v) { o += northArrow(at: Pt(298, 42), azimuth: az, radius: 13, ink: navy) }
        return Sketch(width: 330, height: 300, ops: o)
    }
}
