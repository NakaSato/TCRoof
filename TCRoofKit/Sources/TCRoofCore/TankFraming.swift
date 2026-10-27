import Foundation

/// The tank roof's beam plan in D1's DXF (แปลนคานหลังคาถัง / ROOF BEAM PLAN), after the team's
/// `docs/specs/cad-export-dxf/reference/Tank_Truss.dxf` (a 40 × 24 m tank on a 4.00 m grid): on the grid's centre lines a
/// B1 on the perimeter wall line and a B2 on every interior line, 0.20 m wide, marked on every span, with the grid's
/// bubbles, the span chains and overall sizes as live DIMENSIONs, the beam schedule and its notes. Drawn from the tank's
/// own spans, so any rectangular tank gets its plan; a round tank (ring beams) has none.
public enum TankFraming {
    /// The beams' width on plan (m), as the team's reference draws B1 and B2.
    public static let beamWidth = 0.20

    /// One span of one beam: its mark (B1 on the perimeter, B2 inside), the axis it runs along, its grid line (an index
    /// into the other axis' lines: a letter line for a beam along x, a number line for one along y) and its span.
    public struct Beam: Hashable, Sendable {
        public var mark: String
        public var along: Roof.Axis
        public var line: Int
        public var span: Int
        public var length: Double
    }

    /// Every beam span on a grid of spans `x` (across, lines 1, 2, 3 …) and `y` (down, lines A, B, C …).
    public static func beams(x: [Double], y: [Double]) -> [Beam] {
        guard !x.isEmpty, !y.isEmpty else { return [] }
        var out: [Beam] = []
        for j in 0...y.count {
            for (i, s) in x.enumerated() { out.append(Beam(mark: j == 0 || j == y.count ? "B1" : "B2", along: .x, line: j, span: i, length: s)) }
        }
        for i in 0...x.count {
            for (j, s) in y.enumerated() { out.append(Beam(mark: i == 0 || i == x.count ? "B1" : "B2", along: .y, line: i, span: j, length: s)) }
        }
        return out
    }

    /// A row of the beam schedule: the mark, where it runs, its spans and their length centre to centre (m).
    public struct Row: Hashable, Sendable {
        public var mark: String
        public var location: String
        public var spans: Int
        public var length: Double
    }
    public static func schedule(_ beams: [Beam]) -> [Row] {
        [("B1", "คานขอบ บนแนวผนังถัง / Perimeter, on the walls"), ("B2", "คานภายใน ตามแนวกริด / Interior, on the grid lines")]
            .compactMap { mark, location in
                let b = beams.filter { $0.mark == mark }
                return b.isEmpty ? nil : Row(mark: mark, location: location, spans: b.count, length: b.map(\.length).reduce(0, +))
            }
    }

    /// Text sizes (m) and the grid's reach past the beams and its bubbles' radius.
    static let markH = 0.25, dimH = 0.24, reach = 1.2, bubbleR = 0.35

    /// Draws the plan with the tank's top-left grid crossing (line 1 × line A) at `o` in DXF metres (Y up), and its
    /// schedule to the right; nil for a round tank or a tank without spans, else the plan's right edge.
    @discardableResult
    static func draw(_ dxf: inout SketchDXF, _ v: Values, origin o: (Double, Double)) -> Double? {
        guard !Tank.isRound(v) else { return nil }
        let s = Tank.spans(v)
        guard !s.x.isEmpty, !s.y.isEmpty else { return nil }
        let xs = s.x.reduce(into: [0.0]) { $0.append($0.last! + $1) }, ys = s.y.reduce(into: [0.0]) { $0.append($0.last! + $1) }
        let W = xs.last!, H = ys.last!, h = beamWidth / 2
        // tank metres (y down from line A) → DXF
        func p(_ x: Double, _ y: Double) -> (Double, Double) { (o.0 + x, o.1 - y) }
        let beam = CADLayers.tankBeamPlan

        // the perimeter's outer edge in one piece; every other edge runs between the faces of the beams crossing it
        dxf.polyline(beam, [p(-h, -h), p(W + h, -h), p(W + h, H + h), p(-h, H + h)], closed: true)
        for (j, y) in ys.enumerated() {
            let sides = j == 0 ? [h] : j == ys.count - 1 ? [-h] : [-h, h]
            for (a, b) in zip(xs, xs.dropFirst()) { for d in sides { dxf.line(beam, p(a + h, y + d), p(b - h, y + d)) } }
        }
        for (i, x) in xs.enumerated() {
            let sides = i == 0 ? [h] : i == xs.count - 1 ? [-h] : [-h, h]
            for (a, b) in zip(ys, ys.dropFirst()) { for d in sides { dxf.line(beam, p(x + d, a + h), p(x + d, b - h)) } }
        }

        // the marks: on each span's middle, beside the beam towards the inside of the tank, along the beam
        for b in beams(x: s.x, y: s.y) {
            let off = h + 0.08 + markH / 2
            if b.along == .x {
                let x = (xs[b.span] + xs[b.span + 1]) / 2, y = ys[b.line] + (b.line == ys.count - 1 ? -off : off)
                dxf.text(CADLayers.text, p(x, y), height: markH, b.mark, align: .center, middle: true)
            } else {
                let y = (ys[b.span] + ys[b.span + 1]) / 2, x = xs[b.line] + (b.line == xs.count - 1 ? -off : off)
                dxf.text(CADLayers.text, p(x, y), height: markH, b.mark, align: .center, middle: true, angle: 90)
            }
        }

        // the grid: centre lines past the beams with a bubble at both ends
        let r = bubbleR, e = h + reach
        for (i, x) in xs.enumerated() {
            dxf.line(CADLayers.grid, p(x, -e), p(x, H + e))
            for y in [-e - r, H + e + r] { TankDXF.bubble(&dxf, p(x, y), r: r, Roof.gridName(.x, i)) }
        }
        for (j, y) in ys.enumerated() {
            dxf.line(CADLayers.grid, p(-e, y), p(W + e, y))
            for x in [-e - r, W + e + r] { TankDXF.bubble(&dxf, p(x, y), r: r, Roof.gridName(.y, j)) }
        }

        // the span chains past the top bubbles and the left ones, then the overall sizes
        let top = -e - 2 * r - 0.6, left = -e - 2 * r - 0.6
        for (a, b) in zip(xs, xs.dropFirst()) {
            dxf.dimension(CADLayers.dim, p(a, -e), p(b, -e), at: p(0, top), vertical: false, text: String(format: "%.2f", b - a), height: dimH)
        }
        dxf.dimension(CADLayers.dim, p(0, -e), p(W, -e), at: p(0, top - 0.7), vertical: false, text: String(format: "%.2f", W), height: dimH)
        for (a, b) in zip(ys, ys.dropFirst()) {
            dxf.dimension(CADLayers.dim, p(-e, a), p(-e, b), at: p(left, 0), vertical: true, text: String(format: "%.2f", b - a), height: dimH)
        }
        dxf.dimension(CADLayers.dim, p(-e, 0), p(-e, H), at: p(left - 0.7, 0), vertical: true, text: String(format: "%.2f", H), height: dimH)

        // the title under the bottom bubbles
        let ty = H + e + 2 * r + 1.0
        dxf.text(CADLayers.text, p(0, ty), height: 0.5, "แปลนคานหลังคาถัง / ROOF BEAM PLAN")
        dxf.text(CADLayers.text, p(0, ty + 0.75), height: 0.28,
                 String(format: "คาน B1 / B2 กว้าง %.2f ม. บนเส้นศูนย์กลางกริด | หน่วย ม. | ", beamWidth) + TankDrawings.note)

        // the schedule right of the plan
        let right = W + e + 2 * r + 1.5
        scheduleTable(&dxf, schedule(beams(x: s.x, y: s.y)), at: p(right, -e))
        return p(right, 0).0 + scheduleWidth
    }

    static let scheduleCols: [Double] = [0, 1.4, 9.0, 11.6, 13.4, 15.6]
    static var scheduleWidth: Double { scheduleCols.last! }

    /// BEAM SCHEDULE: mark, location, size (width × depth: the depth is the tank's drawings'), spans and total length,
    /// the total, and the notes under it; `o` its top-left corner.
    static func scheduleTable(_ dxf: inout SketchDXF, _ rows: [Row], at o: (Double, Double)) {
        let L = CADLayers.roofTable, cols = scheduleCols, rh = 0.5, th = 0.22, w = scheduleWidth
        dxf.text(CADLayers.text, (o.0, o.1 + 0.35), height: 0.32, "ตารางคาน / BEAM SCHEDULE")
        let head = ["คาน", "ตำแหน่ง / Location", "ขนาด ก × ล (ม.)", "จำนวนช่วง", "ยาวรวม (ม.)"]
        let size = String(format: "%.2f × ตามแบบ", beamWidth)
        let body = rows.map { [$0.mark, $0.location, size, "\($0.spans)", String(format: "%.2f", $0.length)] }
        let total = ["", "รวม / Total", "", "\(rows.map(\.spans).reduce(0, +))", String(format: "%.2f", rows.map(\.length).reduce(0, +))]
        let all = [head] + body + [total]
        for (r, cells) in all.enumerated() {
            let y = o.1 - Double(r) * rh
            dxf.line(L, (o.0, y), (o.0 + w, y))
            for (c, s) in cells.enumerated() where !s.isEmpty {
                dxf.text(L, (o.0 + cols[c] + 0.1, y - rh / 2), height: th, s, align: .left, middle: true)
            }
        }
        let bottom = o.1 - Double(all.count) * rh
        dxf.line(L, (o.0, bottom), (o.0 + w, bottom))
        for x in cols { dxf.line(L, (o.0 + x, o.1), (o.0 + x, bottom)) }
        let notes = [
            "หมายเหตุ / Notes",
            "1. คานเดิมของหลังคาถัง (อยู่ใต้พื้นหลังคา) / Existing beams of the tank roof, under the roof slab.",
            "2. ความยาวคิดจากศูนย์กลางกริดถึงศูนย์กลางกริด / Lengths centre to centre of the grid.",
            "3. ความลึกคานและเหล็กเสริมตามแบบก่อสร้างถัง ตรวจสอบที่หน้างาน / Depth and reinforcement per the tank's drawings; verify on site.",
        ]
        for (i, n) in notes.enumerated() {
            dxf.text(CADLayers.text, (o.0, bottom - 0.6 - Double(i) * 0.42), height: i == 0 ? 0.26 : 0.2, n)
        }
    }
}
