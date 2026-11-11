import XCTest
@testable import TCRoofCore

final class StakeholdersTests: XCTestCase {
    private let cal = MasterSchedule.calendar

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testCadenceReadsTheSheetsWords() {
        func cadence(_ f: String, _ d: String) -> Stakeholder.Cadence { Stakeholder(id: "S", name: "", frequency: f, due: d).cadence }
        XCTAssertEqual(cadence("รายสัปดาห์", "ศุกร์"), .weekly(weekday: 6))
        XCTAssertEqual(cadence("รายสัปดาห์", "วันพฤหัสบดี"), .weekly(weekday: 5))
        XCTAssertEqual(cadence("รายสัปดาห์", "พฤ."), .weekly(weekday: 5))
        XCTAssertEqual(cadence("รายสัปดาห์", "จ."), .weekly(weekday: 2))
        XCTAssertEqual(cadence("รายสัปดาห์", ""), .weekly(weekday: 6), "Friday when no day is given")
        XCTAssertEqual(cadence("รายเดือน", "25"), .monthly(day: 25))
        XCTAssertEqual(cadence("รายเดือน", "สิ้นเดือน"), .monthly(day: nil))
        XCTAssertEqual(cadence("รายเดือน", ""), .monthly(day: nil))
        XCTAssertEqual(cadence("รายเดือน", "40"), .monthly(day: 31))
        XCTAssertEqual(cadence("ก่อนส่งมอบ", "3 วัน"), .beforeHandover(days: 3))
        XCTAssertEqual(cadence("เมื่อส่งมอบ", ""), .beforeHandover(days: 0))
        XCTAssertEqual(cadence("ตามเหตุการณ์", "ศุกร์"), .asNeeded)
        XCTAssertEqual(cadence("", ""), .asNeeded)
    }

    func testDecodesTheSheetsJSONSkippingARowWithoutAnId() {
        let json = """
        {"stakeholders":[{"id":"S01","name":"ผอ.กองแผนงาน","organisation":"กปภ. เขต 5","reports":"R3","frequency":"รายสัปดาห์","due":"ศุกร์"},
        {"name":"no id"},{"id":"S02","jobs":["job-1"]}]}
        """
        let list = StakeholderList.decode(json)
        XCTAssertEqual(list?.stakeholders.map(\.id), ["S01", "S02"])
        XCTAssertEqual(list?.stakeholders.first?.label, "ผอ.กองแผนงาน (กปภ. เขต 5)")
        XCTAssertEqual(list?.stakeholders.last?.jobs, ["job-1"])
        XCTAssertEqual(list?.stakeholders.last?.reportTitle, "รายงาน")
        XCTAssertNil(StakeholderList.decode("not json"))
    }

    func testDuesOfTwoWeeks() {
        let list = StakeholderList(stakeholders: [
            Stakeholder(id: "S01", name: "กปภ. เขต 5", reports: "R3", frequency: "รายสัปดาห์", due: "ศุกร์"),
            Stakeholder(id: "S02", name: "ผอ.", reports: "R4", frequency: "รายเดือน", due: "สิ้นเดือน"),
            Stakeholder(id: "S03", name: "หัวหน้าสถานี", reports: "เอกสารส่งมอบ", frequency: "ก่อนส่งมอบ", due: "3", jobs: ["j1"]),
            Stakeholder(id: "S04", name: "สื่อ", frequency: "ตามเหตุการณ์")
        ])
        let stations = [StakeholderList.Station(id: "j1", label: "MP 1 ก", handover: day(2026, 11, 20)),
                        StakeholderList.Station(id: "j2", label: "MP 2 ข", handover: day(2026, 11, 20))]
        // Wednesday 11 November 2026, 14 days: to Tuesday the 24th
        let dues = list.dues(stations: stations, from: day(2026, 11, 11).addingTimeInterval(9 * 3600), calendar: cal)
        XCTAssertEqual(dues.map(\.id), ["comm-S01-2026-11-13", "comm-S03-2026-11-17-j1", "comm-S01-2026-11-20"],
                       "two Fridays, the 30th is past the range, the handover row only for j1")
        XCTAssertEqual(dues[1].station, "MP 1 ก")
        XCTAssertEqual(dues[0].title, "ส่ง R3 ให้ กปภ. เขต 5")

        let november = list.dues(stations: [], from: day(2026, 11, 25), days: 7, calendar: cal)
        XCTAssertEqual(november.map(\.id), ["comm-S01-2026-11-27", "comm-S02-2026-11-30"])
        let february = StakeholderList(stakeholders: [Stakeholder(id: "M", name: "", frequency: "รายเดือน", due: "30")])
            .dues(stations: [], from: day(2027, 2, 20), days: 10, calendar: cal)
        XCTAssertEqual(february.map(\.id), ["comm-M-2027-02-28"], "a day past the month's end is its last day")
    }

    func testRemindedAtEightTheDayBefore() {
        let list = StakeholderList(stakeholders: [
            Stakeholder(id: "S01", name: "กปภ.", reports: "R3", channel: "อีเมล", frequency: "รายสัปดาห์", due: "ศุกร์", owner: "PM")
        ])
        let now = day(2026, 11, 12).addingTimeInterval(7 * 3600)  // Thursday 07:00
        let plans = StakeholderNotification.plans(list.dues(stations: [], from: now, calendar: cal), now: now, calendar: cal)
        XCTAssertEqual(plans.map(\.id), ["comm-S01-2026-11-13", "comm-S01-2026-11-20"])
        XCTAssertEqual(plans.first?.title, "พรุ่งนี้ส่ง R3 ให้ กปภ.")
        XCTAssertEqual(plans.first?.sub, "ทาง อีเมล | ผู้ส่ง PM")
        if case .at(let at)? = plans.first?.fire { XCTAssertEqual(at, day(2026, 11, 12).addingTimeInterval(8 * 3600)) } else { XCTFail() }
        let later = StakeholderNotification.plans(list.dues(stations: [], from: now, calendar: cal),
                                                  now: now.addingTimeInterval(2 * 3600), calendar: cal)
        XCTAssertEqual(later.map(\.id), ["comm-S01-2026-11-20"], "this week's eve has passed")
    }

    func testPlanPageRowsMergeByDate() {
        let s = Stakeholder(id: "S01", name: "กปภ.", reports: "R3", channel: "อีเมล", frequency: "รายสัปดาห์", due: "ศุกร์")
        let dues = StakeholderList(stakeholders: [s]).dues(stations: [], from: day(2026, 11, 13), days: 8, calendar: cal)
        let rows = PWAPlan.stakeholderDeadlines(dues, today: day(2026, 11, 13), calendar: cal)
        XCTAssertEqual(rows.map(\.chip), ["วันนี้", "รายสัปดาห์"])
        XCTAssertEqual(rows.map(\.tone), [.risk, .ok])
        XCTAssertEqual(rows.first?.kind, .report)
        XCTAssertEqual(rows.first?.station, "", "a programme report opens nothing")

        let hand = PWAPlan.Deadline(id: "hand-x", date: day(2026, 11, 13), kind: .handover, title: "ส่งมอบงาน", subtitle: "",
                                    chip: "", tone: .ok)
        let early = PWAPlan.Deadline(id: "doc-x", date: day(2026, 11, 12), kind: .document, title: "", subtitle: "", chip: "", tone: .ok)
        XCTAssertEqual(PWAPlan.merged([early, hand], rows).map(\.id), ["doc-x", "hand-x", rows[0].id, rows[1].id])
    }
}
