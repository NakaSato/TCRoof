import Foundation

/// Any `Sketch` as a plain DXF R12 drawing (LINE / CIRCLE / TEXT on named layers) that AutoCAD, BricsCAD, DraftSight and
/// LibreCAD open (docs/specs/cad-export-dxf). Callers map sketch points to metres (Y up) and pick a layer per op;
/// coordinates are written in millimetres or metres. Thai text is written in TIS-620 (`$DWGCODEPAGE` ANSI_874).
/// The default options write what `RoofDXF` always wrote; the others add what the C1 export never needed.
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
        public init() {}
    }

    public var options: Options
    private var ents: [String] = []
    private var count: [String: Int] = [:]
    private var order: [String] = []
    private var aciOf: [String: Int] = [:]
    /// The DASHED pattern (dash, gap) in drawing units, from the first dashed op.
    private var dashPattern: (Double, Double)?

    public init(options: Options = .init()) { self.options = options }

    public var entityCount: Int { count.values.reduce(0, +) }
    /// Layers in order of first use.
    public var layers: [String] { order }
    var unit: Double { options.millimetres ? 1000 : 1 }

    // MARK: entities

    private mutating func use(_ l: Layer) {
        if count[l.name] == nil { order.append(l.name); aciOf[l.name] = l.aci }
        count[l.name, default: 0] += 1
    }
    private func q(_ m: Double) -> String { Self.num((m * unit * 1000).rounded() / 1000) }
    /// Linetype and colour groups after the layer.
    private func style(_ l: Layer, _ color: RGBA?, _ dash: [Double]) -> [String] {
        var g: [String] = []
        if options.dashes, dash.count >= 2 { g += ["6", "DASHED"] }
        if options.opColours, let color, Self.aci(color) != l.aci { g += ["62", String(Self.aci(color))] }
        return g
    }

    public mutating func line(_ l: Layer, _ a: (Double, Double), _ b: (Double, Double)) { line(l, a, b, extra: []) }
    private mutating func line(_ l: Layer, _ a: (Double, Double), _ b: (Double, Double), extra: [String]) {
        guard hypot(b.0 - a.0, b.1 - a.1) > 1e-6 else { return }
        use(l); ents += ["0", "LINE", "8", l.name] + extra + ["10", q(a.0), "20", q(a.1), "30", "0", "11", q(b.0), "21", q(b.1), "31", "0"]
    }
    public mutating func circle(_ l: Layer, _ c: (Double, Double), r: Double) { circle(l, c, r: r, extra: []) }
    private mutating func circle(_ l: Layer, _ c: (Double, Double), r: Double, extra: [String]) {
        use(l); ents += ["0", "CIRCLE", "8", l.name] + extra + ["10", q(c.0), "20", q(c.1), "30", "0", "40", q(r)]
    }
    /// `height` in metres; `angle` in degrees counter-clockwise; `middle` aligns the line's vertical middle on `p`.
    public mutating func text(_ l: Layer, _ p: (Double, Double), height: Double, _ s: String, align: TextAlign = .left, middle: Bool = false, angle: Double = 0) {
        text(l, p, height: height, s, align: align, middle: middle, angle: angle, extra: [])
    }
    private mutating func text(_ l: Layer, _ p: (Double, Double), height: Double, _ s: String, align: TextAlign, middle: Bool, angle: Double, extra: [String]) {
        guard !s.isEmpty else { return }
        use(l); ents += ["0", "TEXT", "8", l.name] + extra + ["10", q(p.0), "20", q(p.1), "30", "0", "40", q(height), "1", s]
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
    public mutating func add(_ ops: [DrawOp], layer: (Int, DrawOp) -> Layer?, transform tf: (Pt) -> (Double, Double), pointsPerMetre ppm: Double) {
        for (i, op) in ops.enumerated() {
            guard let l = layer(i, op) else { continue }
            write(op, l, tf, ppm)
        }
    }

    private mutating func noteDash(_ dash: [Double], _ ppm: Double) {
        guard options.dashes, dash.count >= 2, dashPattern == nil else { return }
        dashPattern = (dash[0] / ppm * unit, dash[1] / ppm * unit)
    }

    private mutating func outline(_ l: Layer, _ c: [Pt], _ tf: (Pt) -> (Double, Double), _ extra: [String]) {
        for i in c.indices { line(l, tf(c[i]), tf(c[(i + 1) % c.count]), extra: extra) }
    }

    /// A white or empty shape with no stroke only paints over what is under it (a background, a mask); a solid one
    /// (an SLD junction dot, a north arrow) is written as its outline.
    private func background(_ stroke: RGBA?, _ fill: RGBA?) -> Bool {
        options.skipFillOnly && stroke == nil && (fill == nil || fill == .white)
    }

    private mutating func write(_ op: DrawOp, _ l: Layer, _ tf: (Pt) -> (Double, Double), _ ppm: Double) {
        func corners(_ b: Box) -> [Pt] { [Pt(b.x, b.y), Pt(b.maxX, b.y), Pt(b.maxX, b.maxY), Pt(b.x, b.maxY)] }
        let fixed = options.fixedTextHeight
        func textHeight(_ size: Double) -> Double { fixed ?? size * 0.7 / ppm }
        switch op {
        case let .line(a, b, _, color, dash):
            noteDash(dash, ppm); line(l, tf(a), tf(b), extra: style(l, color, dash))
        case let .polyline(p, _, color, dash):
            noteDash(dash, ppm)
            let e = style(l, color, dash)
            for i in 0..<max(0, p.count - 1) { line(l, tf(p[i]), tf(p[i + 1]), extra: e) }
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

    /// Header, tables and entities: R12, CRLF line ends, TIS-620 bytes.
    public func data() -> Data {
        var out = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1009", "9", "$DWGCODEPAGE", "3", "ANSI_874",
                   "9", "$INSUNITS", "70", options.millimetres ? "4" : "6", "0", "ENDSEC",
                   "0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LTYPE", "70", dashPattern == nil ? "1" : "2",
                   "0", "LTYPE", "2", "CONTINUOUS", "70", "0", "3", "Solid line", "72", "65", "73", "0", "40", "0.0"]
        if let (d, g) = dashPattern {
            func n(_ x: Double) -> String { Self.num((x * 1000).rounded() / 1000) }
            out += ["0", "LTYPE", "2", "DASHED", "70", "0", "3", "Dashed __ __", "72", "65", "73", "2", "40", n(d + g), "49", n(d), "49", n(-g)]
        }
        out += ["0", "ENDTAB", "0", "TABLE", "2", "LAYER", "70", String(order.count)]
        for l in order { out += ["0", "LAYER", "2", l, "70", "0", "62", String(aciOf[l] ?? 7), "6", "CONTINUOUS"] }
        out += ["0", "ENDTAB", "0", "ENDSEC", "0", "SECTION", "2", "ENTITIES"] + ents + ["0", "ENDSEC", "0", "EOF"]
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

    /// Thai to TIS-620 bytes; a few symbols to their CAD codes, anything else outside ASCII to "?".
    static func tis620(_ s: String) -> Data {
        let swap: [Character: String] = ["·": "-", "×": "x", "□": "SHS ", "–": "-", "°": "%%d", "Ø": "%%c", "½": "1/2", "¼": "1/4"]
        var bytes: [UInt8] = []
        bytes.reserveCapacity(s.utf8.count)
        for ch in s {
            if ch == "\r\n" { bytes += [13, 10]; continue }
            for u in ch.unicodeScalars {
                let v = u.value
                if v >= 0x20 && v <= 0x7E || v == 10 || v == 13 { bytes.append(UInt8(v)) }
                else if v >= 0x0E01 && v <= 0x0E5B { bytes.append(UInt8(v - 0x0D60)) }
                else if let r = swap[Character(u)] { bytes += Array(r.utf8) }
                else { bytes.append(UInt8(ascii: "?")) }
            }
        }
        return Data(bytes)
    }
}
