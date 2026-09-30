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
