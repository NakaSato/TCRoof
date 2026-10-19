import Foundation

/// The tank's printed drawings beyond the plan (docs/specs/tank-drawing-swift.md §4.3 and §5,
/// docs/specs/tank-mounting-layout.md §5): the panel layout on the full plan, the tank sections 1–1 and 2–2, and the
/// standard side section of two table rows. Each is a `Sketch` for the PDF; nil when the tank has no size.
public enum TankDrawings {
    static let ink = RGBA(hex: 0x111111), muted = RGBA(hex: 0x6B7280), navy = RGBA(hex: 0x16325C), dim = RGBA(hex: 0x1D4ED8)
    static let concrete = RGBA(hex: 0xC9CED6), soil = RGBA(hex: 0x8B6F47), panel = RGBA(hex: 0x1F4F8F), cut = RGBA(hex: 0xE0433A)
    static let post = RGBA(hex: 0x334155), vent = RGBA(hex: 0xB42318), ok = RGBA(hex: 0x2E7D32)

    /// Wall and slab thickness and the soil over a buried tank, assumed (ค่าสมมติ).
    public static let wall = 0.30, cover = 0.50, column = 0.40

    // MARK: layout plan

    /// The full tank plan with the stored layout over it: panels (dashed when switched off), cut columns in red, the
    /// post footings, and a slope tag towards the wall the panels face.
    public static func layoutPlan(_ v: Values, _ l: TankLayout, width: Double = 690) -> Sketch? {
        guard let plan = TankPlan(v, width: width) else { return nil }
        var o = plan.sketch.ops
        let f = plan.frame
        func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Box { Box(f.ox + x * f.k, f.oy + y * f.k, w * f.k, h * f.k) }
        for t in l.tables {
            for p in t.panels {
                let b = box(p.x, p.y, p.w, p.h)
                if p.on { o.append(.rect(b, stroke: .white, fill: panel.withAlpha(0.88), width: 0.4)) }
                else { o.append(.polyline([Pt(b.x, b.y), Pt(b.maxX, b.y), Pt(b.maxX, b.maxY), Pt(b.x, b.maxY), Pt(b.x, b.y)], width: 0.6,
                                         color: panel.withAlpha(0.6), dash: [2, 1.5])) }
            }
        }
        for c in l.cuts {
            let b = box(c.x, c.y, c.w, c.h)
            o.append(.polyline([Pt(b.x, b.y), Pt(b.maxX, b.y), Pt(b.maxX, b.maxY), Pt(b.x, b.maxY), Pt(b.x, b.y)], width: 0.9, color: cut, dash: [3, 2]))
        }
        let r = max(1.2, l.params.footing / 2 * f.k)
        for t in l.builtTables { for p in t.posts { o.append(.rect(Box(f.ox + p.x * f.k - r, f.oy + p.y * f.k - r, 2 * r, 2 * r), stroke: nil, fill: post)) } }
        // the slope tag in the bottom-left corner: an arrow towards the wall the panels face
        let wall = ["ผนังล่าง", "ผนังขวา", "ผนังบน", "ผนังซ้าย"][l.turn]
        let d = [Pt(0, 1), Pt(1, 0), Pt(0, -1), Pt(-1, 0)][l.turn]
        let c = Pt(f.ox + 18, f.oy + l.size.h * f.k + 34)
        o.append(.line(Pt(c.x - d.x * 9, c.y - d.y * 9), Pt(c.x + d.x * 9, c.y + d.y * 9), width: 1.6, color: navy))
        let tip = Pt(c.x + d.x * 9, c.y + d.y * 9), n = Pt(-d.y * 4, d.x * 4)
        o.append(.polygon([Pt(tip.x + d.x * 5, tip.y + d.y * 5), Pt(tip.x + n.x, tip.y + n.y), Pt(tip.x - n.x, tip.y - n.y)], stroke: nil, fill: navy))
        o.append(.text("แผงลาดลงด้าน" + wall + String(format: " · เอียง %.1f°", l.params.tilt), at: Pt(c.x + 18, c.y), size: 9, bold: true, color: navy))
        return Sketch(width: plan.sketch.width, height: plan.sketch.height, ops: o)
    }

    // MARK: tank sections

    /// Section 1–1 (`across` false: cut at half of Σ spansX, the tank across Σ spansY) or 2–2 (`across` true: cut at
    /// half of Σ spansY, across Σ spansX). The ground follows the position: at the base above ground, 0.50 m of soil
    /// over the roof when buried, at H − exposed when partly buried. nil without a size; without a height it says so.
    public static func section(_ v: Values, across: Bool, width W: Double = 760) -> Sketch? {
        let s = Tank.spans(v)
        guard !s.x.isEmpty, !s.y.isEmpty else { return nil }
        let spans = across ? s.x : s.y, L = spans.reduce(0, +)
        let name = across ? "รูปตัด 2–2" : "รูปตัด 1–1"
        var o: [DrawOp] = []
        o.append(.text(name + " · ตัดที่กึ่งกลาง" + (across ? "แนว A…" : "แนว 1…") + String(format: " · ยาว %@ ม.", fmt(L)), at: Pt(16, 16),
                       size: 12, bold: true, color: ink))
        guard let H = Tank.height(v), H > 0 else {
            o.append(.text("ใส่ความสูงถังเพื่อวาดรูปตัด", at: Pt(W / 2, 60), size: 13, color: muted, align: .center))
            return Sketch(width: W, height: 90, ops: [.rect(Box(0, 0, W, 90), stroke: nil, fill: .white)] + o)
        }
        let pos = Tank.position(v), exposed = Tank.exposed(v) ?? H
        let buried = pos == Tank.buried, partly = pos == Tank.partly
        let soilTop = buried ? H + cover : partly ? H - min(H, max(0, exposed)) : 0
        let topPad = 44.0, side = 70.0
        let k = min((W - 2 * side) / (L + 4), 150 / (H + (buried ? cover : 0) + 0.6))
        let x0 = (W - L * k) / 2, roofY = topPad + (buried ? cover * k : 0) + 8, baseY = roofY + H * k
        func X(_ m: Double) -> Double { x0 + m * k }
        let t = max(3, wall * k)
        // soil: beside the walls up to the ground line, and over the roof when buried
        let groundY = baseY - soilTop * k + (buried ? 0 : 0)
        if soilTop > 0 {
            let gy = buried ? roofY - cover * k : groundY
            for b in [Box(X(-2), gy, 2 * k - t, baseY + t - gy), Box(X(L) + t, gy, 2 * k - t, baseY + t - gy)] {
                o.append(.rect(b, stroke: nil, fill: soil.withAlpha(0.12))); o.append(.hatch(b, color: soil.withAlpha(0.55), spacing: 6))
            }
            if buried {
                let b = Box(X(0) - t, gy, L * k + 2 * t, cover * k)
                o.append(.rect(b, stroke: nil, fill: soil.withAlpha(0.12))); o.append(.hatch(b, color: soil.withAlpha(0.55), spacing: 6))
            }
        }
        // ground line
        let gy = soilTop > 0 ? (buried ? roofY - cover * k : groundY) : baseY + t
        o.append(.line(Pt(X(-2.4), gy), Pt(X(L) + t + 2 * k + 40, gy), width: 1.4, color: soil))
        o.append(.text("ระดับดิน", at: Pt(X(L) + t + 2 * k + 44, gy), size: 8.5, color: soil))
        // walls, roof and base slabs, columns
        let shell = [Box(X(0) - t, roofY - t, t, H * k + 2 * t), Box(X(L), roofY - t, t, H * k + 2 * t),
                     Box(X(0) - t, roofY - t, L * k + 2 * t, t), Box(X(0) - t, baseY, L * k + 2 * t, t)]
        for b in shell { o.append(.rect(b, stroke: ink, fill: concrete, width: 0.8)) }
        var at = 0.0
        for sp in spans.dropLast() {
            at += sp
            o.append(.rect(Box(X(at) - column * k / 2, roofY, max(1.5, column * k), H * k), stroke: ink, fill: concrete.withAlpha(0.7), width: 0.5))
        }
        o.append(.text("น้ำ", at: Pt(X(L / 2), (roofY + baseY) / 2), size: 10, color: muted, align: .center))
        // dimensions: length below, height on the right, the exposed part on the left when partly buried
        func dimH(_ a: Double, _ b: Double, _ y: Double, _ label: String) {
            o.append(.line(Pt(a, y), Pt(b, y), width: 0.8, color: dim))
            for x in [a, b] { o.append(.line(Pt(x, y - 4), Pt(x, y + 4), width: 0.8, color: dim)) }
            o.append(.text(label, at: Pt((a + b) / 2, y + 9), size: 9.5, bold: true, color: dim, align: .center))
        }
        func dimV(_ x: Double, _ a: Double, _ b: Double, _ label: String, right: Bool) {
            o.append(.line(Pt(x, a), Pt(x, b), width: 0.8, color: dim))
            for y in [a, b] { o.append(.line(Pt(x - 4, y), Pt(x + 4, y), width: 0.8, color: dim)) }
            o.append(.text(label, at: Pt(x + (right ? 6 : -6), (a + b) / 2), size: 9.5, bold: true, color: dim, align: right ? .left : .right))
        }
        dimH(X(0), X(L), baseY + t + 16, fmt(L))
        dimV(X(L) + t + 2 * k + 8, roofY, baseY, "สูง " + fmt(H), right: true)
        if partly { dimV(X(0) - t - 2 * k - 8, roofY, groundY, "พ้นดิน " + String(format: "%.2f", min(H, max(0, exposed))), right: false) }
        if buried { dimV(X(0) - t - 2 * k - 8, roofY - cover * k, roofY, "ดินถม " + String(format: "%.2f", cover), right: false) }
        let vol = (L + 2 * wall) * (otherLength(s, across: across) + 2 * wall) * (H + 2 * wall)
        o.append(.text(String(format: "ปริมาตรภายนอกโดยประมาณ %@ ม³ · ผนังและพื้น %.2f ม.", fmt((vol).rounded()), wall)
                       + (buried ? String(format: " · ดินถมบนหลังคา %.2f ม.", cover) : "") + " (ค่าสมมติ)",
                       at: Pt(16, baseY + t + 40), size: 8.5, color: muted))
        let h = baseY + t + 52
        return Sketch(width: W, height: h, ops: [.rect(Box(0, 0, W, h), stroke: nil, fill: .white)] + o)
    }

    static func otherLength(_ s: (x: [Double], y: [Double]), across: Bool) -> Double { (across ? s.y : s.x).reduce(0, +) }

    // MARK: table rows

    /// The standard side section of two rows (§5): the roof slab, footings, front and back posts with their heights, a
    /// brace, the two modules down the slope, the spacings 2.80 / 2.70 / 2.80 and a vent under the first row with its
    /// clearance. Drawn from the layout's parameters.
    public static func tableSection(_ p: TankLayout.Params, width W: Double = 760) -> Sketch {
        let h0 = 272.0
        var o: [DrawOp] = [.rect(Box(0, 0, W, h0), stroke: nil, fill: .white)]
        o.append(.text("รูปตัดแถวแผงบนหลังคาถัง (มาตรฐาน) · หน่วย ม.", at: Pt(16, 16), size: 12, bold: true, color: ink))
        let span = p.frontIn + 2 * p.postDY + p.rowGap + (p.depth - p.frontIn - p.postDY) + 0.8
        let k = min((W - 80) / (span + 0.4), 130 / (p.hBack + 0.8))
        let x0 = 40 + (p.frontIn + 0.4) * k, roofY = 192.0
        func X(_ m: Double) -> Double { x0 + m * k }
        func Y(_ m: Double) -> Double { roofY - m * k }
        // roof slab
        o.append(.rect(Box(X(-p.frontIn - 0.4), roofY, (span + 0.4) * k, 7), stroke: ink, fill: concrete, width: 0.8))
        o.append(.text("หลังคาถัง (พื้น ค.ส.ล.)", at: Pt(X(-p.frontIn - 0.4), roofY + 16), size: 8.5, color: muted))
        let fw = p.footing * k
        for row in 0..<2 {
            let front = Double(row) * p.rowPitch, back = front + p.postDY
            for (x, h) in [(front, p.hFront), (back, p.hBack)] {
                o.append(.rect(Box(X(x) - fw / 2, roofY - 0.15 * k, fw, 0.15 * k), stroke: ink, fill: concrete, width: 0.6))
                o.append(.line(Pt(X(x), roofY - 0.15 * k), Pt(X(x), Y(h)), width: 2.2, color: post))
            }
            o.append(.line(Pt(X(front), Y(0.2)), Pt(X(back), Y(p.hBack - 0.25)), width: 0.8, color: post, dash: [4, 2]))
            // the two modules: lower edge `frontIn` south of the front post, along the tilt
            let a = front - p.frontIn, b = a + p.depth
            let ya = p.hFront - p.frontIn * p.tanT, yb = ya + p.depth * p.tanT
            let mid = a + p.cellH + p.moduleGap * p.cosT / 2
            o.append(.line(Pt(X(a), Y(ya) - 2), Pt(X(b), Y(yb) - 2), width: 5, color: panel))
            let ym = ya + (mid - a) * p.tanT
            o.append(.line(Pt(X(mid), Y(ym) - 5), Pt(X(mid), Y(ym) + 1), width: 1.2, color: .white))
        }
        // dimensions along the roof
        func dimH(_ a: Double, _ b: Double, _ y: Double, _ label: String) {
            o.append(.line(Pt(X(a), y), Pt(X(b), y), width: 0.8, color: dim))
            for x in [a, b] { o.append(.line(Pt(X(x), y - 4), Pt(X(x), y + 4), width: 0.8, color: dim)) }
            o.append(.text(label, at: Pt((X(a) + X(b)) / 2, y + 9), size: 9.5, bold: true, color: dim, align: .center))
        }
        let dy = roofY + 34
        dimH(0, p.postDY, dy, String(format: "%.2f", p.postDY))
        dimH(p.postDY, p.rowPitch, dy, String(format: "%.2f", p.rowGap))
        dimH(p.rowPitch, p.rowPitch + p.postDY, dy, String(format: "%.2f", p.postDY))
        // post heights
        o.append(.text(String(format: "%.2f", p.hFront), at: Pt(X(0) - 5, Y(p.hFront / 2)), size: 9.5, bold: true, color: dim, align: .right))
        o.append(.text(String(format: "%.2f", p.hBack), at: Pt(X(p.postDY) + 5, Y(p.hBack / 2)), size: 9.5, bold: true, color: dim))
        o.append(.text(String(format: "เอียง %.1f°", p.tilt), at: Pt(X(p.postDY / 2), Y(p.hBack) - 14), size: 9.5, bold: true, color: navy, align: .center))
        // a vent under the back half of the first row, with the clearance left above it
        let vx = 0.55, vw = 0.6
        let under = p.hFront + (vx + vw) * p.tanT, room = under - p.ventH
        o.append(.rect(Box(X(vx), Y(p.ventH), vw * k, p.ventH * k), stroke: vent, fill: vent.withAlpha(0.12), width: 1))
        o.append(.text(String(format: "ปล่อง %.2f", p.ventH), at: Pt(X(vx + vw) + 4, Y(p.ventH * 0.4)), size: 8.5, color: vent))
        o.append(.text(String(format: "ปล่องระบายอยู่ใต้แผงได้เมื่อเหลือช่องว่าง ≥ %.2f ม. (ในรูป %.2f ม.)", p.underClear, room), at: Pt(16, h0 - 24),
                       size: 8.5, color: room >= p.underClear ? ok : vent))
        o.append(.text(String(format: "ฐานราก %.0f×%.0f×150 มม. ยึดพื้นหลังคา · ค้ำ X ทุกช่วงเสา · ราง 4 เส้นต่อโต๊ะ · แผง 2 แผงตามแนวลาด",
                              p.footing * 1000, p.footing * 1000), at: Pt(16, h0 - 10), size: 8.5, color: muted))
        return Sketch(width: W, height: h0, ops: o)
    }
}

// MARK: - Energy and report lines

extension TankLayout {
    /// The compass azimuth the panels face (the wall they slope down to), nil without a measured tank azimuth.
    public static func facing(_ v: Values) -> Double? {
        guard let az = Tank.azimuth(v) else { return nil }
        let d = [180.0, 90, 0, 270][turn(v)]
        return (Double(az) + d).truncatingRemainder(dividingBy: 360)
    }

    /// kWh per kWp per year from the roof layout's sun model (`SolarModel`), at the panels' tilt and facing; south
    /// facing when the tank has no azimuth.
    public func yield(latitude: Double, facing: Double?) -> Double {
        let fromSouth = facing.map { ($0 - 180 + 540).truncatingRemainder(dividingBy: 360) - 180 } ?? 0
        return SolarModel.yield(lat: latitude, tilt: params.tilt, azimuthFromSouth: fromSouth)
    }

    /// `ผังแผงอัตโนมัติ 410 แผง · 233.7 kWp · 340.2 MWh/ปี · 13 โต๊ะ · 7 แถว · เอียง 19.7°`
    public func summaryLine(latitude: Double, facing: Double?) -> String {
        let e = kWp * yield(latitude: latitude, facing: facing) / 1000
        return "ผังแผงอัตโนมัติ \(count) แผง · " + String(format: "%.1f kWp · %.1f MWh/ปี · ", kWp, e)
            + "\(builtTables.count) โต๊ะ · \(rows) แถว · " + String(format: "เอียง %.1f°", params.tilt)
    }

    /// `BOQ: เสา 198 · ฐานราก 198 · ราง 1,234.5 ม. · ตัวยึดราง 396 · ตัวจับกลาง … · ค้ำ X … · กราวด์ 13`
    public var boqLine: String {
        let b = bom
        return String(format: "BOQ: เสา %d · ฐานราก %d · คานรับราง %d · ราง %.1f ม. · ตัวยึดราง %d · ตัวจับกลาง %d · ตัวจับปลาย %d · ค้ำ X %d · กราวด์ %d",
                      b.posts, b.footings, b.rafters, b.railLength, b.railClamps, b.midClamps, b.endClamps, b.braces, b.groundLugs)
            + (checks.cutColumns > 0 ? " · ตัดแผง \(checks.cutColumns) คอลัมน์" : "")
    }

    /// The three checks as one line.
    public var checksLine: String {
        let c = checks
        var parts: [String] = []
        parts.append(c.ventsUnder > 0 ? String(format: "ปล่องใต้แผง %d จุด เหลือ ≥ %.2f ม.", c.ventsUnder, c.ventHeadroom ?? 0) : "ไม่มีปล่องใต้แผง")
        parts.append(String(format: "ห่างขอบถัง %.2f ม.", c.edge ?? 0))
        parts.append(c.legsOK ? "ขาไม่ชนสิ่งกีดขวาง" : "ขาชนสิ่งกีดขวาง")
        return "ตรวจ \(c.passed)/3: " + parts.joined(separator: " · ")
    }

    /// What the report assumed.
    public static func assumptions(_ v: Values, latitude: Double?) -> [String] {
        var out: [String] = []
        if latitude == nil { out.append("ละติจูด \(Int(RoofMount.defaultLatitude))° (ยังไม่มีพิกัด A1)") }
        if Tank.azimuth(v) == nil { out.append("ผนังล่างหันทิศใต้ (ยังไม่วัดทิศ)") }
        if Tank.ventHeight(v) == nil { out.append("ปล่องสูง 1.00 ม.") }
        return out
    }
}
