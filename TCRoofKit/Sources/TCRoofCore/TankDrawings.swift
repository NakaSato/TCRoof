import Foundation

/// The tank's printed drawings beyond the plan (docs/specs/tank-drawing-swift.md §4.3 and §5,
/// docs/specs/tank-mounting-layout.md §5): the panel layout on the full plan, the tank sections 1–1 and 2–2, and the
/// standard side section of two table rows. Each is a `Sketch` for the PDF; nil when the tank has no size.
public enum TankDrawings {
    static let ink = RGBA(hex: 0x111111), muted = RGBA(hex: 0x6B7280), navy = RGBA(hex: 0x16325C), dim = RGBA(hex: 0x1D4ED8)
    static let concrete = RGBA(hex: 0xC9CED6), soil = RGBA(hex: 0x8B6F47), panel = RGBA(hex: 0x1F4F8F), cut = RGBA(hex: 0xE0433A)
    static let post = RGBA(hex: 0x334155), vent = RGBA(hex: 0xB42318), ok = RGBA(hex: 0x2E7D32), shade = RGBA(hex: 0xF59E0B)

    // MARK: shade heat map

    /// The heat map colours: no shade, up to 25 %, up to 50 %, 50 % and over, night.
    public static let heatColours = [RGBA(hex: 0xDCFCE7), RGBA(hex: 0xFDE68A), RGBA(hex: 0xFB923C), RGBA(hex: 0xDC2626), RGBA(hex: 0x334155)]
    public static func heatColour(_ share: Double?) -> RGBA {
        guard let s = share else { return heatColours[4] }
        return s < 0.005 ? heatColours[0] : s <= 0.25 ? heatColours[1] : s < 0.5 ? heatColours[2] : heatColours[3]
    }
    static let months = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."]

    /// `สัดส่วนแผงที่โดนเงา รายเดือน × รายชั่วโมง`: months down, hours 06–18 across, with the legend.
    public static func heatMap(_ s: TankShade, width W: Double = 760) -> Sketch {
        let hours = Array(6...18), left = 46.0, top = 30.0, cellH = 13.0
        let cellW = (W - left - 16) / Double(hours.count), h = top + 12 * cellH + 44
        var o: [DrawOp] = [.rect(Box(0, 0, W, h), stroke: nil, fill: .white)]
        o.append(.text("สัดส่วนแผงที่โดนเงา รายเดือน × รายชั่วโมง", at: Pt(16, 12), size: 11, bold: true, color: ink))
        for (j, hr) in hours.enumerated() {
            o.append(.text(String(format: "%02d", hr), at: Pt(left + (Double(j) + 0.5) * cellW, top - 7), size: 8, color: muted, align: .center))
        }
        for m in 0..<12 {
            let y = top + Double(m) * cellH
            o.append(.text(months[m], at: Pt(left - 6, y + cellH / 2), size: 8, color: muted, align: .right))
            for (j, hr) in hours.enumerated() {
                o.append(.rect(Box(left + Double(j) * cellW, y, cellW - 1, cellH - 1), stroke: nil, fill: heatColour(s.heat[m][hr])))
            }
        }
        var x = left, ly = top + 12 * cellH + 16
        for (i, t) in ["ไม่มีเงา", "เงา ≤ 25%", "เงา 25–50%", "เงา ≥ 50%", "กลางคืน"].enumerated() {
            o.append(.rect(Box(x, ly - 5, 12, 10), stroke: RGBA(hex: 0xCBD5E1), fill: heatColours[i], width: 0.5))
            o.append(.text(t, at: Pt(x + 16, ly), size: 8.5, color: ink)); x += 16 + ApproxText.width(t, size: 8.5) + 18
        }
        o.append(.text("แดดจัดเต็มท้องฟ้า (ค่าสมมติ) | แผงที่โดนเงาเสียแดดตรง เก็บแสงกระจาย", at: Pt(16, h - 8), size: 8, color: muted))
        return Sketch(width: W, height: h, ops: o)
    }

    /// Wall and slab thickness and the soil over a buried tank, assumed (ค่าสมมติ).
    public static let wall = 0.30, cover = 0.50, column = 0.40

    // MARK: layout plan

    /// The full tank plan with the stored layout over it: panels (dashed when switched off), cut columns in red, the
    /// post footings, and a slope tag towards the wall the panels face. `shaded` panels (a shade snapshot) are orange.
    public static func layoutPlan(_ v: Values, _ l: TankLayout, width: Double = 690, shaded: Set<String> = []) -> Sketch? {
        guard let plan = TankPlan(v, width: width) else { return nil }
        var o = plan.sketch.ops
        let f = plan.frame
        func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Box { Box(f.ox + x * f.k, f.oy + y * f.k, w * f.k, h * f.k) }
        for t in l.tables {
            for p in t.panels {
                let b = box(p.x, p.y, p.w, p.h)
                if p.on { o.append(.rect(b, stroke: .white, fill: shaded.contains(p.key) ? shade : panel.withAlpha(0.88), width: 0.4)) }
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
        let wall = (l.circle == nil ? ["ผนังล่าง", "ผนังขวา", "ผนังบน", "ผนังซ้าย"] : ["ล่างของแปลน", "ขวาของแปลน", "บนของแปลน", "ซ้ายของแปลน"])[l.turn]
        let d = [Pt(0, 1), Pt(1, 0), Pt(0, -1), Pt(-1, 0)][l.turn]
        let c = Pt(f.ox + 18, f.oy + l.size.h * f.k + 34)
        o.append(.line(Pt(c.x - d.x * 9, c.y - d.y * 9), Pt(c.x + d.x * 9, c.y + d.y * 9), width: 1.6, color: navy))
        let tip = Pt(c.x + d.x * 9, c.y + d.y * 9), n = Pt(-d.y * 4, d.x * 4)
        o.append(.polygon([Pt(tip.x + d.x * 5, tip.y + d.y * 5), Pt(tip.x + n.x, tip.y + n.y), Pt(tip.x - n.x, tip.y - n.y)], stroke: nil, fill: navy))
        o.append(.text("แผงลาดลงด้าน" + wall + String(format: " | เอียง %.1f°", l.params.tilt), at: Pt(c.x + 18, c.y), size: 9, bold: true, color: navy))
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
        // a round tank (one span of D each way): cut through the centre, across the diameter
        let title = Tank.isRound(v) ? name + " | ตัดผ่านศูนย์กลาง" + String(format: " | Ø %@ ม.", fmt(L))
            : name + " | ตัดที่กึ่งกลาง" + (across ? "แนว A…" : "แนว 1…") + String(format: " | ยาว %@ ม.", fmt(L))
        o.append(.text(title, at: Pt(16, 16), size: 12, bold: true, color: ink))
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
        dimH(X(0), X(L), baseY + t + 16, (Tank.isRound(v) ? "Ø " : "") + fmt(L))
        dimV(X(L) + t + 2 * k + 8, roofY, baseY, "สูง " + fmt(H), right: true)
        if partly { dimV(X(0) - t - 2 * k - 8, roofY, groundY, "พ้นดิน " + String(format: "%.2f", min(H, max(0, exposed))), right: false) }
        if buried { dimV(X(0) - t - 2 * k - 8, roofY - cover * k, roofY, "ดินถม " + String(format: "%.2f", cover), right: false) }
        // the size and volume summary (§5.5), the assumed thicknesses and the note every drawing sheet carries
        if let sum = Tank.summary(v) {
            o.append(.text(sum.text, at: Pt(16, baseY + t + 40), size: 9, bold: true, color: ink))
        }
        o.append(.text(String(format: "ผนังและพื้น %.2f ม.", wall) + (buried ? String(format: " | ดินถมบนหลังคา %.2f ม.", cover) : "") + " (ค่าสมมติ) | "
                       + note, at: Pt(16, baseY + t + 53), size: 8, color: muted))
        let h = baseY + t + 64
        return Sketch(width: W, height: h, ops: [.rect(Box(0, 0, W, h), stroke: nil, fill: .white)] + o)
    }

    /// The note every drawing sheet carries (docs/specs/auto-drawing.md §1).
    public static let note = "สร้างอัตโนมัติจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง"

    // MARK: table rows

    /// The standard side section of two rows (§5): the roof slab, footings, front and back posts with their heights, a
    /// brace, the two modules down the slope, the spacings 2.80 / 2.70 / 2.80 and a vent under the first row with its
    /// clearance. Drawn from the layout's parameters.
    public static func tableSection(_ p: TankLayout.Params, width W: Double = 760) -> Sketch {
        let h0 = 272.0
        var o: [DrawOp] = [.rect(Box(0, 0, W, h0), stroke: nil, fill: .white)]
        o.append(.text("รูปตัดแถวแผงบนหลังคาถัง (มาตรฐาน) | หน่วย ม.", at: Pt(16, 16), size: 12, bold: true, color: ink))
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
        let vx = 0.55, vw = TankPoints.ventSize
        let under = p.hFront + (vx + vw) * p.tanT, room = under - p.ventH
        o.append(.rect(Box(X(vx), Y(p.ventH), vw * k, p.ventH * k), stroke: vent, fill: vent.withAlpha(0.12), width: 1))
        o.append(.text(String(format: "ปล่อง %.2f", p.ventH), at: Pt(X(vx + vw) + 4, Y(p.ventH * 0.4)), size: 8.5, color: vent))
        o.append(.text(String(format: "ปล่องระบายอยู่ใต้แผงได้เมื่อเหลือช่องว่าง ≥ %.2f ม. (ในรูป %.2f ม.)", p.underClear, room), at: Pt(16, h0 - 24),
                       size: 8.5, color: room >= p.underClear ? ok : vent))
        o.append(.text(String(format: "ฐานราก %.0f×%.0f×150 มม. ยึดพื้นหลังคา | ค้ำ X ทุกช่วงเสา | ราง 4 เส้นต่อโต๊ะ | แผง 2 แผงตามแนวลาด",
                              p.footing * 1000, p.footing * 1000), at: Pt(16, h0 - 10), size: 8.5, color: muted))
        return Sketch(width: W, height: h0, ops: o)
    }
}

// MARK: - Front elevation

extension TankDrawings {
    /// The front elevation of one table (docs/specs/tank-mounting-layout.md §5), seen from the low side: the slab,
    /// footings, front posts with the back posts behind, X bracing in every bay, the 4 rails, the modules (those
    /// switched off as outlines), the bay spacings, the cantilevers and the length. The longest built table; nil
    /// without one.
    public static func tableFront(_ l: TankLayout, width W: Double = 760) -> Sketch? {
        let p = l.params
        guard let t = l.builtTables.max(by: { $0.columns < $1.columns }) else { return nil }
        let fr = TankLayout.Frame(q: l.turn, W: l.size.w, H: l.size.h)
        func along(_ x: Double, _ y: Double) -> Double { fr.to(x, y).0 }
        // the table's west end in the layout frame, and its posts' places along it
        let ends = t.panels.flatMap { [along($0.x, $0.y), along($0.x + $0.w, $0.y + $0.h)] }
        let a = ends.min() ?? 0, L = p.width(t.columns)
        let xs = stride(from: 0, to: t.posts.count, by: 2).map { along(t.posts[$0].x, t.posts[$0].y) - a }.sorted()
        let ya = p.hFront - p.frontIn * p.tanT, yb = ya + p.depth * p.tanT
        let k = min((W - 80) / L, 120 / (p.hBack + 0.3))
        let x0 = (W - L * k) / 2, roofY = 44 + (yb + 0.2) * k
        let h0 = roofY + 78
        func X(_ m: Double) -> Double { x0 + m * k }
        func Y(_ m: Double) -> Double { roofY - m * k }
        var o: [DrawOp] = [.rect(Box(0, 0, W, h0), stroke: nil, fill: .white)]
        o.append(.text("รูปด้านหน้าโต๊ะแผง แถว \(t.row + 1) | \(t.columns) คอลัมน์ × 2 แผง | หน่วย ม.", at: Pt(16, 16), size: 12, bold: true, color: ink))
        // slab
        o.append(.rect(Box(X(-0.6), roofY, (L + 1.2) * k, 7), stroke: ink, fill: concrete, width: 0.8))
        // posts: the back one behind, lighter; footings
        let fw = max(3, p.footing * k)
        for x in xs {
            o.append(.rect(Box(X(x) - fw / 2, roofY - max(2, 0.15 * k), fw, max(2, 0.15 * k)), stroke: ink, fill: concrete, width: 0.6))
            o.append(.line(Pt(X(x), roofY), Pt(X(x), Y(p.hBack)), width: 1.2, color: post.withAlpha(0.45)))
            o.append(.line(Pt(X(x), roofY), Pt(X(x), Y(p.hFront)), width: 2, color: post))
        }
        // X bracing in every bay
        for (x1, x2) in zip(xs, xs.dropFirst()) {
            o.append(.line(Pt(X(x1), Y(0.15)), Pt(X(x2), Y(p.hFront - 0.1)), width: 0.7, color: post, dash: [4, 2]))
            o.append(.line(Pt(X(x1), Y(p.hFront - 0.1)), Pt(X(x2), Y(0.15)), width: 0.7, color: post, dash: [4, 2]))
        }
        // modules: lower and upper, seen from the front; off panels as outlines
        let on = Set(t.panels.filter(\.on).map(\.key)), mid = ya + (p.cellH + p.moduleGap * p.cosT / 2) * p.tanT
        for c in 0..<t.columns {
            let cx = Double(c) * (p.cellW + p.moduleGap)
            for (k2, lo, hi) in [(1, ya, mid), (0, mid, yb)] {
                let key = "\(t.row).\(t.index).\(c).\(k2)", lit = on.contains(key)
                o.append(.rect(Box(X(cx), Y(hi), p.cellW * k, (hi - lo) * k), stroke: lit ? .white : panel,
                               fill: lit ? panel : nil, width: lit ? 0.6 : 0.8))
            }
        }
        // the 4 rails, two under each module, the length of the table
        for f in [0.125, 0.375, 0.625, 0.875] {
            let y = ya + f * p.depth * p.tanT
            o.append(.line(Pt(X(0), Y(y)), Pt(X(L), Y(y)), width: 0.9, color: RGBA(hex: 0x94A3B8)))
        }
        // dimensions: the cantilevers and bays, then the length
        func dimH(_ a: Double, _ b: Double, _ y: Double, _ label: String) {
            o.append(.line(Pt(X(a), y), Pt(X(b), y), width: 0.8, color: dim))
            for x in [a, b] { o.append(.line(Pt(X(x), y - 4), Pt(X(x), y + 4), width: 0.8, color: dim)) }
            if (b - a) * k >= 18 { o.append(.text(label, at: Pt((X(a) + X(b)) / 2, y + 9), size: 8.5, bold: true, color: dim, align: .center)) }
        }
        let marks = [0.0] + xs + [L]
        for (u, w) in zip(marks, marks.dropFirst()) where w - u > 1e-6 { dimH(u, w, roofY + 26, String(format: "%.2f", w - u)) }
        dimH(0, L, roofY + 48, String(format: "ยาว %.2f", L))
        o.append(.text(String(format: "%.2f", p.hFront), at: Pt(X(0) - 6, Y(p.hFront / 2)), size: 9, bold: true, color: dim, align: .right))
        let bays = zip(xs, xs.dropFirst()).map { $1 - $0 }
        o.append(.text(String(format: "เสา %d คู่ (หน้า %.2f / หลัง %.2f ม.) | ช่วงเสามากสุด %.2f ม. | ค้ำ X ทุกช่วงเสา แนวหน้าและแนวหลัง | ราง 4 เส้น | ฐานราก %.0f×%.0f×150 มม. ทุกเสา",
                              xs.count, p.hFront, p.hBack, bays.max() ?? 0, p.footing * 1000, p.footing * 1000),
                       at: Pt(16, h0 - 10), size: 8.5, color: muted))
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

    /// kWh per kWp per year at the panels' tilt and facing (`PlaneYield`: the hourly engine with a longitude near the
    /// bundled weather, else `SolarModel`); south facing when the tank has no azimuth.
    public func yield(latitude: Double, longitude: Double? = nil, facing: Double?) -> Double {
        let fromSouth = facing.map { ($0 - 180 + 540).truncatingRemainder(dividingBy: 360) - 180 } ?? 0
        return PlaneYield.kWhPerKWp(latitude: latitude, longitude: longitude, tilt: params.tilt, azimuthFromSouth: fromSouth)
    }

    /// `ผังแผงอัตโนมัติ 410 แผง | 233.7 kWp | 340.2 MWh/ปี | 13 โต๊ะ | 7 แถว | เอียง 19.7°`
    public func summaryLine(latitude: Double, longitude: Double? = nil, facing: Double?) -> String {
        let e = kWp * yield(latitude: latitude, longitude: longitude, facing: facing) / 1000
        return "ผังแผงอัตโนมัติ \(count) แผง | " + String(format: "%.1f kWp | %.1f MWh/ปี | ", kWp, e)
            + "\(builtTables.count) โต๊ะ | \(rows) แถว | " + String(format: "เอียง %.1f°", params.tilt)
            + (params.rowGap > params.standardGap + 1e-6 ? String(format: " | แถวห่าง %.2f ม.", params.rowGap) : "")
    }

    /// `BOQ: เสา 198 | ฐานราก 198 | ราง 1,234.5 ม. | ตัวยึดราง 396 | ตัวจับกลาง … | ค้ำ X … | กราวด์ 13`
    public var boqLine: String {
        let b = bom
        return String(format: "BOQ: เสา %d | ฐานราก %d | คานรับราง %d | ราง %.1f ม. | ตัวยึดราง %d | ตัวจับกลาง %d | ตัวจับปลาย %d | ค้ำ X %d | กราวด์ %d",
                      b.posts, b.footings, b.rafters, b.railLength, b.railClamps, b.midClamps, b.endClamps, b.braces, b.groundLugs)
            + (checks.cutColumns > 0 ? " | ตัดแผง \(checks.cutColumns) คอลัมน์" : "")
    }

    /// The three checks as one line.
    public var checksLine: String {
        let c = checks
        var parts: [String] = []
        parts.append(c.ventsUnder > 0 ? String(format: "ปล่องใต้แผง %d จุด เหลือ ≥ %.2f ม.", c.ventsUnder, c.ventHeadroom ?? 0) : "ไม่มีปล่องใต้แผง")
        parts.append(String(format: "ห่างขอบถัง %.2f ม.", c.edge ?? 0))
        parts.append(c.legsOK ? "ขาไม่ชนสิ่งกีดขวาง" : "ขาชนสิ่งกีดขวาง")
        return "ตรวจ \(c.passed)/3: " + parts.joined(separator: " | ")
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
