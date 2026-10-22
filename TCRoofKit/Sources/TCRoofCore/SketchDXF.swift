import Foundation

/// Any `Sketch` as a plain DXF R12 drawing (LINE / CIRCLE / TEXT on named layers) that AutoCAD, BricsCAD, DraftSight and
/// LibreCAD open (docs/specs/cad-export-dxf). Callers map sketch points to metres (Y up) and pick a layer per op;
/// coordinates are written in millimetres or metres. Thai text is written in TIS-620 (`$DWGCODEPAGE` ANSI_874), the
/// byte codes a Thai SHX font reads, in the text style `CORDIA` (cordia.shx, width 0.85) so CAD programs show Thai
/// instead of their default font's blanks. The header carries the drawing's extents and limits and the VPORT table its
/// view, so the drawing opens framed. Shapes are POLYLINEs (a rectangle is one closed polyline, not four lines), and
/// the symbols a caller marks (`Symbol`) are BLOCKs placed by INSERTs, so the drawing edits as objects in CAD. The other
/// options add what the C1 export never needed.
public struct SketchDXF: Sendable {
    public struct Layer: Sendable, Hashable {
        public var name: String
        /// AutoCAD colour index.
        public var aci: Int
        public init(_ name: String, aci: Int) { self.name = name; self.aci = aci }
    }

    public struct Options: Sendable {
        /// `$INSUNITS` 4 (mm) or 6 (m); coordinates × 1000 when true.
        public var millimetres = true
        /// Ops with a dash pattern get linetype `DASHED` (declared in the LTYPE table when used).
        public var dashes = false
        /// Group 62 when an op's colour maps to another ACI than its layer's.
        public var opColours = false
        /// `textBox` → wrapped `TEXT` lines.
        public var textBoxes = false
        /// `hatch` → its diagonal lines clipped to the box.
        public var hatches = false
        /// `photo` / `checkbox` → outline rectangle (checkbox: an X when on).
        public var outlineBoxes = false
        /// White or empty `rect` / `polygon` / `circle` with no stroke write nothing.
        public var skipFillOnly = false
        /// Text cap height in metres; nil = the op's font size × 0.7.
        public var fixedTextHeight: Double? = nil
        /// Every `.text` op centred on its anchor, ignoring its align and angle (`RoofDXF`).
        public var centreText = true
        /// The text style every `TEXT` uses (the STYLE table, group 7, and the width factor, group 41).
        public var textStyle = TextStyle.cordia
        /// `polyline`, `rect`, `polygon` and outlines as one POLYLINE each (closed for the shapes) instead of LINEs.
        public var polylines = true
        /// The ops of each `Symbol` passed to `add` as an INSERT of a BLOCK.
        public var blocks = true
        public init() {}
    }

    /// Ops of a sketch that draw one symbol (a breaker, a transformer, a meter): written as an INSERT of the block
    /// `name` at `origin`. Every symbol of a name must draw the same thing relative to its origin; one that doesn't gets
    /// a block of its own (`name-2`, …), so the drawing never changes.
    public struct Symbol: Sendable, Equatable {
        public var name: String
        public var origin: Pt
        /// The symbol's ops, as indices into the sketch's ops.
        public var range: Range<Int>
        public init(_ name: String, origin: Pt, range: Range<Int>) { self.name = name; self.origin = origin; self.range = range }
    }

    /// A text style: its name, its font file and its width factor.
    public struct TextStyle: Sendable, Equatable {
        public var name: String, font: String, width: Double
        public init(name: String, font: String, width: Double) { self.name = name; self.font = font; self.width = width }
        /// The team's Thai CAD font: cordia.shx at width 0.85.
        public static let cordia = TextStyle(name: "CORDIA", font: "cordia.shx", width: 0.85)
    }

    public var options: Options
    private var ents: [String] = []
    private var count: [String: Int] = [:]
    private var order: [String] = []
    private var aciOf: [String: Int] = [:]
    /// The DASHED pattern (dash, gap) in drawing units, from the first dashed op.
    private var dashPattern: (Double, Double)?
    /// What the entities cover, in drawing units (text by an estimate of its width).
    private var lo = (x: Double.infinity, y: Double.infinity), hi = (x: -Double.infinity, y: -Double.infinity)
    /// The BLOCKS section, each block's body (to compare a symbol with it) and what it covers (drawing units, from its
    /// base point).
    private var blockSection: [String] = []
    private var blockBody: [String: [String]] = [:]
    private var blockBox: [String: (lo: (x: Double, y: Double), hi: (x: Double, y: Double))] = [:]
    /// Drawing a block's body: entities on layer 0, colour BYBLOCK, measured into `blockLo` / `blockHi`.
    private var inBlock = false
    private var blockLo = (x: Double.infinity, y: Double.infinity), blockHi = (x: -Double.infinity, y: -Double.infinity)

    public init(options: Options = .init()) { self.options = options }

    public var entityCount: Int { count.values.reduce(0, +) }
    /// Layers in order of first use.
    public var layers: [String] { order }
    var unit: Double { options.millimetres ? 1000 : 1 }

    // MARK: entities

    private mutating func use(_ l: Layer) {
        if inBlock { return }
        if count[l.name] == nil { order.append(l.name); aciOf[l.name] = l.aci }
        count[l.name, default: 0] += 1
    }
    private func q(_ m: Double) -> String { Self.num((m * unit * 1000).rounded() / 1000) }
    /// Grows the extents by a point in metres.
    private mutating func cover(_ x: Double, _ y: Double) {
        if inBlock { blockLo = (min(blockLo.x, x * unit), min(blockLo.y, y * unit)); blockHi = (max(blockHi.x, x * unit), max(blockHi.y, y * unit)); return }
        lo = (min(lo.x, x * unit), min(lo.y, y * unit)); hi = (max(hi.x, x * unit), max(hi.y, y * unit))
    }
    /// The layer an entity goes on: 0 inside a block, so the INSERT's layer shows through.
    private func layerName(_ l: Layer) -> String { inBlock ? "0" : l.name }
    /// Linetype and colour groups after the layer.
    private func style(_ l: Layer, _ color: RGBA?, _ dash: [Double]) -> [String] {
        var g: [String] = []
        if options.dashes, dash.count >= 2 { g += ["6", "DASHED"] }
        // inside a block: BYBLOCK, so the INSERT's layer and colour show through
        if inBlock { return g + ["62", "0"] }
        if options.opColours, let color, Self.aci(color) != l.aci { g += ["62", String(Self.aci(color))] }
        return g
    }

    public mutating func line(_ l: Layer, _ a: (Double, Double), _ b: (Double, Double)) { line(l, a, b, extra: []) }
    private mutating func line(_ l: Layer, _ a: (Double, Double), _ b: (Double, Double), extra: [String]) {
        guard hypot(b.0 - a.0, b.1 - a.1) > 1e-6 else { return }
        use(l); ents += ["0", "LINE", "8", layerName(l)] + extra + ["10", q(a.0), "20", q(a.1), "30", "0", "11", q(b.0), "21", q(b.1), "31", "0"]
        cover(a.0, a.1); cover(b.0, b.1)
    }
    public mutating func circle(_ l: Layer, _ c: (Double, Double), r: Double) { circle(l, c, r: r, extra: []) }
    private mutating func circle(_ l: Layer, _ c: (Double, Double), r: Double, extra: [String]) {
        use(l); ents += ["0", "CIRCLE", "8", layerName(l)] + extra + ["10", q(c.0), "20", q(c.1), "30", "0", "40", q(r)]
        cover(c.0 - r, c.1 - r); cover(c.0 + r, c.1 + r)
    }
    /// One POLYLINE through `pts` (metres), closed back to the first; LINEs with `polylines` off.
    public mutating func polyline(_ l: Layer, _ pts: [(Double, Double)], closed: Bool = false) { polyline(l, pts, closed: closed, extra: []) }
    private mutating func polyline(_ l: Layer, _ pts: [(Double, Double)], closed: Bool, extra: [String]) {
        var p: [(Double, Double)] = []
        for v in pts where p.last.map({ hypot(v.0 - $0.0, v.1 - $0.1) > 1e-6 }) ?? true { p.append(v) }
        if closed, p.count > 1, hypot(p[0].0 - p[p.count - 1].0, p[0].1 - p[p.count - 1].1) <= 1e-6 { p.removeLast() }
        guard p.count >= 2 else { return }
        guard options.polylines, p.count > 2 || closed else {
            let n = closed ? p.count : p.count - 1
            for i in 0..<n { line(l, p[i], p[(i + 1) % p.count], extra: extra) }
            return
        }
        let name = layerName(l)
        use(l); ents += ["0", "POLYLINE", "8", name] + extra + ["66", "1", "10", "0", "20", "0", "30", "0", "70", closed ? "1" : "0"]
        for v in p { ents += ["0", "VERTEX", "8", name, "10", q(v.0), "20", q(v.1), "30", "0"]; cover(v.0, v.1) }
        ents += ["0", "SEQEND", "8", name]
    }

    /// `height` in metres; `angle` in degrees counter-clockwise; `middle` aligns the line's vertical middle on `p`.
    public mutating func text(_ l: Layer, _ p: (Double, Double), height: Double, _ s: String, align: TextAlign = .left, middle: Bool = false, angle: Double = 0) {
        text(l, p, height: height, s, align: align, middle: middle, angle: angle, extra: [])
    }
    private mutating func text(_ l: Layer, _ p: (Double, Double), height: Double, _ s: String, align: TextAlign, middle: Bool, angle: Double, extra: [String]) {
        guard !s.isEmpty else { return }
        let ts = options.textStyle
        use(l); ents += ["0", "TEXT", "8", layerName(l)] + extra + (inBlock && !extra.contains("62") ? ["62", "0"] : []) + ["7", ts.name, "10", q(p.0), "20", q(p.1), "30", "0", "40", q(height), "1", s,
                                                             "41", Self.num(ts.width)]
        // the extents: about 0.6 of the height a letter, along the angle from where the alignment puts the start
        let w = Double(s.count) * height * 0.6 * ts.width, r = angle * .pi / 180
        let start = align == .left ? 0 : align == .center ? -w / 2 : -w
        for t in [start, start + w] { for dy in [-height, height] { cover(p.0 + t * cos(r) - dy * sin(r), p.1 + t * sin(r) + dy * cos(r)) } }
        var a = angle.truncatingRemainder(dividingBy: 360); if a < 0 { a += 360 }
        if abs(a) > 1e-9 { ents += ["50", Self.num((a * 1000).rounded() / 1000)] }
        let h = align == .left ? 0 : align == .center ? 1 : 2
        if h != 0 || middle {
            if h != 0 { ents += ["72", String(h)] }
            if middle { ents += ["73", "2"] }
            ents += ["11", q(p.0), "21", q(p.1), "31", "0"]
        }
    }

    // MARK: sketch ops

    /// Writes `ops` mapped by `transform` (sketch point → metres, Y up). `layer` picks a layer per op (index, op); nil
    /// skips it. `pointsPerMetre` converts radii, text sizes and dash lengths.
    /// `symbols` become INSERTs of their blocks (with `blocks` on); the INSERT takes the layer and colour of the symbol's
    /// first non-text op.
    public mutating func add(_ ops: [DrawOp], layer: (Int, DrawOp) -> Layer?, transform tf: (Pt) -> (Double, Double), pointsPerMetre ppm: Double,
                             symbols: [Symbol] = []) {
        var starts: [Int: Symbol] = [:]
        if options.blocks {
            for s in symbols where !s.range.isEmpty && s.range.upperBound <= ops.count && starts[s.range.lowerBound] == nil { starts[s.range.lowerBound] = s }
        }
        var i = 0
        while i < ops.count {
            if let s = starts[i] {
                let shown = s.range.filter { layer($0, ops[$0]) != nil }
                // the layer and colour of the first op that draws (not a label, not a white mask)
                let skip = options.skipFillOnly
                let drawn: (DrawOp) -> Bool = { op in
                    switch op {
                    case .text, .runs, .textBox: return false
                    case let .rect(_, st, f, _), let .polygon(_, st, f, _), let .circle(_, _, st, f, _):
                        return !(skip && st == nil && (f == nil || f == .white))
                    default: return true
                    }
                }
                if let first = shown.first(where: { drawn(ops[$0]) }) ?? shown.first, let l = layer(first, ops[first]) {
                    let o = tf(s.origin)
                    let name = block(s.name) { d in
                        for k in shown { d.write(ops[k], l, { p in let a = tf(p); return (a.0 - o.0, a.1 - o.1) }, ppm) }
                    }
                    insert(l, name, at: o, color: Self.colour(ops[first]))
                }
                i = s.range.upperBound
                continue
            }
            if let l = layer(i, ops[i]) { write(ops[i], l, tf, ppm) }
            i += 1
        }
    }

    /// The op's stroke (or fill) colour, for an INSERT's colour.
    static func colour(_ op: DrawOp) -> RGBA? {
        switch op {
        case let .line(_, _, _, c, _), let .polyline(_, _, c, _), let .hatch(_, c, _): return c
        case let .rect(_, s, f, _), let .polygon(_, s, f, _), let .circle(_, _, s, f, _): return s ?? f
        case let .text(_, _, _, _, c, _, _), let .textBox(_, _, _, _, c, _), let .runs(_, _, c, _): return c
        case .photo, .photoFill, .checkbox: return nil
        }
    }

    /// Defines a block drawn by `draw` (block-relative metres, Y up) and returns its name: `name`, or `name-2`, … when a
    /// block of that name already holds something else. An identical body reuses the existing block.
    @discardableResult
    public mutating func block(_ name: String, _ draw: (inout SketchDXF) -> Void) -> String {
        let saved = ents
        ents = []; inBlock = true
        blockLo = (.infinity, .infinity); blockHi = (-.infinity, -.infinity)
        draw(&self)
        let body = ents, box = (lo: blockLo, hi: blockHi)
        ents = saved; inBlock = false
        var n = 1, nm = name
        while let existing = blockBody[nm] {
            if existing == body { return nm }
            n += 1; nm = "\(name)-\(n)"
        }
        blockBody[nm] = body
        blockBox[nm] = box
        blockSection += ["0", "BLOCK", "8", "0", "2", nm, "70", "0", "10", "0", "20", "0", "30", "0", "3", nm] + body + ["0", "ENDBLK", "8", "0"]
        return nm
    }

    /// An INSERT of the block `name` at `p` (metres), turned `rotation` degrees counter-clockwise.
    public mutating func insert(_ l: Layer, _ name: String, at p: (Double, Double), rotation: Double = 0, color: RGBA? = nil) {
        use(l)
        ents += ["0", "INSERT", "8", l.name] + style(l, color, []) + ["2", name, "10", q(p.0), "20", q(p.1), "30", "0"]
        if abs(rotation) > 1e-9 { ents += ["50", Self.num((rotation * 1000).rounded() / 1000)] }
        if let b = blockBox[name], b.lo.x <= b.hi.x {
            let r = rotation * .pi / 180
            for x in [b.lo.x, b.hi.x] { for y in [b.lo.y, b.hi.y] {
                cover(p.0 + (x * cos(r) - y * sin(r)) / unit, p.1 + (x * sin(r) + y * cos(r)) / unit)
            } }
        }
    }

    private mutating func noteDash(_ dash: [Double], _ ppm: Double) {
        guard options.dashes, dash.count >= 2, dashPattern == nil else { return }
        dashPattern = (dash[0] / ppm * unit, dash[1] / ppm * unit)
    }

    private mutating func outline(_ l: Layer, _ c: [Pt], _ tf: (Pt) -> (Double, Double), _ extra: [String]) {
        polyline(l, c.map(tf), closed: true, extra: extra)
    }

    /// A white or empty shape with no stroke only paints over what is under it (a background, a mask); a solid one
    /// (an SLD junction dot, a north arrow) is written as its outline.
    private func background(_ stroke: RGBA?, _ fill: RGBA?) -> Bool {
        options.skipFillOnly && stroke == nil && (fill == nil || fill == .white)
    }

    fileprivate mutating func write(_ op: DrawOp, _ l: Layer, _ tf: (Pt) -> (Double, Double), _ ppm: Double) {
        func corners(_ b: Box) -> [Pt] { [Pt(b.x, b.y), Pt(b.maxX, b.y), Pt(b.maxX, b.maxY), Pt(b.x, b.maxY)] }
        let fixed = options.fixedTextHeight
        func textHeight(_ size: Double) -> Double { fixed ?? size * 0.7 / ppm }
        switch op {
        case let .line(a, b, _, color, dash):
            noteDash(dash, ppm); line(l, tf(a), tf(b), extra: style(l, color, dash))
        case let .polyline(p, _, color, dash):
            noteDash(dash, ppm)
            polyline(l, p.map(tf), closed: false, extra: style(l, color, dash))
        case let .rect(b, stroke, fill, _):
            if background(stroke, fill) { return }
            outline(l, corners(b), tf, style(l, stroke, []))
        case let .polygon(p, stroke, fill, _):
            if background(stroke, fill) { return }
            outline(l, p, tf, style(l, stroke, []))
        case let .circle(c, r, stroke, fill, _):
            if background(stroke, fill) { return }
            circle(l, tf(c), r: r / ppm, extra: style(l, stroke ?? fill, []))
        case let .text(t, at, size, _, color, align, angle):
            if options.centreText { text(l, tf(at), height: textHeight(size), t, align: .center, middle: true, angle: 0, extra: []) }
            // sketch angles turn clockwise (Y down); DXF angles counter-clockwise
            else { text(l, tf(at), height: textHeight(size), t, align: align, middle: true, angle: -angle, extra: style(l, color, [])) }
        case let .textBox(t, r, size, bold, color, align):
            guard options.textBoxes else { return }
            let x = align == .left ? r.x : align == .center ? r.x + r.w / 2 : r.maxX
            for (i, s) in ApproxText.wrap(t, width: r.w, size: size, bold: bold).enumerated() where Double(i + 1) * size * 1.3 <= r.h + 1 {
                // baseline as `Sketch.svg` draws it
                text(l, tf(Pt(x, r.y + size * (1.0 + 1.3 * Double(i)))), height: textHeight(size), s, align: align, middle: false, angle: 0,
                     extra: style(l, color, []))
            }
        case let .hatch(r, color, sp):
            guard options.hatches, r.w > 0, r.h > 0, sp > 0 else { return }
            let e = style(l, color, [])
            for (a, b) in Self.hatchLines(r, spacing: sp) { line(l, tf(a), tf(b), extra: e) }
        case let .photo(p, r):
            guard options.outlineBoxes else { return }
            outline(l, corners(r.fit(Double(p.width), Double(p.height))), tf, [])
        case let .photoFill(_, r):
            guard options.outlineBoxes else { return }
            outline(l, corners(r), tf, [])
        case let .runs(rs, at, color, align):
            write(.text(rs.map(\.text).joined(), at: at, size: rs.map(\.size).max() ?? 10, color: color, align: align), l, tf, ppm)
        case let .checkbox(r, on):
            guard options.outlineBoxes else { return }
            outline(l, corners(r), tf, [])
            if on { line(l, tf(Pt(r.x, r.y)), tf(Pt(r.maxX, r.maxY))); line(l, tf(Pt(r.maxX, r.y)), tf(Pt(r.x, r.maxY))) }
        }
    }

    /// `Sketch.svg`'s hatch lines (bottom-left to top-right, `spacing` apart), clipped to the box.
    static func hatchLines(_ r: Box, spacing sp: Double) -> [(Pt, Pt)] {
        var out: [(Pt, Pt)] = []
        var t = -r.h
        while t < r.w {
            // the line runs (r.x + t + s·h, maxY − s·h) for s in 0…1; keep the part with x inside the box
            let s0 = max(0, -t / r.h), s1 = min(1, (r.w - t) / r.h)
            if s1 > s0 { out.append((Pt(r.x + t + s0 * r.h, r.maxY - s0 * r.h), Pt(r.x + t + s1 * r.h, r.maxY - s1 * r.h))) }
            t += sp
        }
        return out
    }

    // MARK: file

    /// What the entities cover (drawing units), or a unit square when there are none.
    var extents: (min: (x: Double, y: Double), max: (x: Double, y: Double)) {
        guard lo.x <= hi.x, lo.y <= hi.y else { return (min: (x: 0, y: 0), max: (x: 1, y: 1)) }
        return (min: lo, max: hi)
    }

    /// Header, tables and entities: R12, CRLF line ends, TIS-620 bytes.
    public func data() -> Data {
        func n(_ x: Double) -> String { Self.num((x * 1000).rounded() / 1000) }
        let e = extents, ts = options.textStyle
        let w = max(e.max.x - e.min.x, 1e-3), h = max(e.max.y - e.min.y, 1e-3)
        var out = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1009", "9", "$DWGCODEPAGE", "3", "ANSI_874",
                   "9", "$INSUNITS", "70", options.millimetres ? "4" : "6",
                   "9", "$EXTMIN", "10", n(e.min.x), "20", n(e.min.y), "30", "0",
                   "9", "$EXTMAX", "10", n(e.max.x), "20", n(e.max.y), "30", "0",
                   "9", "$LIMMIN", "10", n(e.min.x), "20", n(e.min.y),
                   "9", "$LIMMAX", "10", n(e.max.x), "20", n(e.max.y),
                   "9", "$TEXTSTYLE", "7", ts.name, "0", "ENDSEC",
                   "0", "SECTION", "2", "TABLES"]
        // the view the drawing opens in: the extents with a 5 % margin
        out += ["0", "TABLE", "2", "VPORT", "70", "1",
                "0", "VPORT", "2", "*ACTIVE", "70", "0", "10", "0", "20", "0", "11", "1", "21", "1",
                "12", n((e.min.x + e.max.x) / 2), "22", n((e.min.y + e.max.y) / 2), "13", "0", "23", "0", "14", "1", "24", "1",
                "15", "0", "25", "0", "16", "0", "26", "0", "36", "1", "17", "0", "27", "0", "37", "0",
                "40", n(max(h, w / 1.5) * 1.05), "41", "1.5", "42", "50", "43", "0", "44", "0", "50", "0", "51", "0",
                "71", "0", "72", "100", "73", "1", "74", "3", "75", "0", "76", "0", "77", "0", "78", "0", "0", "ENDTAB"]
        out += ["0", "TABLE", "2", "LTYPE", "70", dashPattern == nil ? "1" : "2",
                   "0", "LTYPE", "2", "CONTINUOUS", "70", "0", "3", "Solid line", "72", "65", "73", "0", "40", "0.0"]
        if let (d, g) = dashPattern {
            out += ["0", "LTYPE", "2", "DASHED", "70", "0", "3", "Dashed __ __", "72", "65", "73", "2", "40", n(d + g), "49", n(d), "49", n(-g)]
        }
        out += ["0", "ENDTAB", "0", "TABLE", "2", "LAYER", "70", String(order.count)]
        for l in order { out += ["0", "LAYER", "2", l, "70", "0", "62", String(aciOf[l] ?? 7), "6", "CONTINUOUS"] }
        out += ["0", "ENDTAB"]
        // STANDARD stays as CAD programs expect it; the text uses `textStyle`
        out += ["0", "TABLE", "2", "STYLE", "70", ts.name == "STANDARD" ? "1" : "2"]
        for s in ts.name == "STANDARD" ? [ts] : [TextStyle(name: "STANDARD", font: "txt", width: 1), ts] {
            out += ["0", "STYLE", "2", s.name, "70", "0", "40", "0", "41", Self.num(s.width), "50", "0", "71", "0", "42", "2.5", "3", s.font, "4", ""]
        }
        out += ["0", "ENDTAB", "0", "ENDSEC"]
        if !blockSection.isEmpty { out += ["0", "SECTION", "2", "BLOCKS"] + blockSection + ["0", "ENDSEC"] }
        out += ["0", "SECTION", "2", "ENTITIES"] + ents + ["0", "ENDSEC", "0", "EOF"]
        return Self.tis620(out.joined(separator: "\r\n") + "\r\n")
    }

    public var output: RoofDXF.Output { RoofDXF.Output(data: data(), entities: entityCount, layers: order) }

    // MARK: helpers

    /// Nearest AutoCAD colour index by hue: 1 red, 30 orange, 2 yellow, 3 green, 4 cyan, 5 blue, 6 magenta; greys are
    /// 8, near-black and near-white 7.
    public static func aci(_ c: RGBA) -> Int {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
        if mx == 0 || d / mx < 0.25 { return mx < 0.35 || mx > 0.9 ? 7 : 8 }
        var h: Double
        if mx == c.r { h = (c.g - c.b) / d * 60 } else if mx == c.g { h = 120 + (c.b - c.r) / d * 60 } else { h = 240 + (c.r - c.g) / d * 60 }
        if h < 0 { h += 360 }
        switch h {
        case ..<15: return 1
        case ..<45: return 30
        case ..<70: return 2
        case ..<160: return 3
        case ..<200: return 4
        case ..<260: return 5
        case ..<330: return 6
        default: return 1
        }
    }

    /// The design's `String(number)`: integers without a decimal point, others without trailing zeros.
    static func num(_ x: Double) -> String {
        if x == x.rounded() && abs(x) < 1e15 { return String(Int(x)) }
        var s = String(format: "%.3f", x)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    /// Thai to TIS-620 bytes; "|" to "-", the symbols the app's texts use to their CAD codes or ASCII (`m²` and `m³` as
    /// the Thai drawing's ตร.ม. / ลบ.ม.), anything else outside ASCII to "?".
    static func tis620(_ s: String) -> Data {
        let s = s.replacingOccurrences(of: "ม²", with: "ตร.ม.").replacingOccurrences(of: "ม³", with: "ลบ.ม.")
        let swap: [Character: String] = [
            "·": "-", "×": "x", "□": "SHS ", "–": "-", "—": "-", "−": "-", "°": "%%d", "Ø": "%%c", "ø": "%%c", "φ": "%%c", "Φ": "%%c", "⌀": "%%c", "±": "%%p",
            "½": "1/2", "¼": "1/4", "¾": "3/4", "²": "2", "³": "3", "→": "->", "…": "...", "≥": ">=", "≤": "<=",
            "≠": "<>", "≈": "~", "÷": "/", "“": "\"", "”": "\"", "‘": "'", "’": "'", "›": ">", "•": "-",
            "✓": "/", "✕": "x", "✗": "x", "Ω": "ohm",
        ]
        var bytes: [UInt8] = []
        bytes.reserveCapacity(s.utf8.count)
        for ch in s {
            if ch == "\r\n" { bytes += [13, 10]; continue }
            for u in ch.unicodeScalars {
                let v = u.value
                // the "|" between items prints as "-", as the "·" it replaced did
                if v == 0x7C { bytes.append(UInt8(ascii: "-")) }
                else if v >= 0x20 && v <= 0x7E || v == 10 || v == 13 { bytes.append(UInt8(v)) }
                else if v >= 0x0E01 && v <= 0x0E5B { bytes.append(UInt8(v - 0x0D60)) }
                else if let r = swap[Character(u)] { bytes += Array(r.utf8) }
                else { bytes.append(UInt8(ascii: "?")) }
            }
        }
        return Data(bytes)
    }
}
