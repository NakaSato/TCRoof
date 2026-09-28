import Foundation

// MARK: - small XML helpers (string level; no XMLDocument on iOS)

enum XML {
    static func escape(_ s: String) -> String {
        var o = ""; o.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": o += "&amp;"
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            default:
                // drop characters XML 1.0 cannot carry
                if let a = ch.unicodeScalars.first, ch.unicodeScalars.count == 1, a.value < 0x20, a != "\n", a != "\r", a != "\t" { continue }
                o.append(ch)
            }
        }
        return o
    }
    static func unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var o = "", i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].firstIndex(of: ";"), s.distance(from: i, to: semi) <= 10 {
                let ent = s[s.index(after: i)..<semi]
                var rep: String?
                switch ent {
                case "amp": rep = "&"; case "lt": rep = "<"; case "gt": rep = ">"; case "quot": rep = "\""; case "apos": rep = "'"
                default:
                    if ent.hasPrefix("#x"), let v = UInt32(ent.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { rep = String(Character(u)) }
                    else if ent.hasPrefix("#"), let v = UInt32(ent.dropFirst()), let u = Unicode.Scalar(v) { rep = String(Character(u)) }
                }
                if let r = rep { o += r; i = s.index(after: semi); continue }
            }
            o.append(s[i]); i = s.index(after: i)
        }
        return o
    }
    /// Attributes of a start tag body such as ` r="A1" s="5"`.
    static func attributes(_ b: ArraySlice<UInt8>) -> [(String, String)] {
        var out: [(String, String)] = []
        var i = b.startIndex
        while i < b.endIndex {
            while i < b.endIndex, b[i] == 0x20 || b[i] == 0x0a || b[i] == 0x0d || b[i] == 0x09 || b[i] == 0x2f { i += 1 }
            let ns = i
            while i < b.endIndex, b[i] != 0x3d, b[i] != 0x20 { i += 1 }
            guard i < b.endIndex, b[i] == 0x3d else { break }
            let name = String(decoding: b[ns..<i], as: UTF8.self)
            i += 1
            guard i < b.endIndex else { break }
            let q = b[i]; i += 1
            let vs = i
            while i < b.endIndex, b[i] != q { i += 1 }
            out.append((name, String(decoding: b[vs..<min(i, b.endIndex)], as: UTF8.self)))
            i += 1
        }
        return out
    }
    static func find(_ p: [UInt8], in b: [UInt8], from: Int, to: Int? = nil) -> Int? {
        let end = (to ?? b.count) - p.count
        guard !p.isEmpty, from <= end else { return nil }
        let first = p[0]
        var i = from
        while i <= end {
            if b[i] == first {
                var k = 1
                while k < p.count && b[i + k] == p[k] { k += 1 }
                if k == p.count { return i }
            }
            i += 1
        }
        return nil
    }
    /// Text content of every <t> element (excluding phonetic runs).
    static func runsText(_ s: String) -> String {
        var s = s
        while let a = s.range(of: "<rPh"), let b = s.range(of: "</rPh>", range: a.upperBound..<s.endIndex) { s.removeSubrange(a.lowerBound..<b.upperBound) }
        var out = "", idx = s.startIndex
        while let a = s.range(of: "<t", range: idx..<s.endIndex) {
            guard let gt = s.range(of: ">", range: a.upperBound..<s.endIndex) else { break }
            let nameEnd = s[a.upperBound]
            if nameEnd != ">" && nameEnd != " " && nameEnd != "/" { idx = gt.upperBound; continue }
            if s[s.index(before: gt.lowerBound)] == "/" { idx = gt.upperBound; continue }
            guard let close = s.range(of: "</t>", range: gt.upperBound..<s.endIndex) else { break }
            out += unescape(String(s[gt.upperBound..<close.lowerBound]))
            idx = close.upperBound
        }
        return out
    }
}

// MARK: - cell references

enum CellRef {
    static func col(_ letters: Substring) -> Int { letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } }
    static func name(_ n: Int) -> String {
        var n = n, s = ""
        while n > 0 { let m = (n - 1) % 26; s = String(UnicodeScalar(UInt8(65 + m))) + s; n = (n - 1) / 26 }
        return s
    }
    static func split(_ ref: String) -> (col: Int, row: Int) {
        let letters = ref.prefix { $0.isLetter }
        return (col(letters), Int(ref.dropFirst(letters.count)) ?? 0)
    }
}

// MARK: - worksheet

/// One worksheet: rows and cells are parsed into an editable list, everything else is kept verbatim.
final class SheetXML {
    struct Cell { var col: Int; var attrs: [(String, String)]; var inner: String
        func attr(_ n: String) -> String? { attrs.first { $0.0 == n }?.1 }
        mutating func setAttr(_ n: String, _ v: String?) {
            if let i = attrs.firstIndex(where: { $0.0 == n }) { if let v { attrs[i].1 = v } else { attrs.remove(at: i) } }
            else if let v { attrs.append((n, v)) }
        }
    }
    struct Row { var r: Int; var attrs: [(String, String)]; var cells: [Cell]
        func attr(_ n: String) -> String? { attrs.first { $0.0 == n }?.1 }
    }

    private(set) var head: String
    private(set) var tail: String
    var rows: [Row] = []
    let shared: [String]
    let checkboxStyles: [String: (off: String, on: String)]

    // geometry
    private var defaultColWidth = 8.71, defaultRowHeight = 15.0
    private var colWidth: [Int: Double] = [:]
    private var rowHeight: [Int: Double] = [:]

    init(_ xml: String, shared: [String], checkboxStyles: [String: (off: String, on: String)] = [:]) {
        self.shared = shared; self.checkboxStyles = checkboxStyles
        let b = Array(xml.utf8)
        guard let s0 = XML.find(Array("<sheetData".utf8), in: b, from: 0), let e0 = XML.find([0x3e], in: b, from: s0) else {
            head = xml; tail = ""; return
        }
        var bodyEnd = e0 + 1
        if b[e0 - 1] == 0x2f {
            head = String(decoding: b[..<s0], as: UTF8.self) + "<sheetData>"
            tail = "</sheetData>" + String(decoding: b[(e0 + 1)...], as: UTF8.self)
        } else {
            head = String(decoding: b[...e0], as: UTF8.self)
            bodyEnd = XML.find(Array("</sheetData>".utf8), in: b, from: e0) ?? b.count
            tail = String(decoding: b[bodyEnd...], as: UTF8.self)
            parseRows(b, from: e0 + 1, to: bodyEnd)
        }
        parseGeometry()
    }

    private func parseRows(_ b: [UInt8], from: Int, to: Int) {
        let rowOpen = Array("<row".utf8), rowClose = Array("</row>".utf8), cOpen = Array("<c ".utf8), cClose = Array("</c>".utf8)
        var i = from
        while let rs = XML.find(rowOpen, in: b, from: i, to: to), let gt = XML.find([0x3e], in: b, from: rs) {
            let selfClosing = b[gt - 1] == 0x2f
            let attrs = XML.attributes(b[(rs + 4)..<(selfClosing ? gt - 1 : gt)])
            var row = Row(r: Int(attrs.first { $0.0 == "r" }?.1 ?? "") ?? ((rows.last?.r ?? 0) + 1), attrs: attrs, cells: [])
            if selfClosing { rows.append(row); i = gt + 1; continue }
            let re = XML.find(rowClose, in: b, from: gt, to: to) ?? to
            var j = gt + 1
            while let cs = XML.find(cOpen, in: b, from: j, to: re), let cg = XML.find([0x3e], in: b, from: cs) {
                let sc = b[cg - 1] == 0x2f
                let ca = XML.attributes(b[(cs + 3)..<(sc ? cg - 1 : cg)])
                var inner = ""
                if sc { j = cg + 1 } else {
                    let ce = XML.find(cClose, in: b, from: cg, to: re) ?? re
                    inner = String(decoding: b[(cg + 1)..<ce], as: UTF8.self)
                    j = ce + 4
                }
                let ref = ca.first { $0.0 == "r" }?.1 ?? ""
                row.cells.append(Cell(col: CellRef.split(ref).col, attrs: ca, inner: inner))
            }
            rows.append(row)
            i = re + rowClose.count
        }
    }

    private func parseGeometry() {
        let hb = Array(head.utf8)
        if let s = XML.find(Array("<sheetFormatPr".utf8), in: hb, from: 0), let e = XML.find([0x3e], in: hb, from: s) {
            let a = Dictionary(XML.attributes(hb[(s + 14)..<e]), uniquingKeysWith: { x, _ in x })
            if let w = a["defaultColWidth"].flatMap(Double.init) { defaultColWidth = w }
            else { defaultColWidth = (a["baseColWidth"].flatMap(Double.init) ?? 8) + 0.71 }
            defaultRowHeight = a["defaultRowHeight"].flatMap(Double.init) ?? 15
        }
        var i = 0
        let colTag = Array("<col ".utf8)
        while let s = XML.find(colTag, in: hb, from: i), let e = XML.find([0x3e], in: hb, from: s) {
            let a = Dictionary(XML.attributes(hb[(s + 5)..<e]), uniquingKeysWith: { x, _ in x })
            let lo = Int(a["min"] ?? "") ?? 1, hi = min(Int(a["max"] ?? "") ?? lo, 200)
            let w = a["hidden"] == "1" ? 0 : (a["width"].flatMap(Double.init) ?? defaultColWidth)
            if lo <= hi { for c in lo...hi { colWidth[c] = w } }
            i = e
        }
        for r in rows {
            if let h = r.attr("ht").flatMap(Double.init) { rowHeight[r.r] = r.attr("hidden") == "1" ? 0 : h }
        }
    }

    // MARK: cells

    private func rowIndex(_ r: Int) -> Int {
        var lo = 0, hi = rows.count
        while lo < hi { let m = (lo + hi) / 2; if rows[m].r < r { lo = m + 1 } else { hi = m } }
        if lo < rows.count && rows[lo].r == r { return lo }
        rows.insert(Row(r: r, attrs: [("r", String(r))], cells: []), at: lo)
        return lo
    }
    private func cellIndex(_ ref: String) -> (Int, Int) {
        let (c, r) = CellRef.split(ref)
        let ri = rowIndex(r)
        if let ci = rows[ri].cells.firstIndex(where: { $0.col >= c }) {
            if rows[ri].cells[ci].col == c { return (ri, ci) }
            rows[ri].cells.insert(Cell(col: c, attrs: [("r", ref)], inner: ""), at: ci)
            return (ri, ci)
        }
        rows[ri].cells.append(Cell(col: c, attrs: [("r", ref)], inner: ""))
        return (ri, rows[ri].cells.count - 1)
    }
    private func withCell(_ ref: String, _ f: (inout Cell) -> Void) {
        let (ri, ci) = cellIndex(ref)
        f(&rows[ri].cells[ci])
    }

    func text(_ ref: String) -> String {
        let (ri, ci) = cellIndex(ref)
        let c = rows[ri].cells[ci]
        switch c.attr("t") {
        case "s":
            guard let v = Self.between(c.inner, "<v>", "</v>"), let n = Int(v), n < shared.count else { return "" }
            return shared[n]
        case "inlineStr": return XML.runsText(c.inner)
        default: return XML.unescape(Self.between(c.inner, "<v>", "</v>") ?? "")
        }
    }
    func style(_ ref: String) -> String? { let (ri, ci) = cellIndex(ref); return rows[ri].cells[ci].attr("s") }

    /// Writes a value; digits become numbers unless `asText`.
    func set(_ ref: String, _ value: String?, asText: Bool = false) {
        let s = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        let isNum = !asText && s.count < 15 && Self.isNumber(s) && !(s.count > 1 && s.hasPrefix("0") && s.dropFirst().first != ".")
        withCell(ref) { c in
            if isNum { c.setAttr("t", nil); c.inner = "<v>\(s)</v>" }
            else { c.setAttr("t", "inlineStr"); c.inner = "<is><t xml:space=\"preserve\">\(XML.escape(s))</t></is>" }
        }
    }
    func setRaw(_ ref: String, _ s: String) {
        withCell(ref) { c in c.setAttr("t", "inlineStr"); c.inner = "<is><t xml:space=\"preserve\">\(XML.escape(s))</t></is>" }
    }
    /// Puts a value into a label cell: replaces a run of dots, or appends.
    func fillLabel(_ ref: String, _ value: String?, append: Bool = false) {
        let v = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        let cur = text(ref)
        var out: String
        if append {
            var t = cur
            while let l = t.last, l == "." || l == "…" || l.isWhitespace { t.removeLast() }
            out = t + " " + v
        } else if let r = cur.range(of: "\\.{3,}", options: .regularExpression) {
            out = cur.replacingCharacters(in: r, with: " \(v) ")
        } else { out = cur + " " + v }
        out = out.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        setRaw(ref, out)
    }
    /// Switches a checkbox cell between its empty and green-ticked style.
    func tick(_ ref: String, _ on: Bool) {
        guard let st = checkboxStyles[ref] else { return }
        withCell(ref) { $0.setAttr("s", on ? st.on : st.off) }
    }

    static func isNumber(_ s: String) -> Bool {
        var t = Substring(s)
        if t.hasPrefix("-") { t = t.dropFirst() }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts[0].isEmpty else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }
    static func between(_ s: String, _ a: String, _ b: String) -> String? {
        guard let r1 = s.range(of: a), let r2 = s.range(of: b, range: r1.upperBound..<s.endIndex) else { return nil }
        return String(s[r1.upperBound..<r2.lowerBound])
    }

    // MARK: geometry (pixels at 96 dpi; Excel column width × 7 px max digit width)

    func colPx(_ c: Int) -> Double { ((colWidth[c] ?? defaultColWidth) * 7).rounded() }
    func rowPx(_ r: Int) -> Double { (rowHeight[r] ?? defaultRowHeight) * 4 / 3 }

    struct Rect { var x0, y0, x1, y1: Double }
    func frame(_ range: String) -> Rect {
        let p = range.split(separator: ":").map(String.init)
        let (c1, r1) = CellRef.split(p[0]), (c2, r2) = CellRef.split(p.count > 1 ? p[1] : p[0])
        var x0 = 0.0; for c in stride(from: 1, to: c1, by: 1) { x0 += colPx(c) }
        var x1 = x0; for c in c1...c2 { x1 += colPx(c) }
        var y0 = 0.0; for r in stride(from: 1, to: r1, by: 1) { y0 += rowPx(r) }
        var y1 = y0; for r in r1...r2 { y1 += rowPx(r) }
        return Rect(x0: x0, y0: y0, x1: x1, y1: y1)
    }
    struct Anchor { var col, colOff, row, rowOff: Int }
    func locate(_ x: Double, _ y: Double) -> Anchor {
        var c = 1, acc = 0.0
        while acc + colPx(c) <= x && c < 300 { acc += colPx(c); c += 1 }
        let colOff = x - acc
        var r = 1; var accY = 0.0
        while accY + rowPx(r) <= y && r < 5000 { accY += rowPx(r); r += 1 }
        return Anchor(col: c - 1, colOff: Int((colOff * 9525).rounded()), row: r - 1, rowOff: Int(((y - accY) * 9525).rounded()))
    }

    // MARK: output

    func xml(removeTabSelected: Bool) -> String {
        var o = head
        o.reserveCapacity(head.count + tail.count + rows.count * 400)
        for r in rows {
            o += "<row"
            for (k, v) in r.attrs { o += " \(k)=\"\(v)\"" }
            if r.cells.isEmpty { o += "/>"; continue }
            o += ">"
            for c in r.cells {
                o += "<c"
                for (k, v) in c.attrs { o += " \(k)=\"\(v)\"" }
                o += c.inner.isEmpty ? "/>" : ">\(c.inner)</c>"
            }
            o += "</row>"
        }
        o += tail
        if removeTabSelected { o = o.replacingOccurrences(of: " tabSelected=\"1\"", with: "") }
        if !o.hasPrefix("<?xml") { o = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + o }
        return o
    }
}
