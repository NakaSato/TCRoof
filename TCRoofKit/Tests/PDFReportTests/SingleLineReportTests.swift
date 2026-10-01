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
