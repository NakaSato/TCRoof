import Foundation

/// The editor's cross-section (docs/ui/survey-a4-ipad-v2 §1.4): a metre ruler and a legend, the freeboard as a hatched
/// band, level tags as pills on the right (the water's with a drag grip), the B2 room with INV, SMDB and an E-stop at
/// their heights, each with the height check's ✓ / ✗. Coordinates follow that board's viewBox (0 100 540 420), moved
/// up by 100 as the report's drawing is.
extension FloodSection {
    static let frame = RGBA(hex: 0x3B4A60), rule = RGBA(hex: 0x8A97A8)
    static let passFill = RGBA(hex: 0x2E9E5B), failFill = RGBA(hex: 0xD9453B)
    static let bandFill = RGBA(hex: 0xE6F4F1), bandHatch = RGBA(hex: 0xB5DDD6), water = RGBA(hex: 0x5C97D3).withAlpha(0.5)
    static let groundFill = RGBA(hex: 0xEFEAE2)

    /// Rough width of a line of Sarabun: Thai marks above and below the line take no width.
    static func textWidth(_ t: String, _ size: Double) -> Double {
        Double(t.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }.count) * size * 0.55
    }

    /// A fully rounded box (the level tags), as a polygon: `DrawOp` has no rounded rect.
    static func pill(_ b: Box, fill: RGBA?, stroke: RGBA? = nil, width: Double = 1) -> DrawOp {
        let r = b.h / 2, n = 8
        var pts: [Pt] = []
        for i in 0...n {
            let a = -Double.pi / 2 + Double.pi * Double(i) / Double(n)
            pts.append(Pt(b.maxX - r + r * cos(a), b.y + r + r * sin(a)))
        }
        for i in 0...n {
            let a = Double.pi / 2 + Double.pi * Double(i) / Double(n)
            pts.append(Pt(b.x + r + r * cos(a), b.y + r + r * sin(a)))
        }
        return .polygon(pts, stroke: stroke, fill: fill, width: width)
    }

    /// "+1.30" for 130 cm.
    static func metres(_ cm: Double) -> String { "+" + String(format: "%.2f", cm / 100) }

    enum TagKind { case ground, floor, water, minimum }

    static func screenSketch(_ job: Job) -> Sketch {
        let v = job.values, r = job.floodCheck
        let floor = FloodCheck.floorCm(v), mount = FloodCheck.mountCm(v), emg = FloodCheck.emergencyCm(v)
        let lvl = r.level, minCm = Double(r.minCm), wet = lvl > 0, flooded = r.state == .flooded
        let k = scale(job, style: .screen), g = groundY
        func y(_ cm: Double) -> Double { g - cm * k }
        let x0 = 40.0, x1 = 424.0
        let fy = y(floor), my = y(minCm), wy = y(lvl), mountY = y(floor + mount), ey = y(emg)
        var o: [DrawOp] = [.rect(Box(0, 0, width, height), stroke: nil, fill: .white)]
        func halo(_ t: String, _ p: Pt, size: Double, bold: Bool = true, color: RGBA, align: TextAlign = .left,
                  angle: Double = 0, bg: RGBA = RGBA(1, 1, 1, 0.85)) {
            let w = textWidth(t, size)
            if angle == 0 {
                let left = align == .left ? p.x : align == .right ? p.x - w : p.x - w / 2
                o.append(.rect(Box(left - 2, p.y - size * 0.62, w + 4, size * 1.24), stroke: nil, fill: bg))
            } else {
                o.append(.rect(Box(p.x - size * 0.62, p.y - w / 2 - 2, size * 1.24, w + 4), stroke: nil, fill: bg))
            }
            o.append(.text(t, at: p, size: size, bold: bold, color: color, align: align, angle: angle))
        }
        func ticks(_ x: Double, _ ys: [Double], _ c: RGBA) {
            for yy in ys { o.append(.line(Pt(x - 5, yy + 5), Pt(x + 5, yy - 5), width: 1, color: c)) }
        }

        o.append(.text("ระดับเป็นเมตร | มิติเป็น ซม.", at: Pt(538, 14), size: 10.5, color: rule, align: .right))
        // the freeboard: from the water (or the reference level) up to the minimum install level
        if my < wy - 0.5 {
            let band = Box(x0, my, x1 - x0, wy - my)
            o.append(.rect(band, stroke: nil, fill: bandFill))
            o.append(.hatch(band, color: bandHatch, spacing: 8))
        }
        // metre ruler: a tick every 10 cm, a label every 50
        o.append(.line(Pt(34, 24), Pt(34, g), width: 1, color: rule))
        var cm = 0.0
        while y(cm) >= 23.5 {
            let major = Int(cm.rounded()) % 50 == 0
            o.append(.line(Pt(major ? 27 : 30, y(cm)), Pt(34, y(cm)), width: 1, color: rule))
            if major { o.append(.text(cm == 0 ? "0" : String(format: "%.1f", cm / 100), at: Pt(24, y(cm) - (cm == 0 ? 5 : 0)), size: 10, color: rule, align: .right)) }
            cm += 10
        }
        // existing main board
        o.append(.rect(Box(56, 78, 70, g - 78), stroke: frame, fill: .white, width: 1.4))
        o.append(.line(Pt(56, 110), Pt(126, 110), width: 0.8, color: frame))
        o.append(.text(r.mdbName.replacingOccurrences(of: "MDB", with: "MDB "), at: Pt(91, 89), size: 12, bold: true, color: ink, align: .center))
        o.append(.text("เดิม | A3", at: Pt(91, 102), size: 9.5, color: muted, align: .center))
        for yy in [122.0, 132, 142] { o.append(.line(Pt(66, yy), Pt(116, yy), width: 3, color: RGBA(hex: 0xDDE4ED))) }
        // inverter room on its slab
        if floor > 0 {
            o.append(.rect(Box(156, fy, 268, g - fy), stroke: frame, fill: RGBA(hex: 0xF1F3F5), width: 1.2))
            var dy = fy + 3, row = 0
            while dy < g - 1 {
                var dx = row % 2 == 0 ? 160.0 : 164.0
                while dx < 422 { o.append(.circle(Pt(dx, dy), r: 0.8, stroke: nil, fill: RGBA(hex: 0x8E959B))); dx += 8 }
                dy += 5; row += 1
            }
        }
        o.append(.polyline([Pt(164, fy), Pt(164, 20), Pt(416, 20), Pt(416, fy)], width: 2.4, color: frame))
        let inverterTag = job.sectionsByCategory.flatMap(\.sections).first { $0.module.type == .inverter }?.number
        o.append(.runs([TextRun("ห้อง Inverter", size: 12, bold: true)] + (inverterTag.map { [TextRun(" " + $0, size: 12)] } ?? []),
                       at: Pt(342, 36), color: ink, align: .center))
        let invTop = mountY - 104, smdbTop = mountY - 84
        o.append(.rect(Box(196, invTop, 60, 104), stroke: blue, fill: .white, width: 1.8))
        for d in [20.0, 30] { o.append(.line(Pt(206, invTop + d), Pt(246, invTop + d), width: 2, color: RGBA(hex: 0xC8DAEE))) }
        o.append(.text("INV", at: Pt(226, mountY - 34), size: 12, bold: true, color: blue, align: .center))
        o.append(.rect(Box(272, smdbTop, 46, 84), stroke: blue, fill: .white, width: 1.8))
        o.append(.text("SMDB", at: Pt(295, mountY - 41), size: 10, bold: true, color: blue, align: .center))
        o.append(.rect(Box(362, ey - 13, 22, 26), stroke: blue, fill: .white, width: 1.6))
        o.append(.circle(Pt(373, ey), r: 6, stroke: nil, fill: failFill))
        o.append(.text("E-stop", at: Pt(358, ey - 22), size: 9.5, bold: true, color: blue, align: .center))
        // the water over everything it reaches
        if wet {
            o.append(.rect(Box(x0, wy, x1 - x0, g - wy), stroke: nil, fill: water))
            let wave = stride(from: x0, through: x1, by: 2).map { x in Pt(x, wy - 1.5 * sin(2 * Double.pi * (x - x0) / 16)) }
            o.append(.polyline(wave, width: 1.8, color: blue, dash: flooded ? [] : [6, 4]))
        }
        // ground
        o.append(.rect(Box(0, g, width, 36), stroke: nil, fill: groundFill))
        o.append(.hatch(Box(0, g, width, 36), color: RGBA(hex: 0xB9AB95), spacing: 10))
        o.append(.line(Pt(0, g), Pt(width, g), width: 2, color: frame))
        // minimum install level
        o.append(.line(Pt(x0, my), Pt(x1, my), width: 1.8, color: teal, dash: [14, 4, 3, 4]))
        // dimensions: the inverter's mount over the floor, the freeboard over the water
        if mount > 0 {
            o.append(.line(Pt(182, fy), Pt(182, mountY), width: 1, color: ink))
            o.append(.line(Pt(176, mountY), Pt(196, mountY), width: 1, color: ink, dash: [2, 2]))
            ticks(182, [fy, mountY], ink)
            halo(FloodCheck.cmText(mount), Pt(176, (fy + mountY) / 2), size: 10.5, bold: false, color: ink, align: .center, angle: -90)
        }
        if my < wy - 0.5 {
            o.append(.line(Pt(146, wy), Pt(146, my), width: 1.2, color: teal))
            ticks(146, [wy, my], teal)
            halo("เผื่อ " + FloodCheck.cmText(r.freeboard), Pt(137, (my + wy) / 2), size: 10.5, color: teal, align: .center, angle: -90)
        }
        // the check's ✓ / ✗ on each new device
        func badge(_ c: Pt, _ id: String) {
            guard let row = r.rows.first(where: { $0.id == id }) else { return }
            let ok = !row.status.isFail
            o.append(.circle(c, r: 9, stroke: .white, fill: ok ? passFill : failFill, width: 2))
            if ok {
                o.append(.polyline([Pt(c.x - 4, c.y), Pt(c.x - 1.2, c.y + 3), Pt(c.x + 4, c.y - 3)], width: 2, color: .white))
            } else {
                o.append(.line(Pt(c.x - 3.2, c.y - 3.2), Pt(c.x + 3.2, c.y + 3.2), width: 2, color: .white))
                o.append(.line(Pt(c.x + 3.2, c.y - 3.2), Pt(c.x - 3.2, c.y + 3.2), width: 2, color: .white))
            }
        }
        badge(Pt(256, invTop), "inv")
        badge(Pt(318, smdbTop), "smdb")
        badge(Pt(384, ey - 13), "emg")
        // level tags, bottom up, each kept clear of the one below
        var tags: [(kind: TagKind, y: Double)] = [(.ground, g)]
        if floor > 0 { tags.append((.floor, fy)) }
        if wet { tags.append((.water, wy)) }
        tags.append((.minimum, my))
        let order: [TagKind] = [.ground, .floor, .water, .minimum]
        tags.sort { $0.y != $1.y ? $0.y > $1.y : order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
        var placed: [Double] = []
        for t in tags {
            let ty = placed.last.map { min(t.y, $0 - 24) } ?? t.y
            let below = placed.last
            placed.append(ty)
            switch t.kind {
            case .ground:
                o.append(pill(Box(434, g - 10, 58, 20), fill: frame))
                o.append(.text("±0.00", at: Pt(463, g), size: 11.5, bold: true, color: .white, align: .center))
                halo(v.choice("floodRef") ?? "ดินเดิม", Pt(434, g + 22), size: 10.5, bold: false, color: frame, bg: groundFill)
            case .floor:
                o.append(.line(Pt(x1, t.y), Pt(434, ty), width: 1.4, color: frame))
                o.append(pill(Box(434, ty - 10, 58, 20), fill: .white, stroke: frame, width: 1.2))
                o.append(.text(metres(floor), at: Pt(463, ty), size: 11.5, bold: true, color: ink, align: .center))
                let roomBelow = (below ?? g) - ty >= 46
                halo("พื้นห้อง INV", Pt(434, roomBelow ? ty + 20 : ty - 18), size: 10.5, color: frame)
            case .water:
                o.append(.line(Pt(x1, t.y), Pt(434, ty), width: 1.4, color: blue))
                o.append(pill(Box(434, ty - 11, 74, 22), fill: blue, stroke: .white, width: 2))
                o.append(.polyline([Pt(444, ty - 3), Pt(447, ty - 6), Pt(450, ty - 3)], width: 1.6, color: .white))
                o.append(.polyline([Pt(444, ty + 3), Pt(447, ty + 6), Pt(450, ty + 3)], width: 1.6, color: .white))
                o.append(.text(metres(lvl), at: Pt(480, ty), size: 11.5, bold: true, color: .white, align: .center))
                let year = v.text("floodYear").trimmingCharacters(in: .whitespaces)
                let caption = flooded ? "น้ำสูงสุด" + (year.isEmpty ? "" : " " + year) : "ประเมิน GISTDA"
                let roomBelow = (below ?? g) - ty >= 46
                halo(caption, Pt(434, roomBelow ? ty + 21 : ty - 20), size: 10.5, color: blue)
            case .minimum:
                o.append(.line(Pt(x1, t.y), Pt(434, ty), width: 1.4, color: teal))
                o.append(pill(Box(434, ty - 10, 58, 20), fill: teal))
                o.append(.text(metres(minCm), at: Pt(463, ty), size: 11.5, bold: true, color: .white, align: .center))
                halo("ติดตั้งต่ำสุด", Pt(434, ty - 18), size: 10.5, color: teal)
            }
        }
        // legend
        o.append(.rect(Box(44, 10, 10, 10), stroke: nil, fill: bandFill))
        o.append(.hatch(Box(44, 10, 10, 10), color: bandHatch, spacing: 4))
        o.append(.rect(Box(44, 10, 10, 10), stroke: teal, fill: nil, width: 0.8))
        o.append(.text("ระยะเผื่อ", at: Pt(58, 15), size: 10.5, color: frame))
        if wet {
            o.append(.rect(Box(112, 10, 10, 10), stroke: blue, fill: water, width: 0.8))
            o.append(.text("น้ำท่วม", at: Pt(126, 15), size: 10.5, color: frame))
        }
        return Sketch(width: width, height: height, ops: o)
    }
}
