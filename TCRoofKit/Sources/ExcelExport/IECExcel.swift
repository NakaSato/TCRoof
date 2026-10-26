import Foundation
import TCRoofCore

/// The IEC 62446 test as the PWA's own workbook (docs/specs/iec62446-excel-export-swift.md): the customer's original
/// `1FORMI1` with values typed into its input cells and nothing else changed. Sheet names, cell addresses, styles,
/// formulas and print set-up stay as they are, because the PWA's other files point at them. Each touched cell is
/// replaced in the sheet XML in place; text goes through the shared strings, reusing the original's entries.
public enum IECExcel {
    public enum Failure: Error, Equatable {
        case noInverters
        case template(String)

        public var message: String {
            switch self {
            case .noInverters: "ยังไม่ได้ตั้งค่า inverter"
            case .template(let s): "แม่แบบ Excel ผิดรูป: \(s)"
            }
        }
    }

    /// `IEC62446 <station> 2026-10-15.XLS`: the customer's own extension, so PWA files that link to the form by name
    /// keep working (the package inside is .xlsx; Excel notes the mismatch when opening it).
    public static func fileName(station: String, date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "Asia/Bangkok")!, from: date)
        let name = station.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        return String(format: "IEC62446 %@ %04d-%02d-%02d.XLS", name, c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func template() throws -> Data {
        guard let url = Bundle.module.url(forResource: "iec62446_template", withExtension: "xlsx")
                ?? Bundle.module.url(forResource: "iec62446_template", withExtension: "xlsx", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url) else { throw Failure.template("missing iec62446_template.xlsx") }
        return data
    }

    public static func export(_ r: IECReport, template: Data? = nil) throws -> Data {
        try export(r, template: template, overrides: Overrides())
    }

    /// Values a test sets instead of the derived ones (the original's hand-typed PR / Yf), and whether to tick.
    struct Overrides {
        struct Performance { var pr, yf, daily, energy7d, efficiency: Double? }
        var performance: [Int: Performance] = [:]
        var irSummary: [Int: IECReport.Check] = [:]
        var ticks = true
    }

    static func export(_ r: IECReport, template: Data?, overrides: Overrides) throws -> Data {
        guard !r.inverters.isEmpty else { throw Failure.noInverters }
        var zip = try ZipArchive(template ?? Self.template())
        guard let sstXML = zip.string("xl/sharedStrings.xml") else { throw Failure.template("sharedStrings.xml") }
        let strings = SharedStrings(sstXML)
        if r.inverters.count > 2 { try addInverterSheets(&zip, count: r.inverters.count) }

        // INV 01-ก่อน, INV 02-ก่อน, INV 01-หลัง, INV 02-หลัง, then the clones of a third inverter on
        let layout = IECReport.Phase.allCases.flatMap { phase in
            (0..<max(r.inverters.count, 2)).map { (part: "xl/worksheets/sheet\(sheetNumber($0, phase)).xml", inverter: $0, phase: phase) }
        }
        var linked: [IECReport.Phase: [String: String]] = [:]
        for phase in IECReport.Phase.allCases { linked[phase] = linkTexts(r, phase) }
        for (part, i, phase) in layout {
            guard let xml = zip.string(part) else { throw Failure.template(part) }
            var sheet = SheetCells(xml)
            let inv = r.inverters.indices.contains(i) ? r.inverters[i] : IECReport.Inverter()
            write(r, inv, inverter: i, phase: phase, into: &sheet, strings: strings, overrides: overrides)
            // formula caches: AA9, and the INV 02 sheets' links to INV 01
            sheet.setCached("AA9", .number(Double(inv.moduleCount) * r.module.powerW))
            if i > 0 { for (ref, text) in linked[phase] ?? [:] { sheet.setCached(ref, .string(text)) } }
            zip.set(part, sheet.xml)
        }
        zip.set("xl/sharedStrings.xml", strings.xml(count: layout.compactMap { zip.string($0.part) }.reduce(0) { $0 + SheetCells.sharedCount($1) }))
        if r.inverters.count == 1 { try removeSecondInverter(&zip) }
        return try zip.write()
    }

    // MARK: values

    static let columns = (0..<IECReport.slotCount).map { column(4 + $0) }

    /// 0 = A.
    static func column(_ n: Int) -> String {
        var n = n, s = ""
        repeat { s = String(UnicodeScalar(UInt8(65 + n % 26))) + s; n = n / 26 - 1 } while n >= 0
        return s
    }

    /// Shortest text that reads back as the same number: `755`, `561.2`, `0.69`.
    static func number(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        return "\(v)"
    }

    static func check(_ c: IECReport.Check?) -> String? { c.map { $0 == .normal ? "Normal" : "Abnormal" } }

    static let blankIrradiance = "Solar irradiance (เฉลี่ย) =   kWh/m2"
    static let blankArrayTemp = "Array Temperature =   (ºC)"

    /// The INV 01 cells the INV 02 sheets link to, as text, for one phase.
    static func linkTexts(_ r: IECReport, _ phase: IECReport.Phase) -> [String: String] {
        let c = phase == .before ? r.before : r.after
        return ["C3": r.stationLine,
                "E29": c.ambientC.map { String(format: "%.1f (ºC)", $0) } ?? "",
                "E30": c.irradianceWm2.map { String(format: "%.0f (W/m²)", $0) } ?? "",
                "AA30": c.time.map { $0.replacingOccurrences(of: ":", with: ".") + " น." } ?? "",
                "AA25": phase == .after ? (r.yrKWhM2Day.map { "Solar irradiance (เฉลี่ย) =   \(number($0)) kWh/m2" } ?? blankIrradiance) : blankIrradiance,
                "AA26": phase == .after ? (r.arrayTempC.map { "Array Temperature = \(number($0)) (ºC)" } ?? blankArrayTemp) : blankArrayTemp]
    }

    /// A cell the export writes: a number, text (through the shared strings), or empty.
    public enum CellValue: Equatable, Sendable { case number(Double), text(String), empty }

    /// Every input cell of a sheet (`INV 01-ก่อน`), as the export writes it: the one source of truth for the file and
    /// the in-app preview. Formula caches (AA9, the INV 02+ links) are refreshed by the export, not listed here.
    public static func cells(for r: IECReport, sheet: String) -> [String: CellValue] {
        let after = sheet.hasSuffix("หลัง")
        guard let n = Int(sheet.dropFirst(4).prefix(2)), n >= 1 else { return [:] }
        let inv = r.inverters.indices.contains(n - 1) ? r.inverters[n - 1] : IECReport.Inverter()
        return Dictionary(cells(r, inv, inverter: n - 1, phase: after ? .after : .before, overrides: Overrides()), uniquingKeysWith: { _, b in b })
    }

    /// The input cells of one inverter's sheet, in the order they are written.
    static func cells(_ r: IECReport, _ inv: IECReport.Inverter, inverter i: Int, phase: IECReport.Phase,
                      overrides: Overrides) -> [(String, CellValue)] {
        var out: [(String, CellValue)] = []
        let after = phase == .after
        func text(_ ref: String, _ s: String?) { out.append((ref, s.flatMap { $0.isEmpty ? nil : .text($0) } ?? .empty)) }
        func num(_ ref: String, _ v: Double?) { out.append((ref, v.map { .number($0) } ?? .empty)) }

        if i == 0 { for (ref, t) in linkTexts(r, phase) { text(ref, t) } }
        text("E5", "Inverter \(i + 1) (\(number(inv.ratedKW)) kW) ")
        text("O5", "S/N : \(inv.serial)")
        num("AA4", r.module.powerW > 0 ? r.module.powerW : nil)
        for (n, col) in columns.enumerated() {
            let s = inv.slots[n]
            text("\(col)8", s.map { $0.brand ?? r.module.brand })
            num("\(col)9", s.map { Double($0.modules) })
            num("\(col)10", s?.optimizers.flatMap { $0 > 0 ? Double($0) : nil })
            text("\(col)12", s?.polarityOK.map { $0 ? "P" : "O" })
            text("\(col)13", s?.irTestV.map { "\($0)V" })
            num("\(col)16", s?.vocV)
            num("\(col)18", s?.iBeforeA)
            num("\(col)17", after ? s?.vmpV : nil)
            num("\(col)19", after ? s?.impA : nil)
        }
        text("E11", check(inv.continuity))
        text("E14", check(overrides.irSummary[i] ?? r.irSummary(inv)))
        text("E20", check(inv.functionalBefore))
        text("E21", check(inv.functionalAfter))
        let o = overrides.performance[i]
        num("E22", after ? (o?.pr ?? r.pr(inv)) : nil)
        num("E23", after ? (o?.yf ?? r.yf(inv)) : nil)
        num("E24", after ? (o?.daily ?? r.dailyKWh(inv)) : nil)
        num("E25", after ? (o?.energy7d ?? inv.energy7dKWh) : nil)
        num("E26", after ? (o?.efficiency ?? r.efficiency(inv)) : nil)
        text("D31", after ? inv.remark : nil)

        for row in tickRows { out.append(("Y\(row)", .empty)); out.append(("Z\(row)", .empty)) }
        guard overrides.ticks else { return out }
        for (row, pass) in ticks(r, inv, phase).sorted(by: { $0.key < $1.key }) { out.append((pass ? "Y\(row)" : "Z\(row)", .text("✓"))) }
        return out
    }

    static func write(_ r: IECReport, _ inv: IECReport.Inverter, inverter i: Int, phase: IECReport.Phase,
                      into sheet: inout SheetCells, strings: SharedStrings, overrides: Overrides) {
        for (ref, v) in cells(r, inv, inverter: i, phase: phase, overrides: overrides) {
            switch v {
            case .empty: sheet.set(ref, .empty)
            case .number(let n): sheet.set(ref, .number(n))
            case .text(let t): sheet.set(ref, .string(strings.index(t)))
            }
        }
    }

    static let tickRows = [11, 12, 13, 16, 17, 18, 19, 20, 21, 22, 27]

    /// `ผ่าน` (true) or `ไม่ผ่าน` (false) per sheet row, from the app's rules; a row with data missing is left out.
    /// Rows 17, 19 and 22 (after the connection) only on the หลัง sheet.
    static func ticks(_ r: IECReport, _ inv: IECReport.Inverter, _ phase: IECReport.Phase) -> [Int: Bool] {
        var out: [Int: Bool] = [:]
        let strings = inv.strings.map(\.value)
        guard !strings.isEmpty else { return out }
        if let c = inv.continuity { out[11] = c == .normal }
        let polarity = strings.map(\.polarityOK)
        if !polarity.contains(nil) { out[12] = polarity.allSatisfy { $0 == true } }
        if let ir = r.irSummary(inv) { out[13] = ir == .normal }
        if strings.allSatisfy({ $0.vocV != nil }) { out[16] = r.vocOutliers(inv).isEmpty }
        let current = strings.map(\.iBeforeA)
        if !current.contains(nil) { out[18] = current.allSatisfy { $0 == 0 } }
        if let f = inv.functionalBefore { out[20] = f == .normal }
        if let f = inv.functionalAfter { out[21] = f == .normal }
        if !r.thermalPhotos.isEmpty { out[27] = true }
        if phase == .after {
            if strings.allSatisfy({ $0.vmpV != nil }) { out[17] = vmpWithinTolerance(inv) }
            if let pr = r.pr(inv) { out[22] = pr >= IECReport.defaultPRThreshold }
        }
        return out
    }

    /// Vmp, like Voc: each string within 5 % of the median of the strings with as many modules.
    static func vmpWithinTolerance(_ inv: IECReport.Inverter) -> Bool {
        let s = inv.slots.compactMap { $0 }
        for x in s {
            let peers = s.filter { $0.modules == x.modules }.compactMap(\.vmpV).sorted()
            guard peers.count > 1, let v = x.vmpV else { continue }
            let m = peers.count % 2 == 1 ? peers[peers.count / 2] : (peers[peers.count / 2 - 1] + peers[peers.count / 2]) / 2
            if m > 0, abs(v - m) / m > IECReport.vocTolerance { return false }
        }
        return true
    }

    // MARK: one inverter (spec §4)

    /// Removes `INV 02-ก่อน` and `INV 02-หลัง` and everything only they use.
    static func removeSecondInverter(_ zip: inout ZipArchive) throws {
        guard var wb = zip.string("xl/workbook.xml"), var rels = zip.string("xl/_rels/workbook.xml.rels"),
              var ct = zip.string("[Content_Types].xml"), var app = zip.string("docProps/app.xml") else { throw Failure.template("workbook parts") }
        for name in ["INV 02-ก่อน", "INV 02-หลัง"] {
            wb = wb.replacingOccurrences(of: #"<sheet name="\#(name)"[^>]*/>"#, with: "", options: .regularExpression)
            wb = wb.replacingOccurrences(of: #"<definedName name="_xlnm.Print_Area" localSheetId="\d+">'\#(name)'![^<]*</definedName>"#, with: "", options: .regularExpression)
            app = app.replacingOccurrences(of: "<vt:lpstr>\(name)</vt:lpstr>", with: "")
            app = app.replacingOccurrences(of: "<vt:lpstr>'\(name)'!Print_Area</vt:lpstr>", with: "")
        }
        // INV 01-หลัง moves from the third tab to the second
        wb = wb.replacingOccurrences(of: #"localSheetId="2">'INV 01-หลัง'"#, with: #"localSheetId="1">'INV 01-หลัง'"#)
        for id in ["rId2", "rId4"] {
            rels = rels.replacingOccurrences(of: #"<Relationship Id="\#(id)" [^>]*/>"#, with: "", options: .regularExpression)
        }
        for n in [2, 4] {
            for p in ["xl/worksheets/sheet\(n).xml", "xl/worksheets/_rels/sheet\(n).xml.rels", "xl/drawings/drawing\(n).xml",
                      "xl/drawings/_rels/drawing\(n).xml.rels", "xl/drawings/vmlDrawing\(n).vml", "xl/drawings/_rels/vmlDrawing\(n).vml.rels",
                      "xl/printerSettings/printerSettings\(n).bin"] { zip.remove(p) }
            ct = ct.replacingOccurrences(of: #"<Override PartName="/xl/worksheets/sheet\#(n).xml"[^>]*/>"#, with: "", options: .regularExpression)
            ct = ct.replacingOccurrences(of: #"<Override PartName="/xl/drawings/drawing\#(n).xml"[^>]*/>"#, with: "", options: .regularExpression)
        }
        app = app.replacingOccurrences(of: #"<vt:vector size="8" baseType="lpstr">"#, with: #"<vt:vector size="4" baseType="lpstr">"#)
        app = app.replacingOccurrences(of: "<vt:i4>4</vt:i4>", with: "<vt:i4>2</vt:i4>")
        if var chain = zip.string("xl/calcChain.xml") {
            chain = chain.replacingOccurrences(of: #"<c r="[A-Z]+\d+" i="(86|90)"( l="1")?/>"#, with: "", options: .regularExpression)
            zip.set("xl/calcChain.xml", chain)
        }
        zip.set("xl/workbook.xml", wb); zip.set("xl/_rels/workbook.xml.rels", rels)
        zip.set("[Content_Types].xml", ct); zip.set("docProps/app.xml", app)
    }

    // MARK: three or more inverters (spec §4)

    /// The sheet part of inverter `i` (0-based) in a phase: the template's 1–4, then 5 / 6 for INV 03 and so on.
    static func sheetNumber(_ i: Int, _ phase: IECReport.Phase) -> Int {
        i < 2 ? i + 1 + (phase == .after ? 2 : 0) : 2 * i + 1 + (phase == .after ? 1 : 0)
    }

    static func sheetName(_ i: Int, _ phase: IECReport.Phase) -> String {
        String(format: "INV %02d-", i + 1) + (phase == .before ? "ก่อน" : "หลัง")
    }

    /// The INV 02 formula cells, which a clone keeps pointing at INV 01.
    static let linkFormulaCells = ["AA9", "C3", "AA25", "AA26", "E29", "E30", "AA30"]

    /// Clones `INV 02-ก่อน` / `INV 02-หลัง` for INV 03 on: their own sheet, drawing, header VML and printer settings
    /// parts (the images stay shared), new sheetIds 91, 92 … and rIds 9, 10 …, the ก่อน clones after INV 02-ก่อน and
    /// the หลัง clones last, every Print_Area renumbered to its tab, their calcChain cells and `TitlesOfParts`.
    static func addInverterSheets(_ zip: inout ZipArchive, count: Int) throws {
        guard var wb = zip.string("xl/workbook.xml"), var rels = zip.string("xl/_rels/workbook.xml.rels"),
              var ct = zip.string("[Content_Types].xml"), var app = zip.string("docProps/app.xml"),
              var chain = zip.string("xl/calcChain.xml") else { throw Failure.template("workbook parts") }
        var sheetEntries: [IECReport.Phase: String] = [:]
        for phase in IECReport.Phase.allCases {
            let src = sheetNumber(1, phase)
            guard let sheet = zip.string("xl/worksheets/sheet\(src).xml"), let sheetRels = zip.string("xl/worksheets/_rels/sheet\(src).xml.rels"),
                  let drawing = zip.data("xl/drawings/drawing\(src).xml"), let drawingRels = zip.data("xl/drawings/_rels/drawing\(src).xml.rels"),
                  let vml = zip.string("xl/drawings/vmlDrawing\(src).vml"), let vmlRels = zip.data("xl/drawings/_rels/vmlDrawing\(src).vml.rels"),
                  let printer = zip.data("xl/printerSettings/printerSettings\(src).bin") else { throw Failure.template("INV 02 parts") }
            for i in 2..<count {
                let n = sheetNumber(i, phase), sheetId = 86 + n, rId = "rId\(n + 4)"
                // a sheet's own revision id, and a VML id block above the template's (85, 91, 97, 98)
                let uid = String(format: "{6800007C-B798-4FEF-9DDE-%012X}", n)
                let idmap = 94 + n
                zip.set("xl/worksheets/sheet\(n).xml", sheet.replacingOccurrences(of: #"xr:uid="\{[0-9A-F-]+\}""#, with: #"xr:uid="\#(uid)""#, options: .regularExpression))
                zip.set("xl/worksheets/_rels/sheet\(n).xml.rels", sheetRels
                    .replacingOccurrences(of: "vmlDrawing\(src).vml", with: "vmlDrawing\(n).vml")
                    .replacingOccurrences(of: "drawing\(src).xml", with: "drawing\(n).xml")
                    .replacingOccurrences(of: "printerSettings\(src).bin", with: "printerSettings\(n).bin"))
                zip.set("xl/drawings/drawing\(n).xml", drawing)
                zip.set("xl/drawings/_rels/drawing\(n).xml.rels", drawingRels)
                zip.set("xl/drawings/vmlDrawing\(n).vml", vml
                    .replacingOccurrences(of: #"data="\d+""#, with: #"data="\#(idmap)""#, options: .regularExpression)
                    .replacingOccurrences(of: #"o:spid="_x0000_s\d+""#, with: #"o:spid="_x0000_s\#(idmap * 1024 + 1)""#, options: .regularExpression))
                zip.set("xl/drawings/_rels/vmlDrawing\(n).vml.rels", vmlRels)
                zip.set("xl/printerSettings/printerSettings\(n).bin", printer)

                ct = ct.replacingOccurrences(of: "</Types>", with:
                    #"<Override PartName="/xl/worksheets/sheet\#(n).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
                    + #"<Override PartName="/xl/drawings/drawing\#(n).xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/></Types>"#)
                rels = rels.replacingOccurrences(of: "</Relationships>", with:
                    #"<Relationship Id="\#(rId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(n).xml"/></Relationships>"#)
                sheetEntries[phase, default: ""] += #"<sheet name="\#(sheetName(i, phase))" sheetId="\#(sheetId)" r:id="\#(rId)"/>"#
                chain = chain.replacingOccurrences(of: "</calcChain>", with: linkFormulaCells.map { #"<c r="\#($0)" i="\#(sheetId)"/>"# }.joined() + "</calcChain>")
            }
        }
        // tabs: every ก่อน sheet, then every หลัง sheet
        for phase in IECReport.Phase.allCases {
            let after = #"<sheet name="\#(sheetName(1, phase))"[^>]*/>"#
            guard let r = wb.range(of: after, options: .regularExpression) else { throw Failure.template("INV 02 sheet") }
            wb.insert(contentsOf: sheetEntries[phase] ?? "", at: r.upperBound)
        }
        let tabs = IECReport.Phase.allCases.flatMap { p in (0..<count).map { sheetName($0, p) } }
        // Print_Areas listed by name, as Excel keeps them
        let byName = (0..<count).flatMap { i in IECReport.Phase.allCases.map { sheetName(i, $0) } }
        let names = byName.map { #"<definedName name="_xlnm.Print_Area" localSheetId="\#(tabs.firstIndex(of: $0)!)">'\#($0)'!$A$1:$AB$35</definedName>"# }
        guard let defs = wb.range(of: "<definedNames>.*</definedNames>", options: .regularExpression) else { throw Failure.template("definedNames") }
        wb.replaceSubrange(defs, with: "<definedNames>" + names.joined() + "</definedNames>")

        app = app.replacingOccurrences(of: "<vt:i4>4</vt:i4>", with: "<vt:i4>\(2 * count)</vt:i4>")
        guard let titles = app.range(of: "<TitlesOfParts>.*</TitlesOfParts>", options: .regularExpression) else { throw Failure.template("TitlesOfParts") }
        let parts = tabs.map { "<vt:lpstr>\($0)</vt:lpstr>" } + byName.map { "<vt:lpstr>'\($0)'!Print_Area</vt:lpstr>" }
        app.replaceSubrange(titles, with: #"<TitlesOfParts><vt:vector size="\#(parts.count)" baseType="lpstr">"# + parts.joined() + "</vt:vector></TitlesOfParts>")

        zip.set("xl/workbook.xml", wb); zip.set("xl/_rels/workbook.xml.rels", rels)
        zip.set("[Content_Types].xml", ct); zip.set("docProps/app.xml", app); zip.set("xl/calcChain.xml", chain)
    }
}

// MARK: - Shared strings

/// `xl/sharedStrings.xml`: existing entries keep their index; new text is appended.
final class SharedStrings {
    private let original: String
    private var lookup: [String: Int] = [:]
    private var added: [String] = []
    private let existing: Int

    init(_ xml: String) {
        original = xml
        let items = xml.components(separatedBy: "<si>").dropFirst()
        existing = items.count
        for (i, item) in items.enumerated() {
            let body = item.components(separatedBy: "</si>").first ?? ""
            let text = Self.plain(body)
            if lookup[text] == nil { lookup[text] = i }
        }
    }

    /// The text of an `<si>`: its `<t>` runs joined, entities decoded.
    static func plain(_ si: String) -> String {
        var out = "", rest = Substring(si)
        while let open = rest.range(of: "<t") {
            guard let gt = rest[open.upperBound...].firstIndex(of: ">") else { break }
            if rest[rest.index(before: gt)] == "/" { rest = rest[rest.index(after: gt)...]; continue }
            guard let close = rest[gt...].range(of: "</t>") else { break }
            out += rest[rest.index(after: gt)..<close.lowerBound]
            rest = rest[close.upperBound...]
        }
        return unescape(out)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }

    func index(_ text: String) -> Int {
        if let i = lookup[text] { return i }
        let i = existing + added.count
        added.append(text); lookup[text] = i
        return i
    }

    /// The part with the new entries appended and `count` / `uniqueCount` recomputed.
    func xml(count: Int) -> String {
        var xml = original
        if !added.isEmpty, let end = xml.range(of: "</sst>", options: .backwards) {
            let items = added.map { t -> String in
                let keep = t.hasPrefix(" ") || t.hasSuffix(" ") || t.contains("  ") || t.contains("\n")
                return "<si><t\(keep ? #" xml:space="preserve""# : "")>\(Self.escape(t))</t></si>"
            }.joined()
            xml.replaceSubrange(end, with: items + "</sst>")
        }
        // ` count=` (lowercase, after a space) is only on <sst>; `uniqueCount=` doesn't match it
        if let r = xml.range(of: #" count="\d+""#, options: .regularExpression) { xml.replaceSubrange(r, with: #" count="\#(count)""#) }
        if let r = xml.range(of: #"uniqueCount="\d+""#, options: .regularExpression) { xml.replaceSubrange(r, with: #"uniqueCount="\#(existing + added.count)""#) }
        return xml
    }
}

// MARK: - Sheet cells

/// One sheet's XML with its `<c>` elements indexed once; cells are replaced in place, from the end, so the rest of the
/// sheet (rows, merges, print set-up) stays byte for byte.
struct SheetCells {
    /// `inline` writes the text in the cell itself (`t="inlineStr"`), for a sheet whose shared strings aren't rewritten.
    enum Value: Equatable { case number(Double), string(Int), inline(String), empty }
    enum Cached { case number(Double), string(String) }

    private(set) var source: String
    private var ranges: [String: Range<String.Index>] = [:]
    private var changes: [String: String] = [:]

    init(_ xml: String) {
        source = xml
        var i = xml.startIndex
        while let open = xml.range(of: "<c r=\"", range: i..<xml.endIndex) {
            guard let q = xml[open.upperBound...].firstIndex(of: "\""), let gt = xml[q...].firstIndex(of: ">") else { break }
            let ref = String(xml[open.upperBound..<q])
            let end: String.Index
            if xml[xml.index(before: gt)] == "/" { end = xml.index(after: gt) }
            else if let close = xml.range(of: "</c>", range: gt..<xml.endIndex) { end = close.upperBound }
            else { break }
            ranges[ref] = open.lowerBound..<end
            i = end
        }
    }

    func element(_ ref: String) -> String? { ranges[ref].map { String(source[$0]) } }
    /// Replaces a cell's whole element (a formula cell with a new cached result).
    mutating func replace(_ ref: String, _ element: String) {
        guard ranges[ref] != nil else { return }
        changes[ref] = element
    }

    /// Every cell the sheet has.
    var refs: Dictionary<String, Range<String.Index>>.Keys { ranges.keys }

    private func style(_ el: String) -> String? {
        guard let r = el.range(of: #" s="\d+""#, options: .regularExpression) else { return nil }
        return String(el[r]).dropFirst(4).dropLast().description
    }

    /// Writes an input cell, keeping its style; a cell the sheet doesn't have is skipped (the template has them all).
    mutating func set(_ ref: String, _ v: Value) {
        guard let el = element(ref) else { return }
        let s = style(el).map { #" s="\#($0)""# } ?? ""
        switch v {
        case .empty: changes[ref] = #"<c r="\#(ref)"\#(s)/>"#
        case .number(let n): changes[ref] = #"<c r="\#(ref)"\#(s)><v>\#(IECExcel.number(n))</v></c>"#
        case .string(let i): changes[ref] = #"<c r="\#(ref)"\#(s) t="s"><v>\#(i)</v></c>"#
        case .inline(let t): changes[ref] = #"<c r="\#(ref)"\#(s) t="inlineStr"><is><t>\#(SharedStrings.escape(t))</t></is></c>"#
        }
    }

    /// Refreshes a formula cell's cached value, keeping its formula.
    mutating func setCached(_ ref: String, _ v: Cached) {
        guard let el = changes[ref] ?? element(ref), let f = el.range(of: "</f>") else { return }
        let head = String(el[..<f.upperBound])
        switch v {
        case .number(let n): changes[ref] = head + "<v>\(IECExcel.number(n))</v></c>"
        case .string(let t): changes[ref] = head + "<v>\(SharedStrings.escape(t))</v></c>"
        }
    }

    /// The sheet with the changed cells swapped in; everything between them is copied as it was.
    var xml: String {
        var out = "", at = source.startIndex
        out.reserveCapacity(source.utf8.count + 4096)
        for (ref, el) in changes.sorted(by: { ranges[$0.key]!.lowerBound < ranges[$1.key]!.lowerBound }) {
            let r = ranges[ref]!
            out += source[at..<r.lowerBound]
            out += el
            at = r.upperBound
        }
        out += source[at...]
        return out
    }

    /// Cells of a sheet that point at a shared string.
    static func sharedCount(_ xml: String) -> Int { xml.components(separatedBy: #" t="s""#).count - 1 }
}
