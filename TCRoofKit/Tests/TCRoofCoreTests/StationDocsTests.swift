import XCTest
@testable import TCRoofCore

final class StationDocsTests: XCTestCase {
    typealias S = StationDocs

    func testCatalogIdsAreUniqueAndChecklistPointsAtKnownKinds() {
        let ids = S.kinds.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(S.kinds.count, 44)
        for item in S.pk2Checklist { for id in item.docs { XCTAssertNotNil(S.kind(id), "\(item.number) → \(id)") } }
        XCTAssertEqual(S.pk2Checklist.map(\.number), Array(1...23))
    }

    func testTrackingFilePapersJoinGridConnection() {
        let ids = S.papers(in: .gridConnection, S.Context(S.Station(), inverterKW: 100)).map(\.id)
        for id in ["owner_signoff", "self_cert_vspp", "self_cert_k1", "install_inspection_report", "outage_letter", "outage_attachment"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        XCTAssertTrue(S.papers(in: .pk2, S.Context(S.Station(), inverterKW: 300)).map(\.id).contains("owner_signoff"))
    }

    func testOver200ComesFromInverterUnlessSetByHand() {
        XCTAssertFalse(S.Context(S.Station(), inverterKW: 150).over200kVA)
        XCTAssertTrue(S.Context(S.Station(), inverterKW: 200).over200kVA)
        XCTAssertFalse(S.Context(S.Station(over200kVA: false), inverterKW: 300).over200kVA)
        XCTAssertFalse(S.packages(S.Context(S.Station(), inverterKW: 100)).contains(.pk2))
        XCTAssertTrue(S.packages(S.Context(S.Station(), inverterKW: 250)).contains(.pk2))
    }

    func testBuildingRoutePicksPermitOrNotice() {
        let ids = { (route: S.BuildingRoute) in
            S.papers(in: .building, S.Context(S.Station(buildingRoute: route), inverterKW: 100)).map(\.id) }
        XCTAssertTrue(ids(.unknown).contains("building_permit_request"))
        XCTAssertTrue(ids(.unknown).contains("building_exempt_notice"))
        XCTAssertFalse(ids(.notify).contains("building_permit_request"))
        XCTAssertFalse(ids(.notify).contains("building_permit_o1"))
        XCTAssertFalse(ids(.permit).contains("building_exempt_notice"))
    }

    func testSharedPapersComeFromTheLibrary() {
        let act = S.kind("pwa_act")!, bill = S.kind("electric_bill")!
        var station = S.Station()
        station.docs["pwa_act"] = S.DocState(status: .missing)
        station.docs["electric_bill"] = S.DocState(status: .signed)
        let library = S.Library(docs: ["pwa_act": S.DocState(status: .approved, fileName: "act.pdf")])
        XCTAssertEqual(S.state(act, station: station, library: library).status, .approved)
        XCTAssertEqual(S.state(bill, station: station, library: library).status, .signed)
    }

    func testProgressSkipsNotNeeded() {
        let ctx = S.Context(S.Station(), inverterKW: 100)
        let total = S.papers(in: .gridConnection, ctx).count
        var station = S.Station()
        station.docs["sld"] = S.DocState(status: .signed)
        station.docs["site_map"] = S.DocState(status: .notNeeded)
        let p = S.progress(.gridConnection, station: station, library: S.Library(), ctx)
        XCTAssertEqual(p.total, total - 1)
        XCTAssertEqual(p.ready, 1)
        XCTAssertFalse(p.isComplete)
    }

    func testChecklistTicksFromPaperStates() {
        var station = S.Station(buildingRoute: .notify)
        let ctx = S.Context(station, inverterKW: 300)
        let item = { (n: Int) in S.pk2Checklist.first { $0.number == n }! }
        station.docs["sld"] = S.DocState(status: .signed)
        var library = S.Library()
        XCTAssertEqual(S.check(item(10), station: station, library: library, ctx), .done)
        XCTAssertEqual(S.check(item(8), station: station, library: library, ctx), .missing(["แผนผังบริเวณ (Layout) วิศวกรรับรอง"]))
        // item 7 needs three papers, two of them shared
        library.docs["pwa_poa_order"] = S.DocState(status: .approved)
        library.docs["grantor_docs"] = S.DocState(status: .signed)
        XCTAssertEqual(S.check(item(7), station: station, library: library, ctx), .missing(["เอกสารผู้รับมอบอำนาจ (บัตร ผจก.สาขา)"]))
        library.docs["grantee_docs"] = S.DocState(status: .submitted)
        XCTAssertEqual(S.check(item(7), station: station, library: library, ctx), .done)
        // conditional lines
        XCTAssertEqual(S.check(item(2), station: station, library: library, ctx), .notApplicable)
        XCTAssertEqual(S.check(item(20), station: station, library: library, ctx), .manual)
        XCTAssertEqual(S.check(item(14), station: station, library: library, ctx), .notApplicable)
        // item 23: อ.1 is skipped when the เทศบาล only wants a notice
        station.docs["install_photo_report"] = S.DocState(status: .signed)
        library.docs["vat_pp20"] = S.DocState(status: .signed)
        XCTAssertEqual(S.check(item(23), station: station, library: library, ctx), .done)
    }

    func testExpiryWarnsWithin30Days() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 9))!
        let license = S.kind("engineer_license")!
        func state(_ days: Int) -> S.DocState {
            S.DocState(status: .signed, expiresAt: cal.date(byAdding: .day, value: days, to: today))
        }
        XCTAssertEqual(S.expiry(license, state(-1), on: today, calendar: cal), .expired)
        XCTAssertEqual(S.expiry(license, state(10), on: today, calendar: cal), .soon(days: 10))
        XCTAssertNil(S.expiry(license, state(60), on: today, calendar: cal))
        XCTAssertNil(S.expiry(S.kind("sld")!, state(-5), on: today, calendar: cal))
    }

    func testStationRoundTripsAndOldJSONDecodes() {
        var s = S.Station(over200kVA: true, buildingRoute: .permit)
        s.docs["sld"] = S.DocState(status: .draft, fileName: "SLD.pdf", note: "รอวิศวกรเซ็น")
        XCTAssertEqual(S.Station.decode(s.json), s)
        XCTAssertEqual(S.Station.decode(nil), S.Station())
        let partial = S.Station.decode(#"{"docs":{"sld":{"status":"signed"}},"buildingRoute":"what"}"#)
        XCTAssertEqual(partial.docs["sld"]?.status, .signed)
        XCTAssertEqual(partial.buildingRoute, .unknown)
        XCTAssertTrue(partial.srtProject)
    }

    // MARK: Drafts

    func testOnlyTheOutageLetterIsDrafted() {
        XCTAssertEqual(S.kinds.filter { S.draft(for: $0) != nil }.map(\.id), ["outage_letter"])
    }

    func testOutageLetterStandardTextAndRewrittenText() {
        let facts = S.Facts(station: "สถานีจ่ายน้ำ ก", address: "อ.เมือง จ.สมุทรสงคราม", capacityKW: 209.76, company: "บริษัท ข จำกัด")
        var o = S.OutageLetter()
        o.outageDay = Date(timeIntervalSince1970: 1_791_000_000) // 3 ต.ค. 2569 (Bangkok)
        o.end = 11 * 60 + 30
        let letter = o.letter(facts, today: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(letter.paragraphs.count, 3)
        XCTAssertTrue(letter.paragraphs[0].contains("บริษัท ข จำกัด"))
        XCTAssertTrue(letter.paragraphs[0].contains("209.76 kWp ณ สถานีจ่ายน้ำ ก อ.เมือง จ.สมุทรสงคราม"))
        XCTAssertTrue(letter.paragraphs[1].contains("\(PermitDate.long(o.outageDay!)) เวลา 09:00–11:30 น. (ประมาณ 2 ชั่วโมง 30 นาที)"))
        XCTAssertEqual(letter.date, PermitDate.long(Date(timeIntervalSince1970: 1_790_000_000)))

        o.body = "บรรทัดแรก\n\n  บรรทัดสอง "
        XCTAssertEqual(o.letter(facts).paragraphs, ["บรรทัดแรก", "บรรทัดสอง"])
    }

    func testOutageLetterIssues() {
        var o = S.OutageLetter()
        XCTAssertEqual(o.issues.count, 4)
        o.number = "TC-PML-012/2569"; o.to = "ผู้จัดการ"; o.outageDay = .now; o.signer = "ก"
        XCTAssertTrue(o.issues.isEmpty)
        o.end = o.start
        XCTAssertEqual(o.issues, ["เวลาดับไฟ"])
        XCTAssertEqual(o.duration, "")
    }

    func testStationKeepsTheOutageLetterAndOldJSONHasNone() throws {
        XCTAssertNil(S.Station.decode(#"{"docs":{}}"#).outageLetter)
        var s = S.Station()
        s.outageLetter = S.OutageLetter(number: "TC-PML-001/2569", to: "ผู้จัดการ", start: 600, end: 720)
        XCTAssertEqual(S.Station.decode(s.json), s)
        let partial = S.Station.decode(#"{"outageLetter":{"to":"ผู้จัดการ"}}"#).outageLetter
        XCTAssertEqual(partial, S.OutageLetter(to: "ผู้จัดการ"))
    }
}
