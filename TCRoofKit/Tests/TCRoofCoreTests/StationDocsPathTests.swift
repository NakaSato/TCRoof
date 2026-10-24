import XCTest
@testable import TCRoofCore

/// The install page's `เอกสาร` tab (docs/ui/install-tracking-ipad-docs): legend, path and summary.
final class StationDocsPathTests: XCTestCase {
    func ctx(_ s: StationDocs.Station, kW: Double = 90) -> StationDocs.Context { .init(s, inverterKW: kW) }

    func testTheLegendAndTheFlowLevel() {
        let expected: [StationDocs.Status: (StationDocs.Legend, Int)] = [
            .missing: (.todo, 0), .draft: (.todo, 1), .signed: (.todo, 1), .requested: (.waiting, 2),
            .submitted: (.waiting, 2), .approved: (.done, 3), .notNeeded: (.notYet, 0)]
        for s in StationDocs.Status.allCases {
            XCTAssertEqual(StationDocs.legend(s), expected[s]?.0, s.rawValue)
            XCTAssertEqual(StationDocs.flowLevel(s), expected[s]?.1, s.rawValue)
        }
    }

    func testThePathUnder200kVA() {
        let s = StationDocs.Station(buildingRoute: .notify)
        let steps = StationDocs.path(station: s, library: .init(), ctx(s))
        XCTAssertEqual(steps.map(\.package), [.building, .gridConnection, .pk2])
        XCTAssertEqual(steps.map(\.agency), ["เทศบาล", "กฟภ.", "กกพ."])
        XCTAssertEqual(steps[0].title, "แจ้งเทศบาล")
        XCTAssertFalse(steps[2].applies)
        XCTAssertEqual(steps[2].chip, "ไม่ต้องยื่น")
        XCTAssertEqual(steps[2].note, "ต่ำกว่า 200 kVA")
        XCTAssertTrue(steps[2].cleared)
        XCTAssertEqual(steps[0].chip, "กำลังยื่น")
        XCTAssertEqual(steps[0].note, "\(steps[0].progress.total) ฉบับยังไม่เสร็จ")
        XCTAssertEqual(StationDocs.defaultStep(steps), .building)
    }

    func testTheDefaultStepIsTheFirstWithWorkLeft() {
        var s = StationDocs.Station(over200kVA: true, buildingRoute: .permit)
        var lib = StationDocs.Library()
        let c = ctx(s)
        for k in StationDocs.papers(in: .building, c) {
            if k.scope.isShared { lib.docs[k.id] = .init(status: .approved) } else { s.docs[k.id] = .init(status: .approved) }
        }
        let steps = StationDocs.path(station: s, library: lib, c)
        XCTAssertEqual(steps[0].title, "อ.1 (ขออนุญาต)")
        XCTAssertTrue(steps[0].progress.isComplete)
        XCTAssertEqual(steps[0].chip, "ครบ \(steps[0].progress.total)/\(steps[0].progress.total)")
        XCTAssertTrue(steps[2].applies)
        // a paper shared with step 1 is ready in step 2 too, but step 2 has more to do
        XCTAssertEqual(StationDocs.defaultStep(steps), .gridConnection)
    }

    func testTheSummaryCountsEachPaperOnce() {
        var s = StationDocs.Station(over200kVA: true)
        s.docs["site_map"] = .init(status: .approved)       // in ขนานไฟ and พค.2
        s.docs["sld"] = .init(status: .submitted)
        s.docs["outage_letter"] = .init(status: .notNeeded)
        let c = ctx(s)
        let sum = StationDocs.pathSummary(station: s, library: .init(), c)
        var unique = Set<String>()
        for p in [StationDocs.Package.building, .gridConnection, .pk2] { StationDocs.papers(in: p, c).forEach { unique.insert($0.id) } }
        XCTAssertEqual(sum.packages, 3)
        XCTAssertEqual(sum.done, 1)
        XCTAssertEqual(sum.count(.waiting), 1)
        XCTAssertEqual(sum.count(.notYet), 1)
        XCTAssertEqual(sum.total + sum.count(.notYet), unique.count)
        XCTAssertEqual(sum.count(.todo), unique.count - 3)
    }

    func testSourceAndCode() throws {
        XCTAssertEqual(StationDocs.source(try XCTUnwrap(StationDocs.kind("site_map"))), "ทีมเราทำ")
        XCTAssertEqual(StationDocs.source(try XCTUnwrap(StationDocs.kind("sld"))), "ทีมเราทำ | วิศวกรไฟฟ้า")
        XCTAssertEqual(StationDocs.source(try XCTUnwrap(StationDocs.kind("engineer_license"))), "ดึงจากคลังกลาง")
        XCTAssertEqual(StationDocs.source(try XCTUnwrap(StationDocs.kind("electric_bill"))), "ขอจาก กปภ.สาขา")
        XCTAssertEqual(StationDocs.source(try XCTUnwrap(StationDocs.kind("poa_letter"))), "เราร่าง → ผจก. กปภ.สาขาลงนาม")
        XCTAssertEqual(StationDocs.code(section: "4.2", index: 6), "4.2-07")
    }
}
