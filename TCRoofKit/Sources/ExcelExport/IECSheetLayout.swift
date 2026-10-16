import Foundation

/// One sheet of the IEC 62446 workbook as the preview draws it (docs/ui/iec62446-sheet-before): the print area's
/// columns and rows in points, merges, every cell's style (fill, font, borders, alignment, number format) and shown
/// text, and the logos. Read from an exported workbook, so the preview shows what the file holds; no UI here.
public struct IECSheetLayout: Sendable {
    public struct RGB: Equatable, Sendable { public var r, g, b: Double }

    public struct Line: Equatable, Sendable {
        /// Points: hair 0.5, thin 1, medium 2, thick 3.
        public var width: Double
        public var dashed: Bool
        public var color: RGB
    }

    public struct Style: Sendable {
        public var fill: RGB?
        public var fontSize: Double = 11
        public var bold = false
        public var color = RGB(r: 0, g: 0, b: 0)
        public var fontName = "Calibri"
        public var left: Line?, right: Line?, top: Line?, bottom: Line?
        /// `left`, `center`, `right`, or `general` (numbers right, text left).
        public var horizontal = "general"
        /// `top`, `center`, `bottom`.
        public var vertical = "bottom"
        public var wrap = false
        public var numFmt = "General"
        /// Wingdings fonts: `P` is ✓ and `O` ✗ in the form.
        public var symbols: Bool { fontName.hasPrefix("Wingdings") }
    }

    public struct Cell: Sendable {
        public var col: Int
        public var row: Int
        public var style: Int
        /// As shown: shared strings resolved, numbers in the cell's format, Wingdings ticks as ✓ / ✗.
        public var text: String
        public var isNumber: Bool
    }

    /// A merged range, 1-based and inclusive.
    public struct Merge: Equatable, Sendable { public var c0, r0, c1, r1: Int }

    public struct Image: Sendable {
        public var data: Data
        /// In points from the sheet's top left.
        public var x, y, width, height: Double
    }

    /// Column widths (index 0 = column A) and row heights (index 0 = row 1), points, over the print area.
    public var columns: [Double]
    public var rows: [Double]
    public var merges: [Merge]
    public var cells: [String: Cell]
    public var styles: [Style]
    public var images: [Image]

    public var width: Double { columns.reduce(0, +) }
    public var height: Double { rows.reduce(0, +) }

    /// The left of a 1-based column and the top of a 1-based row, points.
    public func x(_ col: Int) -> Double { columns.prefix(col - 1).reduce(0, +) }
    public func y(_ row: Int) -> Double { rows.prefix(row - 1).reduce(0, +) }

    /// The merge a cell belongs to, if any.
    public func merge(at col: Int, _ row: Int) -> Merge? {
        merges.first { (($0.c0)...($0.c1)).contains(col) && (($0.r0)...($0.r1)).contains(row) }
    }

    /// The cell under a point (the merge's top left when merged), 1-based.
    public func cell(at px: Double, _ py: Double) -> (col: Int, row: Int)? {
        guard px >= 0, py >= 0 else { return nil }
        var c = 0, acc = 0.0
        while c < columns.count, acc + columns[c] <= px { acc += columns[c]; c += 1 }
        var r = 0
        acc = 0
        while r < rows.count, acc + rows[r] <= py { acc += rows[r]; r += 1 }
        guard c < columns.count, r < rows.count else { return nil }
        if let m = merge(at: c + 1, r + 1) { return (m.c0, m.r0) }
        return (c + 1, r + 1)
    }

    // MARK: - reading

    public enum Failure: Error { case part(String) }

    /// The sheet named `sheet` (`INV 01-ก่อน`) of a workbook, over `A1:AB35`.
    public static func make(workbook data: Data, sheet name: String, lastColumn: Int = 28, lastRow: Int = 35) throws -> IECSheetLayout {
        let zip = try ZipArchive(data)
        guard let wb = zip.string("xl/workbook.xml"), let rels = zip.string("xl/_rels/workbook.xml.rels"),
              let stylesXML = zip.string("xl/styles.xml") else { throw Failure.part("workbook") }
        let escaped = SharedStrings.escape(name)
        guard let rid = attribute(in: element(wb, "<sheet name=\"\(escaped)\""), "r:id"),
              let target = attribute(in: element(rels, "<Relationship Id=\"\(rid)\""), "Target") else { throw Failure.part(name) }
        let path = "xl/" + target
        guard let xml = zip.string(path) else { throw Failure.part(path) }
        let shared = (zip.string("xl/sharedStrings.xml") ?? "").components(separatedBy: "<si>").dropFirst()
            .map { SharedStrings.plain($0.components(separatedBy: "</si>").first ?? "") }
        let theme = Self.theme(zip.string("xl/theme/theme1.xml") ?? "")
        let styles = Self.styles(stylesXML, theme: theme)
        let sheet = SheetXML(xml, shared: Array(shared))

        // geometry: Excel's width in characters of the 7 px digit → points; row heights are points
        var colW = [Double](repeating: 0, count: lastColumn), defaultW = 8.43
        if let f = attribute(in: element(sheet.head, "<sheetFormatPr"), "defaultColWidth").flatMap(Double.init) { defaultW = f }
        for i in colW.indices { colW[i] = points(chars: defaultW) }
        for col in elements(sheet.head, "<col ") {
            guard let lo = attribute(in: col, "min").flatMap(Int.init), let hi = attribute(in: col, "max").flatMap(Int.init) else { continue }
            let w = attribute(in: col, "hidden") == "1" ? 0 : points(chars: attribute(in: col, "width").flatMap(Double.init) ?? defaultW)
            for c in lo...min(hi, lastColumn) where c >= 1 { colW[c - 1] = w }
        }
        let defaultH = attribute(in: element(sheet.head, "<sheetFormatPr"), "defaultRowHeight").flatMap(Double.init) ?? 15
        var rowH = [Double](repeating: defaultH, count: lastRow)
        var cells: [String: Cell] = [:]
        for row in sheet.rows where row.r <= lastRow {
            if let h = row.attr("ht").flatMap(Double.init) { rowH[row.r - 1] = row.attr("hidden") == "1" ? 0 : h }
            for c in row.cells where c.col <= lastColumn {
                let s = Int(c.attr("s") ?? "0") ?? 0
                let style = styles.indices.contains(s) ? styles[s] : Style()
                let (text, number) = display(c, shared: Array(shared), style: style)
                cells[CellRef.name(c.col) + String(row.r)] = Cell(col: c.col, row: row.r, style: s, text: text, isNumber: number)
            }
        }
        let merges = elements(xml, "<mergeCell ").compactMap { attribute(in: $0, "ref") }.compactMap { ref -> Merge? in
            let p = ref.split(separator: ":")
            guard p.count == 2 else { return nil }
            let a = CellRef.split(String(p[0])), b = CellRef.split(String(p[1]))
            return Merge(c0: a.col, r0: a.row, c1: b.col, r1: b.row)
        }
        var layout = IECSheetLayout(columns: colW, rows: rowH, merges: merges, cells: cells, styles: styles, images: [])
        layout.images = readImages(zip, sheetPath: path, layout: layout)
        return layout
    }

    /// Excel's column width (characters of the default font's 7 px digit) in points.
    static func points(chars w: Double) -> Double { (w * 7 + 5).rounded(.down) * 0.75 }

    /// The text a cell shows.
    static func display(_ c: SheetXML.Cell, shared: [String], style: Style) -> (String, Bool) {
        let v = between(c.inner, "<v>", "</v>").map(XML.unescape) ?? ""
        var text: String, number = false
        switch c.attr("t") {
        case "s": text = Int(v).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? ""
        case "str", "e": text = v
        case "inlineStr": text = XML.runsText(c.inner)
        case "b": text = v == "1" ? "TRUE" : "FALSE"
        default:
            if let d = Double(v) { text = format(d, style.numFmt); number = true } else { text = v }
        }
        if style.symbols { text = text.replacingOccurrences(of: "P", with: "✓").replacingOccurrences(of: "O", with: "✗") }
        return (text, number)
    }

    /// Numbers as the cell's format shows them: General, `0.00`, `0%`, `0.00%`, zero-padded codes.
    public static func format(_ v: Double, _ code: String) -> String {
        let c = code.lowercased()
        if c == "general" || c.isEmpty { return IECExcel.number((v * 1e9).rounded() / 1e9) }
        let decimals = c.split(separator: ".").dropFirst().first.map { $0.filter { $0 == "0" }.count } ?? 0
        if c.contains("%") { return String(format: "%.\(decimals)f%%", v * 100) }
        if !c.contains("."), c.allSatisfy({ $0 == "0" }) { return String(format: "%0\(c.count)d", Int(v.rounded())) }
        return String(format: "%.\(decimals)f", v)
    }

    // MARK: styles

    static let builtinFormats: [Int: String] = [0: "General", 1: "0", 2: "0.00", 9: "0%", 10: "0.00%", 3: "#,##0", 4: "#,##0.00"]

    static func styles(_ xml: String, theme: [RGB]) -> [Style] {
        var formats = builtinFormats
        for f in elements(xml, "<numFmt ") {
            if let id = attribute(in: f, "numFmtId").flatMap(Int.init), let code = attribute(in: f, "formatCode") { formats[id] = XML.unescape(code) }
        }
        let fonts = blocks(section(xml, "fonts"), "font").map { f -> (Double, Bool, RGB, String) in
            let size = attribute(in: element(f, "<sz "), "val").flatMap(Double.init) ?? 11
            let name = attribute(in: element(f, "<name "), "val") ?? "Calibri"
            return (size, f.contains("<b/>"), color(element(f, "<color "), theme) ?? RGB(r: 0, g: 0, b: 0), name)
        }
        let fills = blocks(section(xml, "fills"), "fill").map { f -> RGB? in
            guard attribute(in: element(f, "<patternFill"), "patternType") == "solid" else { return nil }
            return color(element(f, "<fgColor"), theme)
        }
        let borders = blocks(section(xml, "borders"), "border").map { b -> [String: Line] in
            var out: [String: Line] = [:]
            for side in ["left", "right", "top", "bottom"] {
                let open = element(b, "<\(side)")
                guard let st = attribute(in: open, "style") else { continue }
                let inner = between(b, open, "</\(side)>") ?? ""
                let width: Double = ["thick": 3, "medium": 2, "mediumDashed": 2, "double": 2.5, "hair": 0.5][st] ?? 1
                out[side] = Line(width: width, dashed: st.lowercased().contains("dash") || st.contains("dotted") || st == "hair",
                                 color: color(element(inner, "<color"), theme) ?? RGB(r: 0, g: 0, b: 0))
            }
            return out
        }
        let xfs = blocks(section(xml, "cellXfs"), "xf", selfClosing: true)
        return xfs.map { xf in
            var s = Style()
            let head = element(xf, "<xf")
            if let i = attribute(in: head, "fontId").flatMap(Int.init), fonts.indices.contains(i) {
                (s.fontSize, s.bold, s.color, s.fontName) = fonts[i]
            }
            if let i = attribute(in: head, "fillId").flatMap(Int.init), fills.indices.contains(i) { s.fill = fills[i] }
            if let i = attribute(in: head, "borderId").flatMap(Int.init), borders.indices.contains(i) {
                let b = borders[i]
                s.left = b["left"]; s.right = b["right"]; s.top = b["top"]; s.bottom = b["bottom"]
            }
            if let id = attribute(in: head, "numFmtId").flatMap(Int.init) { s.numFmt = formats[id] ?? "General" }
            let al = element(xf, "<alignment")
            s.horizontal = attribute(in: al, "horizontal") ?? "general"
            s.vertical = attribute(in: al, "vertical") ?? "bottom"
            s.wrap = attribute(in: al, "wrapText") == "1"
            return s
        }
    }

    /// The workbook theme's colours in Excel's index order: lt1, dk1, lt2, dk2, accent 1–6, hyperlinks.
    static func theme(_ xml: String) -> [RGB] {
        func value(_ tag: String) -> RGB {
            let e = between(xml, "<a:\(tag)>", "</a:\(tag)>") ?? ""
            let hex = attribute(in: element(e, "<a:srgbClr"), "val") ?? attribute(in: element(e, "<a:sysClr"), "lastClr") ?? "000000"
            return rgb(hex)
        }
        return ["lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink"].map(value)
    }

    static func color(_ tag: String, _ theme: [RGB]) -> RGB? {
        guard !tag.isEmpty else { return nil }
        if let hex = attribute(in: tag, "rgb") { return rgb(String(hex.suffix(6))) }
        if let t = attribute(in: tag, "theme").flatMap(Int.init), theme.indices.contains(t) {
            return tinted(theme[t], attribute(in: tag, "tint").flatMap(Double.init) ?? 0)
        }
        // indexed 64 is the system foreground; the form only uses it for borders
        if attribute(in: tag, "indexed") != nil { return RGB(r: 0, g: 0, b: 0) }
        return nil
    }

    static func rgb(_ hex: String) -> RGB {
        let v = UInt32(hex, radix: 16) ?? 0
        return RGB(r: Double(v >> 16 & 0xFF) / 255, g: Double(v >> 8 & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    /// Excel's tint: towards white (positive) or black (negative) in HSL lightness.
    static func tinted(_ c: RGB, _ tint: Double) -> RGB {
        guard tint != 0 else { return c }
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        var l = (mx + mn) / 2
        let d = mx - mn
        var h = 0.0, s = 0.0
        if d > 0 {
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            h = mx == c.r ? (c.g - c.b) / d + (c.g < c.b ? 6 : 0) : mx == c.g ? (c.b - c.r) / d + 2 : (c.r - c.g) / d + 4
            h /= 6
        }
        l = tint < 0 ? l * (1 + tint) : l * (1 - tint) + tint
        func hue(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        if s == 0 { return RGB(r: l, g: l, b: l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        return RGB(r: hue(p, q, h + 1 / 3), g: hue(p, q, h), b: hue(p, q, h - 1 / 3))
    }

    // MARK: images

    /// The sheet's pictures from its drawing: a two-cell anchor, with a group's pictures placed inside it.
    static func readImages(_ zip: ZipArchive, sheetPath: String, layout: IECSheetLayout) -> [Image] {
        let file = (sheetPath as NSString).lastPathComponent
        guard let sheetRels = zip.string("xl/worksheets/_rels/\(file).rels"),
              let drawingTarget = elements(sheetRels, "<Relationship ").first(where: { $0.contains("/drawing\"") })
                .flatMap({ attribute(in: $0, "Target") }) else { return [] }
        let drawingPath = "xl/" + drawingTarget.replacingOccurrences(of: "../", with: "")
        guard let drawing = zip.string(drawingPath),
              let rels = zip.string(drawingPath.replacingOccurrences(of: "drawings/", with: "drawings/_rels/") + ".rels") else { return [] }
        var out: [Image] = []
        for anchor in drawing.components(separatedBy: "<xdr:twoCellAnchor").dropFirst() {
            func pos(_ tag: String) -> (Double, Double)? {
                guard let b = between(anchor, "<xdr:\(tag)>", "</xdr:\(tag)>") else { return nil }
                func n(_ t: String) -> Double { Double(between(b, "<xdr:\(t)>", "</xdr:\(t)>") ?? "0") ?? 0 }
                return (layout.x(Int(n("col")) + 1) + n("colOff") / 12700, layout.y(Int(n("row")) + 1) + n("rowOff") / 12700)
            }
            guard let from = pos("from"), let to = pos("to") else { continue }
            // a group maps its children's coordinates onto the anchor
            let grp = element(anchor, "<xdr:grpSpPr")
            let gx = between(anchor, grp, "</xdr:grpSpPr>") ?? ""
            let chOff = (attribute(in: element(gx, "<a:chOff"), "x").flatMap(Double.init), attribute(in: element(gx, "<a:chOff"), "y").flatMap(Double.init))
            let chExt = (attribute(in: element(gx, "<a:chExt"), "cx").flatMap(Double.init), attribute(in: element(gx, "<a:chExt"), "cy").flatMap(Double.init))
            for pic in anchor.components(separatedBy: "<xdr:pic>").dropFirst() {
                guard let rid = attribute(in: element(pic, "<a:blip"), "r:embed"),
                      let target = attribute(in: element(rels, "<Relationship Id=\"\(rid)\""), "Target"),
                      let data = zip.data("xl/" + target.replacingOccurrences(of: "../", with: "")) else { continue }
                var rect = (x: from.0, y: from.1, w: to.0 - from.0, h: to.1 - from.1)
                if let ox = chOff.0, let oy = chOff.1, let ex = chExt.0, let ey = chExt.1, ex > 0, ey > 0 {
                    let xf = element(pic, "<a:off"), xe = element(pic, "<a:ext ")
                    let px = attribute(in: xf, "x").flatMap(Double.init) ?? ox, py = attribute(in: xf, "y").flatMap(Double.init) ?? oy
                    let pw = attribute(in: xe, "cx").flatMap(Double.init) ?? ex, ph = attribute(in: xe, "cy").flatMap(Double.init) ?? ey
                    let sx = rect.w / ex, sy = rect.h / ey
                    rect = (from.0 + (px - ox) * sx, from.1 + (py - oy) * sy, pw * sx, ph * sy)
                }
                out.append(Image(data: data, x: rect.x, y: rect.y, width: rect.w, height: rect.h))
            }
        }
        return out
    }

    // MARK: small XML helpers

    static func element(_ s: String, _ open: String) -> String {
        guard let r = s.range(of: open), let end = s[r.upperBound...].firstIndex(of: ">") else { return "" }
        return String(s[r.lowerBound...end])
    }

    static func elements(_ s: String, _ open: String) -> [String] {
        s.components(separatedBy: open).dropFirst().compactMap { part in part.firstIndex(of: ">").map { open + part[...$0] } }
    }

    static func attribute(in tag: String, _ name: String) -> String? {
        guard let r = tag.range(of: " \(name)=\"") else { return nil }
        return tag[r.upperBound...].split(separator: "\"", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }

    static func between(_ s: String, _ a: String, _ b: String) -> String? {
        guard !a.isEmpty, let ra = s.range(of: a), let rb = s.range(of: b, range: ra.upperBound..<s.endIndex) else { return nil }
        return String(s[ra.upperBound..<rb.lowerBound])
    }

    static func section(_ s: String, _ tag: String) -> String { between(s, "<\(tag) ", "</\(tag)>") ?? between(s, "<\(tag)>", "</\(tag)>") ?? "" }

    /// The `<tag …>…</tag>` (or `<tag …/>`) items of a section, in order.
    static func blocks(_ s: String, _ tag: String, selfClosing: Bool = false) -> [String] {
        var out: [String] = [], rest = Substring(s)
        while let open = rest.range(of: "<\(tag)") {
            let after = rest[open.upperBound...]
            guard let next = after.first, next == " " || next == ">" || next == "/" else { rest = after; continue }
            guard let gt = after.firstIndex(of: ">") else { break }
            // `<tag/>` (a bare `<tag>` has nothing before its `>`)
            if gt > after.startIndex, after[after.index(before: gt)] == "/" {
                out.append(String(rest[open.lowerBound...gt])); rest = rest[after.index(after: gt)...]; continue
            }
            guard let close = rest.range(of: "</\(tag)>", range: gt..<rest.endIndex) else { break }
            out.append(String(rest[open.lowerBound..<close.upperBound]))
            rest = rest[close.upperBound...]
        }
        return out
    }
}
