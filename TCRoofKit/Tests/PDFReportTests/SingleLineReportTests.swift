import XCTest
@testable import PDFReport
@testable import TCRoofCore

final class SingleLineReportTests: XCTestCase {
    func testAttachAddsOneA3PageAndLeavesTheRestAlone() {
        var job = SingleLineTestsFixture.job()
        let base = ReportLayout(job: job).pages()
        XCTAssertTrue(base.allSatisfy { $0.width == ReportLayout.pageW })
        job.values["sldAttach"] = .text("1")
        let with = ReportLayout(job: job).pages()
        XCTAssertEqual(with.count, base.count + 1)
        let a3 = with.filter { $0.width != ReportLayout.pageW }
        XCTAssertEqual(a3.count, 1)
        XCTAssertEqual(a3[0].width, ReportLayout.a3W, accuracy: 0.01)
        XCTAssertGreaterThan(a3[0].width, a3[0].height)
        // the A4 pages are unchanged (same number of ops each)
        XCTAssertEqual(with.filter { $0.width == ReportLayout.pageW }.map(\.ops.count), base.map(\.ops.count))
    }

    func testSingleLinePageStandsAlone() {
        let page = ReportLayout(job: SingleLineTestsFixture.job()).singleLinePage()
        XCTAssertFalse(page.ops.isEmpty)
    }
}

enum SingleLineTestsFixture {
    static func job() -> Job {
        var v = Values()
        v["capacity"] = .text("120"); v["docNo"] = .text("215")
        var t = Transformer(kva: "630"); t.impedance = "4.14"
        t.setBoards([Board(name: "MDP-1", isMain: true, at: "800")])
        v["trafos"] = .transformers([t])
        return Job(values: v, modules: [SurveyModule(type: .inverter, values: Values(["inverterCount": .text("2")]))])
    }
}

final class BuildingPanelReportTests: XCTestCase {
    /// B1 linked to an A3 breaker with a PV point on its wide photo: the unit prints the link and draws the point.
    func testPanelUnitPrintsA3LinkAndPoint() {
        var job = SingleLineTestsFixture.job()
        var trafos = job.values.transformers("trafos")
        trafos[0].boards[0].breakers = [Breaker(at: "400")]
        job.values["trafos"] = .transformers(trafos)
        var m = SurveyModule(type: .panel, name: "โรงสูบน้ำ")
        m.values["photoWide"] = .photo(Photo(fileName: "w.jpg", width: 400, height: 300))
        m.values["pvPoint"] = .shapes([SiteShape(kind: .pvPoint, points: [ShapePoint(0.2, 0.2), ShapePoint(0.4, 0.5)])])
        m.values["spareSlots"] = .text("2")
        job.modules.insert(m, at: 0)
        BuildingPanels.link(&job, panel: m.id, to: BuildingPanels.options(job)[0].ref)
        let texts = ReportLayout(job: job).moduleUnits(job.modules[0]).flatMap(\.ops).compactMap { op -> String? in
            switch op {
            case .text(let t, _, _, _, _, _, _): return t
            case .textBox(let t, _, _, _, _, _): return t
            default: return nil
            }
        }
        XCTAssertTrue(texts.contains("จุดเชื่อมต่อ PV · ช่องว่าง 2 ช่อง"), "\(texts)")
        XCTAssertTrue(texts.contains { $0.contains("MDP-1 · CB1 · 400 AT") }, "\(texts)")
    }
}
