import XCTest
@testable import TCRoofCore

/// The site ICL: the bundled catalog is docs/specs/master-plan/icl-site-items.json, and a sheet's hand-over.
final class SiteICLTests: XCTestCase {
    private let catalog = SiteICL.catalog

    func testCatalogMatchesTheSpec() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../docs/specs/master-plan/icl-site-items.json")
        let spec = try SiteICL.Catalog(json: Data(contentsOf: url))
        XCTAssertEqual(catalog, spec)
        XCTAssertEqual(catalog.groups.count, 10)
        XCTAssertEqual(catalog.items.count, 69)
        XCTAssertEqual(Set(catalog.items.map(\.id)).count, catalog.items.count, "ids are unique")
        XCTAssertEqual(Set(catalog.items.map(\.group)), Set(catalog.groups.map(\.id)))
        XCTAssertEqual(catalog.groups.filter(\.perPoint).map(\.id), ["2.1"])
        XCTAssertEqual(catalog.items.filter { $0.hold == .hold }.count, 14)
        for i in catalog.items { for m in i.mounts ?? [] { XCTAssertTrue(catalog.mounts.contains(m), "\(i.id) \(m)") } }
    }

    func testAPointSheetHasItsMountingsItems() throws {
        let tank = SiteICL.Sheet(group: "2.1", point: "T1", pointName: "หลังคาถังน้ำใส 1", mount: "ถังน้ำใส")
        XCTAssertEqual(tank.id, "2.1/T1")
        let ids = catalog.items(for: tank).map(\.id)
        XCTAssertTrue(ids.contains("ICL-2.1-08"), "anchors on the tank roof")
        XCTAssertFalse(ids.contains("ICL-2.1-02"), "hanger bolts are for corrugated roofs")
        XCTAssertTrue(ids.contains("ICL-2.1-01"), "every mounting")
        let station = SiteICL.Sheet(group: "2.8")
        XCTAssertFalse(catalog.items(for: station, zeroExport: "LV").map(\.id).contains("ICL-2.8-01"))
        XCTAssertTrue(catalog.items(for: station, zeroExport: "LV").map(\.id).contains("ICL-2.8-03"))
        XCTAssertEqual(catalog.items(for: station).count, catalog.items.filter { $0.group == "2.8" }.count)
    }

    func testAnItemIsDoneWithResultValueAndPhoto() throws {
        var s = SiteICL.Sheet(group: "2.6")
        let earth = try XCTUnwrap(catalog.items.first { $0.group == "2.6" && $0.unit == "Ω" })
        XCTAssertFalse(s.isDone(earth, photos: 1))
        s.results[earth.id] = .init(passed: true)
        XCTAssertFalse(s.isDone(earth, photos: 1), "a measured item needs its value")
        s.results[earth.id]?.value = "2.4"
        XCTAssertFalse(s.isDone(earth, photos: 0), "and a photo")
        XCTAssertTrue(s.isDone(earth, photos: 1))
        s.results[earth.id] = .init(notApplicable: true)
        XCTAssertTrue(s.isDone(earth, photos: 0), "ไม่เกี่ยว needs nothing")
    }

    func testHandOver() throws {
        var s = SiteICL.Sheet(group: "2.2")
        let items = catalog.items(for: s)
        for i in items { s.results[i.id] = .init(value: "1", passed: true) }
        XCTAssertTrue(s.isComplete(items) { _ in 1 })
        XCTAssertEqual(s.lockState, .open)
        s.submit(by: "con@x")
        XCTAssertEqual(s.lockState, .sent)
        s.returnForFix(by: "eng@tc", note: "ป้ายสายไม่ครบ")
        XCTAssertEqual(s.lockState, .open)
        XCTAssertEqual(s.sendBack?.note, "ป้ายสายไม่ครบ")
        s.submit(by: "con@x")
        XCTAssertNil(s.sendBack)
        s.sign(by: "eng@tc")
        XCTAssertEqual(s.lockState, .closed)
        XCTAssertTrue(s.passed(items))
        XCTAssertFalse(s.signoffIsStale)
        s.results[items[0].id]?.passed = false
        XCTAssertTrue(s.signoffIsStale)
        XCTAssertFalse(s.passed(items))
        s.reopen()
        XCTAssertEqual(s.lockState, .open)
    }

    /// A signature the document's state doesn't record is dropped (only the team sets `closed`).
    func testTrustingDropsAnUnrecordedSignature() {
        var s = SiteICL.Sheet(group: "2.4")
        s.sign(by: "con@x")
        XCTAssertNil(s.trusting(.sent).signoff)
        XCTAssertNotNil(s.trusting(.closed).signoff)
        XCTAssertNotNil(s.trusting(nil).signoff)
    }

    func testOldJSONStillDecodes() throws {
        let s = try JSONDecoder().decode(SiteICL.Sheet.self, from: Data(#"{"group":"2.1","point":"R1","results":{"ICL-2.1-01":{"passed":true}}}"#.utf8))
        XCTAssertEqual(s.id, "2.1/R1")
        XCTAssertEqual(s.results["ICL-2.1-01"]?.passed, true)
        XCTAssertEqual(s.results["ICL-2.1-01"]?.value, "")
        XCTAssertEqual(SiteICL.photoName(sheet: s.id, item: "ICL-2.1-01", index: 2), "2.1 R1 ICL-2.1-01 2.jpg")
    }
}
