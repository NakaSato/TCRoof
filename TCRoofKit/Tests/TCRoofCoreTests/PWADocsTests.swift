import XCTest
@testable import TCRoofCore

final class PWADocsTests: XCTestCase {
    typealias S = StationDocs
    typealias D = PWADocs

    private let cal = MasterSchedule.calendar
    private lazy var today = cal.date(from: DateComponents(year: 2026, month: 10, day: 15))!

    private func station(_ id: String, kW: Double = 100, route: S.BuildingRoute = .notify,
                         _ statuses: [String: S.Status] = [:], due: [S.Package: Date] = [:]) -> PWAPlan.Station {
        var docs = S.Station(buildingRoute: route, docs: statuses.mapValues { S.DocState(status: $0) })
        for (p, d) in due { docs.setDue(d, for: p) }
        return PWAPlan.Station(id: id, name: id, docs: docs, docsContext: S.Context(docs, inverterKW: kW))
    }

    /// Every site paper of the station's packages set to `status`, then the overrides.
    private func all(_ status: S.Status, kW: Double = 100, route: S.BuildingRoute = .notify,
                     except: [String: S.Status] = [:]) -> [String: S.Status] {
        let ctx = S.Context(S.Station(buildingRoute: route), inverterKW: kW)
        var out = Dictionary(uniqueKeysWithValues: D.sitePapers(ctx).map { ($0.id, status) })
        out.merge(except) { $1 }
        return out
    }

    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

    // MARK: summary

    func testSummaryExcludesNotNeededAndCountsLibraryOnce() {
        let a = station("a", ["site_map": .approved, "outage_letter": .notNeeded])
        let b = station("b")
        let library = S.Library(docs: ["pwa_act": S.DocState(status: .approved), "vat_pp20": S.DocState(status: .notNeeded)])
        let s = D.summary([a, b], library: library)
        let sites = D.sitePapers(a.docsContext).count
        XCTAssertEqual(s.total, sites - 1 + sites + D.libraryKinds.count - 1)
        XCTAssertEqual(s.approved, 2)
        XCTAssertEqual(s.bands[.missing], s.total - 2)
        XCTAssertEqual(s.open.values.reduce(0, +), s.total - 2)
    }

    func testOver200AddsPK2Papers() {
        let small = D.sitePapers(station("s").docsContext).map(\.id)
        let big = D.sitePapers(station("b", kW: 250).docsContext).map(\.id)
        XCTAssertFalse(small.contains("pk1_form"))
        XCTAssertTrue(big.contains("pk1_form"))
        XCTAssertTrue(big.contains("layout_plan"))
        XCTAssertFalse(small.contains("layout_plan"))
        XCTAssertFalse(big.contains { S.kind($0)!.scope.isShared })
    }

    func testBandsPlaceEveryStatus() {
        XCTAssertEqual(D.Band(.signed), .submitted)
        XCTAssertEqual(D.Band(.requested), .waiting)
        XCTAssertNil(D.Band(.notNeeded))
        XCTAssertEqual(D.Summary(bands: [.approved: 1, .missing: 2], open: [:]).percent, 33)
    }

    // MARK: stepper

    func testStepperDoneCurrentLaterSkip() {
        // the building papers submitted, grid connection not: building done, grid current, handover later, พค.2 skipped
        let building = S.papers(in: .building, station("x").docsContext).map(\.id)
        let st = station("x", Dictionary(uniqueKeysWithValues: building.map { ($0, S.Status.submitted) }))
        let library = S.Library(docs: Dictionary(uniqueKeysWithValues: D.libraryKinds.map { ($0.id, S.DocState(status: .approved)) }))
        let steps = D.stepper(st, library: library)
        XCTAssertEqual(steps.map(\.title), ["อ.1", "ขนานไฟ", "พค.2", "ส่งมอบ"])
        XCTAssertEqual(steps.map(\.state), [.done, .current, .skip, .later])
        XCTAssertEqual(D.stepper(station("y", kW: 300), library: library).map(\.state), [.current, .later, .later, .later])
    }

    func testStepperAllDone() {
        let library = S.Library(docs: Dictionary(uniqueKeysWithValues: D.libraryKinds.map { ($0.id, S.DocState(status: .approved)) }))
        let st = station("z", all(.approved))
        XCTAssertEqual(D.stepper(st, library: library).map(\.state), [.done, .done, .skip, .done])
        let row = D.row(st, library: library, today: today)
        XCTAssertEqual(row.state, .ready)
        XCTAssertEqual(row.tag, "ครบ")
    }

    // MARK: stations

    func testStationStatesAndSort() {
        let lib = S.Library(docs: Dictionary(uniqueKeysWithValues: D.libraryKinds.map { ($0.id, S.DocState(status: .approved)) }))
        // building: ours (an internal paper missing)
        let ours = station("ours", all(.signed, except: ["structural_plan": .missing]))
        // building: only the notice left, sent to PWA to sign
        let pwa = station("pwa", all(.signed, except: ["building_exempt_notice": .requested]))
        // building in; grid connection: only the outage attachment, an outside paper asked for
        let outside = station("outside", all(.submitted, except: ["outage_attachment": .requested]))
        // building due yesterday and still missing a paper
        let late = station("late", all(.signed, except: ["structural_calc": .draft]), due: [.building: day(-1)])
        let ready = station("ready", all(.signed))
        let rows = D.rows([ready, outside, pwa, ours, late], library: lib, today: today)
        XCTAssertEqual(rows.map(\.id), ["late", "ours", "pwa", "outside", "ready"])
        XCTAssertEqual(rows.map(\.tag), ["ครบกำหนด", "ทีมเรา", "รอ กปภ.", "รอหน่วยงานนอก", "พร้อมยื่น"])
        XCTAssertEqual(rows[1].next?.id, "structural_plan")
        XCTAssertEqual(rows.filter { D.StationFilter.todo.holds($0.state) }.map(\.id), ["late", "ours"])
        XCTAssertEqual(rows.filter { D.StationFilter.waiting.holds($0.state) }.map(\.id), ["pwa", "outside"])
        XCTAssertEqual(rows.filter { D.StationFilter.all.holds($0.state) }.count, 5)
    }

    func testReadyToSubmitWhenCurrentPackageHasNoOpenPaper() {
        // everything signed: the building package is current and ready to go in; not-needed papers don't block it
        let lib = S.Library(docs: Dictionary(uniqueKeysWithValues: D.libraryKinds.map { ($0.id, S.DocState(status: .approved)) }))
        let st = station("s", all(.signed, except: ["outage_letter": .notNeeded, "outage_attachment": .notNeeded]))
        let row = D.row(st, library: lib, today: today)
        XCTAssertEqual(row.state, .ready)
        XCTAssertEqual(row.tag, "พร้อมยื่น")
        XCTAssertEqual(row.steps.first?.state, .current)
        // past its day it is late, ready or not
        let due = station("d", all(.signed), due: [.building: day(0)])
        XCTAssertEqual(D.row(due, library: lib, today: today).state, .late)
    }

    func testOutsideOfficeTag() {
        let lib = S.Library(docs: Dictionary(uniqueKeysWithValues: D.libraryKinds.map { ($0.id, S.DocState(status: .approved)) }))
        let st = station("p", route: .permit, all(.signed, route: .permit, except: ["building_permit_o1": .requested]))
        XCTAssertEqual(D.row(st, library: lib, today: today).tag, "รอเทศบาล")
    }

    // MARK: to do

    func testTodoGroupsByOriginSortedByDueWithLateFlag() {
        let lib = S.Library(docs: Dictionary(uniqueKeysWithValues: D.libraryKinds.map { ($0.id, S.DocState(status: .approved)) }))
        let a = station("a", all(.approved, except: ["asbuilt": .draft, "punch_list": .requested]), due: [.handover: day(-4)])
        let b = station("b", all(.approved, except: ["structural_plan": .missing, "outage_attachment": .requested]),
                        due: [.building: day(3), .gridConnection: day(1)])
        let groups = D.todo([b, a], library: lib)
        XCTAssertEqual(groups.map(\.origin), [.internalDoc, .signoff, .external])
        XCTAssertEqual(groups[0].items.map(\.id), ["a/asbuilt", "b/structural_plan"])
        XCTAssertEqual(groups[1].items.map(\.kind.id), ["punch_list"])
        XCTAssertEqual(groups[1].items[0].statusWord, "รอลงนาม")
        XCTAssertEqual(groups[2].items.map(\.kind.id), ["outage_attachment"])
        XCTAssertTrue(groups[0].items[0].isLate(today: today))
        XCTAssertEqual(groups[0].items[0].days(today: today), -4)
        XCTAssertFalse(groups[0].items[1].isLate(today: today))
        XCTAssertEqual(groups[0].items[1].package, .building)
    }

    func testTodoTakesEarliestPackageAndCountsDrafts() {
        // the as-built is in handover and พค.2; พค.2 is due first
        let a = station("a", kW: 300, ["outage_letter": .missing], due: [.pk2: day(2), .handover: day(9)])
        let groups = D.todo([a], library: .init())
        let asbuilt = groups[0].items.first { $0.kind.id == "asbuilt" }
        XCTAssertEqual(asbuilt?.package, .pk2)
        XCTAssertEqual(groups[0].draftable, 1)
        // the library's open papers are listed once, with no station
        XCTAssertEqual(groups.flatMap(\.items).filter { $0.station == nil }.count, D.libraryKinds.count)
    }

    // MARK: library

    func testLibraryPills() {
        let license = S.kind("engineer_license")!, act = S.kind("pwa_act")!
        XCTAssertEqual(D.pill(act, S.DocState(status: .approved), today: today), .latest)
        XCTAssertEqual(D.pill(act, S.DocState(), today: today), .missing)
        XCTAssertEqual(D.pill(license, S.DocState(status: .approved, expiresAt: day(20)), today: today), .soon(days: 20))
        XCTAssertEqual(D.pill(license, S.DocState(status: .approved, expiresAt: day(49)), today: today), .latest)
        XCTAssertEqual(D.pill(license, S.DocState(status: .approved, expiresAt: day(49)), today: today, warnDays: 60), .soon(days: 49))
        XCTAssertEqual(D.pill(license, S.DocState(status: .approved, expiresAt: day(-1)), today: today), .expired)
    }

    func testNearestExpiryPrefersExpired() {
        let lib = S.Library(docs: ["engineer_license": S.DocState(status: .approved, expiresAt: day(10)),
                                   "pwa_poa_order": S.DocState(status: .approved, expiresAt: day(-3))])
        let rows = D.library(lib, today: today)
        XCTAssertEqual(D.nearestExpiry(rows)?.kind.id, "pwa_poa_order")
        XCTAssertNil(D.nearestExpiry(D.library(.init(), today: today)))
    }

    // MARK: iPad

    func testDueNowCountsLateAndToday() {
        let late = station("late", ["building_exempt_notice": .draft], due: [.building: day(-2)])
        let today = station("today", ["building_exempt_notice": .draft], due: [.building: day(0)])
        let later = station("later", ["building_exempt_notice": .draft], due: [.building: day(3)])
        let groups = D.todo([late, today, later], library: S.Library())
        let open = groups.flatMap(\.items).filter { $0.due != nil }
        let lateOrToday = open.filter { ($0.days(today: self.today) ?? 1) <= 0 }.count
        XCTAssertEqual(D.dueNow(groups, today: self.today), lateOrToday)
        XCTAssertGreaterThan(lateOrToday, 0)
        // undated items (the library's) never count
        XCTAssertEqual(D.dueNow(D.todo([], library: S.Library()), today: self.today), 0)
    }

    func testStationOpenCountIncludesSharedAndSkipsReadyAndNotNeeded() {
        let all = D.stationPapers(S.Context(S.Station(buildingRoute: .notify), inverterKW: 100))
        let st = station("a", ["site_map": .approved, "outage_letter": .notNeeded])
        XCTAssertEqual(D.open(st, library: S.Library()).count, all.count - 2)
        let lib = S.Library(docs: Dictionary(uniqueKeysWithValues: D.libraryKinds.map { ($0.id, S.DocState(status: .approved)) }))
        XCTAssertEqual(D.open(st, library: lib).count, all.count - 2 - all.filter(\.scope.isShared).count)
    }

    func testUsedInCountsStationsNeedingTheKind() {
        let small = station("small", kW: 100), big = station("big", kW: 250)
        XCTAssertEqual(D.usedIn(S.kind("pwa_act")!, [small, big]).count, 2)
        // only for พค.2: under 200 kVA the station doesn't need it
        XCTAssertEqual(D.usedIn(S.kind("contract_mou")!, [small, big]).map(\.id), ["big"])
    }

    func testContractorsAndSort() {
        var a = station("a"), b = station("b"), c = station("c")
        a.contractor = "B"; b.contractor = "A"; c.contractor = ""
        XCTAssertEqual(D.contractors([a, b, c]), ["A", "B"])
        let full = station("full", all(.approved))
        let rows = D.rows([full, a], library: S.Library(), today: today)
        XCTAssertEqual(D.sorted(rows, by: .missing, library: S.Library()).first?.id, "a")
    }

    func testFlowSteps() {
        XCTAssertEqual(D.flow(.signoff, .requested), D.Flow(labels: ["ยังไม่มี", "ร่าง", "รอลงนาม", "ยื่นแล้ว", "อนุมัติ"], done: 2, current: 2))
        XCTAssertNil(D.flow(.signoff, .approved).current)
        XCTAssertEqual(D.flow(.external, .requested).labels, ["ยังไม่มี", "ขอแล้ว", "ได้รับแล้ว"])
        XCTAssertEqual(D.flow(.external, .signed).done, 3)
    }

    func testStatusAfterUpload() {
        let sign = S.kind("poa_letter")!, ours = S.kind("asbuilt")!, outside = S.kind("land_deed")!
        XCTAssertEqual(D.statusAfterUpload(sign, .requested), .submitted)
        XCTAssertEqual(D.statusAfterUpload(sign, .missing), .draft)
        XCTAssertEqual(D.statusAfterUpload(ours, .draft), .submitted)
        XCTAssertEqual(D.statusAfterUpload(outside, .requested), .approved)
        XCTAssertEqual(D.statusAfterUpload(sign, .approved), .approved)
    }

    func testPK2TitleAndLetterNumber() {
        let item = D.Item(kind: S.kind("layout_plan")!, status: .draft, station: nil, package: .pk2, due: nil)
        XCTAssertEqual(D.title(item), "พค.2 ข้อ 8 · " + S.kind("layout_plan")!.name)
        XCTAssertEqual(D.letterNumber("ส่งแล้ว เลขที่ TC-PML-001/2569 รอ"), "TC-PML-001/2569")
        XCTAssertNil(D.letterNumber("รอลงนาม"))
    }

    func testExpiryMarksWithinAYear() {
        let lib = S.Library(docs: ["engineer_license": S.DocState(status: .approved, expiresAt: day(49)),
                                   "pwa_poa_order": S.DocState(status: .approved, expiresAt: day(400))])
        let marks = D.expiryMarks(D.library(lib, today: today), today: today)
        XCTAssertEqual(marks.map(\.kind.id), ["engineer_license"])
        XCTAssertEqual(marks.first?.days, 49)
    }

    func testSearchFindsStationsPapersByNoteAndLibrary() {
        var st = station("a", ["poa_letter": .draft])
        st.mpNumber = 189
        st.docs.docs["poa_letter"]?.note = "เลขที่ กปภ.123/2569"
        let hits = D.search("123/2569", stations: [st], library: S.Library())
        XCTAssertEqual(hits.map(\.type), [.paper])
        XCTAssertEqual(D.search("MP 189", stations: [st], library: S.Library()).first?.type, .station)
        XCTAssertTrue(D.search("พ.ร.บ.", stations: [st], library: S.Library()).contains { $0.type == .library })
    }
}
