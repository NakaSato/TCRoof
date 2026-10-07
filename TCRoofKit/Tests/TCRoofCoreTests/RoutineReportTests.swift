import XCTest
@testable import TCRoofCore

/// docs/specs/routine-reports-swift.md §3, on a July 2025 (ก.ค. 2568) station like โชคชัย.
final class RoutineReportTests: XCTestCase {
    private let cal = RoutineReport.calendar

    private func d(_ day: Int, _ m: Int = 7, _ y: Int = 2025) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day))!
    }

    private func daily(_ day: Int, crew: [Int] = [1, 1, 7], rain: Int = 0,
                       lines: [(MasterSchedule.Task?, String, Double)] = []) -> RoutineReport.Daily {
        var r = RoutineReport.Daily(date: d(day))
        r.crew = zip(["ผู้ควบคุมงาน", "หัวหน้างาน", "ผู้ปฏิบัติงาน"], crew).map { .init(name: $0, count: $1) }
        r.crewConfirmed = true
        r.tools = [.init(name: "สว่านไฟฟ้า", count: 2), .init(name: "บันได", count: 2)]
        r.weather = RoutineReport.weatherHours.indices.map { $0 < rain ? .rain : .fine }
        r.progress = lines.map { .init(task: $0.0, description: "", location: $0.1, percent: $0.2) }
        return r
    }

    func testTodayIsTheDifferenceFromThePreviousReport() {
        let all = [daily(1, lines: [(.inverter, "ห้องอินเวอร์เตอร์", 10)]),
                   daily(2, lines: [(.inverter, "ห้องอินเวอร์เตอร์", 15)]),
                   daily(4, lines: [(.inverter, "ห้องอินเวอร์เตอร์", 40)])]
        let line = all[2].progress[0]
        XCTAssertEqual(RoutineReport.previousPercent(line, before: d(4), in: all), 15)
        XCTAssertEqual(RoutineReport.todayDelta(line, on: d(4), in: all), 25)
        XCTAssertEqual(RoutineReport.todayDelta(all[0].progress[0], on: d(1), in: all), 10)
    }

    func testLineIdentityIsTaskDescriptionAndLocation() {
        let a = RoutineReport.ProgressLine(task: .structure, description: "", location: "หลังคา 1", percent: 50)
        let b = RoutineReport.ProgressLine(task: .structure, description: "", location: "หลังคา 2", percent: 20)
        let all = [daily(1, lines: [(.structure, "หลังคา 1", 50)])]
        XCTAssertNotEqual(a.key, b.key)
        XCTAssertEqual(RoutineReport.todayDelta(b, on: d(2), in: all), 20)
    }

    func testNextDayCarriesCrewUnconfirmedOpenProblemsAndUnfinishedLines() {
        var y = daily(1, lines: [(.structure, "หลังคา 1", 100), (.structure, "หลังคา 2", 40)])
        y.problems = [.init(description: "ของไม่ครบ", since: d(1)), .init(description: "ฝนตก", closed: true, since: d(1))]
        let t = RoutineReport.nextDay(from: y, date: d(2), settings: .init())
        XCTAssertEqual(t.crew.map(\.count), [1, 1, 7])
        XCTAssertFalse(t.crewConfirmed)
        XCTAssertEqual(t.problems.map(\.description), ["ของไม่ครบ"])
        XCTAssertEqual(t.progress.map(\.location), ["หลังคา 2"])
        XCTAssertEqual(t.blankWeatherHours, 15)
        XCTAssertEqual(cal.startOfDay(for: t.date), d(2))
    }

    func testFirstDayStartsFromTheSettingsLists() {
        let t = RoutineReport.nextDay(from: nil, date: d(1), settings: .init())
        XCTAssertEqual(t.crew.map(\.name), RoutineReport.defaultRoles)
        XCTAssertEqual(t.crewTotal, 0)
    }

    /// The sample month: 21 reports, Mon–Sat, missing 12, 17, 24, 28, 29 and 31 July.
    private func july() -> [RoutineReport.Daily] {
        let missing: Set = [12, 17, 24, 28, 29, 31]
        let days = (1...31).filter { RoutineReport.isWorkingDay(d($0), settings: .init()) && !missing.contains($0) }
        let rain = [5: 4, 9: 6, 14: 3, 19: 5, 22: 2, 26: 5]
        return days.map { daily($0, rain: rain[$0] ?? 0) }
    }

    func testMonthTotalsMatchTheSampleFiles() {
        let all = july()
        XCTAssertEqual(all.count, 21)
        XCTAssertEqual(RoutineReport.manDays(all).reduce(0) { $0 + $1.days }, 189)
        XCTAssertEqual(RoutineReport.manDays(all).map(\.name), ["ผู้ควบคุมงาน", "หัวหน้างาน", "ผู้ปฏิบัติงาน"])
        XCTAssertEqual(RoutineReport.toolDays(all).reduce(0) { $0 + $1.days }, 84)
        XCTAssertEqual(RoutineReport.rainHours(all), 25)
        XCTAssertEqual(RoutineReport.rainDays(all), 6)
        let missing = RoutineReport.missingDays(reported: all.map(\.date), settings: .init(), from: d(1), to: d(31))
        XCTAssertEqual(missing.map { cal.component(.day, from: $0) }, [12, 17, 24, 28, 29, 31])
    }

    func testHolidaysAndWeekdaysFromSettings() {
        var s = RoutineReport.Settings()
        s.holidays = ["2025-07-10"]
        s.workingWeekdays = [2, 3, 4, 5, 6]
        XCTAssertFalse(RoutineReport.isWorkingDay(d(10), settings: s))   // holiday
        XCTAssertFalse(RoutineReport.isWorkingDay(d(12), settings: s))   // Saturday
        XCTAssertTrue(RoutineReport.isWorkingDay(d(11), settings: s))
        XCTAssertEqual(RoutineReport.workingDays(settings: s, from: d(6), to: d(12)).count, 4)
    }

    func testTaskPercentAveragesItsLocations() {
        let all = [daily(1, lines: [(.structure, "หลังคา 1", 100), (.structure, "หลังคา 2", 20)]),
                   daily(2, lines: [(.structure, "หลังคา 2", 60)])]
        XCTAssertEqual(RoutineReport.taskPercent(.structure, reports: all, through: d(1), settings: .init()), 60)
        XCTAssertEqual(RoutineReport.taskPercent(.structure, reports: all, through: d(2), settings: .init()), 80)
        var s = RoutineReport.Settings()
        s.taskLocations = [MasterSchedule.Task.structure.rawValue: ["หลังคา 1", "หลังคา 2", "หลังคา 3", "หลังคา 4"]]
        XCTAssertEqual(RoutineReport.taskPercent(.structure, reports: all, through: d(2), settings: s), 40)
        XCTAssertNil(RoutineReport.taskPercent(.panels, reports: all, through: d(2), settings: s))
    }

    func testFeedBooksEachWeeksPercentIntoTheMP() {
        // weeks of 6 Jul and 13 Jul 2025
        let all = [daily(7, lines: [(.inverter, "ห้องอินเวอร์เตอร์", 20)]),
                   daily(9, lines: [(.inverter, "ห้องอินเวอร์เตอร์", 40)]),
                   daily(15, lines: [(.inverter, "ห้องอินเวอร์เตอร์", 100)])]
        var a = MasterSchedule.Actual()
        RoutineReport.feed(&a, reports: all, settings: .init(), over200kVA: false)
        XCTAssertEqual(a.points(.inverter, week: d(6)), 6, accuracy: 1e-9)          // 40 % of 15
        XCTAssertEqual(a.points(.inverter, week: d(13)), 9, accuracy: 1e-9)
        XCTAssertEqual(a.done(.inverter, through: d(19)), 15, accuracy: 1e-9)
        // an edited old report corrects the plan when fed again
        var edited = all
        edited[1].progress[0].percent = 60
        RoutineReport.feed(&a, reports: edited, settings: .init(), over200kVA: false)
        XCTAssertEqual(a.points(.inverter, week: d(6)), 9, accuracy: 1e-9)
        XCTAssertEqual(a.done(.inverter, through: d(19)), 15, accuracy: 1e-9)
    }

    func testWarningsBeforeSigning() {
        let y = daily(1, lines: [(.structure, "หลังคา 1", 50)])
        var t = RoutineReport.nextDay(from: y, date: d(2), settings: .init())
        t.progress[0].percent = 40
        let w = RoutineReport.warnings(t, previous: [y])
        XCTAssertTrue(w.contains(.weatherBlank(15)))
        XCTAssertTrue(w.contains(.crewUnconfirmed))
        XCTAssertTrue(w.contains(.wentDown(t.progress[0].title)))
        var stop = RoutineReport.Daily(date: d(3))
        XCTAssertTrue(RoutineReport.warnings(stop, previous: []).contains(.noProgress))
        XCTAssertTrue(RoutineReport.warnings(stop, previous: []).contains(.noCrew))
        stop.stopReason = "ฝนตกทั้งวัน"
        XCTAssertFalse(RoutineReport.warnings(stop, previous: []).contains(.noProgress))
        XCTAssertTrue(RoutineReport.warnings(daily(4, lines: [(.panels, "หลังคา 1", 10)]), previous: []).isEmpty)
    }

    func testRequestDraftTakesThisWeeksUnfinishedTasks() {
        let input = MasterSchedule.Input(installStart: d(1), installEnd: d(30, 8), kickoff: d(1, 5), engineeringStart: d(1, 5),
                                         siteHandover: d(1, 6), over200kVA: false)
        let plan = MasterSchedule.plan(input)
        var a = MasterSchedule.Actual()
        a.setPercent(100, task: .inverter, week: d(6), over200kVA: false)
        let r = RoutineReport.requestDraft(weekStart: d(9), plan: plan, actual: a, latest: daily(5), settings: .init())
        XCTAssertEqual(r.weekStart, d(6))
        let tasks = r.work.compactMap(\.task)
        XCTAssertTrue(tasks.contains(.structure))
        XCTAssertFalse(tasks.contains(.inverter))
        XCTAssertFalse(tasks.contains(.training))
        XCTAssertEqual(r.crew.map(\.count), [1, 1, 7])
        XCTAssertEqual(r.status, .draft)
    }

    func testProblemsOpenAndClosedInARange() {
        var a = daily(1), b = daily(2)
        let p = RoutineReport.Problem(description: "ของไม่ครบ", since: d(1))
        a.problems = [p]
        var closed = p; closed.closed = true; closed.solution = "สั่งเพิ่ม"
        b.problems = [closed, .init(description: "ไฟดับ", since: d(2))]
        let r = RoutineReport.problems([a, b])
        XCTAssertEqual(r.open.map(\.description), ["ไฟดับ"])
        XCTAssertEqual(r.closed.map(\.solution), ["สั่งเพิ่ม"])
    }

    func testOldOrPartialJSONDecodes() throws {
        let json = #"{"date": 773020800, "progress": [{"id": "6F9619FF-8B86-D011-B42D-00CF4FC964FF", "description": "เดินสาย", "location": "", "percent": 30}]}"#
        let r = try JSONDecoder().decode(RoutineReport.Daily.self, from: Data(json.utf8))
        XCTAssertEqual(r.weather.count, 15)
        XCTAssertEqual(r.workStart, "08.00")
        XCTAssertEqual(r.progress.first?.percent, 30)
        XCTAssertNil(r.progress.first?.task)
        let s = try JSONDecoder().decode(RoutineReport.Settings.self, from: Data(#"{"locations": ["หลังคา 1"]}"#.utf8))
        XCTAssertEqual(s.workingWeekdays, [2, 3, 4, 5, 6, 7])
        XCTAssertEqual(s.roles, RoutineReport.defaultRoles)
        let round = try JSONDecoder().decode(RoutineReport.Daily.self, from: JSONEncoder().encode(daily(3, rain: 2)))
        XCTAssertEqual(round, daily(3, rain: 2).withIDs(of: round))
    }

    func testFileNamesAndFolders() {
        XCTAssertEqual(RoutineReport.fileName(.daily, date: d(1), station: "สถานีผลิตน้ำ  โชคชัย"),
                       "2568-07-01 รายงานประจำวัน สถานีผลิตน้ำ โชคชัย.pdf")
        XCTAssertEqual(RoutineReport.fileName(.monthly, date: d(31), station: "โชคชัย"),
                       "2568-07 รายงานผลความก้าวหน้าประจำเดือน โชคชัย.pdf")
        XCTAssertEqual(RoutineReport.folder(.daily, date: d(14)), ["2. รายงานประจำวัน", "2568-07 กรกฎาคม"])
        XCTAssertEqual(RoutineReport.thaiDate(d(1)), "1 ก.ค. 2568")
        XCTAssertEqual(RoutineReport.photoFolder(date: d(1)), ["5. ภาพถ่ายประจำวัน", "2568-07 กรกฎาคม", "2568-07-01"])
        let line = RoutineReport.ProgressLine(task: .structure, description: "", location: "หลังคา 1/2")
        XCTAssertEqual(RoutineReport.photoName(date: d(1), index: 3, line: line), "2568-07-01 03 หลังคา 1-2.jpg")
        XCTAssertEqual(RoutineReport.photoName(date: d(1), index: 12, line: nil), "2568-07-01 12.jpg")
    }

    func testWeatherTapCycle() {
        XCTAssertEqual(RoutineReport.Weather.next(nil), .fine)
        XCTAssertEqual(RoutineReport.Weather.next(.fine), .cloudy)
        XCTAssertEqual(RoutineReport.Weather.next(.cloudy), .rain)
        XCTAssertNil(RoutineReport.Weather.next(.rain))
    }
}

private extension RoutineReport.Daily {
    /// The same report with the line ids of `other`, since a fresh `daily()` makes new ids.
    func withIDs(of other: Self) -> Self {
        var r = self
        for i in r.crew.indices { r.crew[i].id = other.crew[i].id }
        for i in r.tools.indices { r.tools[i].id = other.tools[i].id }
        return r
    }
}
