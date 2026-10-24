import XCTest
@testable import TCRoofCore

/// The weekly request's days and sums (docs/ui/install-tracking-ipad-weekly-request §5 item 2).
final class WeeklyRequestDaysTests: XCTestCase {
    let cal = RoutineReport.calendar
    /// July 2025: the 6th is a Sunday, so the week of the 6th runs Monday 7 … Saturday 12.
    func d(_ day: Int, _ m: Int = 7) -> Date { cal.date(from: DateComponents(year: 2025, month: m, day: day))! }

    func testOlderJSONDecodesWithoutDaysOrRolesOff() throws {
        let json = #"{"weekStart":0,"crew":[{"id":"\#(UUID())","name":"ช่างไฟฟ้า","count":2}],"tools":[],"risks":[],"approvedBy":"","sentBy":"","#
            + #""work":[{"id":"\#(UUID())","task":"structure","description":"โครงสร้าง","location":"หลังคา 1","qty":0,"unit":""}]}"#
        let r = try JSONDecoder().decode(RoutineReport.WeeklyRequest.self, from: Data(json.utf8))
        XCTAssertEqual(r.crewOff, [])
        XCTAssertEqual(r.work.first?.days, [])
        XCTAssertEqual(r.work.first?.task, .structure)
        // nothing new is written while they are empty
        let out = String(decoding: try JSONEncoder().encode(r), as: UTF8.self)
        XCTAssertFalse(out.contains("crewOff"))
        XCTAssertFalse(out.contains("\"days\""))
        // a line missing its newer keys still loads
        let bare = try JSONDecoder().decode(RoutineReport.PlanLine.self, from: Data(#"{"description":"งานอื่น"}"#.utf8))
        XCTAssertNil(bare.task)
        XCTAssertEqual(bare.description, "งานอื่น")
    }

    func testTheDraftFillsDaysAndCarriesOverLateWork() throws {
        var s = RoutineReport.Settings()
        s.workingWeekdays = [2, 3, 4, 5, 6, 7]
        let input = MasterSchedule.Input(installStart: d(1), installEnd: d(30, 8), kickoff: d(1, 5), engineeringStart: d(1, 5),
                                         siteHandover: d(1, 6), over200kVA: false)
        let plan = MasterSchedule.plan(input)
        let r = RoutineReport.requestDraft(weekStart: d(9), plan: plan, actual: MasterSchedule.Actual(), latest: nil, settings: s)
        XCTAssertEqual(r.weekStart, d(6))
        for line in r.work {
            let p = try XCTUnwrap(plan.first { $0.task == line.task })
            let (start, end) = (try XCTUnwrap(p.start), try XCTUnwrap(p.end))
            if end < r.weekStart {
                XCTAssertEqual(line.days, [0], "\(line.description) carries over from Monday")
                XCTAssertGreaterThanOrEqual(end, RoutineReport.add(r.weekStart, -7))
                XCTAssertNotEqual(line.task?.part, .permit)
            } else {
                XCTAssertEqual(line.days, r.days(from: start, to: end, settings: s), line.description)
            }
        }
        XCTAssertFalse(r.work.isEmpty)
    }

    func testPeopleAndManDaysHonourRolesOff() {
        var r = RoutineReport.WeeklyRequest(weekStart: d(6))
        r.crew = [.init(name: "หัวหน้างาน", count: 1), .init(name: "ช่างไฟฟ้า", count: 3)]
        r.work = [.init(task: .structure, description: "โครงสร้าง", days: [0, 1, 2]), .init(task: nil, description: "อื่น", days: [2])]
        let days = [0, 1, 2, 3, 4, 5]
        XCTAssertEqual(r.lines(on: 2), 2)
        XCTAssertEqual(r.lines(on: 3), 0)
        XCTAssertNil(r.people(role: 1, day: 3), "no work that day")
        XCTAssertEqual(r.people(on: 0), 4)
        XCTAssertEqual(r.manDays(days: days), 12)
        r.toggleOff(role: 1, day: 1)
        XCTAssertEqual(r.people(role: 1, day: 1), 0)
        XCTAssertEqual(r.people(on: 1), 1)
        XCTAssertEqual(r.manDays(role: 1, days: days), 6)
        XCTAssertEqual(r.manDays(days: days), 9)
        r.toggleOff(role: 1, day: 1)
        XCTAssertEqual(r.manDays(days: days), 12)
        r.toggleDay(line: r.work[1].id, day: 4)
        XCTAssertEqual(r.work[1].days, [2, 4])
        XCTAssertEqual(r.manDays(days: days), 16)
        // taking a role out moves the later roles' days off
        r.toggleOff(role: 1, day: 0)
        r.removeCrew(at: 0)
        XCTAssertEqual(r.crewOff, ["0-0"])
        XCTAssertEqual(r.perDay, 3)
    }

    func testRefreshKeepsTheLinesOutsideThePlan() {
        var r = RoutineReport.WeeklyRequest(weekStart: d(6))
        r.work = [.init(task: .structure, description: "เก่า"), .init(task: nil, description: "นอกแผน")]
        var draft = r
        draft.work = [.init(task: .panels, description: "แผง", days: [1])]
        XCTAssertEqual(r.refreshed(from: draft).work.map(\.description), ["แผง", "นอกแผน"])
    }

    func testDeadlineIsTheFridayBefore() {
        let due = RoutineReport.requestDeadline(d(9))
        XCTAssertEqual(cal.component(.weekday, from: due), 6)
        XCTAssertEqual(cal.component(.hour, from: due), 15)
        XCTAssertTrue(cal.isDate(due, inSameDayAs: d(4)))
    }
}
