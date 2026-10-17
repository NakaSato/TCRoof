import XCTest
@testable import TCRoofCore

/// Expected values come from the workbook `MP 189 สถานีผลิตน้ำทุ่งน้อย กปภ.สาขาเมืองพล 92.34 kWp.xlsx`
/// (install 22 ก.พ.–8 เม.ย. 2569, 46 days, not over 200 kVA).
final class MasterScheduleTests: XCTestCase {
    private let cal = MasterSchedule.calendar

    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day))!
    }

    private func mp189(over200kVA: Bool = false) -> MasterSchedule.Input {
        MasterSchedule.Input(installStart: d(2026, 2, 22), installEnd: d(2026, 4, 8),
                             kickoff: d(2026, 1, 5), engineeringStart: d(2026, 1, 5), siteHandover: d(2026, 1, 12),
                             over200kVA: over200kVA)
    }

    private func dates(_ plan: [MasterSchedule.PlannedTask], _ task: MasterSchedule.Task) -> (Date?, Date?) {
        let p = plan.first { $0.task == task }!
        return (p.start, p.end)
    }

    /// MP 189's actual weight points, by week start (Sunday), as typed in the workbook.
    private func mp189Actual() -> MasterSchedule.Actual {
        let rows: [(MasterSchedule.Task, [(String, Double)])] = [
            (.kickoff, [("2026-01-04", 0.5)]),
            (.engineering, [("2026-01-04", 0.5), ("2026-01-11", 0.5)]),
            (.siteHandover, [("2026-01-11", 0.5)]),
            (.buildingPermit, [("2026-01-18", 0.25), ("2026-01-25", 1), ("2026-02-01", 0.25)]),
            (.structure, [("2026-03-08", 15), ("2026-03-15", 3), ("2026-03-22", 1), ("2026-08-02", 1)]),
            (.dcSide, [("2026-02-22", 3), ("2026-03-08", 2), ("2026-04-05", 2), ("2026-08-02", 2), ("2026-08-16", 0.5), ("2026-08-23", 0.5)]),
            (.panels, [("2026-03-29", 12.5), ("2026-04-05", 5.5), ("2026-04-12", 1), ("2026-08-02", 0.5), ("2026-08-09", 0.5)]),
            (.fireSwitch, [("2026-02-22", 0.5), ("2026-03-08", 0.5), ("2026-04-12", 1), ("2026-08-23", 0.5)]),
            (.inverter, [("2026-02-15", 3), ("2026-02-22", 3), ("2026-03-08", 2), ("2026-04-12", 3), ("2026-08-02", 2), ("2026-08-16", 2)]),
            (.acSide, [("2026-02-15", 2), ("2026-02-22", 1), ("2026-03-22", 1), ("2026-04-05", 2), ("2026-08-02", 2), ("2026-08-09", 1), ("2026-08-16", 0.5), ("2026-08-23", 0.5)]),
            (.controlCabinet, [("2026-02-22", 2), ("2026-08-02", 1), ("2026-08-09", 1), ("2026-08-16", 0.5), ("2026-08-23", 0.5)]),
            (.zeroExport, [("2026-04-05", 1), ("2026-04-12", 1), ("2026-08-16", 2.5), ("2026-08-23", 0.5)]),
            (.monitoring, [("2026-08-16", 2), ("2026-08-30", 0.5)]),
            (.preCommissioning, [("2026-08-23", 1), ("2026-08-30", 1), ("2026-09-06", 0.5)]),
        ]
        var a = MasterSchedule.Actual()
        for (task, weeks) in rows { a.points[task.rawValue] = Dictionary(uniqueKeysWithValues: weeks) }
        return a
    }

    func testWeightsSumTo100() {
        for big in [false, true] {
            let all = MasterSchedule.Task.allCases.map { $0.weight(over200kVA: big) }.reduce(0, +)
            XCTAssertEqual(all, 100, accuracy: 1e-9)
            let permit = MasterSchedule.Task.allCases.filter { $0.part == .permit }.map { $0.weight(over200kVA: big) }.reduce(0, +)
            XCTAssertEqual(permit, 5, accuracy: 1e-9)
        }
        XCTAssertEqual(MasterSchedule.Task.pk2.weight(over200kVA: false), 0)
        XCTAssertEqual(MasterSchedule.Task.buildingPermit.weight(over200kVA: false), 1.5)
        XCTAssertEqual(MasterSchedule.Task.buildingPermit.weight(over200kVA: true), 1)
    }

    func testPlanDatesMatchWorkbook() {
        let plan = MasterSchedule.plan(mp189())
        let expected: [(MasterSchedule.Task, Date, Date)] = [
            (.kickoff, d(2026, 1, 5), d(2026, 1, 5)),
            (.engineering, d(2026, 1, 5), d(2026, 1, 12)),
            (.siteHandover, d(2026, 1, 12), d(2026, 1, 12)),
            (.buildingPermit, d(2026, 1, 12), d(2026, 2, 2)),
            (.gridConnection, d(2026, 4, 1), d(2026, 4, 8)),
            (.structure, d(2026, 2, 22), d(2026, 3, 22)),
            (.dcSide, d(2026, 3, 8), d(2026, 3, 16)),
            (.panels, d(2026, 3, 23), d(2026, 4, 2)),
            (.fireSwitch, d(2026, 3, 17), d(2026, 3, 23)),
            (.inverter, d(2026, 2, 22), d(2026, 3, 22)),
            (.acSide, d(2026, 3, 17), d(2026, 3, 26)),
            (.controlCabinet, d(2026, 3, 1), d(2026, 3, 17)),
            (.zeroExport, d(2026, 4, 2), d(2026, 4, 4)),
            (.monitoring, d(2026, 4, 4), d(2026, 4, 6)),
            (.preCommissioning, d(2026, 4, 6), d(2026, 4, 7)),
            (.training, d(2026, 4, 7), d(2026, 4, 8)),
        ]
        for (task, start, end) in expected {
            let (s, e) = dates(plan, task)
            XCTAssertEqual(s, start, "\(task) start")
            XCTAssertEqual(e, end, "\(task) end")
        }
        XCTAssertNil(dates(plan, .pk2).0)
        XCTAssertNil(dates(plan, .cop).0)
        XCTAssertEqual(plan.first { $0.task == .structure }?.days(), 29)
    }

    func testPK2WhenOver200kVA() {
        let plan = MasterSchedule.plan(mp189(over200kVA: true))
        XCTAssertEqual(dates(plan, .pk2).0, d(2026, 3, 18))
        XCTAssertEqual(dates(plan, .pk2).1, d(2026, 4, 8))
        XCTAssertEqual(plan.first { $0.task == .pk2 }?.weight, 1)
    }

    func testPlannedPointsSpreadPerWeek() {
        let points = MasterSchedule.plannedPoints(MasterSchedule.plan(mp189()))
        // 2.1 spans the weeks of 22 ก.พ. … 22 มี.ค. (5 weeks): 20 / 5
        let structure = points[.structure]!
        XCTAssertEqual(structure.count, 5)
        XCTAssertTrue(structure.values.allSatisfy { abs($0 - 4) < 1e-9 })
        XCTAssertEqual(structure.keys.min(), d(2026, 2, 22))
    }

    func testCumulativePlanMatchesWorkbook() {
        let plan = MasterSchedule.plan(mp189())
        let a = MasterSchedule.Actual()
        // workbook row 53 (cumulative plan) at week numbers 60, 64, 66, 67
        XCTAssertEqual(MasterSchedule.status(plan: plan, actual: a, through: d(2026, 2, 15)).planned, 3.5, accuracy: 1e-9)
        XCTAssertEqual(MasterSchedule.status(plan: plan, actual: a, through: d(2026, 3, 15)).planned, 52.75, accuracy: 1e-9)
        XCTAssertEqual(MasterSchedule.status(plan: plan, actual: a, through: d(2026, 3, 29)).planned, 93, accuracy: 1e-9)
        XCTAssertEqual(MasterSchedule.status(plan: plan, actual: a, through: d(2026, 4, 8)).planned, 100, accuracy: 1e-9)
    }

    func testWeeklyUpdateMatchesWorkbook() {
        let plan = MasterSchedule.plan(mp189())
        let actual = mp189Actual()
        // workbook row 55 (cumulative actual) at weeks 60, 64, 67, 68 and the Weekly Update at week 92
        let checks: [(Date, Double)] = [(d(2026, 2, 15), 8.5), (d(2026, 3, 15), 40.5), (d(2026, 4, 5), 65.5),
                                        (d(2026, 4, 12), 71.5), (d(2026, 9, 27), 96)]
        for (date, value) in checks {
            XCTAssertEqual(MasterSchedule.status(plan: plan, actual: actual, through: date).actual, value, accuracy: 1e-9, "\(date)")
        }
        let wk92 = MasterSchedule.status(plan: plan, actual: actual, through: d(2026, 9, 30))
        XCTAssertEqual(wk92.planned, 100, accuracy: 1e-9)
        XCTAssertEqual(wk92.variance, -4, accuracy: 1e-9)
        XCTAssertTrue(wk92.isBehind)
        XCTAssertEqual(wk92.actualByPart[.permit] ?? 0, 3.5, accuracy: 1e-9)
        XCTAssertEqual(wk92.actualByPart[.construction] ?? 0, 90, accuracy: 1e-9)
        XCTAssertEqual(wk92.actualByPart[.commissioning] ?? 0, 2.5, accuracy: 1e-9)
        XCTAssertEqual(wk92.actualByTask[.structure] ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(wk92.actualByTask[.training] ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(wk92.actualByTask[.gridConnection] ?? -1, 0, accuracy: 1e-9)
    }

    func testMonthlyUpdate() {
        let plan = MasterSchedule.plan(mp189())
        let m = MasterSchedule.month(plan: plan, actual: mp189Actual(), year: 2026, month: 8)
        // August 2569: construction and commissioning catch-up work
        XCTAssertEqual(m.actual[.construction] ?? 0, 22, accuracy: 1e-9)
        XCTAssertEqual(m.actual[.commissioning] ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(m.planned[.construction] ?? 0, 0, accuracy: 1e-9)
    }

    func testSetPercentCapsAtWeight() {
        var a = MasterSchedule.Actual()
        a.setPercent(60, task: .panels, week: d(2026, 3, 29), over200kVA: false)
        XCTAssertEqual(a.points(.panels, week: d(2026, 3, 29)), 12, accuracy: 1e-9)
        a.setPercent(100, task: .panels, week: d(2026, 4, 5), over200kVA: false)
        XCTAssertEqual(a.points(.panels, week: d(2026, 4, 5)), 8, accuracy: 1e-9)
        a.set(50, task: .panels, week: d(2026, 4, 12), over200kVA: false)
        XCTAssertEqual(a.points(.panels, week: d(2026, 4, 12)), 0, accuracy: 1e-9)
        XCTAssertEqual(a.done(.panels, through: d(2026, 12, 31)), 20, accuracy: 1e-9)
        // a weightless task takes nothing
        a.set(1, task: .pk2, week: d(2026, 4, 5), over200kVA: false)
        XCTAssertNil(a.points[MasterSchedule.Task.pk2.rawValue])
    }

    func testActualDatesAreDaysAndFinishNotBeforeStart() {
        var a = MasterSchedule.Actual()
        a.setDates(.panels, started: d(2026, 3, 30).addingTimeInterval(9 * 3600), finished: d(2026, 3, 28))
        XCTAssertEqual(a.started["panels"], d(2026, 3, 30))
        XCTAssertEqual(a.finished["panels"], d(2026, 3, 30), "a finish before the start moves to it")
        a.setDates(.panels, started: d(2026, 3, 30), finished: nil)
        XCTAssertNil(a.finished["panels"])
        a.setDates(.panels, started: nil, finished: nil)
        XCTAssertTrue(a.started.isEmpty && a.finished.isEmpty)
    }

    /// The install page's Gantt takes the typed finish: a task done 3 days past its plan overruns by 3.
    func testTypedFinishGivesTheGanttsOverrun() throws {
        let plan = MasterSchedule.plan(mp189())
        let (start, end) = dates(plan, .panels)
        let s = try XCTUnwrap(start), e = try XCTUnwrap(end)
        var a = MasterSchedule.Actual()
        a.setPercent(100, task: .panels, week: e, over200kVA: false)
        let late = cal.date(byAdding: .day, value: 3, to: e)!
        a.setDates(.panels, started: s, finished: late.addingTimeInterval(15 * 3600))
        let row = try XCTUnwrap(InstallGantt(plan: plan, actual: a, places: [:], today: d(2026, 6, 1)).rows.first { $0.id == "panels" })
        XCTAssertEqual(row.status, .done)
        XCTAssertEqual(row.actualStart, s)
        XCTAssertEqual(row.actualEnd, late)
        XCTAssertEqual(row.overrunDays, 3)
    }

    func testActualRoundTripsThroughJSON() throws {
        var a = mp189Actual()
        a.started["structure"] = d(2026, 3, 8)
        let data = try JSONEncoder().encode(a)
        XCTAssertEqual(try JSONDecoder().decode(MasterSchedule.Actual.self, from: data), a)
    }

    func testWeekKeyIsSunday() {
        XCTAssertEqual(MasterSchedule.Actual.key(d(2026, 9, 30)), "2026-09-27")
        XCTAssertEqual(MasterSchedule.Actual.key(d(2026, 9, 27)), "2026-09-27")
    }
}

/// The weekly-meeting PDF page (§4): MP 189 at week 92, as the workbook's Weekly Update.
extension MasterScheduleTests {
    func testSheetShowsWeeklyUpdate() {
        let s = MasterScheduleSheet.page(input: mp189(), actual: mp189Actual(), week: d(2026, 9, 30), title: "MP 189 ทุ่งน้อย")
        XCTAssertEqual(s.width, 1190.55); XCTAssertEqual(s.height, 841.89)
        let texts = s.ops.compactMap { op -> String? in
            switch op { case let .text(t, _, _, _, _, _, _), let .textBox(t, _, _, _, _, _): return t; default: return nil }
        }
        XCTAssertTrue(texts.contains("แผนงาน MP · MP 189 ทุ่งน้อย"))
        XCTAssertTrue(texts.contains { $0.hasPrefix("ถึงสัปดาห์ 27/9/69") && $0.contains("แผน 100%") && $0.contains("ทำได้ 96%") && $0.hasSuffix("ช้ากว่า 4%") },
                      texts.filter { $0.hasPrefix("ถึง") }.joined())
        // every task has a row; COP and พค.2 (not over 200 kVA) read ไม่ใช้
        for t in MasterSchedule.Task.allCases { XCTAssertTrue(texts.contains(t.title), t.title) }
        XCTAssertEqual(texts.filter { $0 == "ไม่ใช้" }.count, 2)
        // nothing is drawn off the page
        for op in s.ops {
            if case let .text(_, at, _, _, _, _, _) = op { XCTAssertTrue(at.x >= 0 && at.x <= s.width && at.y >= 0 && at.y <= s.height) }
            if case let .rect(b, _, _, _) = op { XCTAssertTrue(b.x >= 0 && b.maxX <= s.width + 0.01 && b.maxY <= s.height) }
        }
    }

    func testMergingTakesTheOtherCopysProgress() {
        let cal = MasterSchedule.calendar
        let w1 = cal.date(from: DateComponents(year: 2024, month: 10, day: 27))!, w2 = cal.date(from: DateComponents(year: 2024, month: 11, day: 3))!
        var app = MasterSchedule.Actual(), file = MasterSchedule.Actual()
        app.set(4, task: .structure, week: w1, weight: 10)          // the file says 5
        app.set(2, task: .structure, week: w2, weight: 10)          // only the app has it
        app.lateCauses[MasterSchedule.Task.structure.rawValue] = .weather
        file.set(5, task: .structure, week: w1, weight: 10)
        file.set(1, task: .panels, week: w2, weight: 10)            // only the file has it
        file.started[MasterSchedule.Task.structure.rawValue] = w1
        let (merged, changed) = app.merging(file)
        XCTAssertEqual(merged.points(.structure, week: w1), 5)
        XCTAssertEqual(merged.points(.structure, week: w2), 2)
        XCTAssertEqual(merged.points(.panels, week: w2), 1)
        XCTAssertEqual(merged.started[MasterSchedule.Task.structure.rawValue], w1)
        XCTAssertEqual(merged.lateCauses[MasterSchedule.Task.structure.rawValue], .weather)
        XCTAssertEqual(changed, 3)
        XCTAssertEqual(merged.merging(file).changed, 0, "taking the same file again changes nothing")
    }

    /// With the progress the file held when the app wrote it, a booking moved or cleared in Excel moves or goes here too,
    /// and one booked in the app since stays.
    func testMergingWithABaseTakesOnlyWhatTheFileChanged() {
        let cal = MasterSchedule.calendar
        func week(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 11, day: d))! }
        let key = { (d: Int) in MasterSchedule.Actual.key(week(d)) }
        let s = MasterSchedule.Task.structure.rawValue, p = MasterSchedule.Task.panels.rawValue
        var exported = MasterSchedule.Actual()
        exported.set(2, task: .structure, week: week(3), weight: 10)
        exported.set(1, task: .panels, week: week(3), weight: 10)
        exported.started[s] = week(3)
        // since the export: the app books week 17; Excel moves 3 Nov's structure to 10 Nov and clears the panels
        var app = exported
        app.set(3, task: .structure, week: week(17), weight: 10)
        var file = MasterSchedule.Actual()
        file.set(2, task: .structure, week: week(10), weight: 10)
        file.started[s] = week(3)
        let covering = MasterSchedule.Actual.Coverage(tasks: [s, p], weeks: Set([3, 10, 17].map(key)))
        let (merged, changed) = app.merging(file, base: exported, covering: covering)
        XCTAssertEqual(merged.points(.structure, week: week(3)), 0, "moved in Excel")
        XCTAssertEqual(merged.points(.structure, week: week(10)), 2)
        XCTAssertEqual(merged.points(.structure, week: week(17)), 3, "booked in the app since the export")
        XCTAssertEqual(merged.points(.panels, week: week(3)), 0, "cleared in Excel")
        XCTAssertEqual(merged.started[s], week(3))
        XCTAssertEqual(changed, 3)

        // a date cleared in Excel goes; a week the file has no column for is left alone
        var cleared = file
        cleared.started[s] = nil
        let narrow = MasterSchedule.Actual.Coverage(tasks: [s], weeks: [key(10)])
        let (m2, _) = app.merging(cleared, base: exported, covering: narrow)
        XCTAssertNil(m2.started[s])
        XCTAssertEqual(m2.points(.structure, week: week(3)), 2, "not a week the file covers")
        XCTAssertEqual(m2.points(.structure, week: week(10)), 2)
    }

    /// No task ends above its weight: its latest weeks give way.
    func testMergingCapsEachTaskAtItsWeight() {
        let cal = MasterSchedule.calendar
        func week(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 11, day: d))! }
        let s = MasterSchedule.Task.structure.rawValue
        var app = MasterSchedule.Actual(), file = MasterSchedule.Actual()
        app.set(6, task: .structure, week: week(3), weight: 10)
        file.set(4, task: .structure, week: week(10), weight: 10)
        file.set(3, task: .structure, week: week(17), weight: 10)
        let (merged, _) = app.merging(file, weights: [s: 10])
        XCTAssertEqual(merged.points(.structure, week: week(3)), 6)
        XCTAssertEqual(merged.points(.structure, week: week(10)), 4)
        XCTAssertEqual(merged.points(.structure, week: week(17)), 0)
    }
}
