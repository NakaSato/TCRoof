import Foundation

/// The clear-water tank's roof plan (docs/ui/survey-d1-size), drawn for the D1 page, the PDF and the Excel plan frame:
/// grid bubbles 1… across the top and A… down the left, the double wall outline, span chains along the bottom and the
/// right with the totals, level tags, the north arrow turned by `tankAzimuth`, the obstacles, and the caption.
/// Wall A (the top wall) stays on top; only the arrow turns.
public struct TankPlan: Sendable {
    /// A span's number on a chain; the D1 page puts its tap target here.
    public struct Chip: Sendable {
        public let axis: Roof.Axis
        public let index: Int
        public let value: Double
        public let at: Pt
    }
    public let sketch: Sketch
    public let chips: [Chip]
    /// What each op of `sketch` draws, for the DXF layers: grid, out, dim, dimtxt, obst, north, txt; nil the background.
    public let tags: [String?]
    /// The tank's top-left corner on the sketch and its points per metre.
    public let frame: (ox: Double, oy: Double, k: Double)
    /// The span chains and totals (the ops tagged dim / dimtxt) as dimensions, for the DXF's DIMENSIONs.
    public let dimensions: [SketchDXF.Dimension]

    /// nil without spans. `chips` leaves the span numbers to the page (it draws them as buttons); `hints` adds the
    /// page's note about sub-step 2. `details` is the printed sheet (the PDF, the Excel picture and the DXF,
    /// docs/specs/auto-drawing.md §5.5): the beams as double dashed bands on the inner grid lines, the section marks
    /// 1–1 and 2–2 at the centre lines, the cross-shaped vents of a `cross` design, and under the caption the size and
    /// volume summary and the note that it is not a construction drawing.
    public init?(_ v: Values, width W: Double = 690, chips: Bool = false, hints: Bool = false, details: Bool = false) {
        if Tank.isRound(v) {
            // a round tank: the circle, its centre lines and the diameter (`TankPlan+Round`); no spans to tap
            guard let r = Self.round(v, width: W, hints: hints, details: details) else { return nil }
            sketch = r.sketch; self.chips = []; tags = r.tags; frame = r.frame; dimensions = r.dimensions
            return
        }
        let sx = parseSpans(v.text(Roof.Key.spansX)), sy = parseSpans(v.text(Roof.Key.spansY))
        guard !sx.isEmpty, !sy.isEmpty else { return nil }
        let TW = sx.reduce(0, +), TH = sy.reduce(0, +)
        let padL = 52.0, padT = 66.0, padR = 78.0, padB = 82.0, maxH = (W * 0.78).rounded()
        let k = min((W - padL - padR) / TW, (maxH - padT - padB) / TH), w = TW * k, h = TH * k
        let ox = padL + ((W - padL - padR) - w) / 2, oy = padT, H = (oy + h + padB).rounded()
        var xs = [0.0]; for s in sx { xs.append(xs.last! + s) }
        var ys = [0.0]; for s in sy { ys.append(ys.last! + s) }
        let minX = sx.map { $0 * k }.min() ?? 40, minY = sy.map { $0 * k }.min() ?? 40
        var o: [DrawOp] = [.rect(Box(0, 0, W, H), stroke: nil, fill: .white)]
        var tags: [String?] = [nil]
        /// Tags the ops added since the last call; text ops get `text` when given.
        func tag(_ t: String, text: String? = nil) {
            for op in o[tags.count...] { if case .text = op { tags.append(text ?? t) } else { tags.append(t) } }
        }
        let grid = RGBA(hex: 0xB9C6D6), ink = RGBA(hex: 0x111111)

        // grid lines and bubbles
        let r = min(8.5, max(4, min(minX, minY) * 0.42)), bx = ox - 34, by = oy - 32
        let dash: [Double] = [6, 3, 1.5, 3]
        for (i, x) in xs.enumerated() {
            let X = ox + x * k
            o.append(.line(Pt(X, by + r), Pt(X, oy + h), width: 0.5, color: grid, dash: dash))
            o.append(.circle(Pt(X, by), r: r, stroke: ink, fill: .white, width: 0.9))
            o.append(.text(Roof.gridName(.x, i), at: Pt(X, by), size: min(8, r * 0.95), bold: true, color: ink, align: .center))
        }
        for (j, y) in ys.enumerated() {
            let Y = oy + y * k
            o.append(.line(Pt(bx + r, Y), Pt(ox + w, Y), width: 0.5, color: grid, dash: dash))
            o.append(.circle(Pt(bx, Y), r: r, stroke: ink, fill: .white, width: 0.9))
            o.append(.text(Roof.gridName(.y, j), at: Pt(bx, Y), size: min(8, r * 0.95), bold: true, color: ink, align: .center))
        }
        tag("grid")
        // the wall: a double outline
        o.append(.rect(Box(ox, oy, w, h), stroke: ink, fill: nil, width: 1.4))
        o.append(.rect(Box(ox + 3, oy + 3, max(0, w - 6), max(0, h - 6)), stroke: ink, fill: nil, width: 0.8))

        tag("out")
        if details {
            // beams: a band 0.30 m wide (assumed) on every inner grid line, as on the กปภ. sheets
            let half = max(1.2, Self.beam / 2 * k), beam = RGBA(hex: 0x9AA8BA)
            for x in xs.dropFirst().dropLast() {
                for d in [-half, half] { o.append(.line(Pt(ox + x * k + d, oy + 3), Pt(ox + x * k + d, oy + h - 3), width: 0.4, color: beam, dash: [3, 2])) }
            }
            for y in ys.dropFirst().dropLast() {
                for d in [-half, half] { o.append(.line(Pt(ox + 3, oy + y * k + d), Pt(ox + w - 3, oy + y * k + d), width: 0.4, color: beam, dash: [3, 2])) }
            }
            tag("beam")
            o += Self.sectionMarks(ox: ox, oy: oy, w: w, h: h)
            tag("sect", text: "txt")
        }
        // level tags in the four quadrants
        if let e = v.number(Tank.Key.exposed) {
            let t = "ระดับหลังถัง +" + String(format: "%.2f", e)
            for (fx, fy) in [(0.25, 0.3), (0.75, 0.3), (0.25, 0.76), (0.75, 0.76)] {
                let p = Pt(ox + w * fx, oy + h * fy)
                o.append(.line(Pt(p.x - 34, p.y + 5), Pt(p.x + 34, p.y + 5), width: 0.5, color: .ink2))
                o.append(.text(t, at: p, size: 6.5, color: .ink2, align: .center))
            }
        }

        tag("txt")
        // obstacles (sub-step 2), as on the old plan; points marked ไม่มีจริง are left out
        let crossVents = TankDesign.current(v)?.design.ventStyle == "cross"
        for ob in v.obstacles(Roof.Key.obstacles) where !ob.isAbsent {
            guard let x = NumberInput.value(ob.x), let y = NumberInput.value(ob.y), let ow = NumberInput.value(ob.w), let oh = NumberInput.value(ob.h), ow > 0, oh > 0 else { continue }
            if TankPoints.onWall(ob.kind) {
                // a ladder or a pipe of a standard design: a small box outside its wall, as on the กปภ. sheet
                let r = TankPoints.Rect(x: x, y: y, w: ow, h: oh), c = Pt(ox + r.cx * k, oy + r.cy * k), d = 9.0
                let side = TankPoints.wall(r, w: TW, h: TH)
                let at: Pt
                switch side {
                case .top: at = Pt(c.x, oy - d)
                case .bottom: at = Pt(c.x, oy + h + d)
                case .left: at = Pt(ox - d, c.y)
                case .right: at = Pt(ox + w + d, c.y)
                }
                let flat = side == .top || side == .bottom
                let b = Box(at.x - (flat ? 3 : 5), at.y - (flat ? 5 : 3), flat ? 6 : 10, flat ? 10 : 6)
                o.append(.rect(b, stroke: .red, fill: .white, width: 0.8))
                if ob.kind == TankPoints.pipe { o.append(.line(Pt(b.x, b.y), Pt(b.maxX, b.maxY), width: 0.6, color: .red)) }
                continue
            }
            let b = Box(ox + x * k, oy + y * k, ow * k, oh * k)
            if details && crossVents && ob.kind == TankPoints.vent { o += Self.crossVent(b) }
            else { o.append(.rect(b, stroke: nil, fill: .white)); o.append(.hatch(b, color: .red)); o.append(.rect(b, stroke: .red, fill: nil, width: 1)) }
            if !ob.label.isEmpty { o.append(.text("\(ob.label) \(fmt(ow))x\(fmt(oh))", at: Pt(b.maxX + 3, b.maxY - 3), size: 8, color: .dark)) }
        }

        tag("obst", text: "txt")
        // span chains: each span along the bottom and the right, then the totals
        func tick(_ p: Pt) -> DrawOp { .line(Pt(p.x - 3, p.y + 3), Pt(p.x + 3, p.y - 3), width: 0.9, color: ink) }
        let cy = oy + h + 22, ty = cy + 22, cx = ox + w + 22, tx = cx + 22
        let fsX = min(8.5, max(5, minX / 2.8)), fsY = min(8.5, max(5, minY / 2.8))
        var chipList: [Chip] = []
        o.append(.line(Pt(ox - 4, cy), Pt(ox + w + 4, cy), width: 0.6, color: ink))
        o.append(.line(Pt(ox - 4, ty), Pt(ox + w + 4, ty), width: 0.6, color: ink))
        for x in xs { let X = ox + x * k; o.append(.line(Pt(X, oy + h + 6), Pt(X, cy + 4), width: 0.4, color: .ink2)); o.append(tick(Pt(X, cy))) }
        o.append(.line(Pt(ox, cy), Pt(ox, ty + 4), width: 0.4, color: .ink2)); o.append(.line(Pt(ox + w, cy), Pt(ox + w, ty + 4), width: 0.4, color: .ink2))
        o.append(tick(Pt(ox, ty))); o.append(tick(Pt(ox + w, ty)))
        for (i, s) in sx.enumerated() {
            let p = Pt(ox + (xs[i] + s / 2) * k, cy - 7)
            if chips { chipList.append(Chip(axis: .x, index: i, value: s, at: p)) }
            else { o.append(.text(String(format: "%.2f", s), at: p, size: fsX, color: ink, align: .center)) }
        }
        o.append(.text(String(format: "%.2f", TW), at: Pt(ox + w / 2, ty - 7), size: 9, bold: true, color: ink, align: .center))
        var dims: [SketchDXF.Dimension] = []
        for (i, s) in sx.enumerated() {
            dims.append(.init(Pt(ox + xs[i] * k, oy + h + 6), Pt(ox + xs[i + 1] * k, oy + h + 6), at: Pt(0, cy), text: String(format: "%.2f", s), size: fsX))
        }
        dims.append(.init(Pt(ox, cy), Pt(ox + w, cy), at: Pt(0, ty), text: String(format: "%.2f", TW), size: 9))
        for (j, s) in sy.enumerated() {
            dims.append(.init(Pt(ox + w + 6, oy + ys[j] * k), Pt(ox + w + 6, oy + ys[j + 1] * k), at: Pt(cx, 0), vertical: true,
                              text: String(format: "%.2f", s), size: fsY))
        }
        dims.append(.init(Pt(cx, oy), Pt(cx, oy + h), at: Pt(tx, 0), vertical: true, text: String(format: "%.2f", TH), size: 9))

        o.append(.line(Pt(cx, oy - 4), Pt(cx, oy + h + 4), width: 0.6, color: ink))
        o.append(.line(Pt(tx, oy - 4), Pt(tx, oy + h + 4), width: 0.6, color: ink))
        for y in ys { let Y = oy + y * k; o.append(.line(Pt(ox + w + 6, Y), Pt(cx + 4, Y), width: 0.4, color: .ink2)); o.append(tick(Pt(cx, Y))) }
        o.append(.line(Pt(cx, oy), Pt(tx + 4, oy), width: 0.4, color: .ink2)); o.append(.line(Pt(cx, oy + h), Pt(tx + 4, oy + h), width: 0.4, color: .ink2))
        o.append(tick(Pt(tx, oy))); o.append(tick(Pt(tx, oy + h)))
        for (j, s) in sy.enumerated() {
            let p = Pt(cx - 8, oy + (ys[j] + s / 2) * k)
            if chips { chipList.append(Chip(axis: .y, index: j, value: s, at: p)) }
            else { o.append(.text(String(format: "%.2f", s), at: p, size: fsY, color: ink, align: .center, angle: -90)) }
        }
        o.append(.text(String(format: "%.2f", TH), at: Pt(tx - 8, oy + h / 2), size: 9, bold: true, color: ink, align: .center, angle: -90))

        tag("dim", text: "dimtxt")
        // note, north arrow, caption
        let wall = Tank.typeName(v).map { "ผนัง " + $0 }
        let note = ([wall] + [hints ? "สิ่งกีดขวางระบุในขั้นที่ 2" : nil]).compactMap { $0 }.joined(separator: " | ")
        if !note.isEmpty { o.append(.text(note, at: Pt(W - 50, 14), size: 8, color: .ink2, align: .right)) }
        tag("txt")
        if let az = Tank.azimuth(v) { o += Self.northArrow(at: Pt(W - 24, 36), azimuth: az) }
        tag("north")
        let caption = "แปลนหลังคาถังน้ำใส \(fmt(TW)) × \(fmt(TH)) ม."
        let capY = ty + 26
        o.append(.text(caption, at: Pt(ox, capY), size: 10.5, bold: true, color: RGBA(hex: 0x16325C)))
        o.append(.line(Pt(ox, capY + 8), Pt(ox + Double(caption.count) * 5.6, capY + 8), width: 0.9, color: RGBA(hex: 0x16325C)))
        o.append(.text("หน่วย: เมตร", at: Pt(W - 16, capY), size: 8, color: .ink2, align: .right))

        var bottom = capY + 14
        if details {
            if let sum = Tank.summary(v) {
                o.append(.text(sum.text, at: Pt(ox, capY + 20), size: 8.5, color: ink)); bottom = capY + 28
            }
            o.append(.text(TankDrawings.note, at: Pt(ox, bottom + 4), size: 7.5, color: .ink2)); bottom += 12
        }
        tag("txt")

        sketch = Sketch(width: W, height: max(H, bottom), ops: o)
        self.chips = chipList
        self.tags = tags
        frame = (ox, oy, k)
        dimensions = dims
    }

    /// The beams' width on the plan (m), assumed.
    public static let beam = 0.30

    /// Section marks: 1–1 cuts at half of the width (seen towards the left), 2–2 at half of the length (seen up).
    static func sectionMarks(ox: Double, oy: Double, w: Double, h: Double) -> [DrawOp] {
        var o: [DrawOp] = []
        let mark = RGBA(hex: 0x16325C), cxm = ox + w / 2, cym = oy + h / 2
        o.append(.line(Pt(cxm, oy - 6), Pt(cxm, oy + h + 6), width: 0.7, color: mark, dash: [10, 3, 2, 3]))
        o.append(.line(Pt(ox - 6, cym), Pt(ox + w + 6, cym), width: 0.7, color: mark, dash: [10, 3, 2, 3]))
        for (c, dir, n) in [(Pt(cxm, oy + 13), Pt(-1, 0), "1"), (Pt(cxm, oy + h - 13), Pt(-1, 0), "1"),
                            (Pt(ox + 13, cym), Pt(0, -1), "2"), (Pt(ox + w - 13, cym), Pt(0, -1), "2")] {
            // the arrow head on the side the section is seen from, then the numbered bubble
            let tip = Pt(c.x + dir.x * 13, c.y + dir.y * 13), nrm = Pt(-dir.y * 4, dir.x * 4)
            o.append(.polygon([tip, Pt(c.x + dir.x * 7 + nrm.x, c.y + dir.y * 7 + nrm.y), Pt(c.x + dir.x * 7 - nrm.x, c.y + dir.y * 7 - nrm.y)],
                              stroke: nil, fill: mark))
            o.append(.circle(c, r: 6, stroke: mark, fill: .white, width: 0.9))
            o.append(.text(n, at: c, size: 7.5, bold: true, color: mark, align: .center))
        }
        return o
    }

    /// A `cross` design's vent (แบบเห็ด on a column head, the 40 × 40 sheet): a plus as wide as the vent, flange ticks
    /// at the arms' ends and a circle in the middle.
    static func crossVent(_ b: Box) -> [DrawOp] {
        let c = Pt(b.x + b.w / 2, b.y + b.h / 2), a = min(b.w, b.h) / 2, t = max(1.2, a * 0.28)
        var o: [DrawOp] = [
            .polygon([Pt(c.x - t, c.y - a), Pt(c.x + t, c.y - a), Pt(c.x + t, c.y - t), Pt(c.x + a, c.y - t), Pt(c.x + a, c.y + t), Pt(c.x + t, c.y + t),
                      Pt(c.x + t, c.y + a), Pt(c.x - t, c.y + a), Pt(c.x - t, c.y + t), Pt(c.x - a, c.y + t), Pt(c.x - a, c.y - t), Pt(c.x - t, c.y - t)],
                     stroke: .red, fill: .white, width: 0.9),
        ]
        let f = t * 1.8
        for (p, horizontal) in [(Pt(c.x, c.y - a), true), (Pt(c.x, c.y + a), true), (Pt(c.x - a, c.y), false), (Pt(c.x + a, c.y), false)] {
            o.append(horizontal ? .line(Pt(p.x - f, p.y), Pt(p.x + f, p.y), width: 1, color: .red) : .line(Pt(p.x, p.y - f), Pt(p.x, p.y + f), width: 1, color: .red))
        }
        o.append(.circle(c, r: max(0.8, t * 0.8), stroke: .red, fill: .white, width: 0.8))
        return o
    }

    /// The iPhone plan (docs/ui/survey-d1-size-iphone, 330 × 300): the outline, the grid lines named 1… / A… and the
    /// two totals, the north arrow at the top right. Each span stays on the full plan (`init`).
    public static func compact(_ v: Values) -> Sketch? {
        if Tank.isRound(v) { return compactRound(v) }
        let sx = parseSpans(v.text(Roof.Key.spansX)), sy = parseSpans(v.text(Roof.Key.spansY))
        guard !sx.isEmpty, !sy.isEmpty, let f = compactFrame(v) else { return nil }
        let TW = sx.reduce(0, +), TH = sy.reduce(0, +), k = f.k, w = TW * k, h = TH * k, ox = f.ox, oy = f.oy
        let navy = RGBA(hex: 0x16325C), label = RGBA(hex: 0x5B6B82), grid = RGBA(hex: 0xC9D3DF)
        var xs = [0.0]; for s in sx { xs.append(xs.last! + s) }
        var ys = [0.0]; for s in sy { ys.append(ys.last! + s) }
        var o: [DrawOp] = [.rect(Box(0, 0, 330, 300), stroke: nil, fill: .white), .rect(Box(ox, oy, w, h), stroke: nil, fill: .white)]
        for x in xs.dropFirst().dropLast() { o.append(.line(Pt(ox + x * k, oy), Pt(ox + x * k, oy + h), width: 1, color: grid, dash: [3, 3])) }
        for y in ys.dropFirst().dropLast() { o.append(.line(Pt(ox, oy + y * k), Pt(ox + w, oy + y * k), width: 1, color: grid, dash: [3, 3])) }
        o.append(.rect(Box(ox, oy, w, h), stroke: navy, fill: nil, width: 2))
        for (i, x) in xs.enumerated() { o.append(.text(Roof.gridName(.x, i), at: Pt(ox + x * k, oy - 10), size: 8, color: label, align: .center)) }
        for (j, y) in ys.enumerated() { o.append(.text(Roof.gridName(.y, j), at: Pt(ox - 10, oy + y * k), size: 8, color: label, align: .center)) }
        o.append(.text(String(format: "%.2f", TW), at: Pt(ox + w / 2, oy + h + 16), size: 9, bold: true, color: navy, align: .center))
        o.append(.text(String(format: "%.2f", TH), at: Pt(ox + w + 16, oy + h / 2), size: 9, bold: true, color: navy, align: .center, angle: 90))
        if let az = Tank.azimuth(v) { o += northArrow(at: Pt(298, 42), azimuth: az, radius: 13, ink: navy) }
        return Sketch(width: 330, height: 300, ops: o)
    }

    /// Where the tank sits on the 330 × 300 iPhone plan: its top-left corner and points per metre (sub-step 2 puts
    /// the vents and hatches on it).
    public static func compactFrame(_ v: Values) -> (ox: Double, oy: Double, k: Double)? {
        guard let t = TankPoints.tankSize(v) else { return nil }
        let side = 240.0, k = min(side / t.w, side / t.h)
        return (30 + (side - t.w * k) / 2, 30 + (side - t.h * k) / 2, k)
    }

    /// The design's north arrow (`d1-north-arrow`) turned by −azimuth: wall A stays on top, N points to true north.
    public static func northArrow(at c: Pt, azimuth az: Int, radius R: Double = 12, ink: RGBA = RGBA(hex: 0x111111)) -> [DrawOp] {
        let a = -Double(az) * .pi / 180, ca = cos(a), sa = sin(a), k = R / 12
        func p(_ x: Double, _ y: Double) -> Pt { Pt(c.x + (x * ca - y * sa) * k, c.y + (x * sa + y * ca) * k) }
        return [
            .circle(c, r: R, stroke: ink, fill: .white, width: 0.9),
            .polygon([p(0, -10), p(4.5, 6), p(0, 2.5), p(-4.5, 6)], stroke: nil, fill: ink),
            .text("N", at: p(0, -17), size: 9 * k, bold: true, color: ink, align: .center),
        ]
    }
}
