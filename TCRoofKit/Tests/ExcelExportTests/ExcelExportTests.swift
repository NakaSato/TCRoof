import XCTest
@testable import ExcelExport
@testable import TCRoofCore

final class ExcelExportTests: XCTestCase {
    var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures") }
    var outDir: URL {
        let u = URL(fileURLWithPath: ProcessInfo.processInfo.environment["EXPORT_DIR"] ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func importFixture() throws -> (Job, JobStore) {
        let s = JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("xl-" + UUID().uuidString))
        let j = try WebBackup.importJobs(Data(contentsOf: fixtures.appendingPathComponent("job215.json")), into: s)[0]
        return (j, s)
    }

    func testZipRoundTrip() throws {
        var z = ZipArchive()
        z.set("a.txt", "สวัสดี hello hello hello hello")
        z.set("b/c.xml", "<x/>")
        let back = try ZipArchive(z.write())
        XCTAssertEqual(back.paths, ["a.txt", "b/c.xml"])
        XCTAssertEqual(back.string("a.txt"), "สวัสดี hello hello hello hello")
    }

    func testSheetCells() throws {
        let xml = #"<worksheet><sheetFormatPr defaultRowHeight="15"/><cols><col min="1" max="3" width="10" customWidth="1"/></cols><sheetData><row r="2" ht="30"><c r="B2" s="3" t="s"><v>0</v></c></row><row r="5"/></sheetData></worksheet>"#
        let s = SheetXML(xml, shared: ["ขนาด .......... A"], checkboxStyles: ["C4": ("1", "2")])
        s.fillLabel("B2", "100")
        XCTAssertEqual(s.text("B2"), "ขนาด 100 A")
        s.set("A1", "12.5"); s.set("A3", "0812345678"); s.tick("C4", true)
        let out = s.xml(removeTabSelected: false)
        XCTAssertTrue(out.contains(#"<row r="1"><c r="A1"><v>12.5</v></c></row>"#), out)
        XCTAssertTrue(out.contains(#"<c r="A3" t="inlineStr"><is><t xml:space="preserve">0812345678</t></is></c>"#))
        XCTAssertTrue(out.contains(#"<row r="4"><c r="C4" s="2"/></row><row r="5"/>"#))
        XCTAssertEqual(s.frame("A1:B2").x1, 140)
        XCTAssertEqual(s.frame("A2:A2").y1 - s.frame("A2:A2").y0, 40)
    }

    func testExportFixture() throws {
        var (job, store) = try importFixture()
        // exercise sheet copies: 4 panels (station copy), a second roof and tank, plus the house / roof-form / sediment forms
        let panel = job.modules.first { $0.type == .panel }!
        for k in 2...4 { var p = panel; p.id = UUID(); p.name = "อาคาร \(k)"; job.modules.append(p) }
        var house = SurveyModule(type: .house)
        house.values["roofShape"] = .choice("หลังคาทรงปั้นหยา", other: ""); house.values["measA"] = .text("120")
        house.values["mainBreaker"] = .text("63"); house.values["hasCutout"] = .choice("มี", other: "")
        house.values["aerialPhoto"] = job.values["siteMap"]
        job.modules.append(house)
        var rf = SurveyModule(type: .roofForm); rf.values["facing"] = .choice("อื่นๆ", other: "ทิศใต้ค่อนตะวันตก"); job.modules.append(rf)
        var sed = SurveyModule(type: .sed); sed.values["distA"] = .text("1200"); job.modules.append(sed)
        if let r = job.modules.first(where: { $0.type == .roof }) { var r2 = r; r2.id = UUID(); r2.name = "2 อาคารสูบ"; r2.values["planPhoto"] = nil; job.modules.append(r2) }

        if let ti = job.modules.firstIndex(where: { $0.type == .tank }) {
            job.modules[ti].values["tankType"] = .choice("ค.ส.ล.", other: ""); job.modules[ti].values["tankPos"] = .choice("กึ่งฝัง", other: "")
            job.modules[ti].values["shade"] = .choice("มี", other: ""); job.modules[ti].values["shadeFrom"] = .multi(["ต้นไม้", "หอถังสูง"])
            job.modules[ti].values["shadeDir"] = .multi(["S", "SW"]); job.modules[ti].values["shadeNote"] = .text("ต้นไม้สูง ~8 ม. ห่าง 5 ม.")
            XCTAssertEqual(Schema.shadeText(job.modules[ti].values), "เงาบัง: ต้นไม้, หอถังสูง ทิศ S, SW (ต้นไม้สูง ~8 ม. ห่าง 5 ม.)")
            XCTAssertEqual(Schema.tankKind(job.modules[ti].values), "ถัง ค.ส.ล. · กึ่งฝัง")
        }
        let png = try Data(contentsOf: fixtures.appendingPathComponent("plan.png"))
        let size = ImageSize.of(png)!
        let result = try ExcelExporter().export(job, photoData: { store.data(of: $0, in: job.id) },
                                                planImage: { _ in ExcelImage(data: png, width: size.width, height: size.height, isPNG: true) })
        print("sheets:", result.sheets, "pictures:", result.pictures, "bytes:", result.data.count)
        XCTAssertEqual(result.sheets.first, "ระบบไฟฟ้า 2")
        XCTAssertTrue(result.sheets.contains("ระบบไฟฟ้า (2)"))
        XCTAssertTrue(result.sheets.contains("หลังคาทั่วไป R2"))
        XCTAssertGreaterThan(result.pictures, 25)
        let url = outDir.appendingPathComponent("native-test.xlsx")
        try result.data.write(to: url)
        // package sanity: every sheet listed in the workbook exists
        let z = try ZipArchive(result.data)
        let wb = z.string("xl/workbook.xml")!
        XCTAssertEqual(wb.components(separatedBy: "<sheet ").count - 1, result.sheets.count)
        XCTAssertTrue(z.string("xl/worksheets/sheet5.xml")!.contains("1250"))
    }
}

extension ExcelExportTests {
    /// The roof PV layout's figures and BOQ go into the roof sheet's blank rows 38–39.
    func testRoofPVLayoutRows() throws {
        var (job, store) = try importFixture()
        guard let i = job.modules.firstIndex(where: { $0.type == .roof }) else { return XCTFail("the fixture has a roof") }
        job.modules[i].values["spansX"] = .text("1.5,4,4,4,4,1.5"); job.modules[i].values["spansY"] = .text("1.5,4.5,4,4.5,1.5")
        job.modules[i].values[Roof.Key.shape] = .choice("หลังคาทรงจั่ว", other: "")
        Roof.setFrame(&job.modules[i].values, .pratt)
        let result = try ExcelExporter().export(job, photoData: { store.data(of: $0, in: job.id) })
        let z = try ZipArchive(result.data)
        let sheets = z.paths.filter { $0.hasPrefix("xl/worksheets/sheet") }.compactMap { z.string($0) }
        let roof = try XCTUnwrap(sheets.first { $0.contains("ผังแผงอัตโนมัติ") })
        XCTAssertTrue(roof.contains(#"r="A38""#))
        XCTAssertTrue(roof.contains("BOQ: ราง "))
    }
}

/// The BOQ workbook: both sheets rebuilt from the template's row styles, formulas with cached values.
final class BOQExcelTests: XCTestCase {
    func testBOQWorkbook() throws {
        var j = HomeJob()
        j.pvKWp = "5.175"; j.phase = .single
        j.ppim.panels[0].brand = "ZNShine"; j.ppim.panels[0].model = "ZXM7-UHLD144"; j.ppim.panels[0].watt = "575"; j.ppim.panels[0].count = "9"
        j.ppim.inverters[0].brand = "Growatt"; j.ppim.inverters[0].model = "MIN 5000TL-X"; j.ppim.inverters[0].kW = "5"
        var b = HomeBOQ.draft(job: j)
        for i in b.lines.indices where !b.lines[i].isNote { b.lines[i].material = 100 }
        b.customer = "ลูกค้า & ทดสอบ"
        let zip = try ZipArchive(BOQExcel.export(b))
        let cost = try XCTUnwrap(zip.string("xl/worksheets/sheet1.xml"))
        let sent = try XCTUnwrap(zip.string("xl/worksheets/sheet2.xml"))
        XCTAssertTrue(cost.contains("ขนาด 5.175 kWp"))
        XCTAssertTrue(cost.contains("ลูกค้า &amp; ทดสอบ"))
        XCTAssertTrue(cost.contains("<f>SUM(M17:M"))
        XCTAssertTrue(cost.contains("<v>9</v>"))                       // 9 modules on the cost sheet
        XCTAssertTrue(sent.contains(">Lot<"))                          // one lot a line for the customer
        XCTAssertFalse(cost.contains("{{DATE}}"))
        let wb = try XCTUnwrap(zip.string("xl/workbook.xml"))
        XCTAssertTrue(wb.contains("fullCalcOnLoad=\"1\""))
        XCTAssertNotNil(wb.range(of: #"Sent!\$A\$1:\$M\$\d+"#, options: .regularExpression))
        // every merged cell refers to a row that exists
        let rows = Set(BOQExcel.rows(cost).compactMap(BOQExcel.rowNumber))
        for m in cost.components(separatedBy: "<mergeCell ref=\"").dropFirst() {
            let ref = m.prefix { $0 != "\"" }
            for n in ref.split(separator: ":").map({ Int($0.filter(\.isNumber))! }) where n > 16 { XCTAssertTrue(rows.contains(n), "\(ref)") }
        }
    }
}
