import XCTest
@testable import TCRoofCore

/// MP plan links (master-schedule-swift.md §5): permit tasks booked from the station's papers, and the install photos a
/// construction task needs before 100 %.
final class MasterScheduleLinksTests: XCTestCase {
    private let cal = MasterSchedule.calendar

    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day))!
    }

    private func input(over200kVA: Bool) -> MasterSchedule.Input {
        MasterSchedule.Input(installStart: d(2026, 2, 22), installEnd: d(2026, 4, 8),
                             kickoff: d(2026, 1, 5), engineeringStart: d(2026, 1, 5), siteHandover: d(2026, 1, 12),
                             over200kVA: over200kVA)
    }

    private func ctx(_ s: StationDocs.Station, over200kVA: Bool) -> StationDocs.Context {
        var s = s
        s.over200kVA = over200kVA
        return StationDocs.Context(s, inverterKW: nil)
    }

    private func approved(_ day: Date) -> StationDocs.DocState { .init(status: .approved, updatedAt: day) }

    private func total(_ a: MasterSchedule.Actual, _ t: MasterSchedule.Task) -> Double {
        (a.points[t.rawValue] ?? [:]).values.reduce(0, +)
    }

    // MARK: mapping

    func testTheTableCoversTheThreePermitTasks() {
        XCTAssertEqual(PermitLink.sources.map(\.task), [.buildingPermit, .pk2, .gridConnection])
        XCTAssertEqual(PermitLink.sources(for: .buildingPermit), [.paper("building_permit_o1"), .paper("building_exempt_notice")])
        XCTAssertEqual(PermitLink.sources(for: .pk2), [.paper("pk1_form"), .erc(.pk2Signed)])
        XCTAssertEqual(PermitLink.sources(for: .gridConnection), [.sitePackage(.gridConnection), .erc(.cod)])
        XCTAssertTrue(PermitLink.sources(for: .structure).isEmpty)
        // every paper named is a site paper of the catalog
        for case .paper(let id) in PermitLink.sources.flatMap(\.sources) {
            XCTAssertEqual(StationDocs.kind(id)?.scope, .site, id)
        }
    }

    func testBuildingPermitFollowsTheMunicipalitysAnswer() {
        var s = StationDocs.Station(buildingRoute: .permit)
        XCTAssertNil(PermitLink.approval(.buildingPermit, station: s, ctx(s, over200kVA: false)))
        s.docs["building_permit_o1"] = .init(status: .submitted, updatedAt: d(2026, 2, 1))
        XCTAssertNil(PermitLink.approval(.buildingPermit, station: s, ctx(s, over200kVA: false)), "submitted isn't approved")
        s.docs["building_permit_o1"] = approved(d(2026, 2, 3))
        XCTAssertEqual(PermitLink.approval(.buildingPermit, station: s, ctx(s, over200kVA: false)), d(2026, 2, 3))

        // a notice approved doesn't count where the เทศบาล wants a permit
        var n = StationDocs.Station(buildingRoute: .permit)
        n.docs["building_exempt_notice"] = approved(d(2026, 2, 3))
        XCTAssertNil(PermitLink.approval(.buildingPermit, station: n, ctx(n, over200kVA: false)))
        n.buildingRoute = .notify
        XCTAssertEqual(PermitLink.approval(.buildingPermit, station: n, ctx(n, over200kVA: false)), d(2026, 2, 3))
    }

    func testPK2FromThePaperOrTheERCFlowWhicheverIsFirst() {
        var s = StationDocs.Station()
        s.docs["pk1_form"] = approved(d(2026, 3, 20))
        XCTAssertNil(PermitLink.approval(.pk2, station: s, ctx(s, over200kVA: false)), "no พค.2 under 200 kVA")
        XCTAssertEqual(PermitLink.approval(.pk2, station: s, ctx(s, over200kVA: true)), d(2026, 3, 20))
        var r = ERCFlow.Record()
        r.add(.pk2Signed, day: "2026-03-10")
        s.erc = r
        XCTAssertEqual(PermitLink.approval(.pk2, station: s, ctx(s, over200kVA: true)), d(2026, 3, 10))
    }

    func testGridConnectionNeedsEverySitePaperOfItsSetApproved() {
        var s = StationDocs.Station()
        let c = ctx(s, over200kVA: false)
        let site = StationDocs.papers(in: .gridConnection, c).filter { !$0.scope.isShared }
        XCTAssertTrue(site.count > 3)
        for (i, k) in site.enumerated() { s.docs[k.id] = approved(d(2026, 4, 1 + i)) }
        s.docs[site[0].id]?.status = .submitted
        XCTAssertNil(PermitLink.approval(.gridConnection, station: s, c))
        s.docs[site[0].id]?.status = .notNeeded
        XCTAssertEqual(PermitLink.approval(.gridConnection, station: s, c), d(2026, 4, site.count), "the last one approved")
        // the shared papers (device library) don't count
        XCTAssertTrue(StationDocs.papers(in: .gridConnection, c).contains { $0.scope.isShared })

        var e = StationDocs.Station()
        var r = ERCFlow.Record()
        r.add(.cod, day: "2026-04-20")
        e.erc = r
        XCTAssertEqual(PermitLink.approval(.gridConnection, station: e, ctx(e, over200kVA: true)), d(2026, 4, 20))
    }

    // MARK: booking

    func testApprovalBooksOneHundredPercentInItsWeekWithItsFinishDate() {
        var s = StationDocs.Station(buildingRoute: .permit)
        s.docs["building_permit_o1"] = approved(d(2026, 2, 4))
        let i = input(over200kVA: false)
        var a = MasterSchedule.Actual()
        a.setPercent(25, task: .buildingPermit, week: d(2026, 1, 20), weight: i.weight(.buildingPermit))
        let booked = PermitLink.book(&a, input: i, station: s, ctx(s, over200kVA: false))
        XCTAssertEqual(booked, [.buildingPermit])
        XCTAssertEqual(total(a, .buildingPermit), 1.5, accuracy: 1e-9)
        XCTAssertEqual(a.points(.buildingPermit, week: d(2026, 2, 4)), 1.5 * 0.75, accuracy: 1e-9, "the rest in the approval's week")
        XCTAssertEqual(a.finished["buildingPermit"], d(2026, 2, 4))
        XCTAssertEqual(a.fromDocuments["buildingPermit"], d(2026, 2, 4))
    }

    func testBookingIsIdempotentAndNeverUndone() {
        var s = StationDocs.Station(buildingRoute: .permit)
        s.docs["building_permit_o1"] = approved(d(2026, 2, 4))
        let i = input(over200kVA: false), c = ctx(s, over200kVA: false)
        var a = MasterSchedule.Actual()
        PermitLink.book(&a, input: i, station: s, c)
        let once = a
        XCTAssertEqual(PermitLink.book(&a, input: i, station: s, c), [])
        XCTAssertEqual(a, once, "a second run changes nothing")

        // the approval taken back: nothing lowered
        s.docs["building_permit_o1"]?.status = .submitted
        XCTAssertEqual(PermitLink.book(&a, input: i, station: s, c), [])
        XCTAssertEqual(a, once)

        // the team lowers it while the paper is approved again: the link has already answered
        a.setPercent(50, task: .buildingPermit, week: d(2026, 2, 4), weight: 1.5)
        s.docs["building_permit_o1"]?.status = .approved
        XCTAssertEqual(PermitLink.book(&a, input: i, station: s, c), [])
        XCTAssertEqual(total(a, .buildingPermit), 0.75, accuracy: 1e-9)
    }

    func testATaskAlreadyDoneIsNotBookedTwice() {
        var s = StationDocs.Station()
        var r = ERCFlow.Record()
        r.add(.cod, day: "2026-04-20")
        s.erc = r
        let i = input(over200kVA: true)
        var a = MasterSchedule.Actual()
        a.setPercent(100, task: .gridConnection, week: d(2026, 4, 1), weight: 1)
        a.finished["gridConnection"] = d(2026, 4, 2)
        XCTAssertEqual(PermitLink.book(&a, input: i, station: s, ctx(s, over200kVA: true)), [])
        XCTAssertEqual(total(a, .gridConnection), 1, accuracy: 1e-9)
        XCTAssertEqual(a.points(.gridConnection, week: d(2026, 4, 20)), 0)
        XCTAssertEqual(a.finished["gridConnection"], d(2026, 4, 2), "its own finish stays")
        XCTAssertNotNil(a.fromDocuments["gridConnection"])
    }

    func testATaskWithoutWeightIsSkippedAndAStartAfterTheApprovalMovesBack() {
        var s = StationDocs.Station()
        s.docs["pk1_form"] = approved(d(2026, 3, 20))
        var a = MasterSchedule.Actual()
        // under 200 kVA the plan gives พค.2 no weight
        XCTAssertEqual(PermitLink.book(&a, input: input(over200kVA: false), station: s, ctx(s, over200kVA: true)), [])
        XCTAssertNil(a.fromDocuments["pk2"])

        a.started["pk2"] = d(2026, 3, 25)
        XCTAssertEqual(PermitLink.book(&a, input: input(over200kVA: true), station: s, ctx(s, over200kVA: true)), [.pk2])
        XCTAssertEqual(a.started["pk2"], d(2026, 3, 20))
        XCTAssertEqual(a.finished["pk2"], d(2026, 3, 20))
    }

    /// The two passes the app runs besides a paper change (`Job.bookPermitsFromDocs`): a plan made after the approval,
    /// and a workbook import whose progress replaced the job's (so it has no `fromDocuments`).
    func testAPlanMadeLaterOrAnImportedProgressIsBookedOnTheNextPass() {
        var s = StationDocs.Station(buildingRoute: .permit)
        s.docs["building_permit_o1"] = approved(d(2026, 2, 4))
        let i = input(over200kVA: false), c = ctx(s, over200kVA: false)

        // approved while there was no plan: the first pass after the plan books it
        var fresh = MasterSchedule.Actual()
        XCTAssertEqual(PermitLink.book(&fresh, input: i, station: s, c), [.buildingPermit])
        XCTAssertEqual(total(fresh, .buildingPermit), 1.5, accuracy: 1e-9)

        // a file's progress: other tasks booked, the permit at 40 %, no record of the link
        var file = MasterSchedule.Actual()
        file.setPercent(40, task: .buildingPermit, week: d(2026, 1, 27), weight: 1.5)
        file.setPercent(60, task: .structure, week: d(2026, 3, 1), weight: i.weight(.structure))
        let structure = total(file, .structure)
        XCTAssertEqual(PermitLink.book(&file, input: i, station: s, c), [.buildingPermit])
        XCTAssertEqual(total(file, .buildingPermit), 1.5, accuracy: 1e-9, "brought to 100 % again")
        XCTAssertEqual(file.fromDocuments["buildingPermit"], d(2026, 2, 4))
        XCTAssertEqual(total(file, .structure), structure, accuracy: 1e-9, "the file's other tasks stay")

        // a file already at 100 % is only remembered
        var done = MasterSchedule.Actual()
        done.setPercent(100, task: .buildingPermit, week: d(2026, 2, 10), weight: 1.5)
        XCTAssertEqual(PermitLink.book(&done, input: i, station: s, c), [])
        XCTAssertEqual(done.points(.buildingPermit, week: d(2026, 2, 10)), 1.5, accuracy: 1e-9)
        XCTAssertEqual(done.fromDocuments["buildingPermit"], d(2026, 2, 4))
    }

    func testFromDocumentsDecodesFromOlderPlansAndIsLeftOutWhenEmpty() throws {
        let old = #"{"points":{"kickoff":{"2026-01-04":0.5}},"started":{},"finished":{},"lateCauses":{}}"#
        let a = try JSONDecoder().decode(MasterSchedule.Actual.self, from: Data(old.utf8))
        XCTAssertTrue(a.fromDocuments.isEmpty)
        let json = String(data: try JSONEncoder().encode(a), encoding: .utf8)!
        XCTAssertFalse(json.contains("fromDocuments"))
        var b = a
        b.fromDocuments["pk2"] = d(2026, 3, 20)
        XCTAssertEqual(try JSONDecoder().decode(MasterSchedule.Actual.self, from: try JSONEncoder().encode(b)), b)
    }

    // MARK: install photos

    private func twoInverters() -> IECReport {
        IECReport(inverters: [IECReport.Inverter(ratedKW: 125, serial: "A"), IECReport.Inverter(ratedKW: 60, serial: "B")])
    }

    func testEachReportSlotBelongsToOneConstructionTask() {
        let r = twoInverters()
        let byTask = Dictionary(grouping: MasterSchedule.Task.allCases, by: { $0 }).mapValues { r.installPhotos(for: $0[0]).count }
        XCTAssertEqual(byTask[.structure], 3)
        XCTAssertEqual(byTask[.panels], 1)
        XCTAssertEqual(byTask[.dcSide], 3)
        XCTAssertEqual(byTask[.inverter], 5, "two per inverter and the Inverter Station")
        XCTAssertEqual(byTask[.acSide], 3)
        XCTAssertEqual(byTask[.zeroExport], 2)
        XCTAssertEqual(byTask[.monitoring], 2)
        XCTAssertEqual(byTask[.fireSwitch], 0)
        XCTAssertEqual(byTask[.controlCabinet], 0)
        XCTAssertEqual(byTask[.buildingPermit], 0)
        XCTAssertEqual(MasterSchedule.Task.allCases.reduce(0) { $0 + (byTask[$1] ?? 0) }, r.installTally.total, "every slot is mapped once")
    }

    func testMissingPhotosNameWhatIsLeft() {
        var r = twoInverters()
        r.installPhotos.addRoof("หลังคา 2")
        XCTAssertEqual(r.installPhotos(for: .structure).count, 6, "three per roof")
        let ac = r.installPages.first { $0.id == "ac" }!
        r.setInstallPhoto("p1", for: ac.slots[0])
        let missing = IECReport.missingPhotoLabels(r, for: .acSide)
        XCTAssertEqual(missing, ["ตู้ AC · ภาพถ่ายตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสสลับ (ด้านนอก)", "กราวน์ AC / Inverter Station · ภาพถ่ายกราวน์กระแสสลับ"])
        let gac = r.installPages.first { $0.id == "gac" }!
        r.setInstallPhoto("p2", for: ac.slots[1])
        r.setInstallPhoto("p3", for: gac.slots[0])
        XCTAssertEqual(IECReport.missingPhotoLabels(r, for: .acSide), [])

        // step 1's inverter photos count
        r.inverters[0].photos["front"] = "f"
        XCTAssertEqual(r.missingInstallPhotos(for: .inverter).count, 4)
    }

    func testTasksOutsideConstructionOrWithoutSlotsNeedNothingAndNoTestMeansAllMissing() {
        XCTAssertEqual(IECReport.missingPhotoLabels(nil, for: .preCommissioning), [])
        XCTAssertEqual(IECReport.missingPhotoLabels(nil, for: .fireSwitch), [])
        XCTAssertEqual(IECReport.missingPhotoLabels(nil, for: .panels), ["หลังคา 1 (2/2) · ภาพถ่ายแผงเซลล์แสงอาทิตย์"])
        let inv = IECReport.missingPhotoLabels(nil, for: .inverter)
        XCTAssertEqual(inv.first, "Inverter · ยังไม่ได้เพิ่มเครื่องในขั้น 1 ของการทดสอบ IEC")
        XCTAssertEqual(inv.count, 2, "and the Inverter Station")
    }
}
