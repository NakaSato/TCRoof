import Foundation

/// Any `Sketch` as a standard DXF R2000 drawing (AC1015: handles, owners and subclass markers, every standard table,
/// `*Model_Space` / `*Paper_Space`, the layouts and the root dictionary) that AutoCAD, BricsCAD, DraftSight and LibreCAD
/// open (docs/specs/cad-export-dxf). Callers map sketch points to metres (Y up) and pick a layer per op;
/// coordinates are written in millimetres or metres. Thai text is written in TIS-620 (`$DWGCODEPAGE` ANSI_874), the
/// byte codes a Thai SHX font reads, in the text style `CORDIA` (cordia.shx, width 0.85) so CAD programs show Thai
/// instead of their default font's blanks. The header carries the drawing's extents and limits and the VPORT table its
/// view, so the drawing opens framed. Shapes are LWPOLYLINEs (a rectangle is one closed polyline, not four lines), the
/// symbols a caller marks (`Symbol`) are BLOCKs placed by INSERTs, so the drawing edits as objects in CAD, and a block can
/// hold a WIPEOUT (`wipeout`) that hides what lies under it, its frame off. The other options add what the C1 export
/// never needed.
public struct SketchDXF: Sendable {
    /// A layer and its settings in the layer manager (`CADLayers` is the team's standard).
    public struct Layer: Sendable, Hashable {
        /// A layer's linetype. CENTER and HIDDEN are declared when a layer uses them, in paper millimetres scaled by
        /// `$LTSCALE`.
        public enum Linetype: String, Sendable, Hashable { case continuous = "Continuous", center = "CENTER", hidden = "HIDDEN" }
        public var name: String
        /// AutoCAD colour index.
        public var aci: Int
        public var linetype: Linetype
        /// Lineweight in 1/100 mm (25 = 0.25 mm); -3 is the CAD program's default.
        public var lineweight: Int
        /// False: shown but never plotted.
        public var plot: Bool
        /// The layer manager's Description column.
        public var description: String
        public init(_ name: String, aci: Int, linetype: Linetype = .continuous, lineweight: Int = -3, plot: Bool = true, description: String = "") {
            self.name = name; self.aci = aci; self.linetype = linetype; self.lineweight = lineweight; self.plot = plot; self.description = description
        }
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
        /// `hatch` as a HATCH entity (pattern ANSI31 at the sketch's spacing) instead of its lines, and an opaque fill with
        /// no stroke (a junction dot, a column base) as a SOLID HATCH inside its outline.
        public var hatchEntities = true
        /// Each layer's standard lineweight, shown on screen ($LWDISPLAY). Off: every layer Default (370 = -3) and the
        /// display off, as the team's own drawings come (the roof export).
        public var lineweights = true
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

    /// A linear dimension on a sketch, in sketch points: extension lines from `a` and `b` to the dimension line through
    /// `at`, measuring along x (along y when `vertical`). `text` is what the drawing prints there and `size` its font
    /// size; the part of it that is the measured length (`4.00`) stays live in CAD.
    public struct Dimension: Sendable, Equatable {
        public var a, b, at: Pt
        public var vertical: Bool
        public var text: String
        public var size: Double
        public init(_ a: Pt, _ b: Pt, at: Pt, vertical: Bool = false, text: String, size: Double) {
            self.a = a; self.b = b; self.at = at; self.vertical = vertical; self.text = text; self.size = size
        }
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
    private var layerOf: [String: Layer] = [:]
    /// The DASHED pattern (dash, gap) in drawing units, from the first dashed op.
    private var dashPattern: (Double, Double)?
    /// What the entities cover, in drawing units (text by an estimate of its width).
    private var lo = (x: Double.infinity, y: Double.infinity), hi = (x: -Double.infinity, y: -Double.infinity)
    /// The BLOCKS section, each block's body (to compare a symbol with it) and what it covers (drawing units, from its
    /// base point).
    private var blockList: [(name: String, body: [String])] = []
    private var blockBody: [String: [String]] = [:]
    private var blockBox: [String: (lo: (x: Double, y: Double), hi: (x: Double, y: Double))] = [:]
    /// Drawing a block's body: entities on layer 0, colour BYBLOCK, measured into `blockLo` / `blockHi`.
    private var inBlock = false
    /// Coordinates to a micrometre instead of a millimetre of drawing units: the team's component blocks
    /// (`TankComponents`), whose profiles have sub-millimetre detail in a file in metres.
    var fine = false
    /// Drawing a block whose entities keep their own layers and colours (a detail sheet), not layer 0 / BYBLOCK.
    private var blockLayers = false
    /// A WIPEOUT was written: the file declares its class and its frame setting.
    private var wipeouts = false
    /// The dimension styles in use (one per text height, drawing units), in order of first use, and the dimensions written.
    /// `arrow` (drawing units) is a leader style's arrowhead (`leader`); 0 for a dimension style's ticks.
    private var dimStyles: [(name: String, height: Double, zeros: Bool, arrow: Double)] = []
    private var dimCount = 0
    private var blockLo = (x: Double.infinity, y: Double.infinity), blockHi = (x: -Double.infinity, y: -Double.infinity)

    public init(options: Options = .init()) { self.options = options }

    public var entityCount: Int { count.values.reduce(0, +) }
    /// Layers in order of first use.
    public var layers: [String] { order }
    var unit: Double { options.millimetres ? 1000 : 1 }

    // MARK: entities

    private mutating func use(_ l: Layer) {
        // a block's own layers are declared, but its entities aren't counted
        if inBlock && blockLayers, layerOf[l.name] == nil { order.append(l.name); layerOf[l.name] = l; count[l.name] = 0 }
        if inBlock { return }
        if count[l.name] == nil { order.append(l.name); layerOf[l.name] = l }
        count[l.name, default: 0] += 1
    }
    /// Handle and owner placeholders, given their values when the file is written.
    static let handle = "\u{1}H", owner = "\u{1}O"
    /// An entity's first groups: type, handle, owner, `AcDbEntity` and its layer.
    private func head(_ type: String, _ layer: String) -> [String] {
        ["0", type, "5", Self.handle, "330", Self.owner, "100", "AcDbEntity", "8", layer]
    }
    private func q(_ m: Double) -> String { fine ? Self.num((m * unit * 1e6).rounded() / 1e6, places: 6) : Self.num((m * unit * 1000).rounded() / 1000) }
    /// Grows the extents by a point in metres.
    private mutating func cover(_ x: Double, _ y: Double) {
        if inBlock { blockLo = (min(blockLo.x, x * unit), min(blockLo.y, y * unit)); blockHi = (max(blockHi.x, x * unit), max(blockHi.y, y * unit)); return }
        lo = (min(lo.x, x * unit), min(lo.y, y * unit)); hi = (max(hi.x, x * unit), max(hi.y, y * unit))
    }
    /// The layer an entity goes on: 0 inside a block, so the INSERT's layer shows through.
    private func layerName(_ l: Layer) -> String { inBlock && !blockLayers ? "0" : l.name }
    /// Linetype and colour groups after the layer.
    private func style(_ l: Layer, _ color: RGBA?, _ dash: [Double]) -> [String] {
        var g: [String] = []
        if options.dashes, dash.count >= 2 { g += ["6", "DASHED"] }
        // inside a block: BYBLOCK, so the INSERT's layer and colour show through
        if inBlock && !blockLayers { return g + ["62", "0"] }
        if options.opColours, let color, Self.aci(color) != l.aci { g += ["62", String(Self.aci(color))] }
        return g
    }

    public mutating func line(_ l: Layer, _ a: (Double, Double), _ b: (Double, Double)) { line(l, a, b, extra: []) }
    /// The entity's own colour (ACI) when it isn't the layer's.
    private func colourGroup(_ l: Layer, _ aci: Int) -> [String] { inBlock && !blockLayers ? ["62", "0"] : aci == l.aci ? [] : ["62", String(aci)] }
    /// A LINE in colour `aci`.
    public mutating func line(_ l: Layer, _ a: (Double, Double), _ b: (Double, Double), aci: Int) { line(l, a, b, extra: colourGroup(l, aci)) }
    /// A polyline in colour `aci`.
    public mutating func polyline(_ l: Layer, _ pts: [(Double, Double)], closed: Bool, aci: Int) { polyline(l, pts, closed: closed, extra: colourGroup(l, aci)) }
    /// A SOLID HATCH in colour `aci`.
    public mutating func solid(_ l: Layer, _ pts: [(Double, Double)], aci: Int) { solid(l, pts, extra: colourGroup(l, aci)) }
    /// A TEXT in colour `aci`, from its baseline.
    public mutating func text(_ l: Layer, _ p: (Double, Double), height: Double, _ s: String, align: TextAlign, angle: Double, aci: Int) {
        text(l, p, height: height, s, align: align, middle: false, angle: angle, extra: colourGroup(l, aci))
    }
    private mutating func line(_ l: Layer, _ a: (Double, Double), _ b: (Double, Double), extra: [String]) {
        guard hypot(b.0 - a.0, b.1 - a.1) > 1e-6 else { return }
        use(l); ents += head("LINE", layerName(l)) + extra + ["100", "AcDbLine", "10", q(a.0), "20", q(a.1), "30", "0", "11", q(b.0), "21", q(b.1), "31", "0"]
        cover(a.0, a.1); cover(b.0, b.1)
    }
    public mutating func circle(_ l: Layer, _ c: (Double, Double), r: Double) { circle(l, c, r: r, extra: []) }
    private mutating func circle(_ l: Layer, _ c: (Double, Double), r: Double, extra: [String]) {
        use(l); ents += head("CIRCLE", layerName(l)) + extra + ["100", "AcDbCircle", "10", q(c.0), "20", q(c.1), "30", "0", "40", q(r)]
        cover(c.0 - r, c.1 - r); cover(c.0 + r, c.1 + r)
    }
    /// One LWPOLYLINE through `pts` (metres), closed back to the first; LINEs with `polylines` off.
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
        // a dashed polyline runs its pattern on through the vertices (128)
        let flag = (closed ? 1 : 0) | (extra.contains("DASHED") ? 128 : 0)
        use(l); ents += head("LWPOLYLINE", layerName(l)) + extra + ["100", "AcDbPolyline", "90", String(p.count), "70", String(flag)]
        for v in p { ents += ["10", q(v.0), "20", q(v.1)]; cover(v.0, v.1) }
    }

    /// A WIPEOUT over the polygon `pts` (metres): it hides what is drawn before it, and its frame is off. Inside a block,
    /// write it before the block's outline so the outline shows on top.
    public mutating func wipeout(_ l: Layer, _ pts: [(Double, Double)]) {
        guard pts.count >= 3, let x0 = pts.map(\.0).min(), let x1 = pts.map(\.0).max(), let y0 = pts.map(\.1).min(),
              let y1 = pts.map(\.1).max(), x1 - x0 > 1e-6, y1 - y0 > 1e-6 else { return }
        let w = x1 - x0, h = y1 - y0
        use(l); wipeouts = true
        ents += head("WIPEOUT", layerName(l)) + ["100", "AcDbWipeout", "90", "0", "10", q(x0), "20", q(y0), "30", "0",
                                                  "11", q(w), "21", "0", "31", "0", "12", "0", "22", q(h), "32", "0", "13", "1", "23", "1",
                                                  "340", "0", "70", "7", "280", "1", "281", "50", "282", "50", "283", "0", "360", "0",
                                                  "71", "2", "91", String(pts.count + 1)]
        // the boundary in the one-pixel image's frame: centred, Y down
        func px(_ v: Double) -> String { Self.num(((v * 1e6).rounded()) / 1e6) }
        for v in pts + [pts[0]] { ents += ["14", px((v.0 - x0) / w - 0.5), "24", px(0.5 - (v.1 - y0) / h)] }
        cover(x0, y0); cover(x1, y1)
    }

    /// A linear DIMENSION (metres): extension lines from `a` and `b` to the dimension line through `p`, measuring along x
    /// (y when `vertical`), with 45° ticks and its text `height` high above the line. Its look is an anonymous block
    /// (`*D1`, …) drawn as the style draws it; the style (`TC_<height>`) has the same sizes, CORDIA text, two decimals
    /// in metres (`TC_<height>_Z` without trailing zeros, for a label like `4` or `1.5`), so CAD redraws it the same
    /// after an edit. The measured part of `text` is written as `<>` so it follows the points; any other label is kept.
    public mutating func dimension(_ l: Layer, _ a: (Double, Double), _ b: (Double, Double), at p: (Double, Double), vertical: Bool,
                                   text: String, height: Double) {
        let length = vertical ? abs(b.1 - a.1) : abs(b.0 - a.0)
        guard length > 1e-6, height > 0 else { return }
        // `4.00` as written, or `4` / `1.5` (trailing zeros suppressed, DIMZIN 8)
        var measured = String(format: "%.2f", length), zeros = true
        var label = text.range(of: measured).map { text.replacingCharacters(in: $0, with: "<>") } ?? text
        let trimmed = Self.num((length * 100).rounded() / 100)
        if label == text, text == trimmed || text.hasSuffix(" " + trimmed) {
            label = String(text.dropLast(trimmed.count)) + "<>"; measured = trimmed; zeros = false
        }
        let hu = (height * unit * (options.millimetres ? 10 : 1000)).rounded() / (options.millimetres ? 10 : 1000)
        let style = "TC_" + Self.num(hu).replacingOccurrences(of: ".", with: "_") + (zeros ? "" : "_Z")
        if !dimStyles.contains(where: { $0.name == style }) { dimStyles.append((style, hu, zeros, 0)) }
        dimCount += 1
        let tick = height * 0.4, ext = height * 0.4, gap = height * 0.25
        // a point along the measured axis and across it
        func pt(_ along: Double, _ across: Double) -> (Double, Double) { vertical ? (across, along) : (along, across) }
        let (u1, u2) = vertical ? (a.1, b.1) : (a.0, b.0), line = vertical ? p.0 : p.1
        let lo = min(u1, u2), hi = max(u1, u2), mid = (lo + hi) / 2
        // text above the line: up for a horizontal one, to the left for a vertical one (reading from the right)
        let side = vertical ? -1.0 : 1.0, textAt = pt(mid, line + side * (gap + height / 2))
        let name = block("*D\(dimCount)") { d in
            for (u, from) in [(u1, vertical ? a.0 : a.1), (u2, vertical ? b.0 : b.1)] {
                let dir: Double = line >= from ? 1 : -1
                d.line(l, pt(u, from), pt(u, line + dir * ext))
            }
            d.line(l, pt(lo - ext, line), pt(hi + ext, line))
            for u in [lo, hi] { d.line(l, (pt(u, line).0 - tick / 2, pt(u, line).1 - tick / 2), (pt(u, line).0 + tick / 2, pt(u, line).1 + tick / 2)) }
            d.text(l, textAt, height: height, label.replacingOccurrences(of: "<>", with: measured), align: .center, middle: true,
                   angle: vertical ? 90 : 0)
        }
        if let box = blockBox[name], box.lo.x <= box.hi.x { cover(box.lo.x / unit, box.lo.y / unit); cover(box.hi.x / unit, box.hi.y / unit) }
        use(l)
        let def = pt(u2, line)
        ents += head("DIMENSION", l.name) + ["100", "AcDbDimension", "2", name, "3", style,
                                              "10", q(def.0), "20", q(def.1), "30", "0", "11", q(textAt.0), "21", q(textAt.1), "31", "0",
                                              "70", "32", "71", "5", "1", label == "<>" ? "" : label,
                                              "100", "AcDbAlignedDimension", "13", q(a.0), "23", q(a.1), "33", "0", "14", q(b.0), "24", q(b.1), "34", "0",
                                              "50", vertical ? "90" : "0", "100", "AcDbRotatedDimension"]
    }

    /// A LEADER, CAD's own leader object: its arrowhead at `points[0]` (metres), its line on through the others, so it
    /// edits as one leader (drag the arrowhead and the line follows). The arrowhead is `arrow` m long, closed and filled,
    /// from the leader style `TC_LDR_<arrow>` (no ticks); the leader has no text of its own, the label is written at its
    /// tail.
    public mutating func leader(_ l: Layer, _ points: [(Double, Double)], arrow: Double) {
        guard points.count >= 2, arrow > 0 else { return }
        let au = (arrow * unit * 1000).rounded() / 1000
        let style = "TC_LDR_" + Self.num(au).replacingOccurrences(of: ".", with: "_")
        if !dimStyles.contains(where: { $0.name == style }) { dimStyles.append((style, au, true, au)) }
        use(l)
        ents += head("LEADER", layerName(l)) + ["100", "AcDbLeader", "3", style, "71", "1", "72", "0", "73", "3", "74", "0", "75", "0",
                                                 "40", "0", "41", "0", "76", String(points.count)]
        for p in points { ents += ["10", q(p.0), "20", q(p.1), "30", "0"]; cover(p.0, p.1) }
        ents += ["210", "0", "220", "0", "230", "1", "211", "1", "221", "0", "231", "0", "212", "0", "222", "0", "232", "0",
                 "213", "0", "223", "0", "233", "0"]
    }

    /// The sketch's dimensions as DIMENSIONs on `l`; the text height is `fixedTextHeight`, else the size × 0.7.
    public mutating func add(_ dims: [Dimension], layer l: Layer, transform tf: (Pt) -> (Double, Double), pointsPerMetre ppm: Double) {
        for d in dims {
            dimension(l, tf(d.a), tf(d.b), at: tf(d.at), vertical: d.vertical, text: d.text, height: options.fixedTextHeight ?? d.size * 0.7 / ppm)
        }
    }

    /// A HATCH inside the polygon `pts` (metres): ANSI31's 45° lines `spacing` metres apart (measured across them).
    public mutating func hatch(_ l: Layer, _ pts: [(Double, Double)], spacing: Double, extra: [String] = []) {
        guard pts.count >= 3, spacing > 0 else { return }
        let d = spacing * unit, k = d / 2.squareRoot()
        hatchEntity(l, boundary: Self.polygonPath(pts.map { (q($0.0), q($0.1)) }), extra: extra,
                    pattern: ["75", "1", "76", "1", "52", "0", "41", Self.num((d / 3.175 * 1e6).rounded() / 1e6), "77", "0", "78", "1",
                              "53", "45", "43", "0", "44", "0", "45", Self.num((-k * 1e6).rounded() / 1e6), "46", Self.num((k * 1e6).rounded() / 1e6), "79", "0"],
                    name: "ANSI31", solid: false)
        for v in pts { cover(v.0, v.1) }
    }

    /// A HATCH crossed at 45° and 135° (ANSI37), `spacing` metres between lines, in colour `aci`.
    public mutating func crossHatch(_ l: Layer, _ pts: [(Double, Double)], spacing: Double, aci: Int) {
        let d = spacing * unit, k = d / 2.squareRoot()
        patternHatch(l, pts, name: "ANSI37", scale: d / 3.175, aci: aci, families: [(45, (-k, k), []), (135, (-k, -k), [])])
    }

    /// A HATCH of dots (DOTS) `spacing` metres apart, in colour `aci`.
    public mutating func dotsHatch(_ l: Layer, _ pts: [(Double, Double)], spacing: Double, aci: Int) {
        let d = spacing * unit
        patternHatch(l, pts, name: "DOTS", scale: d / 1.5875, aci: aci, families: [(0, (0, d), [0, -d])])
    }

    /// A pattern HATCH from its line families (angle in degrees, offset between lines and dashes in drawing units).
    private mutating func patternHatch(_ l: Layer, _ pts: [(Double, Double)], name: String, scale: Double, aci: Int,
                                       families: [(Double, (Double, Double), [Double])]) {
        guard pts.count >= 3 else { return }
        func n6(_ x: Double) -> String { Self.num((x * 1e6).rounded() / 1e6) }
        var pattern = ["75", "1", "76", "1", "52", "0", "41", n6(scale), "77", "0", "78", String(families.count)]
        for (angle, off, dashes) in families {
            pattern += ["53", Self.num(angle), "43", "0", "44", "0", "45", n6(off.0), "46", n6(off.1), "79", String(dashes.count)]
            pattern += dashes.flatMap { ["49", n6($0)] }
        }
        hatchEntity(l, boundary: Self.polygonPath(pts.map { (q($0.0), q($0.1)) }), extra: colourGroup(l, aci), pattern: pattern, name: name, solid: false)
        for v in pts { cover(v.0, v.1) }
    }

    /// One line family of a hatch pattern as a drawing stores it, already scaled and turned: its angle (degrees), a point
    /// it passes through, the offset to the next line and its dashes (metres; negative = gap).
    public struct PatternLine: Sendable {
        public var angle: Double, base: (Double, Double), offset: (Double, Double), dashes: [Double]
        public init(angle: Double, base: (Double, Double), offset: (Double, Double), dashes: [Double]) {
            self.angle = angle; self.base = base; self.offset = offset; self.dashes = dashes
        }
    }

    /// A HATCH named `name` (AR-CONC, …) of the given line families over one or more loops (metres), as the source drew
    /// it, so it reads as that pattern in any CAD program; with no families, SOLID.
    public mutating func patternHatch(_ l: Layer, loops: [[(Double, Double)]], name: String, lines: [PatternLine]) {
        let ls = loops.filter { $0.count >= 3 }
        guard !ls.isEmpty else { return }
        func n6(_ x: Double) -> String { Self.num((x * unit * 1e7).rounded() / 1e7, places: 7) }
        var boundary: [String] = []
        // every loop an outer boundary (the team's toppings hatch the regions around the base as separate loops)
        for loop in ls {
            boundary += ["92", "3", "72", "0", "73", "1", "93", String(loop.count)] + loop.flatMap { ["10", q($0.0), "20", q($0.1)] }
            for v in loop { cover(v.0, v.1) }
        }
        let solid = lines.isEmpty
        var pattern = solid ? ["75", "0", "76", "1"] : ["75", "1", "76", "2", "52", "0", "41", "1", "77", "0", "78", String(lines.count)]
        for f in lines {
            pattern += ["53", Self.num((f.angle * 1e6).rounded() / 1e6, places: 6), "43", n6(f.base.0), "44", n6(f.base.1), "45", n6(f.offset.0), "46", n6(f.offset.1),
                        "79", String(f.dashes.count)] + f.dashes.flatMap { ["49", n6($0)] }
        }
        hatchEntity(l, boundary: boundary, extra: inBlock && !blockLayers ? ["62", "0"] : [], pattern: pattern,
                    name: solid ? "SOLID" : name, solid: solid, loops: ls.count)
    }

    /// A SOLID HATCH inside the polygon `pts` (metres).
    public mutating func solid(_ l: Layer, _ pts: [(Double, Double)], extra: [String] = []) {
        guard pts.count >= 3 else { return }
        hatchEntity(l, boundary: Self.polygonPath(pts.map { (q($0.0), q($0.1)) }), extra: extra, pattern: ["75", "0", "76", "1"], name: "SOLID", solid: true)
        for v in pts { cover(v.0, v.1) }
    }

    /// A SOLID HATCH filling the circle at `c` (metres).
    public mutating func solid(_ l: Layer, circle c: (Double, Double), r: Double, extra: [String] = []) {
        guard r > 0 else { return }
        hatchEntity(l, boundary: ["92", "1", "93", "1", "72", "2", "10", q(c.0), "20", q(c.1), "40", q(r), "50", "0", "51", "360", "73", "1"],
                    extra: extra, pattern: ["75", "0", "76", "1"], name: "SOLID", solid: true)
        cover(c.0 - r, c.1 - r); cover(c.0 + r, c.1 + r)
    }

    static func polygonPath(_ pts: [(String, String)]) -> [String] {
        ["92", "3", "72", "0", "73", "1", "93", String(pts.count)] + pts.flatMap { ["10", $0.0, "20", $0.1] }
    }

    private mutating func hatchEntity(_ layer: Layer, boundary: [String], extra: [String], pattern: [String], name: String, solid: Bool, loops: Int = 1) {
        // a hatch on its layer's HATC layer (P-FTNG-N → P-FTNG-HATC-N), so hatches freeze apart from the lines they fill;
        // inside a block it stays on 0 with the rest
        let l = inBlock && !blockLayers ? layer : CADLayers.hatch(of: layer)
        use(l)
        ents += head("HATCH", layerName(l))
        ents += extra
        ents += ["100", "AcDbHatch", "10", "0", "20", "0", "30", "0", "210", "0", "220", "0", "230", "1",
                 "2", name, "70", solid ? "1" : "0", "71", "0", "91", String(loops)]
        ents += boundary
        ents += ["97", "0"]
        ents += pattern
        ents += ["98", "0"]
    }

    /// `height` in metres; `angle` in degrees counter-clockwise; `middle` aligns the line's vertical middle on `p`.
    public mutating func text(_ l: Layer, _ p: (Double, Double), height: Double, _ s: String, align: TextAlign = .left, middle: Bool = false, angle: Double = 0) {
        text(l, p, height: height, s, align: align, middle: middle, angle: angle, extra: [])
    }
    private mutating func text(_ l: Layer, _ p: (Double, Double), height: Double, _ s: String, align: TextAlign, middle: Bool, angle: Double, extra: [String]) {
        guard !s.isEmpty else { return }
        let ts = options.textStyle
        use(l)
        ents += head("TEXT", layerName(l)) + extra + (inBlock && !blockLayers && !extra.contains("62") ? ["62", "0"] : [])
            + ["100", "AcDbText", "10", q(p.0), "20", q(p.1), "30", "0", "40", q(height), "1", s]
        // the extents: about 0.6 of the height a letter, along the angle from where the alignment puts the start
        let w = Double(s.count) * height * 0.6 * ts.width, r = angle * .pi / 180
        let start = align == .left ? 0 : align == .center ? -w / 2 : -w
        for t in [start, start + w] { for dy in [-height, height] { cover(p.0 + t * cos(r) - dy * sin(r), p.1 + t * sin(r) + dy * cos(r)) } }
        var a = angle.truncatingRemainder(dividingBy: 360); if a < 0 { a += 360 }
        if abs(a) > 1e-9 { ents += ["50", Self.num((a * 1000).rounded() / 1000)] }
        ents += ["41", Self.num(ts.width), "7", ts.name]
        let h = align == .left ? 0 : align == .center ? 1 : 2
        if h != 0 { ents += ["72", String(h)] }
        if h != 0 || middle { ents += ["11", q(p.0), "21", q(p.1), "31", "0"] }
        ents += ["100", "AcDbText"]
        if middle { ents += ["73", "2"] }
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
    /// `keepLayers` keeps each entity on its own layer and colour (a detail sheet) instead of layer 0 and BYBLOCK.
    /// Whether a block of that name is defined.
    func hasBlock(_ name: String) -> Bool { blockBody[name] != nil }

    @discardableResult
    public mutating func block(_ name: String, keepLayers: Bool = false, _ draw: (inout SketchDXF) -> Void) -> String {
        let saved = ents
        ents = []; inBlock = true; blockLayers = keepLayers
        blockLo = (.infinity, .infinity); blockHi = (-.infinity, -.infinity)
        draw(&self)
        let body = ents, box = (lo: blockLo, hi: blockHi)
        ents = saved; inBlock = false; blockLayers = false
        var n = 1, nm = name
        while let existing = blockBody[nm] {
            if existing == body { return nm }
            n += 1; nm = "\(name)-\(n)"
        }
        blockBody[nm] = body
        blockBox[nm] = box
        blockList.append((nm, body))
        return nm
    }

    /// An INSERT of the block `name` at `p` (metres), turned `rotation` degrees counter-clockwise and scaled `scale` times.
    public mutating func insert(_ l: Layer, _ name: String, at p: (Double, Double), rotation: Double = 0, scale: Double = 1, color: RGBA? = nil) {
        insert(l, name, at: p, rotation: rotation, xScale: scale, yScale: scale, color: color)
    }

    /// An INSERT stretched `xScale` along the block's x and `yScale` along its y (a module drawn at another length).
    public mutating func insert(_ l: Layer, _ name: String, at p: (Double, Double), rotation: Double = 0, xScale: Double, yScale: Double, color: RGBA? = nil) {
        use(l)
        ents += head("INSERT", l.name) + style(l, color, []) + ["100", "AcDbBlockReference", "2", name, "10", q(p.0), "20", q(p.1), "30", "0"]
        func n(_ k: Double) -> String { Self.num((k * 1e6).rounded() / 1e6, places: 6) }
        if abs(xScale - 1) > 1e-12 || abs(yScale - 1) > 1e-12 { ents += ["41", n(xScale), "42", n(yScale), "43", n(yScale)] }
        if abs(rotation) > 1e-9 { ents += ["50", Self.num((rotation * 1000).rounded() / 1000)] }
        if let b = blockBox[name], b.lo.x <= b.hi.x {
            let r = rotation * .pi / 180
            for x in [b.lo.x * xScale, b.hi.x * xScale] { for y in [b.lo.y * yScale, b.hi.y * yScale] {
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

    /// An opaque, coloured fill with no stroke: a junction dot, a column base, a solid arrow.
    private func solidFill(_ stroke: RGBA?, _ fill: RGBA?) -> Bool {
        guard options.hatchEntities, stroke == nil, let f = fill, f.a >= 0.99 else { return false }
        return !(f.r > 0.97 && f.g > 0.97 && f.b > 0.97)
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
            if solidFill(stroke, fill) { solid(l, corners(b).map(tf), extra: style(l, fill, [])) }
            outline(l, corners(b), tf, style(l, stroke ?? fill, []))
        case let .polygon(p, stroke, fill, _):
            if background(stroke, fill) { return }
            if solidFill(stroke, fill) { solid(l, p.map(tf), extra: style(l, fill, [])) }
            outline(l, p, tf, style(l, stroke ?? fill, []))
        case let .circle(c, r, stroke, fill, _):
            if background(stroke, fill) { return }
            if solidFill(stroke, fill) { solid(l, circle: tf(c), r: r / ppm, extra: style(l, fill, [])) }
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
            // the sketch's lines are `sp` apart along x, so sp / √2 across them
            if options.hatchEntities { hatch(l, corners(r).map(tf), spacing: sp / ppm / 2.squareRoot(), extra: e); return }
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

    /// The plot scale (1 : n) that fits the drawing on an A3 sheet (400 × 277 mm usable), from the usual scales.
    public var plotScale: Double {
        let e = extents, mm = options.millimetres ? 1.0 : 1000
        let need = max((e.max.x - e.min.x) * mm / 400, (e.max.y - e.min.y) * mm / 277)
        return [1, 2, 5, 10, 20, 25, 50, 75, 100, 125, 200, 250, 500, 1000, 2000, 5000].first { $0 >= need } ?? need.rounded(.up)
    }
    /// `$LTSCALE`: the plot scale, so a CENTER or HIDDEN line prints with its paper-millimetre pattern (× 0.001 in a
    /// metre drawing).
    var ltScale: Double { plotScale * (options.millimetres ? 1 : 0.001) }

    /// What the entities cover (drawing units), or a unit square when there are none.
    var extents: (min: (x: Double, y: Double), max: (x: Double, y: Double)) {
        guard lo.x <= hi.x, lo.y <= hi.y else { return (min: (x: 0, y: 0), max: (x: 1, y: 1)) }
        return (min: lo, max: hi)
    }

    /// Header, classes, tables, blocks, entities and objects: R2000 (AC1015), CRLF line ends, TIS-620 bytes.
    public func data() -> Data {
        func n(_ x: Double) -> String { Self.num((x * 1000).rounded() / 1000) }
        func n6(_ x: Double) -> String { Self.num((x * 1e6).rounded() / 1e6) }
        var next = 0
        func h() -> String { next += 1; return String(next, radix: 16, uppercase: true) }
        /// `a` with each placeholder handle numbered and each placeholder owner set to `owner`.
        func resolve(_ a: [String], owner: String) -> [String] {
            a.map { $0 == Self.handle ? h() : $0 == Self.owner ? owner : $0 }
        }
        let e = extents, ts = options.textStyle
        let w = max(e.max.x - e.min.x, 1e-3), ht = max(e.max.y - e.min.y, 1e-3)
        // the fixed objects' handles
        let tVPort = h(), tLtype = h(), tLayer = h(), tStyle = h(), tView = h(), tUCS = h(), tAppid = h(), tDim = h(), tRecords = h()
        let root = h(), groups = h(), layouts = h(), mlines = h(), mlStandard = h(), plotStyles = h(), normal = h()
        let msRecord = h(), psRecord = h(), msLayout = h(), psLayout = h(), wipeVars = wipeouts ? h() : ""
        func table(_ name: String, _ handle: String, _ count: Int, _ records: [String], extra: [String] = []) -> [String] {
            ["0", "TABLE", "2", name, "5", handle, "330", "0", "100", "AcDbSymbolTable", "70", String(count)] + extra + records + ["0", "ENDTAB"]
        }
        func record(_ type: String, _ owner: String, _ sub: String, _ name: String, handle: String? = nil) -> [String] {
            ["0", type, "5", handle ?? h(), "330", owner, "100", "AcDbSymbolTableRecord", "100", sub, "2", name]
                + (type == "BLOCK_RECORD" ? [] : ["70", "0"])
        }

        var out = ["0", "SECTION", "2", "CLASSES"]
        for (name, cpp, app, flags, entity) in [("ACDBDICTIONARYWDFLT", "AcDbDictionaryWithDefault", "ObjectDBX Classes", "0", "0"),
                                                ("ACDBPLACEHOLDER", "AcDbPlaceHolder", "ObjectDBX Classes", "0", "0"),
                                                ("LAYOUT", "AcDbLayout", "ObjectDBX Classes", "0", "0"),
                                                ("WIPEOUTVARIABLES", "AcDbWipeoutVariables", "WipeOut", "0", "0"),
                                                ("WIPEOUT", "AcDbWipeout", "WipeOut", "127", "1")] {
            out += ["0", "CLASS", "1", name, "2", cpp, "3", app, "90", flags, "280", "0", "281", entity]
        }
        out += ["0", "ENDSEC", "0", "SECTION", "2", "TABLES"]
        // the view the drawing opens in: the extents with a 5 % margin
        out += table("VPORT", tVPort, 1, record("VPORT", tVPort, "AcDbViewportTableRecord", "*Active") + [
            "10", "0", "20", "0", "11", "1", "21", "1",
            "12", n((e.min.x + e.max.x) / 2), "22", n((e.min.y + e.max.y) / 2), "13", "0", "23", "0", "14", "1", "24", "1",
            "15", "0", "25", "0", "16", "0", "26", "0", "36", "1", "17", "0", "27", "0", "37", "0",
            "40", n(max(ht, w / 1.5) * 1.05), "41", "1.5", "42", "50", "43", "0", "44", "0", "50", "0", "51", "0",
            "71", "0", "72", "100", "73", "1", "74", "3", "75", "0", "76", "0", "77", "0", "78", "0", "281", "0", "65", "0"])
        var lt: [String] = []
        for name in ["ByBlock", "ByLayer", "Continuous"] {
            lt += record("LTYPE", tLtype, "AcDbLinetypeTableRecord", name) + ["3", name == "Continuous" ? "Solid line" : "", "72", "65", "73", "0", "40", "0"]
        }
        // the layers' linetypes, in paper millimetres at $LTSCALE 1 (× 0.001 in a metre drawing, see `ltScale`)
        let used = Set(order.compactMap { layerOf[$0]?.linetype })
        var ltCount = 3
        for (type, desc, pattern) in [(Layer.Linetype.center, "Center ____ _ ____ _", [12.0, -3, 3, -3]), (.hidden, "Hidden __ __ __", [4.0, -2])]
            where used.contains(type) {
            lt += record("LTYPE", tLtype, "AcDbLinetypeTableRecord", type.rawValue)
                + ["3", desc, "72", "65", "73", String(pattern.count), "40", n(pattern.map(abs).reduce(0, +))]
                + pattern.flatMap { ["49", n($0), "74", "0"] }
            ltCount += 1
        }
        // a sketch's own dash, in drawing units: divided by $LTSCALE so it prints as drawn
        if let (d, g) = dashPattern {
            let k = ltScale
            lt += record("LTYPE", tLtype, "AcDbLinetypeTableRecord", "DASHED")
                + ["3", "Dashed __ __", "72", "65", "73", "2", "40", n((d + g) / k), "49", n(d / k), "74", "0", "49", n(-g / k), "74", "0"]
            ltCount += 1
        }
        out += table("LTYPE", tLtype, ltCount, lt)
        // layer 0 (the blocks' layer) and Defpoints (the dimensions' points, never plotted) first, then the drawing's
        let layers = [Layer("0", aci: 7), Layer("Defpoints", aci: 7, plot: false)] + order.filter { $0 != "0" && $0 != "Defpoints" }.map { layerOf[$0]! }
        var la: [String] = []
        for l in layers {
            la += record("LAYER", tLayer, "AcDbLayerTableRecord", l.name)
                + ["62", String(l.aci), "6", l.linetype.rawValue, "290", l.plot ? "1" : "0", "370", String(options.lineweights ? l.lineweight : -3), "390", normal]
            // the description, where AutoCAD keeps it
            if !l.description.isEmpty { la += ["1001", "AcAecLayerStandard", "1000", "", "1000", l.description] }
        }
        out += table("LAYER", tLayer, layers.count, la)
        // Standard stays as CAD programs expect it; the text uses `textStyle`
        let standard = ts.name.uppercased() == "STANDARD"
        var st: [String] = [], textStyleHandle = ""
        for s in standard ? [ts] : [TextStyle(name: "Standard", font: "txt", width: 1), ts] {
            let handle = h()
            if s == ts { textStyleHandle = handle }
            st += record("STYLE", tStyle, "AcDbTextStyleTableRecord", s.name, handle: handle)
                + ["40", "0", "41", Self.num(s.width), "50", "0", "71", "0", "42", "2.5", "3", s.font, "4", ""]
        }
        out += table("STYLE", tStyle, standard ? 1 : 2, st)
        out += table("VIEW", tView, 0, []) + table("UCS", tUCS, 0, [])
        out += table("APPID", tAppid, 2, record("APPID", tAppid, "AcDbRegAppTableRecord", "ACAD")
                     + record("APPID", tAppid, "AcDbRegAppTableRecord", "AcAecLayerStandard"))
        // a style per dimension text height: ticks, the text above the line in the drawing's font, two decimals in metres
        var dimRecords: [String] = []
        for ds in dimStyles {
            let x = ds.height, f = { (v: Double) in Self.num((v * 1000).rounded() / 1000) }
            dimRecords += ["0", "DIMSTYLE", "105", h(), "330", tDim, "100", "AcDbSymbolTableRecord", "100", "AcDbDimStyleTableRecord",
                           "2", ds.name, "70", "0", "3", "", "4", "", "40", "1", "41", f(ds.arrow > 0 ? ds.arrow : x * 0.6), "42", "0", "43", f(x * 1.5), "44", f(x * 0.4),
                           "45", "0", "46", f(x * 0.4), "47", "0", "48", "0", "140", f(x), "141", "0", "142", ds.arrow > 0 ? "0" : f(x * 0.4), "143", "0.03937007874",
                           "144", options.millimetres ? "0.001" : "1", "145", "0", "146", "1", "147", f(x * 0.25),
                           "71", "0", "72", "0", "73", "0", "74", "0", "75", "0", "76", "0", "77", "1", "78", ds.zeros ? "0" : "8",
                           "170", "0", "171", "2", "172", "1", "173", "0", "174", "0", "175", "0", "176", "0", "177", "0", "178", "0",
                           "271", "2", "272", "2", "273", "2", "274", "2", "275", "0", "277", "2", "278", "46", "279", "0",
                           "280", "0", "281", "0", "282", "0", "283", "0", "284", "0", "285", "0", "286", "0", "288", "0", "289", "3",
                           "340", textStyleHandle, "371", "-2", "372", "-2"]
        }
        out += table("DIMSTYLE", tDim, 1 + dimStyles.count, dimRecords + ["0", "DIMSTYLE", "105", h(), "330", tDim, "100", "AcDbSymbolTableRecord", "100", "AcDbDimStyleTableRecord",
                                           "2", "Standard", "70", "0", "3", "", "4", "", "40", "1", "41", "2.5", "42", "0.625", "43", "3.75", "44", "1.25",
                                           "45", "0", "46", "0", "47", "0", "48", "0", "140", "2.5", "141", "2.5", "142", "0", "143", "0.03937007874",
                                           "144", "1", "145", "0", "146", "1", "147", "0.625", "71", "0", "72", "0", "73", "0", "74", "0", "75", "0",
                                           "76", "0", "77", "1", "78", "8", "170", "0", "171", "3", "172", "1", "173", "0", "174", "0", "175", "0",
                                           "176", "0", "177", "0", "178", "0", "270", "2", "271", "2", "272", "2", "273", "2", "274", "3", "275", "0",
                                           "280", "0", "281", "0", "282", "0", "283", "0", "284", "8", "285", "0", "286", "0", "287", "3", "288", "0"],
                     extra: ["100", "AcDbDimStyleTable"])
        // one record per block: the two spaces, then the drawing's blocks
        let blockRecords = blockList.map { _ in h() }
        var br = record("BLOCK_RECORD", tRecords, "AcDbBlockTableRecord", "*Model_Space", handle: msRecord) + ["340", msLayout]
            + record("BLOCK_RECORD", tRecords, "AcDbBlockTableRecord", "*Paper_Space", handle: psRecord) + ["340", psLayout]
        for (b, rec) in zip(blockList, blockRecords) {
            br += record("BLOCK_RECORD", tRecords, "AcDbBlockTableRecord", b.name, handle: rec) + ["340", "0"]
        }
        out += table("BLOCK_RECORD", tRecords, 2 + blockList.count, br)
        out += ["0", "ENDSEC", "0", "SECTION", "2", "BLOCKS"]
        func block(_ name: String, _ rec: String, _ body: [String]) -> [String] {
            // a name starting with * is anonymous (a dimension's look)
            ["0", "BLOCK", "5", h(), "330", rec, "100", "AcDbEntity", "8", "0", "100", "AcDbBlockBegin", "2", name,
             "70", name.hasPrefix("*") && !name.hasSuffix("_Space") ? "1" : "0",
             "10", "0", "20", "0", "30", "0", "3", name, "1", ""]
                + resolve(body, owner: rec) + ["0", "ENDBLK", "5", h(), "330", rec, "100", "AcDbEntity", "8", "0", "100", "AcDbBlockEnd"]
        }
        out += block("*Model_Space", msRecord, []) + block("*Paper_Space", psRecord, [])
        for (b, rec) in zip(blockList, blockRecords) { out += block(b.name, rec, b.body) }
        out += ["0", "ENDSEC", "0", "SECTION", "2", "ENTITIES"] + resolve(ents, owner: msRecord) + ["0", "ENDSEC"]

        // the root dictionary and what CAD programs look for in it
        out += ["0", "SECTION", "2", "OBJECTS",
                "0", "DICTIONARY", "5", root, "330", "0", "100", "AcDbDictionary", "281", "1",
                "3", "ACAD_GROUP", "350", groups, "3", "ACAD_LAYOUT", "350", layouts, "3", "ACAD_MLINESTYLE", "350", mlines,
                "3", "ACAD_PLOTSTYLENAME", "350", plotStyles] + (wipeouts ? ["3", "ACAD_WIPEOUT_VARS", "350", wipeVars] : [])
        out += ["0", "DICTIONARY", "5", groups, "330", root, "100", "AcDbDictionary", "281", "1",
                "0", "DICTIONARY", "5", layouts, "330", root, "100", "AcDbDictionary", "281", "1", "3", "Model", "350", msLayout, "3", "Layout1", "350", psLayout,
                "0", "DICTIONARY", "5", mlines, "330", root, "100", "AcDbDictionary", "281", "1", "3", "Standard", "350", mlStandard,
                "0", "ACDBDICTIONARYWDFLT", "5", plotStyles, "330", root, "100", "AcDbDictionary", "281", "1", "3", "Normal", "350", normal,
                "100", "AcDbDictionaryWithDefault", "340", normal,
                "0", "ACDBPLACEHOLDER", "5", normal, "330", plotStyles,
                "0", "MLINESTYLE", "5", mlStandard, "102", "{ACAD_REACTORS", "330", mlines, "102", "}", "330", mlines, "100", "AcDbMlineStyle",
                "2", "Standard", "70", "0", "3", "", "62", "256", "51", "90", "52", "90", "71", "2",
                "49", "0.5", "62", "256", "6", "BYLAYER", "49", "-0.5", "62", "256", "6", "BYLAYER"]
        for (handle, name, space, tab, rec) in [(msLayout, "Model", "1024", "0", msRecord), (psLayout, "Layout1", "0", "1", psRecord)] {
            out += ["0", "LAYOUT", "5", handle, "330", layouts, "100", "AcDbPlotSettings", "1", "", "4", "A3", "6", "",
                    "40", "7.5", "41", "20", "42", "7.5", "43", "20", "44", "420", "45", "297", "46", "0", "47", "0", "48", "0", "49", "0",
                    "140", "0", "141", "0", "142", "1", "143", "1", "70", space, "72", "1", "73", "0", "74", "5", "7", "", "75", "16",
                    "76", "0", "77", "2", "78", "300", "147", "1", "148", "0", "149", "0",
                    "100", "AcDbLayout", "1", name, "70", "1", "71", tab, "10", "0", "20", "0", "11", "420", "21", "297",
                    "12", "0", "22", "0", "32", "0", "14", "1e+20", "24", "1e+20", "34", "1e+20", "15", "-1e+20", "25", "-1e+20", "35", "-1e+20",
                    "146", "0", "13", "0", "23", "0", "33", "0", "16", "1", "26", "0", "36", "0", "17", "0", "27", "1", "37", "0",
                    "76", "1", "330", rec]
        }
        // wipeout frames off, so only the outline drawn with them shows and prints
        if wipeouts {
            out += ["0", "WIPEOUTVARIABLES", "5", wipeVars, "102", "{ACAD_REACTORS", "330", root, "102", "}", "330", root,
                    "100", "AcDbWipeoutVariables", "70", "0"]
        }
        out += ["0", "ENDSEC", "0", "EOF"]

        let header = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1015", "9", "$DWGCODEPAGE", "3", "ANSI_874",
                      "9", "$INSBASE", "10", "0", "20", "0", "30", "0",
                      "9", "$EXTMIN", "10", n(e.min.x), "20", n(e.min.y), "30", "0",
                      "9", "$EXTMAX", "10", n(e.max.x), "20", n(e.max.y), "30", "0",
                      "9", "$LIMMIN", "10", n(e.min.x), "20", n(e.min.y),
                      "9", "$LIMMAX", "10", n(e.max.x), "20", n(e.max.y),
                      "9", "$TEXTSTYLE", "7", ts.name, "9", "$CLAYER", "8", "0", "9", "$DIMSTYLE", "2", "Standard",
                      "9", "$LTSCALE", "40", n6(ltScale), "9", "$PSLTSCALE", "70", "1", "9", "$CELTYPE", "6", "BYLAYER",
                      "9", "$LWDISPLAY", "290", options.lineweights ? "1" : "0",
                      "9", "$LUNITS", "70", "2", "9", "$HANDSEED", "5", String(next + 1, radix: 16, uppercase: true),
                      "9", "$MEASUREMENT", "70", "1", "9", "$INSUNITS", "70", options.millimetres ? "4" : "6", "0", "ENDSEC"]
        return Self.tis620((header + out).joined(separator: "\r\n") + "\r\n")
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
    static func num(_ x: Double, places: Int = 3) -> String {
        if x == x.rounded() && abs(x) < 1e15 { return String(Int(x)) }
        var s = String(format: "%.\(places)f", x)
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
