import Foundation

/// Platform-neutral vector drawing, rendered by the PDF report (UIKit), the editor (SwiftUI Canvas)
/// and rasterised to PNG for the Excel plan frame. Coordinates are points, y grows downward.
public struct Pt: Hashable, Sendable { public var x, y: Double; public init(_ x: Double, _ y: Double) { self.x = x; self.y = y } }
public struct Box: Hashable, Sendable {
    public var x, y, w, h: Double
    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public func inset(_ d: Double) -> Box { Box(x + d, y + d, max(0, w - 2 * d), max(0, h - 2 * d)) }
    public func offset(_ dx: Double, _ dy: Double) -> Box { Box(x + dx, y + dy, w, h) }
    /// Largest rect of the given aspect ratio centred inside this box.
    public func fit(_ iw: Double, _ ih: Double) -> Box {
        guard iw > 0, ih > 0 else { return self }
        let k = min(w / iw, h / ih)
        return Box(x + (w - iw * k) / 2, y + (h - ih * k) / 2, iw * k, ih * k)
    }
}
public struct RGBA: Hashable, Sendable {
    public var r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public init(hex: UInt32) { self.init(Double(hex >> 16 & 0xff) / 255, Double(hex >> 8 & 0xff) / 255, Double(hex & 0xff) / 255) }
    public static let black = RGBA(0, 0, 0), white = RGBA(1, 1, 1)
    public static let ink2 = RGBA(hex: 0x555555), rule = RGBA(hex: 0x9a9a9a), faint = RGBA(hex: 0x999999)
    public static let red = RGBA(hex: 0xE0433A), dark = RGBA(hex: 0x333333), tag = RGBA(hex: 0xC00000)
    public static let tick = RGBA(hex: 0x70AD47), band = RGBA(hex: 0xE2EFDA), blue = RGBA(hex: 0x1F4E79)
    /// The same colour at opacity `a`.
    public func withAlpha(_ a: Double) -> RGBA { RGBA(r, g, b, a) }
}
public enum TextAlign: Sendable { case left, center, right }

/// A font for `DrawOp.runs`: Sarabun (our reports' font), Helvetica (Latin text on the customer's forms) and TH Sarabun
/// (their page numbers).
public enum FontFace: String, Sendable { case sarabun, helvetica, thSarabun }

/// One piece of a line set in its own font.
public struct TextRun: Hashable, Sendable {
    public var text: String
    public var size: Double
    public var bold: Bool
    public var face: FontFace
    public var underline: Bool
    public init(_ text: String, size: Double, bold: Bool = false, face: FontFace = .sarabun, underline: Bool = false) {
        self.text = text; self.size = size; self.bold = bold; self.face = face; self.underline = underline
    }
}

public enum DrawOp: Equatable, Sendable {
    case line(Pt, Pt, width: Double, color: RGBA, dash: [Double] = [])
    case rect(Box, stroke: RGBA?, fill: RGBA?, width: Double = 1)
    /// Diagonal hatching clipped to a rect (obstacles).
    case hatch(Box, color: RGBA, spacing: Double = 6)
    case circle(Pt, r: Double, stroke: RGBA?, fill: RGBA?, width: Double = 1)
    case polygon([Pt], stroke: RGBA?, fill: RGBA?, width: Double = 1)
    /// An open path with mitred joins (truss chords, corrugated sheet).
    case polyline([Pt], width: Double, color: RGBA, dash: [Double] = [])
    /// One line of text; `at` is the anchor point at the vertical centre of the line.
    case text(String, at: Pt, size: Double, bold: Bool = false, color: RGBA = .black, align: TextAlign = .left, angle: Double = 0)
    /// Wrapped text inside a box, clipped to it.
    case textBox(String, Box, size: Double, bold: Bool = false, color: RGBA = .black, align: TextAlign = .left)
    /// A stored photo scaled to fit (aspect kept) and centred in the box.
    case photo(Photo, Box)
    /// A stored photo scaled to cover the box, centred and cropped to it.
    case photoFill(Photo, Box)
    /// One line of text in several fonts, not wrapped; `at` is the anchor at the vertical centre, as for `text`.
    case runs([TextRun], at: Pt, color: RGBA = .black, align: TextAlign = .left)
    case checkbox(Box, on: Bool)
}

public struct Sketch: Sendable {
    public var width: Double
    public var height: Double
    public var ops: [DrawOp]
    public init(width: Double, height: Double, ops: [DrawOp] = []) { self.width = width; self.height = height; self.ops = ops }

    /// The same drawing moved by (dx, dy) — for placing a sketch on a page.
    public func translated(_ dx: Double, _ dy: Double, scale k: Double = 1) -> [DrawOp] {
        func p(_ a: Pt) -> Pt { Pt(dx + a.x * k, dy + a.y * k) }
        func b(_ a: Box) -> Box { Box(dx + a.x * k, dy + a.y * k, a.w * k, a.h * k) }
        return ops.map { op in
            switch op {
            case let .line(a, c, w, col, dash): return .line(p(a), p(c), width: w * k, color: col, dash: dash.map { $0 * k })
            case let .rect(r, s, f, w): return .rect(b(r), stroke: s, fill: f, width: w * k)
            case let .hatch(r, c, sp): return .hatch(b(r), color: c, spacing: sp * k)
            case let .circle(c, r, s, f, w): return .circle(p(c), r: r * k, stroke: s, fill: f, width: w * k)
            case let .polygon(ps, s, f, w): return .polygon(ps.map(p), stroke: s, fill: f, width: w * k)
            case let .polyline(ps, w, col, dash): return .polyline(ps.map(p), width: w * k, color: col, dash: dash.map { $0 * k })
            case let .text(t, at, sz, bold, col, al, ang): return .text(t, at: p(at), size: sz * k, bold: bold, color: col, align: al, angle: ang)
            case let .textBox(t, r, sz, bold, col, al): return .textBox(t, b(r), size: sz * k, bold: bold, color: col, align: al)
            case let .photo(ph, r): return .photo(ph, b(r))
            case let .photoFill(ph, r): return .photoFill(ph, b(r))
            case let .runs(rs, at, col, al):
                return .runs(rs.map { var x = $0; x.size *= k; return x }, at: p(at), color: col, align: al)
            case let .checkbox(r, on): return .checkbox(b(r), on: on)
            }
        }
    }
}

// MARK: - survey drawings

public enum Drawings {
    /// The plan with its sections under it, for a sheet's one drawing box (NO.224's roof and tank sheets, `box` its
    /// width ÷ height): a C1 roof adds section A-A, a tank sections 1–1 and 2–2 side by side, titled as in the PDF. The
    /// plan's canvas already has about the box's shape, so the sections get only the height that keeps the plan at
    /// `keep` of its size alone or more, scaled down (and centred) to fit it; the plan alone when that leaves too
    /// little. Nil where `plan` is nil.
    public static func planWithSections(_ v: Values, tank: Bool, width W: Double = 690, box: Double = 792.0 / 614,
                                        keep: Double = 0.75) -> Sketch? {
        guard let plan = plan(v, tank: tank, width: W) else { return nil }
        // a tank's sections carry their own titles, and are drawn only once the tank has a height (else they're a note)
        var sections: [(title: String?, sketch: Sketch)] = []
        if tank, (Tank.height(v) ?? 0) > 0 {
            for across in [false, true] {
                if let s = TankDrawings.section(v, across: across, width: W) { sections.append((nil, s)) }
            }
        } else if !tank, Roof.hasFrame(v) {
            sections.append(("รูปตัด A-A | " + Roof.frame(v).title + " (หน่วย ม.)", RoofSection(v).sketch))
        }
        guard !sections.isEmpty else { return plan }
        // fitted into a box of height 1, a picture is scaled by min(box ÷ width, 1 ÷ height); the plan keeps `keep` of
        // its scale alone while the picture is no taller than 1 ÷ (keep × that scale)
        let alone = min(box / W, 1 / plan.height), maxHeight = 1 / (keep * alone)
        let gap = 16.0, titleSize = 20.0, top = plan.height + 14
        let title = sections.contains { $0.title != nil } ? titleSize + 10 : 0
        let room = maxHeight - top - title - 8
        // side by side, each in its column; or one per row, as wide as the plan: whichever draws them wider
        let column = (W - gap * Double(sections.count - 1)) / Double(sections.count)
        let sideScales = sections.map { min(column / $0.sketch.width, room / $0.sketch.height) }
        // the drawings shrink to fit the room; the gaps between rows don't
        let rowsHeight = sections.reduce(0) { $0 + $1.sketch.height * (W / $1.sketch.width) }
        let shrink = min(1, (room - gap * Double(sections.count - 1)) / rowsHeight)
        let rowScales = sections.map { W / $0.sketch.width * shrink }
        let stacked = sections.count > 1 && zip(sections, rowScales).map { $0.sketch.width * $1 }.min()!
            > zip(sections, sideScales).map { $0.sketch.width * $1 }.min()!
        let scales = stacked ? rowScales : sideScales
        let narrowest = zip(sections, scales).map { $0.sketch.width * $1 / (stacked ? W : column) }.min()!
        guard room > 40, narrowest >= 0.4 else { return plan }
        var ops: [DrawOp] = [], row = 0.0, y = top
        for (i, (s, k)) in zip(sections, scales).enumerated() {
            let w = s.sketch.width * k
            let x = stacked ? (W - w) / 2 : Double(i) * (column + gap) + (column - w) / 2
            if let t = s.title { ops.append(.text(t, at: Pt(x + 2, y + titleSize / 2 + 2), size: titleSize, bold: true)) }
            ops += s.sketch.translated(x, y + title, scale: k)
            if stacked { y += title + s.sketch.height * k + gap; row = y - top - gap } else { row = max(row, title + s.sketch.height * k) }
        }
        let H = (top + row + 8).rounded()
        return Sketch(width: W, height: H, ops: [.rect(Box(0, 0, W, H), stroke: nil, fill: .white)] + plan.ops + ops)
    }

    /// Dimensioned plan from column spans (m) and obstacles, as on the roof / clear-water-tank sheets.
    /// A roof whose frame type was chosen on the C1 page draws the C1 plan (frame lines, posts, ridge, skylights);
    /// a tank draws `TankPlan` (the D1 page's plan).
    public static func plan(_ v: Values, tank: Bool, width W: Double = 690) -> Sketch? {
        // a tank draws from `Tank.spans` (a round tank from its diameter)
        if tank { return TankPlan(v, width: W, details: true)?.sketch }
        let sx = parseSpans(v.text("spansX")), sy = parseSpans(v.text("spansY"))
        guard !sx.isEmpty, !sy.isEmpty else { return nil }
        if Roof.hasFrame(v) {
            let p = RoofPlan(v).sketch, k = W / p.width
            return Sketch(width: W, height: p.height * k, ops: p.translated(0, 0, scale: k))
        }
        let TW = sx.reduce(0, +), TH = sy.reduce(0, +)
        let padL = 58.0, padT = 50.0, padR = 16.0, padB = 16.0, maxH = (W * 0.52).rounded()
        let k = min((W - padL - padR) / TW, (maxH - padT - padB) / TH), w = TW * k, h = TH * k
        let ox = padL + ((W - padL - padR) - w) / 2, oy = padT, H = (oy + h + padB).rounded()
        var o: [DrawOp] = [.rect(Box(0, 0, W, H), stroke: nil, fill: .white)]
        let horizontal = (v.choice("sheetDir") ?? "แนวนอน") == "แนวนอน", step = max(4, 0.33 * k)
        var p = step
        while p < (horizontal ? h : w) {
            o.append(horizontal ? .line(Pt(ox, oy + p), Pt(ox + w, oy + p), width: 0.6, color: .rule) : .line(Pt(ox + p, oy), Pt(ox + p, oy + h), width: 0.6, color: .rule))
            p += step
        }
        var xs = [0.0]; for s in sx { xs.append(xs.last! + s) }
        var ys = [0.0]; for s in sy { ys.append(ys.last! + s) }
        let dash: [Double] = [10, 3, 2, 3]
        for x in xs { let X = ox + x * k
            o.append(.line(Pt(X, oy - 18), Pt(X, oy + h + 8), width: 0.7, color: .ink2, dash: dash))
            o.append(.circle(Pt(X, oy - 18), r: 2.4, stroke: .black, fill: .white, width: 0.8)) }
        for y in ys { let Y = oy + y * k
            o.append(.line(Pt(ox - 18, Y), Pt(ox + w + 8, Y), width: 0.7, color: .ink2, dash: dash))
            o.append(.circle(Pt(ox - 18, Y), r: 2.4, stroke: .black, fill: .white, width: 0.8)) }
        o.append(.rect(Box(ox, oy, w, h), stroke: .black, fill: nil, width: 1.3))
        // dimension chains
        let dy = oy - 30
        o.append(.line(Pt(ox, dy), Pt(ox + w, dy), width: 0.6, color: .black))
        for x in xs { o.append(.line(Pt(ox + x * k, dy - 3), Pt(ox + x * k, dy + 3), width: 0.8, color: .black)) }
        for (i, s) in sx.enumerated() { o.append(.text(fmt(s), at: Pt(ox + (xs[i] + s / 2) * k, dy - 7), size: 8.5, align: .center)) }
        o.append(.line(Pt(ox, dy - 16), Pt(ox + w, dy - 16), width: 0.6, color: .black))
        o.append(.text(fmt(TW), at: Pt(ox + w / 2, dy - 22), size: 9, bold: true, align: .center))
        let dx = ox - 30
        o.append(.line(Pt(dx, oy), Pt(dx, oy + h), width: 0.6, color: .black))
        for y in ys { o.append(.line(Pt(dx - 3, oy + y * k), Pt(dx + 3, oy + y * k), width: 0.8, color: .black)) }
        for (i, s) in sy.enumerated() { o.append(.text(fmt(s), at: Pt(dx - 7, oy + (ys[i] + s / 2) * k), size: 8.5, align: .center, angle: -90)) }
        o.append(.line(Pt(dx - 16, oy), Pt(dx - 16, oy + h), width: 0.6, color: .black))
        o.append(.text(fmt(TH), at: Pt(dx - 22, oy + h / 2), size: 9, bold: true, align: .center, angle: -90))
        for ob in v.obstacles("obst") where !ob.isAbsent {
            guard let x = NumberInput.value(ob.x), let y = NumberInput.value(ob.y), let ow = NumberInput.value(ob.w), let oh = NumberInput.value(ob.h), ow > 0, oh > 0 else { continue }
            let r = Box(ox + x * k, oy + y * k, ow * k, oh * k)
            o.append(.rect(r, stroke: nil, fill: .white)); o.append(.hatch(r, color: .red)); o.append(.rect(r, stroke: .red, fill: nil, width: 1))
            if !ob.label.isEmpty { o.append(.text("\(ob.label) \(fmt(ow))x\(fmt(oh))", at: Pt(r.maxX + 3, r.maxY - 3), size: 8, color: .dark)) }
        }
        return Sketch(width: W, height: H, ops: o)
    }

    /// Schematic gable roof frame with the numbered components 1–7.
    public static func truss(width W: Double = 360) -> Sketch {
        let k = W / 360, H = (W * 0.56).rounded()
        var o: [DrawOp] = []
        func L(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ sw: Double = 3, _ c: RGBA = .dark) { o.append(.line(Pt(x1 * k, y1 * k), Pt(x2 * k, y2 * k), width: sw * k, color: c)) }
        func tag(_ n: Int, _ x: Double, _ y: Double, _ lx: Double, _ ly: Double) {
            o.append(.line(Pt(x * k, y * k), Pt(lx * k, ly * k), width: 0.8 * k, color: .tag))
            o.append(.rect(Box((lx - 7) * k, (ly - 7) * k, 14 * k, 14 * k), stroke: .tag, fill: .white, width: k))
            o.append(.text("\(n)", at: Pt(lx * k, ly * k), size: 10 * k, bold: true, color: .tag, align: .center))
        }
        L(40, 150, 320, 150, 5); L(20, 158, 180, 40, 4.5); L(340, 158, 180, 40, 4.5); L(180, 40, 180, 150, 4); L(180, 150, 118, 85, 3); L(180, 150, 242, 85, 3)
        let g7 = RGBA(hex: 0x777777)
        L(58, 150, 58, 200, 5, g7); L(302, 150, 302, 200, 5, g7); L(46, 150, 70, 150, 7, .ink2); L(290, 150, 314, 150, 7, .ink2); L(18, 152, 18, 168, 4, .ink2); L(342, 152, 342, 168, 4, .ink2)
        for i in 0...6 {
            let t = Double(i) / 6.4, x = 20 + 160 * t, y = 158 - 118 * t, x2 = 340 - 160 * t
            o.append(.rect(Box((x - 4) * k, (y - 9) * k, 8 * k, 6 * k), stroke: nil, fill: .ink2))
            o.append(.rect(Box((x2 - 4) * k, (y - 9) * k, 8 * k, 6 * k), stroke: nil, fill: .ink2))
        }
        tag(1, 80, 103, 62, 72); tag(2, 262, 98, 288, 70); tag(3, 300, 150, 316, 128); tag(4, 240, 150, 244, 176); tag(5, 150, 118, 126, 128); tag(6, 18, 164, 10, 188); tag(7, 180, 90, 208, 112)
        return Sketch(width: W, height: H, ops: o)
    }

    /// North arrow rotated so N points where the photo's north is.
    public static func compass(_ north: String?, size S: Double = 86) -> Sketch {
        let table: [String: Double] = ["ด้านบน": 0, "ด้านขวา": 90, "ด้านล่าง": 180, "ด้านซ้าย": 270]
        let rot: Double = table[north ?? ""] ?? 0
        let k: Double = S / 86, c = Pt(43, 45), a: Double = rot * Double.pi / 180
        let ca = cos(a), sa = sin(a)
        func R(_ x: Double, _ y: Double) -> Pt {
            let dx = x - c.x, dy = y - c.y
            let rx: Double = c.x + dx * ca - dy * sa
            let ry: Double = c.y + dx * sa + dy * ca
            return Pt(rx * k, ry * k)
        }
        return Sketch(width: S, height: S, ops: [
            .circle(Pt(c.x * k, c.y * k), r: 24 * k, stroke: .black, fill: nil, width: 1),
            .polygon([R(43, 16), R(49, 45), R(43, 41), R(37, 45)], stroke: nil, fill: .black),
            .polygon([R(43, 74), R(49, 45), R(43, 49), R(37, 45)], stroke: .black, fill: .white, width: 0.8),
            .text("N", at: R(43, 9), size: 10 * k, bold: true, align: .center),
            .text("S", at: R(43, 81), size: 8 * k, align: .center),
            .text("E", at: R(75, 45), size: 8 * k, align: .center),
            .text("W", at: R(11, 45), size: 8 * k, align: .center),
        ])
    }
}
