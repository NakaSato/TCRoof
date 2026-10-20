import XCTest
@testable import TCRoofCore

final class ERCFlowTests: XCTestCase {
    typealias E = ERCFlow

    /// A record with these steps recorded in order, a day apart from 2026-10-01.
    private func record(_ steps: [(E.Step, E.Result?)]) -> E.Record {
        var r = E.Record()
        for (i, s) in steps.enumerated() { r.add(s.0, day: String(format: "2026-10-%02d", i + 1), result: s.1) }
        return r
    }

    func testNewRecordOnlyOpensTheDesignRequest() {
        let s = E.states(E.Record())
        XCTAssertEqual(s[.designRequest], .open)
        for step in E.Step.allCases where step != .designRequest { XCTAssertEqual(s[step], .blocked, step.rawValue) }
        XCTAssertEqual(E.current(E.Record()), [.designRequest])
        XCTAssertEqual(E.Step.allCases.compactMap(\.number), Array(1...12))
    }

    func testDesignResultWaitsFifteenWorkingDaysAcrossWeekendsAndHolidays() {
        var r = E.Record()
        r.add(.designRequest, day: "2026-10-01") // Thursday
        XCTAssertEqual(E.states(r)[.designResult], .waiting(since: "2026-10-01", due: "2026-10-22"))
        let ctx = E.Context(holidays: ["2026-10-13", "2026-10-23"])
        XCTAssertEqual(E.states(r, ctx)[.designResult], .waiting(since: "2026-10-01", due: "2026-10-26"))
        XCTAssertEqual(E.states(r)[.install], .blocked)
    }

    func testFailedDesignGoesRoundAgainAndKeepsTheHistory() {
        var r = record([(.designRequest, nil), (.designResult, .failed)])
        var s = E.states(r)
        XCTAssertEqual(s[.designRequest], .open)
        XCTAssertEqual(s[.designResult], .blocked)
        XCTAssertEqual(r.failedRounds(.designResult), 1)

        r.add(.designRequest, day: "2026-10-05") // Monday
        s = E.states(r)
        XCTAssertEqual(s[.designRequest], .done(day: "2026-10-05"))
        XCTAssertEqual(s[.designResult], .waiting(since: "2026-10-05", due: "2026-10-26"))

        r.add(.designResult, day: "2026-10-09")
        s = E.states(r)
        XCTAssertEqual(s[.designResult], .done(day: "2026-10-09"))
        XCTAssertEqual(s[.install], .open)
        XCTAssertEqual(r.events.count, 4)
        XCTAssertEqual(r.failedRounds(.designResult), 1)
    }

    func testAfterInstallThePermitAndTheInspectionRunTogether() {
        let r = record([(.designRequest, nil), (.designResult, .passed)])
        XCTAssertEqual(E.current(r), [.install])
        let ctx = E.Context(installDone: "2026-11-20")
        XCTAssertEqual(E.states(r, ctx)[.install], .done(day: "2026-11-20"))
        XCTAssertEqual(E.current(r, ctx), [.pk2Request, .inspectionRequest])

        var r2 = r
        r2.add(.pk2Request, day: "2026-11-23")
        r2.add(.ercToDede, day: "2026-11-25")
        let s = E.states(r2, ctx)
        XCTAssertEqual(s[.dedeOpinion], .waiting(since: "2026-11-25", due: "2026-12-25")) // 30 calendar days
        XCTAssertEqual(s[.pk2Signed], .waiting(since: "2026-11-23", due: nil))
        XCTAssertEqual(s[.inspectionRequest], .open)
    }

    func testStepsBetweenOtherPartiesCanBePassedOver() {
        var r = record([(.designRequest, nil), (.designResult, .passed), (.install, nil), (.pk2Request, nil)])
        XCTAssertEqual(E.states(r)[.ercToDede], .waiting(since: "2026-10-04", due: nil))
        r.add(.pk2Signed, day: "2026-11-10")
        let s = E.states(r)
        XCTAssertEqual(s[.ercToDede], .notNeeded)
        XCTAssertEqual(s[.dedeOpinion], .notNeeded)
        XCTAssertEqual(s[.pk2Signed], .done(day: "2026-11-10"))
        XCTAssertEqual(E.exemptionBasis(r), .pk2)
    }

    func testConnectingWaitsForPK2OnlyWhereTheUtilityAsks() {
        var r = record([(.designRequest, nil), (.designResult, .passed), (.install, nil),
                        (.inspectionRequest, nil), (.inspectionResult, .passed)])
        XCTAssertTrue(E.canConnect(r))
        XCTAssertEqual(E.states(r)[.pk2ToUtility], .blocked)

        r.utilityWantsPK2 = true
        XCTAssertFalse(E.canConnect(r))
        r.add(.pk2Request, day: "2026-10-06")
        r.add(.pk2Signed, day: "2026-10-20")
        XCTAssertEqual(E.states(r)[.pk2ToUtility], .open)
        XCTAssertFalse(E.canConnect(r))
        r.add(.pk2ToUtility, day: "2026-10-21")
        XCTAssertTrue(E.canConnect(r))
        XCTAssertEqual(E.states(r)[.cod], .waiting(since: "2026-10-21", due: nil))

        r.utilityWantsPK2 = false
        XCTAssertEqual(E.states(r)[.pk2ToUtility], .notNeeded)
        XCTAssertTrue(E.canConnect(r))
    }

    func testFailedInspectionReopensTheRequest() {
        let r = record([(.designRequest, nil), (.designResult, .passed), (.install, nil),
                        (.inspectionRequest, nil), (.inspectionResult, .failed)])
        let s = E.states(r)
        XCTAssertEqual(s[.inspectionRequest], .open)
        XCTAssertEqual(s[.cod], .blocked)
        XCTAssertFalse(E.canConnect(r))
    }

    func testExemptionBasisAndTheEnd() {
        var r = record([(.designRequest, nil), (.designResult, .passed), (.install, nil),
                        (.inspectionRequest, nil), (.inspectionResult, .passed)])
        XCTAssertNil(E.exemptionBasis(r))
        XCTAssertEqual(E.states(r)[.exemptionResult], .waiting(since: "2026-10-05", due: nil))
        r.add(.utilityToERC, day: "2026-10-08")
        XCTAssertEqual(E.exemptionBasis(r), .utilityLetter)
        r.add(.cod, day: "2026-10-09")
        r.add(.exemptionResult, day: "2026-10-12")
        XCTAssertEqual(E.current(r), [])
    }

    func testDaysLeftCountsWorkingDaysAndGoesNegative() {
        let wed = E.date("2026-10-14")!
        XCTAssertEqual(E.daysLeft(.designResult, due: "2026-10-22", on: wed), 6)
        XCTAssertEqual(E.daysLeft(.designResult, due: "2026-10-14", on: wed), 0)
        XCTAssertEqual(E.daysLeft(.designResult, due: "2026-10-09", on: wed), -3)
        XCTAssertEqual(E.daysLeft(.dedeOpinion, due: "2026-10-22", on: wed), 8)
        XCTAssertEqual(E.daysLeft(.designResult, due: "2026-10-22", on: wed, E.Context(holidays: ["2026-10-15"])), 5)
    }

    func testWaitsHeadlineAndTheDayBefore() {
        var r = E.Record()
        XCTAssertEqual(E.headline(r), "ถึงคิวทีมเรา: ข้อ 1 ยื่นคำขอตรวจสอบแบบและระบบไฟฟ้า")
        r.add(.designRequest, day: "2026-10-01")
        XCTAssertEqual(E.headline(r), "รอการไฟฟ้า: ข้อ 2 ผลพิจารณาแบบและระบบไฟฟ้า")
        let waits = E.waits(r, today: E.date("2026-10-19")!)
        XCTAssertEqual(waits, [E.Wait(step: .designResult, since: "2026-10-01", due: "2026-10-22", left: 3)])
        XCTAssertEqual(waits[0].text, "เหลือ 3 วันทำการ")
        XCTAssertEqual(E.waits(r, today: E.date("2026-10-26")!)[0].text, "เกินกำหนด 2 วันทำการ")
        XCTAssertEqual(E.day("2026-10-22", before: 3, working: true), "2026-10-19")
        XCTAssertEqual(E.day("2026-10-20", before: 3, working: true), "2026-10-15")
        XCTAssertEqual(E.day("2026-10-20", before: 3, working: false), "2026-10-17")
        r.add(.designResult, day: "2026-10-10")
        XCTAssertTrue(E.waits(r).isEmpty)
    }

    func testRemindersComeBeforeAndAfterTheLimit() {
        var r = E.Record()
        r.add(.designRequest, day: "2026-10-01") // due 2026-10-22
        let cal = MasterSchedule.calendar
        func at(_ day: String, _ hour: Int) -> Date { cal.date(bySettingHour: hour, minute: 0, second: 0, of: E.date(day)!)! }
        var plans = ERCNotification.plans(jobKey: "J", station: "สถานี ก", record: r, now: at("2026-10-05", 9))
        XCTAssertEqual(plans.map(\.id), ["erc-soon-J-designResult-2026-10-22", "erc-over-J-designResult-2026-10-22"])
        XCTAssertEqual(plans.map(\.fire), [.at(at("2026-10-19", 8)), .at(at("2026-10-23", 8))])
        XCTAssertEqual(plans[0].title, "รอผลพิจารณาแบบและระบบไฟฟ้า เหลือ 3 วันทำการ")
        XCTAssertEqual(DeepLink.route(type: plans[0].type, action: nil, info: plans[0].info), .job(job: "J"))
        // past the first reminder: only the overdue one is left; past both: none
        plans = ERCNotification.plans(jobKey: "J", station: "สถานี ก", record: r, now: at("2026-10-20", 9))
        XCTAssertEqual(plans.map(\.id), ["erc-over-J-designResult-2026-10-22"])
        XCTAssertTrue(ERCNotification.plans(jobKey: "J", station: "สถานี ก", record: r, now: at("2026-10-24", 9)).isEmpty)
        XCTAssertTrue(ERCNotification.plans(jobKey: "J", station: "สถานี ก", record: E.Record(), now: at("2026-10-05", 9)).isEmpty)
    }

    // MARK: Under 200 kVA (utility_lt200)

    private let small = E.Context(variant: .under200)

    func testTheSizePicksTheFlowAtTwoHundred() {
        XCTAssertEqual(E.Variant(kVA: 150), .under200)
        XCTAssertEqual(E.Variant(kVA: 199.9), .under200)
        XCTAssertEqual(E.Variant(kVA: 200), .from200)
        XCTAssertEqual(E.Variant(kVA: 1200), .from200, "1,000 kVA and over keeps the 200–1,000 flow, as before")
        XCTAssertEqual(MasterSchedule.Input.isOver200kVA(inverterKW: 200), StationDocs.Context(StationDocs.Station(), inverterKW: 200).over200kVA)
        XCTAssertFalse(MasterSchedule.Input.isOver200kVA(inverterKW: 199))
    }

    func testSmallFlowHasSevenNumberedStepsAndNoPK2() {
        let steps = E.Variant.under200.steps
        XCTAssertEqual(steps, [.designRequest, .designResult, .install, .inspectionRequest, .inspectionResult, .utilityToERC, .cod, .exemptionResult])
        XCTAssertEqual(steps.compactMap { $0.number(in: .under200) }, Array(1...7))
        XCTAssertNil(E.Step.pk2Request.number(in: .under200))
        XCTAssertEqual(E.Step.inspectionResult.number(in: .from200), 8)
        let s = E.states(E.Record(), small)
        XCTAssertEqual(Set(s.keys), Set(steps))
        XCTAssertEqual(E.current(E.Record(), small), [.designRequest])
        XCTAssertEqual(E.headline(E.Record(), small), "ถึงคิวทีมเรา: ข้อ 1 ยื่นคำขอตรวจสอบแบบและระบบไฟฟ้า")
        XCTAssertEqual(E.Variant.under200.sections, E.Section.allCases)
    }

    func testSmallFlowDueDatesAreTheUtilitysFifteenAndThirtyWorkingDays() {
        var r = E.Record()
        r.add(.designRequest, day: "2026-10-01")
        XCTAssertEqual(E.states(r, small)[.designResult], .waiting(since: "2026-10-01", due: "2026-10-22"))
        r.add(.designResult, day: "2026-10-09")
        let ctx = E.Context(installDone: "2026-11-20", variant: .under200)
        XCTAssertEqual(E.current(r, ctx), [.inspectionRequest], "no พค.2 request after installation")
        r.add(.inspectionRequest, day: "2026-11-23") // Monday
        XCTAssertEqual(E.states(r, ctx)[.inspectionResult], .waiting(since: "2026-11-23", due: "2027-01-04"))
        let waits = E.waits(r, ctx, today: E.date("2026-12-28")!)
        XCTAssertEqual(waits.map(\.step), [.inspectionResult])
        XCTAssertEqual(waits[0].number, 4)
        XCTAssertEqual(waits[0].text, "เหลือ 5 วันทำการ")
        XCTAssertEqual(E.headline(r, ctx), "รอการไฟฟ้า: ข้อ 4 ผลตรวจระบบ / อุปกรณ์การเชื่อมต่อ")
    }

    func testSmallFlowConnectsOnceTheInspectionPassesWithoutPK2() {
        var r = record([(.designRequest, nil), (.designResult, .passed), (.install, nil),
                        (.inspectionRequest, nil), (.inspectionResult, .failed)])
        XCTAssertFalse(E.canConnect(r, small))
        XCTAssertEqual(E.states(r, small)[.inspectionRequest], .open)
        r.add(.inspectionRequest, day: "2026-10-10")
        r.add(.inspectionResult, day: "2026-10-20")
        r.utilityWantsPK2 = true // a step-10 answer means nothing here
        XCTAssertTrue(E.canConnect(r, small))
        let s = E.states(r, small)
        XCTAssertEqual(s[.cod], .waiting(since: "2026-10-20", due: nil))
        XCTAssertEqual(s[.utilityToERC], .waiting(since: "2026-10-20", due: nil))
        XCTAssertEqual(s[.exemptionResult], .waiting(since: "2026-10-20", due: nil))
        XCTAssertNil(s[.pk2ToUtility])
        XCTAssertEqual(E.current(r, small), [.utilityToERC, .cod, .exemptionResult])

        r.add(.utilityToERC, day: "2026-10-22")
        XCTAssertEqual(E.exemptionBasis(r), .utilityLetter)
        r.add(.cod, day: "2026-10-23")
        r.add(.exemptionResult, day: "2026-11-02")
        XCTAssertEqual(E.current(r, small), [])
        XCTAssertEqual(E.headline(r, small), "ครบทุกขั้นแล้ว")
    }

    func testSmallFlowRemindersUseItsNumbers() {
        var r = E.Record()
        r.add(.designRequest, day: "2026-10-01")
        r.add(.designResult, day: "2026-10-05")
        r.add(.install, day: "2026-10-06")
        r.add(.inspectionRequest, day: "2026-10-07")
        let now = MasterSchedule.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: E.date("2026-10-08")!)!
        let plans = ERCNotification.plans(jobKey: "J", station: "สถานี ข", record: r, context: small, now: now)
        XCTAssertEqual(plans.count, 2)
        XCTAssertTrue(plans.allSatisfy { $0.id.contains("inspectionResult") })
        XCTAssertTrue(plans[0].sub.contains("ลำดับ กกพ. ข้อ 4"), plans[0].sub)
    }

    func testARecordKeepsTheFlowItStartedInAcrossTwoHundred() {
        var r = E.Record()
        let big = E.Context(variant: .from200)
        XCTAssertEqual(r.variant(small), .under200, "an empty record follows the station")
        XCTAssertEqual(r.variant(big), .from200)

        r.pin(small)
        r.add(.designRequest, day: "2026-10-01")
        XCTAssertEqual(r.variant(big), .under200, "a started record keeps its flow when the station grows")
        XCTAssertNil(E.states(r, big)[.pk2Request])
        XCTAssertTrue(r.canSwitch(to: .from200))

        // a record from before the small flow: no variant, follows the station
        var legacy = record([(.designRequest, nil), (.designResult, .passed)])
        XCTAssertNil(legacy.variant)
        XCTAssertEqual(legacy.variant(big), .from200)
        legacy.add(.pk2Request, day: "2026-10-05")
        XCTAssertEqual(legacy.variant(small), .from200, "a พค.2 step keeps the big flow when the station shrinks")
        XCTAssertFalse(legacy.canSwitch(to: .under200))
        legacy.variant = .under200 // even if an older build or a hand edit says otherwise
        XCTAssertEqual(legacy.variant(small), .from200)
        XCTAssertEqual(E.states(legacy, small)[.pk2Request], .done(day: "2026-10-05"))
    }

    func testTheFlowRoundTripsAndOldOrUnknownOnesDecode() {
        var r = E.Record(variant: .under200)
        r.add(.designRequest, day: "2026-10-01")
        let data = try! JSONEncoder().encode(r)
        XCTAssertTrue(String(data: data, encoding: .utf8)!.contains(#""variant":"utility_lt200""#))
        XCTAssertEqual(try JSONDecoder().decode(E.Record.self, from: data), r)
        let unknown = #"{"events":[{"step":"designRequest","day":"2026-10-01"}],"variant":"private_lt200"}"#
        let d = try! JSONDecoder().decode(E.Record.self, from: Data(unknown.utf8))
        XCTAssertNil(d.variant)
        XCTAssertEqual(d.events.count, 1)
    }

    func testStationKeepsTheRecordAndOldJSONHasNone() {
        XCTAssertNil(StationDocs.Station.decode(#"{"docs":{}}"#).erc)
        var s = StationDocs.Station()
        s.erc = record([(.designRequest, nil), (.designResult, .failed)])
        s.erc?.utilityWantsPK2 = true
        XCTAssertEqual(StationDocs.Station.decode(s.json), s)
        // a step from a newer build is dropped, the rest stays
        let json = #"{"erc":{"events":[{"step":"designRequest","day":"2026-10-01"},{"step":"someNewStep","day":"2026-10-02"}]}}"#
        XCTAssertEqual(StationDocs.Station.decode(json).erc?.events.map(\.step), [.designRequest])
    }
}
