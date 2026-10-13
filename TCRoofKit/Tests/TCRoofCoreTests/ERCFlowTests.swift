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
