import Foundation

/// An image to place in the workbook.
public struct ExcelImage: Sendable {
    public var data: Data
    public var width: Int
    public var height: Int
    public var isPNG: Bool
    public init(data: Data, width: Int, height: Int, isPNG: Bool) { self.data = data; self.width = width; self.height = height; self.isPNG = isPNG }
}

struct TemplateMeta: Decodable {
    struct Sheet: Decodable { let name: String; let path: String; let printArea: String; let drawing: String }
    let tpl: [String: Sheet]
    let cb: [String: [String: [Int]]]
}

/// What a fill function can do on one sheet.
final class SheetFill {
    let sheet: SheetXML
    var pictures: [(range: String, image: ExcelImage)] = []
    var tokens: [String: String] = [:]
    init(_ s: SheetXML) { sheet = s }

    func set(_ ref: String, _ v: String?) { sheet.set(ref, v) }
    func txt(_ ref: String, _ v: String?) { sheet.set(ref, v, asText: true) }
    func tick(_ ref: String, _ on: Bool) { sheet.tick(ref, on) }
    func label(_ ref: String, _ v: String?, append: Bool = false) { sheet.fillLabel(ref, v, append: append) }
    func raw(_ ref: String, _ s: String) { sheet.setRaw(ref, s) }
    func pic(_ range: String, _ img: ExcelImage?) { if let img { pictures.append((range, img)) } }
    /// Ticks the cell of the chosen option.
    func radio(_ chosen: String?, _ options: [String], _ cells: [String]) {
        for (i, o) in options.enumerated() where i < cells.count { tick(cells[i], chosen == o) }
    }
}

/// The user's NO.224 workbook opened as a template.
final class Workbook {
    static let ctSheet = "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"
    static let ctDrawing = "application/vnd.openxmlformats-officedocument.drawing+xml"
    static let ctDiagramData = "application/vnd.openxmlformats-officedocument.drawingml.diagramData+xml"
    static let ctDiagramDrawing = "application/vnd.ms-office.drawingml.diagramDrawing+xml"

    var zip: ZipArchive
    let meta: TemplateMeta
    var workbook: String, workbookRels: String, contentTypes: String
    let shared: [String]
    private var used: Set<String> = []
    private var media = 0
    private(set) var out: [(name: String, path: String, key: String)] = []
    private(set) var pictureCount = 0

    struct Instance { let key: String; let path: String; let drawing: String }

    init(template: Data, meta: TemplateMeta) throws {
        zip = try ZipArchive(template)
        self.meta = meta
        workbook = zip.string("xl/workbook.xml") ?? ""
        workbookRels = zip.string("xl/_rels/workbook.xml.rels") ?? ""
        contentTypes = zip.string("[Content_Types].xml") ?? ""
        var sh: [String] = []
        if let ss = zip.string("xl/sharedStrings.xml") {
            var idx = ss.startIndex
            while let a = ss.range(of: "<si>", range: idx..<ss.endIndex), let b = ss.range(of: "</si>", range: a.upperBound..<ss.endIndex) {
                sh.append(XML.runsText(String(ss[a.upperBound..<b.lowerBound])))
                idx = b.upperBound
            }
        }
        shared = sh
    }

    private func next(_ prefix: String, _ ext: String) -> String {
        var n = 1
        while zip.contains("\(prefix)\(n).\(ext)") { n += 1 }
        return "\(prefix)\(n).\(ext)"
    }
    private func override(_ part: String, _ type: String) {
        contentTypes = contentTypes.replacingOccurrences(of: "</Types>", with: "<Override PartName=\"/\(part)\" ContentType=\"\(type)\"/></Types>")
    }
    private static func file(_ p: String) -> String { String(p.split(separator: "/").last ?? "") }
    private static func drawingRels(_ d: String) -> String { d.replacingOccurrences(of: "drawings/", with: "drawings/_rels/") + ".rels" }
    private static func diagramTarget(_ rels: String, _ kind: String) -> String? {
        guard let r = rels.range(of: "Target=\"\\.\\./diagrams/\(kind)\\d+\\.xml\"", options: .regularExpression) else { return nil }
        let s = rels[r].dropFirst("Target=\"../diagrams/".count).dropLast()
        return String(s)
    }

    /// First use of a template sheet = the sheet itself; later uses = a copy with its own drawing (and SmartArt).
    func instance(_ key: String) throws -> Instance {
        guard let T = meta.tpl[key] else { throw ExcelExporter.Failure.template("no sheet \(key)") }
        if !used.contains(key) { used.insert(key); return Instance(key: key, path: T.path, drawing: T.drawing) }
        let sheetPath = next("xl/worksheets/sheet", "xml"), drawPath = next("xl/drawings/drawing", "xml")
        let srel = "xl/worksheets/_rels/\(Self.file(T.path)).rels"
        zip.set(sheetPath, zip.data(T.path)!)
        zip.set("xl/worksheets/_rels/\(Self.file(sheetPath)).rels",
                (zip.string(srel) ?? "").replacingOccurrences(of: "../drawings/\(Self.file(T.drawing))", with: "../drawings/\(Self.file(drawPath))"))
        var dr = zip.string(Self.drawingRels(T.drawing)) ?? ""
        for kind in ["data", "drawing"] {
            guard let f = Self.diagramTarget(dr, kind) else { continue }
            let np = next("xl/diagrams/\(kind)", "xml")
            zip.set(np, zip.data("xl/diagrams/" + f)!)
            dr = dr.replacingOccurrences(of: "../diagrams/\(f)", with: "../diagrams/\(Self.file(np))")
            override(np, kind == "data" ? Self.ctDiagramData : Self.ctDiagramDrawing)
        }
        zip.set(Self.drawingRels(drawPath), dr)
        zip.set(drawPath, zip.data(T.drawing)!)
        override(sheetPath, Self.ctSheet)
        override(drawPath, Self.ctDrawing)
        return Instance(key: key, path: sheetPath, drawing: drawPath)
    }

    func fill(_ inst: Instance, name: String, _ body: (SheetFill) -> Void) {
        var cb: [String: (off: String, on: String)] = [:]
        for (ref, st) in meta.cb[inst.key] ?? [:] where st.count == 2 { cb[ref] = (String(st[0]), String(st[1])) }
        let sheet = SheetXML(zip.string(inst.path) ?? "", shared: shared, checkboxStyles: cb)
        let api = SheetFill(sheet)
        body(api)

        let drel = Self.drawingRels(inst.drawing)
        var dx = zip.string(inst.drawing) ?? "", dr = zip.string(drel) ?? ""
        var nextID = 1
        if let re = try? NSRegularExpression(pattern: "<xdr:cNvPr id=\"(\\d+)\"") {
            let ns = dx as NSString
            for m in re.matches(in: dx, range: NSRange(location: 0, length: ns.length)) {
                nextID = max(nextID, (Int(ns.substring(with: m.range(at: 1))) ?? 0) + 1)
            }
        }
        var anchors = ""
        for (range, img) in api.pictures {
            let f = sheet.frame(range), pad = 6.0
            let bw = f.x1 - f.x0 - 2 * pad, bh = f.y1 - f.y0 - 2 * pad
            guard bw >= 20, bh >= 20 else { continue }
            let iw = Double(max(img.width, 1)), ih = Double(max(img.height, 1))
            let k = min(bw / iw, bh / ih), w = iw * k, h = ih * k
            let x = f.x0 + pad + (bw - w) / 2, y = f.y0 + pad + (bh - h) / 2
            let A = sheet.locate(x, y), B = sheet.locate(x + w, y + h)
            media += 1
            let mp = "xl/media/survey\(media).\(img.isPNG ? "png" : "jpeg")"
            zip.set(mp, img.data)
            let id = nextID; nextID += 1
            let rid = "rIdS\(id)"
            dr = dr.replacingOccurrences(of: "</Relationships>", with: "<Relationship Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/\(Self.file(mp))\"/></Relationships>")
            anchors += "<xdr:twoCellAnchor><xdr:from><xdr:col>\(A.col)</xdr:col><xdr:colOff>\(A.colOff)</xdr:colOff><xdr:row>\(A.row)</xdr:row><xdr:rowOff>\(A.rowOff)</xdr:rowOff></xdr:from><xdr:to><xdr:col>\(B.col)</xdr:col><xdr:colOff>\(B.colOff)</xdr:colOff><xdr:row>\(B.row)</xdr:row><xdr:rowOff>\(B.rowOff)</xdr:rowOff></xdr:to><xdr:pic><xdr:nvPicPr><xdr:cNvPr id=\"\(id)\" name=\"Survey photo \(id)\"/><xdr:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(Int((w * 9525).rounded()))\" cy=\"\(Int((h * 9525).rounded()))\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:twoCellAnchor>"
            pictureCount += 1
        }
        dx = dx.replacingOccurrences(of: "</xdr:wsDr>", with: anchors + "</xdr:wsDr>")
        let tok = { (s: String) -> String in Self.replaceTokens(s, api.tokens) }
        dx = tok(dx)
        for kind in ["data", "drawing"] {
            if let f = Self.diagramTarget(dr, kind), let s = zip.string("xl/diagrams/" + f) { zip.set("xl/diagrams/" + f, tok(s)) }
        }
        zip.set(inst.drawing, dx); zip.set(drel, dr)
        zip.set(inst.path, sheet.xml(removeTabSelected: !out.isEmpty))
        out.append((name, inst.path, inst.key))
    }

    /// {{METER}}, {{T0K}}, {{T0M1}} … in shapes and SmartArt.
    static func replaceTokens(_ s: String, _ tokens: [String: String]) -> String {
        guard s.contains("{{") else { return s }
        var o = "", i = s.startIndex
        while let a = s.range(of: "{{", range: i..<s.endIndex) {
            o += s[i..<a.lowerBound]
            guard let b = s.range(of: "}}", range: a.upperBound..<s.endIndex) else { i = a.lowerBound; break }
            let k = String(s[a.upperBound..<b.lowerBound])
            if k.allSatisfy({ ($0.isUppercase || $0.isNumber) && $0.isASCII }) {
                let v = (tokens[k] ?? "").trimmingCharacters(in: .whitespaces)
                o += v.isEmpty ? (k == "METER" ? "___________________" : "_______") : " " + XML.escape(v) + " "
            } else { o += s[a.lowerBound..<b.upperBound] }
            i = b.upperBound
        }
        o += s[i...]
        return o
    }

    func finish() throws -> Data {
        var rels: [String: String] = [:]
        if let re = try? NSRegularExpression(pattern: "<Relationship ([^>]+?)/>") {
            let ns = workbookRels as NSString
            for m in re.matches(in: workbookRels, range: NSRange(location: 0, length: ns.length)) {
                let a = ns.substring(with: m.range(at: 1))
                guard let id = SheetXML.between(a, "Id=\"", "\""), let t = SheetXML.between(a, "Target=\"", "\"") else { continue }
                rels["xl/" + (t.hasPrefix("/xl/") ? String(t.dropFirst(4)) : t)] = id
            }
        }
        var wbr = workbookRels
        let usedPaths = Set(out.map(\.path))
        for (key, T) in meta.tpl where !usedPaths.contains(T.path) {
            if let id = rels[T.path], let r = wbr.range(of: "<Relationship Id=\"\(id)\"[^>]*/>", options: .regularExpression) { wbr.removeSubrange(r) }
            contentTypes = contentTypes
                .replacingOccurrences(of: "<Override PartName=\"/\(T.path)\" ContentType=\"\(Self.ctSheet)\"/>", with: "")
                .replacingOccurrences(of: "<Override PartName=\"/\(T.drawing)\" ContentType=\"\(Self.ctDrawing)\"/>", with: "")
            if key != "station" { zip.remove(T.drawing); zip.remove(Self.drawingRels(T.drawing)) }
            zip.remove(T.path); zip.remove("xl/worksheets/_rels/\(Self.file(T.path)).rels")
        }
        var sheets = "", names = "", rn = 900
        for (i, o) in out.enumerated() {
            var id = rels[o.path]
            if id == nil {
                id = "rId\(rn)"; rn += 1
                wbr = wbr.replacingOccurrences(of: "</Relationships>", with: "<Relationship Id=\"\(id!)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"\(o.path.replacingOccurrences(of: "xl/", with: ""))\"/></Relationships>")
            }
            sheets += "<sheet name=\"\(XML.escape(o.name))\" sheetId=\"\(i + 1)\" r:id=\"\(id!)\"/>"
            let pa = meta.tpl[o.key]?.printArea ?? "$A$1:$Z$70"
            names += "<definedName name=\"_xlnm.Print_Area\" localSheetId=\"\(i)\">'\(XML.escape(o.name.replacingOccurrences(of: "'", with: "''")))'!\(pa)</definedName>"
        }
        var wb = workbook
        if let a = wb.range(of: "<sheets>"), let b = wb.range(of: "</sheets>") { wb.replaceSubrange(a.lowerBound..<b.upperBound, with: "<sheets>\(sheets)</sheets>") }
        if let a = wb.range(of: "<definedNames>"), let b = wb.range(of: "</definedNames>") { wb.replaceSubrange(a.lowerBound..<b.upperBound, with: "<definedNames>\(names)</definedNames>") }
        else if let b = wb.range(of: "</sheets>") { wb.insert(contentsOf: "<definedNames>\(names)</definedNames>", at: b.upperBound) }
        zip.set("xl/workbook.xml", wb)
        zip.set("xl/_rels/workbook.xml.rels", wbr)
        zip.set("[Content_Types].xml", contentTypes)
        return try zip.write()
    }
}
