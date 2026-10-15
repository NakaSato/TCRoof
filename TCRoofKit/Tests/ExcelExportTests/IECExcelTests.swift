import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// docs/specs/iec62446-excel-export-swift.md §5 on the customer's `1FORMI1` and the แพรกหนามแดง sample.
final class IECExcelTests: XCTestCase {
    func sample() throws -> IECReport {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../TCRoofCoreTests/Fixtures/iec62446-praek-nam-daeng.json")
        return try IECReport(form: Data(contentsOf: url))
    }

    /// The original's hand-typed PR / Yf (not the app's computed ones), its `Normal` IR summary (it has no MΩ readings)
    /// and no ticks: what it takes to give back the original.
    var original: IECExcel.Overrides {
        var o = IECExcel.Overrides()
        o.performance = [0: .init(pr: 0.69, yf: 2.93, daily: 457.18, energy7d: 3200.03, efficiency: 0.15),
                         1: .init(pr: 0.79, yf: 3.33, daily: 214.94, energy7d: 1504.6, efficiency: 0.17)]
        o.irSummary = [0: .normal, 1: .normal]
        o.ticks = false
        return o
    }

    struct Cell: Equatable { var s: String?; var family: String; var value: String; var formula: String? }

    /// Every cell of a sheet, its shared strings resolved.
    func cells(_ xml: String, _ strings: [String]) -> [String: Cell] {
        var out: [String: Cell] = [:]
        let re = try! NSRegularExpression(pattern: #"<c r="([A-Z]+\d+)"([^>]*?)(?:/>|>(.*?)</c>)"#, options: [.dotMatchesLineSeparators])
        let ns = xml as NSString
        for m in re.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let ref = ns.substring(with: m.range(at: 1)), attrs = ns.substring(with: m.range(at: 2))
            let body = m.range(at: 3).location == NSNotFound ? "" : ns.substring(with: m.range(at: 3))
            func attr(_ n: String) -> String? {
                guard let r = attrs.range(of: #" \#(n)="([^"]*)""#, options: .regularExpression) else { return nil }
                return String(attrs[r].split(separator: "\"")[1])
            }
            func tag(_ t: String) -> String? {
                guard let a = body.range(of: "<\(t)>"), let b = body.range(of: "</\(t)>") else { return nil }
                return String(body[a.upperBound..<b.lowerBound])
            }
            let t = attr("t"), v = tag("v") ?? ""
            let value = t == "s" ? (Int(v).map { strings[$0] } ?? "?") : v
            let family = t == "s" ? "text" : t == "str" ? "str" : v.isEmpty ? "empty" : "number"
            out[ref] = Cell(s: attr("s"), family: family == "number" && t == nil ? "number" : family,
                            value: family == "number" ? IECExcel.number(Double(v) ?? .nan) : value, formula: tag("f"))
        }
        return out
    }

    func strings(_ zip: ZipArchive) -> [String] {
        (zip.string("xl/sharedStrings.xml") ?? "").components(separatedBy: "<si>").dropFirst()
            .map { SharedStrings.plain($0.components(separatedBy: "</si>").first ?? "") }
    }

    let sheets = (1...4).map { "xl/worksheets/sheet\($0).xml" }

    func testTheSampleGivesBackTheOriginal() throws {
        let template = try IECExcel.template()
        let out = try ZipArchive(IECExcel.export(try sample(), template: template, overrides: original))
        let orig = try ZipArchive(template)
        XCTAssertEqual(out.paths, orig.paths, "the parts and their order")
        for p in orig.paths where !sheets.contains(p) {
            XCTAssertEqual(out.data(p), orig.data(p), "\(p) should be byte-identical")
        }
        let (a, b) = (strings(orig), strings(out))
        XCTAssertEqual(Array(b.prefix(a.count)), a, "existing shared strings keep their index and text")
        for p in sheets {
            let (x, y) = (orig.string(p)!, out.string(p)!)
            let (cx, cy) = (cells(x, a), cells(y, b))
            XCTAssertEqual(Set(cx.keys), Set(cy.keys), p)
            for (ref, c) in cx where cy[ref] != c {
                XCTFail("\(p) \(ref): original \(c), export \(String(describing: cy[ref]))")
            }
            // outside the cells, byte for byte
            let strip = { (s: String) in s.replacingOccurrences(of: #"<c r="[A-Z]+\d+"[^>]*?(?:/>|>.*?</c>)"#, with: "", options: .regularExpression) }
            XCTAssertEqual(strip(x), strip(y), "\(p) outside its cells")
        }
    }

    func testABlankReportGivesTheBlankForm() throws {
        var blank = IECReport()
        blank.inverters = [IECReport.Inverter(), IECReport.Inverter()]
        let out = try ZipArchive(IECExcel.export(blank))
        let s = strings(out)
        let c1 = cells(out.string(sheets[0])!, s), c3 = cells(out.string(sheets[2])!, s)
        for ref in ["E16", "F9", "E12", "E22", "D31", "AA4", "E11"] { XCTAssertEqual(c1[ref]?.family, "empty", ref) }
        XCTAssertEqual(c1["AA9"]?.value, "0", "AA9's cached value follows the empty modules")
        XCTAssertEqual(c1["AA9"]?.formula, "SUM(E9:X9)*$AA$4")
        XCTAssertEqual(c1["AA25"]?.value, IECExcel.blankIrradiance)
        XCTAssertEqual(c3["AA26"]?.value, IECExcel.blankArrayTemp)
        let sst = out.string("xl/sharedStrings.xml")!
        let count = sheets.reduce(0) { $0 + SheetCells.sharedCount(out.string($1)!) }
        XCTAssertTrue(sst.contains(#" count="\#(count)""#) && sst.contains(#"uniqueCount="\#(s.count)""#), "count and uniqueCount agree with the sheets")
    }

    func testTheRules() throws {
        var r = try sample()
        // IR readings on every string of INV 1, one of them under 1 MΩ on INV 2
        for i in r.inverters.indices { for n in r.inverters[i].slots.indices where r.inverters[i].slots[n] != nil {
            r.inverters[i].slots[n]?.irPosMOhm = 250; r.inverters[i].slots[n]?.irNegMOhm = 300
        } }
        r.inverters[1].slots[0]?.irNegMOhm = 0.8
        r.module.areaM2 = 2.58
        let data = try IECExcel.export(r)
        // `IEC_EXPORT_OUT=<path> swift test --filter IECExcelTests/testTheRules` keeps the file, to open it elsewhere
        if let path = ProcessInfo.processInfo.environment["IEC_EXPORT_OUT"] { try data.write(to: URL(fileURLWithPath: path)) }
        let out = try ZipArchive(data)
        let s = strings(out)
        let before1 = cells(out.string(sheets[0])!, s), before2 = cells(out.string(sheets[1])!, s), after1 = cells(out.string(sheets[2])!, s)
        XCTAssertEqual(after1["E23"]?.value, "3.13", "Yf from kWp, not the original's 2.93")
        XCTAssertEqual(after1["E22"]?.value, "0.74")
        XCTAssertEqual(after1["E26"]?.value, "0.16")
        XCTAssertEqual(before1["E14"]?.value, "Normal")
        XCTAssertEqual(before2["E14"]?.value, "Abnormal")
        XCTAssertEqual(before1["E12"]?.value, "P")
        XCTAssertEqual(before1["E5"]?.value, "Inverter 1 (125 kW) ")
        XCTAssertEqual(before1["AA30"]?.value, "13.00 น.")
        XCTAssertEqual(before1["L16"]?.family, "empty", "slot 8 has no string: its column stays empty")
        for ref in ["E17", "E19", "E22", "E23", "E24", "E25", "E26"] { XCTAssertEqual(before1[ref]?.family, "empty", "ก่อน never gets \(ref)") }
        // ticks: ผ่าน in Y, ไม่ผ่าน in Z
        XCTAssertEqual(before1["Y12"]?.value, "✓"); XCTAssertEqual(before1["Y13"]?.value, "✓"); XCTAssertEqual(before1["Y16"]?.value, "✓")
        XCTAssertEqual(before2["Z13"]?.value, "✓"); XCTAssertEqual(before2["Y13"]?.family, "empty")
        XCTAssertEqual(after1["Y22"]?.value, "✓", "PR 0.74 ≥ 0.70")
        XCTAssertEqual(after1["Y17"]?.family, "empty", "no Vmp yet: no tick")
    }

    func testOneInverterDropsTheSecondSheets() throws {
        var r = try sample()
        r.inverters.removeLast()
        let out = try ZipArchive(IECExcel.export(r))
        let wb = out.string("xl/workbook.xml")!, rels = out.string("xl/_rels/workbook.xml.rels")!
        let ct = out.string("[Content_Types].xml")!, app = out.string("docProps/app.xml")!, chain = out.string("xl/calcChain.xml")!
        XCTAssertFalse(wb.contains("INV 02"))
        XCTAssertTrue(wb.contains(#"<definedName name="_xlnm.Print_Area" localSheetId="0">'INV 01-ก่อน'"#))
        XCTAssertTrue(wb.contains(#"<definedName name="_xlnm.Print_Area" localSheetId="1">'INV 01-หลัง'"#))
        XCTAssertFalse(chain.contains(#"i="86""#) || chain.contains(#"i="90""#))
        XCTAssertTrue(app.contains(#"<vt:vector size="4" baseType="lpstr">"#) && !app.contains("INV 02"))
        // every relationship target exists and every part has a content type
        let targets = rels.components(separatedBy: #"Target=""#).dropFirst().map { "xl/" + $0.components(separatedBy: "\"")[0] }
        for t in targets { XCTAssertTrue(out.contains(t), t) }
        for p in out.paths where p.hasSuffix(".xml") && (p.contains("worksheets/sheet") || p.contains("drawings/drawing")) {
            XCTAssertTrue(ct.contains(#"PartName="/\#(p)""#), p)
        }
        for p in ["xl/worksheets/sheet2.xml", "xl/worksheets/sheet4.xml", "xl/drawings/drawing2.xml", "xl/printerSettings/printerSettings4.bin"] {
            XCTAssertFalse(out.contains(p), p)
        }
    }

    func testThreeAndFourInvertersCloneTheSecondSheets() throws {
        for count in [3, 4] {
            var r = try sample()
            while r.inverters.count < count {
                var inv = r.inverters[1]
                inv.ratedKW = 50; inv.serial = "SN-\(r.inverters.count + 1)"
                inv.slots[0]?.vocV = 700 + Double(r.inverters.count)
                r.inverters.append(inv)
            }
            let data = try IECExcel.export(r)
            if count == 3, let path = ProcessInfo.processInfo.environment["IEC_EXPORT_OUT3"] { try data.write(to: URL(fileURLWithPath: path)) }
            let out = try ZipArchive(data)
            let wb = out.string("xl/workbook.xml")!, rels = out.string("xl/_rels/workbook.xml.rels")!
            let ct = out.string("[Content_Types].xml")!, app = out.string("docProps/app.xml")!, chain = out.string("xl/calcChain.xml")!

            // tabs: every ก่อน, then every หลัง; names unique and ≤ 31 characters; ids unique
            let tabs = wb.components(separatedBy: #"<sheet name=""#).dropFirst().map { $0.components(separatedBy: "\"")[0] }
            let expected = ["ก่อน", "หลัง"].flatMap { p in (1...count).map { String(format: "INV %02d-", $0) + p } }
            XCTAssertEqual(tabs, expected)
            XCTAssertTrue(tabs.allSatisfy { $0.count <= 31 })
            let ids = wb.components(separatedBy: #"sheetId=""#).dropFirst().map { Int($0.components(separatedBy: "\"")[0])! }
            XCTAssertEqual(Set(ids).count, ids.count)
            // a Print_Area per tab, on the right localSheetId
            for (n, tab) in tabs.enumerated() {
                XCTAssertTrue(wb.contains(#"localSheetId="\#(n)">'\#(tab)'!$A$1:$AB$35<"#), tab)
            }
            XCTAssertEqual(wb.components(separatedBy: "_xlnm.Print_Area").count - 1, 2 * count)
            // calcChain points only at sheets that exist
            let chainIds = Set(chain.components(separatedBy: #" i=""#).dropFirst().map { Int($0.components(separatedBy: "\"")[0])! })
            XCTAssertTrue(chainIds.isSubset(of: Set(ids)), "\(chainIds) ⊄ \(ids)")
            XCTAssertTrue(app.contains(#"<vt:vector size="\#(4 * count)" baseType="lpstr">"#) && app.contains("<vt:i4>\(2 * count)</vt:i4>"))
            XCTAssertTrue(app.contains("<vt:lpstr>INV 03-หลัง</vt:lpstr>"))
            // every relationship target exists, every part has a content type, each VML id block is its own
            let targets = rels.components(separatedBy: #"Target=""#).dropFirst().map { "xl/" + $0.components(separatedBy: "\"")[0] }
            for t in targets { XCTAssertTrue(out.contains(t), t) }
            for p in out.paths where p.hasSuffix(".rels") {
                let base = p.replacingOccurrences(of: "_rels/", with: "").replacingOccurrences(of: ".rels", with: "")
                let dir = (base as NSString).deletingLastPathComponent
                for t in out.string(p)!.components(separatedBy: #"Target=""#).dropFirst().map({ $0.components(separatedBy: "\"")[0] }) where p.hasPrefix("xl/") && !p.hasPrefix("xl/_rels") {
                    let resolved = (dir.split(separator: "/") + t.split(separator: "/")).reduce(into: [Substring]()) {
                        if $1 == ".." { $0.removeLast() } else { $0.append($1) }
                    }.joined(separator: "/")
                    XCTAssertTrue(out.contains(resolved), "\(p) → \(resolved)")
                }
            }
            for p in out.paths where p.hasSuffix(".xml") && (p.contains("worksheets/sheet") || p.contains("drawings/drawing")) {
                XCTAssertTrue(ct.contains(#"PartName="/\#(p)""#), p)
            }
            let idmaps = out.paths.filter { $0.hasSuffix(".vml") }.map { out.string($0)!.components(separatedBy: #"data=""#)[1].components(separatedBy: "\"")[0] }
            XCTAssertEqual(Set(idmaps).count, idmaps.count, "VML id blocks \(idmaps)")
            let uids = out.paths.filter { $0.hasPrefix("xl/worksheets/sheet") }.map { out.string($0)!.components(separatedBy: #"xr:uid=""#)[1].prefix(38) }
            XCTAssertEqual(Set(uids).count, uids.count)

            // the clones carry their inverter's values and keep their links to INV 01
            let s = strings(out)
            let before3 = cells(out.string("xl/worksheets/sheet5.xml")!, s), after3 = cells(out.string("xl/worksheets/sheet6.xml")!, s)
            XCTAssertEqual(before3["E5"]?.value, "Inverter 3 (50 kW) ")
            XCTAssertEqual(after3["O5"]?.value, "S/N : SN-3")
            XCTAssertEqual(before3["E16"]?.value, "702")
            XCTAssertEqual(before3["C3"]?.formula, "'INV 01-ก่อน'!$C$3")
            XCTAssertEqual(after3["C3"]?.formula, "'INV 01-หลัง'!$C$3")
            XCTAssertEqual(before3["C3"]?.value, r.stationLine, "the link's cached value")
            XCTAssertEqual(after3["AA9"]?.formula, "SUM(E9:X9)*$AA$4")
            if count == 4 {
                XCTAssertEqual(cells(out.string("xl/worksheets/sheet8.xml")!, s)["E5"]?.value, "Inverter 4 (50 kW) ")
            }
            let sst = out.string("xl/sharedStrings.xml")!
            let refs = out.paths.filter { $0.hasPrefix("xl/worksheets/sheet") }.reduce(0) { $0 + SheetCells.sharedCount(out.string($1)!) }
            XCTAssertTrue(sst.contains(#" count="\#(refs)""#), "count covers the clones")
        }
        XCTAssertEqual(IECExcel.fileName(station: "สถานีจ่ายน้ำแพรกหนามแดง", date: Date(timeIntervalSince1970: 1_791_000_000)).suffix(4), ".XLS")
    }

    /// Two inverters change only the sheets and the shared strings (spec §3.1).
    func testTwoInvertersKeepThePackage() throws {
        let template = try IECExcel.template()
        let out = try ZipArchive(IECExcel.export(try sample())), orig = try ZipArchive(template)
        XCTAssertEqual(out.paths, orig.paths)
        for p in ["xl/workbook.xml", "docProps/app.xml", "xl/calcChain.xml", "[Content_Types].xml"] { XCTAssertEqual(out.data(p), orig.data(p), p) }
    }

    /// Step 2's edits change only their own cells: a reversed Voc on INV1ST5 (slot 5, column I) writes I16 and I12
    /// (and the row ticks), nothing else.
    func testStepTwoEditsChangeOnlyTheirCells() throws {
        let before = try sample()
        var after = before
        after.setVoc(-712, inverter: 0, slot: 5)
        after.inverters[0].slots[4]?.iBeforeA = 0.5
        let (a, b) = (try ZipArchive(IECExcel.export(before)), try ZipArchive(IECExcel.export(after)))
        var changed: [String] = []
        for (n, p) in sheets.enumerated() {
            let (x, y) = (cells(a.string(p)!, strings(a)), cells(b.string(p)!, strings(b)))
            for (ref, c) in x where y[ref] != c { changed.append("\(n + 1)!\(ref)") }
        }
        // the ก่อน sheet (1) and the หลัง sheet (3) both carry rows 12, 16, 18; ticks Y/Z move with the rules
        XCTAssertEqual(Set(changed), ["1!I12", "1!I16", "1!I18", "1!Y12", "1!Z12", "1!Y16", "1!Z16", "1!Y18", "1!Z18",
                                      "3!I12", "3!I16", "3!I18", "3!Y12", "3!Z12", "3!Y16", "3!Z16", "3!Y18", "3!Z18"])
    }
}
