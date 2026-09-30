import XCTest
@testable import PDFReport
@testable import TCRoofCore

final class PDFReportTests: XCTestCase {
    func testLayoutFixture() throws {
        let fx = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ExcelExportTests/Fixtures/job215.json")
        let store = JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("pdf-" + UUID().uuidString))
        var job = try WebBackup.importJobs(Data(contentsOf: fx), into: store)[0]
        var h = SurveyModule(type: .house)
        h.values["roofShape"] = .choice("อื่นๆ", other: "ทรงมะนิลา"); h.values["floors"] = .text("2"); h.values["obstacle"] = .choice("มี", other: "")
        h.values["obstacleDetail"] = .text("เสาอากาศทีวี"); h.values["photoFront"] = job.values["siteMap"]
        job.modules.append(h)
        job.modules.append(SurveyModule(type: .sed))
        job.values["floodHistory"] = .choice("เคย", other: ""); job.values["floodYear"] = .text("2554"); job.values["floodDepth"] = .text("80")
        job.values["floodHit"] = .multi(["ห้อง MDB / ตู้ไฟฟ้า"])
        XCTAssertEqual(Schema.recommendedEquipHeight(job.values), 130)
        // transformer photos are required per transformer; removing TR1 shifts TR2's answers down
        XCTAssertEqual(job.transformerGaps.count, 2)
        let c0 = job.completion.total
        job.values["tr1_front"] = job.values["siteMap"]; job.values["tr1_feed"] = .text("MDB1")
        XCTAssertEqual(job.completion.total, c0)
        XCTAssertTrue(job.transformerGaps[1].hasPrefix("TR2: ด้านหลัง"))
        var v2 = job.values; v2.shiftTransformerAnswers(removed: 0)
        XCTAssertEqual(v2.text("tr0_feed"), "MDB1")
        job.values["siteMarks"] = .marks([MapMark(kind: .meter, x: 0.62, y: 0.35), MapMark(kind: .trafo, x: 0.55, y: 0.5, value: "800"),
                                          MapMark(kind: .trafo, x: 0.7, y: 0.52), MapMark(kind: .mdb, x: 0.3, y: 0.6, value: "1250"),
                                          MapMark(kind: .inv, x: 0.45, y: 0.7), MapMark(kind: .water, x: 0.2, y: 0.3), MapMark(kind: .office, x: 0.95, y: 0.9)])
        // marks survive the web JSON round trip
        let back = try WebBackup.importJobs(WebBackup.exportBackup([job], store: store), into: JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("pdf2-" + UUID().uuidString)))[0]
        XCTAssertEqual(back.values.marks("siteMarks").map(\.kind), job.values.marks("siteMarks").map(\.kind))
        XCTAssertEqual(back.values.marks("siteMarks").map(\.rating), ["", "800 kVA", "", "1250 AT", "", "", ""])
        XCTAssertEqual(SiteMarks.suggestedValue(.trafo, existing: [], trafos: job.values.transformers("trafos")), "800")
        if let ti = job.modules.firstIndex(where: { $0.type == .tank }) {
            job.modules[ti].values["tankType"] = .choice("ค.ส.ล.", other: ""); job.modules[ti].values["tankPos"] = .choice("กึ่งฝัง", other: "")
            job.modules[ti].values["shade"] = .choice("มี", other: ""); job.modules[ti].values["shadeFrom"] = .multi(["ต้นไม้", "หอถังสูง"])
            job.modules[ti].values["shadeDir"] = .multi(["S", "SW"]); job.modules[ti].values["shadeNote"] = .text("ต้นไม้สูง ~8 ม. ห่าง 5 ม.")
            XCTAssertEqual(Schema.shadeText(job.modules[ti].values), "เงาบัง: ต้นไม้, หอถังสูง ทิศ S, SW (ต้นไม้สูง ~8 ม. ห่าง 5 ม.)")
            XCTAssertEqual(Schema.tankKind(job.modules[ti].values), "ถัง ค.ส.ล. · กึ่งฝัง")
        }
        let pages = ReportLayout(job: job, header: ReportHeader(company: "TC Roof")).pages()
        print("pages:", pages.count)
        XCTAssertGreaterThan(pages.count, 10)
        if let dir = ProcessInfo.processInfo.environment["EXPORT_DIR"] {
            for (i, p) in pages.enumerated() {
                let svg = Sketch(width: ReportLayout.pageW, height: ReportLayout.pageH, ops: [.rect(Box(0, 0, ReportLayout.pageW, ReportLayout.pageH), stroke: nil, fill: .white)] + p.ops)
                    .svg(photoHref: { "file://" + store.url(of: $0, in: job.id).path })
                try svg.write(toFile: dir + "/page-\(String(format: "%02d", i + 1)).svg", atomically: true, encoding: .utf8)
            }
        }
    }

    /// A2's drawings, new symbols and site note appear over / under the site picture on the report's first page.
    func testSiteDrawingInReport() throws {
        let fx = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ExcelExportTests/Fixtures/job215.json")
        let store = JobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("pdf-" + UUID().uuidString))
        var job = try WebBackup.importJobs(Data(contentsOf: fx), into: store)[0]
        job.values["siteMarks"] = .marks([MapMark(kind: .trafo, x: 0.6, y: 0.5, value: "630", label: "TX 1"), MapMark(kind: .zeroExport, x: 0.8, y: 0.2),
                                          MapMark(kind: .stairs, x: 0.3, y: 0.3), MapMark(kind: .weather, x: 0.2, y: 0.8),
                                          MapMark(kind: .meterSub, x: 0.7, y: 0.8), MapMark(kind: .roofLabel, x: 0.4, y: 0.15, label: "หลังคาถังน้ำใส 1")])
        job.values[SiteShapes.key] = .shapes([
            SiteShape(kind: .panelArea, points: [ShapePoint(0.1, 0.4), ShapePoint(0.5, 0.4), ShapePoint(0.5, 0.9), ShapePoint(0.1, 0.9)]),
            SiteShape(kind: .cableRoute, points: [ShapePoint(0.5, 0.4), ShapePoint(0.6, 0.3), ShapePoint(0.6, 0.5)]),
            SiteShape(kind: .measure, points: [ShapePoint(0.1, 0.35), ShapePoint(0.5, 0.35)]),
            SiteShape(kind: .craneEntry, points: [ShapePoint(0.95, 0.6), ShapePoint(0.7, 0.6)], label: "ทางเข้าเครน"),
            SiteShape(kind: .shade, points: [ShapePoint(0.1, 0.4), ShapePoint(0.2, 0.4), ShapePoint(0.2, 0.9), ShapePoint(0.1, 0.9)], label: "ร่มเงาต้นไม้")])
        job.values[SiteShapes.scaleKey] = .text("100")
        job.values["siteNote"] = .text("รถเครนเข้าทางถนนด้านตะวันออก")
        let pages = ReportLayout(job: job, header: ReportHeader(company: "TC Roof")).pages()
        // the one-page summary draws the picture small; the cover's site box has the legend and note
        let all = pages.flatMap(\.ops), first = pages[0].ops
        func hasText(_ t: String) -> Bool {
            all.contains { op in
                switch op {
                case .text(let s, _, _, _, _, _, _): return s.contains(t)
                case .textBox(let s, _, _, _, _, _): return s.contains(t)
                default: return false
                }
            }
        }
        XCTAssertTrue(hasText("หมายเหตุหน้างาน: รถเครนเข้าทางถนนด้านตะวันออก"))
        XCTAssertTrue(hasText("40.0 ม."))
        XCTAssertTrue(hasText("TX 1"))
        XCTAssertTrue(hasText("หลังคาถังน้ำใส 1"))
        XCTAssertTrue(hasText("ร่มเงาต้นไม้"))
        XCTAssertTrue(hasText("STAIRS"))   // legend
        XCTAssertFalse(hasText("ROOF"))    // roof names label themselves, no legend entry
        if let dir = ProcessInfo.processInfo.environment["EXPORT_DIR"] {
            let svg = Sketch(width: ReportLayout.pageW, height: ReportLayout.pageH, ops: [.rect(Box(0, 0, ReportLayout.pageW, ReportLayout.pageH), stroke: nil, fill: .white)] + first)
                .svg(photoHref: { "file://" + store.url(of: $0, in: job.id).path })
            try svg.write(toFile: dir + "/a2-page1.svg", atomically: true, encoding: .utf8)
            if let i = pages.firstIndex(where: { $0.ops.contains { if case .textBox(let t, _, _, _, _, _) = $0 { return t.hasPrefix("หมายเหตุหน้างาน") }; return false } }) {
                let cover = Sketch(width: ReportLayout.pageW, height: ReportLayout.pageH, ops: [.rect(Box(0, 0, ReportLayout.pageW, ReportLayout.pageH), stroke: nil, fill: .white)] + pages[i].ops)
                    .svg(photoHref: { "file://" + store.url(of: $0, in: job.id).path })
                try cover.write(toFile: dir + "/a2-cover.svg", atomically: true, encoding: .utf8)
            }
        }
    }
}
