import XCTest
@testable import TCRoofCore

/// CHA-71: a daily report line's finished sub-tasks wait for the team (`wbsPending`), become `daily` ticks when
/// confirmed (one by one, or all of a report on `ลงนามรับทราบ`), and go back to the reporter with a reason.
final class WBSDailyPicksTests: XCTestCase {
    let cal = MasterSchedule.calendar
    func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 12, day: d))! }

    let items: [MasterSchedule.WorkItem] = [
        .init(code: "2.3", title: "ติดตั้งแผง", weight: 20, level: 1),
        .init(code: "2.3.1", title: "    วางแผง", weight: 8),
        .init(code: "2.3.2", title: "    ยึดแคลมป์", weight: 12),
        .init(code: "2.3.3", title: "    ทางเดิน (ไม่เกี่ยวกับสถานีนี้)", weight: 0),
    ]

    func report(_ d: Int, picks: [String], signed: Bool = true, photos: Int = 2) -> (RoutineReport.WBSReport, UUID) {
        var line = RoutineReport.ProgressLine(task: .panels, description: "", location: "หลังคา 1", percent: 50)
        line.wbsDone = picks
        var daily = RoutineReport.Daily(date: day(d))
        daily.progress = [line]
        return (.init(daily: daily, reporter: "ช่างเอ", signed: signed, photos: [line.id: photos]), line.id)
    }

    func testASignedReportsPicksWait() {
        let (r, lineID) = report(7, picks: ["2.3.1", "2.3.2"])
        let p = RoutineReport.wbsPending([r], ticks: [:], items: items)
        XCTAssertEqual(p.map(\.code), ["2.3.1", "2.3.2"])
        XCTAssertEqual(p.first?.day, day(7))
        XCTAssertEqual(p.first?.lineID, lineID)
        XCTAssertEqual(p.first?.photos, 2)
        XCTAssertEqual(p.first?.reporter, "ช่างเอ")
        // a draft's picks don't wait yet
        XCTAssertTrue(RoutineReport.wbsPending([report(7, picks: ["2.3.1"], signed: false).0], ticks: [:]).isEmpty)
        // a ticked row, a heading or another case's row doesn't wait
        let other = report(8, picks: ["2.3", "2.3.3", "2.3.1"]).0
        XCTAssertTrue(RoutineReport.wbsPending([other], ticks: ["2.3.1": .init(by: "t", at: day(1))], items: items).isEmpty)
        // the same code on two days waits once, on its first
        let twice = RoutineReport.wbsPending([report(9, picks: ["2.3.1"]).0, report(7, picks: ["2.3.1"]).0], ticks: [:])
        XCTAssertEqual(twice.map(\.day), [day(7)])
    }

    func testConfirmMakesADailyTickOnTheReportsDayThatBooksThere() {
        let (r, _) = report(7, picks: ["2.3.1"])
        let pick = RoutineReport.wbsPending([r], ticks: [:])[0]
        let t = RoutineReport.confirm(pick, by: "pm@tcroof.test", at: day(10))
        XCTAssertEqual(t.source, .daily)
        XCTAssertEqual(t.by, "pm@tcroof.test")
        XCTAssertEqual(t.at, day(7))
        XCTAssertEqual(t.reportedBy, "ช่างเอ")
        XCTAssertEqual(t.confirmedAt, day(10))
        XCTAssertTrue(RoutineReport.wbsPending([r], ticks: ["2.3.1": t]).isEmpty, "confirmed, it no longer waits")

        var input = MasterSchedule.Input(installStart: day(5), installEnd: day(22), kickoff: day(1), engineeringStart: day(1),
                                         siteHandover: day(2), over200kVA: false)
        input.fixed = ["panels": .init(start: day(5), end: day(22), weight: 20)]
        var a = MasterSchedule.Actual()
        MasterSchedule.bookWBS(&a, items: items, ticks: ["2.3.1": t], input: input)
        XCTAssertEqual(a.points["panels"], [MasterSchedule.Actual.key(day(7)): 8])
    }

    func testAckConfirmsEveryPickOfThatReportOnly() {
        let (r, _) = report(7, picks: ["2.3.1", "2.3.2"])
        let team = MasterSchedule.WBSTick(by: "eng@tcroof.test", at: day(6), source: .team)
        let out = RoutineReport.confirmingAll(r, ticks: ["2.3.2": team], items: items, by: "pm@tcroof.test", at: day(8))
        XCTAssertEqual(out["2.3.1"]?.source, .daily)
        XCTAssertEqual(out["2.3.2"], team, "a row ticked another way stays as it was")
        // a draft acknowledged still confirms its picks
        let draft = report(9, picks: ["2.3.1"], signed: false).0
        XCTAssertEqual(RoutineReport.confirmingAll(draft, ticks: [:], by: "pm", at: day(9))["2.3.1"]?.at, day(9))
    }

    func testSendBackAndPickAgain() {
        var (r, lineID) = report(7, picks: ["2.3.1", "2.3.2"])
        XCTAssertTrue(r.daily.returnWBS("2.3.1", line: lineID, reason: "รูปไม่ชัด"))
        XCTAssertFalse(r.daily.returnWBS("2.3.9", line: lineID, reason: "x"), "not picked")
        XCTAssertEqual(r.daily.progress[0].wbsReturned, ["2.3.1": "รูปไม่ชัด"])
        XCTAssertEqual(RoutineReport.wbsPending([r], ticks: [:]).map(\.code), ["2.3.2"])
        // the reporter picks it again: the reason goes and it waits once more
        r.daily.progress[0].toggleWBSDone("2.3.1")
        XCTAssertNil(r.daily.progress[0].wbsReturned)
        XCTAssertEqual(Set(RoutineReport.wbsPending([r], ticks: [:]).map(\.code)), ["2.3.1", "2.3.2"])
        // and takes a pick back
        r.daily.progress[0].toggleWBSDone("2.3.2")
        r.daily.progress[0].toggleWBSDone("2.3.1")
        XCTAssertNil(r.daily.progress[0].wbsDone)
    }

    /// A line without picks writes as before, an older line reads, and the next day's draft carries no picks.
    func testOlderLinesAndTheNextDay() throws {
        let plain = RoutineReport.ProgressLine(task: .panels, description: "", location: "", percent: 10)
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(json.contains("wbsDone") || json.contains("wbsReturned"))
        let old = try JSONDecoder().decode(RoutineReport.ProgressLine.self,
                                           from: Data(#"{"id":"\#(UUID().uuidString)","description":"","location":"","percent":5}"#.utf8))
        XCTAssertNil(old.wbsDone)
        var (r, lineID) = report(7, picks: ["2.3.1"])
        r.daily.returnWBS("2.3.1", line: lineID, reason: "x")
        let next = RoutineReport.nextDay(from: r.daily, date: day(8), settings: .init())
        XCTAssertEqual(next.progress.count, 1)
        XCTAssertNil(next.progress[0].wbsDone)
        XCTAssertNil(next.progress[0].wbsReturned)
    }
}
