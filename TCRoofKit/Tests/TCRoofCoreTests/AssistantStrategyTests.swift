import XCTest
@testable import TCRoofCore

/// The assistant's planning figures: what-if, priorities, look-ahead, re-plan. Same plan as `AssistantTests`, seen on
/// Monday 16 มี.ค. 2569: 2.1 (20 pts, 1–28 มี.ค.) has 4 done at 4/3 a week, 2.2 (10 pts, ended 28 ก.พ.) has 5, 2.3
/// (20 pts, 1–18 เม.ย.) hasn't started, 2.5 is done; six on site.
final class AssistantStrategyTests: XCTestCase {
    private let cal = MasterSchedule.calendar
    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day))! }
    private var today: Date { d(2026, 3, 16) }

    private func input() -> MasterSchedule.Input {
        var i = MasterSchedule.Input(installStart: d(2026, 2, 1), installEnd: d(2026, 4, 18),
                                     kickoff: d(2026, 1, 5), engineeringStart: d(2026, 1, 5), siteHandover: d(2026, 1, 12),
                                     over200kVA: false)
        i.fixed = [
            "structure": .init(start: d(2026, 3, 1), end: d(2026, 3, 28), weight: 20),
            "dcSide": .init(start: d(2026, 2, 1), end: d(2026, 2, 28), weight: 10),
            "panels": .init(start: d(2026, 4, 1), end: d(2026, 4, 18), weight: 20),
            "inverter": .init(start: d(2026, 3, 1), end: d(2026, 3, 14), weight: 15),
        ]
        return i
    }

    private func day(_ date: Date, crew: Int, rain: Int = 0, problem: String? = nil) -> RoutineReport.Daily {
        var r = RoutineReport.Daily(date: date)
        r.crew = [.init(name: "ช่าง", count: crew)]
        for h in 0..<rain { r.weather[h] = .rain }
        if let problem { r.problems = [.init(description: problem, since: date)] }
        return r
    }

    private func job(contractor: String = "A", canReplan: Bool = false) -> Assistant.Job {
        var a = MasterSchedule.Actual()
        a.points = ["structure": ["2026-03-01": 2, "2026-03-08": 2], "dcSide": ["2026-02-08": 5], "inverter": ["2026-03-08": 15]]
        return Assistant.Job(id: "job-1", station: "สถานีผลิตน้ำทุ่งน้อย", mpNumber: 189, kWp: 92.34, input: input(), actual: a,
                             dailies: [day(d(2026, 3, 14), crew: 6, rain: 2, problem: "รางเคเบิลยังไม่มา")], canEdit: true,
                             canReplan: canReplan, contractor: contractor,
                             inspections: [.init(at: d(2026, 3, 24), subject: "2.1 โครงสร้าง")],
                             deadlines: [.init(date: d(2026, 3, 30), title: "ยื่น อ.1")])
    }

    /// Ahead of its plan: 14 of 20 done in three weeks, 6 left over six weeks.
    private func aheadJob() -> Assistant.Job {
        var i = MasterSchedule.Input(installStart: d(2026, 3, 1), installEnd: d(2026, 4, 25), kickoff: d(2026, 1, 5),
                                     engineeringStart: d(2026, 1, 5), siteHandover: d(2026, 1, 12), over200kVA: false)
        i.fixed = ["structure": .init(start: d(2026, 3, 1), end: d(2026, 4, 25), weight: 20)]
        var a = MasterSchedule.Actual()
        a.points = ["structure": ["2026-03-01": 10, "2026-03-08": 4]]
        return Assistant.Job(id: "job-2", station: "สถานีบางไทร", mpNumber: 190, kWp: 50, input: i, actual: a,
                             dailies: [day(d(2026, 3, 13), crew: 6)], canEdit: true, contractor: "A")
    }

    // MARK: What if

    func testWhatIfAtTodaysPaceMatchesTheBrief() {
        let w = Assistant.Strategy.whatIf(job(), input: input(), today: today)
        XCTAssertEqual(w.crewAverage, 6)
        XCTAssertEqual(w.workingDaysPerWeek, 6)
        XCTAssertEqual(w.base.tasks.first { $0.code == "2.1" }?.finish, "2026-06-06")   // 16 left at 4/3 a week = 84 days
        // 2.3 waits for 2.1: 70 days later, same 18 days
        XCTAssertEqual(w.base.tasks.first { $0.code == "2.3" }?.finish, "2026-06-27")
        XCTAssertEqual(w.base.stationFinish, "2026-06-27")
        XCTAssertEqual(w.base.slipDays, 70)
        XCTAssertEqual(w.base.stationFinish, job().brief(today: today)?.projectedFinish)   // the brief starts from it
        XCTAssertEqual(w.base.tasks.first { $0.code == "2.3" }?.assumedRate, true)
        XCTAssertNil(w.scenario)
    }

    func testWhatIfDoublingTheCrew() throws {
        let w = Assistant.Strategy.whatIf(job(), input: input(), crewChange: 6, today: today)
        let s = try XCTUnwrap(w.scenario)
        XCTAssertEqual(s.paceFactor, 2)
        XCTAssertEqual(s.tasks.first { $0.code == "2.1" }?.finish, "2026-04-25")   // 6 weeks
        // 2.1 ends 28 days late, so 2.3 starts 29 เม.ย. and takes 9 days at twice the pace
        XCTAssertEqual(s.stationFinish, "2026-05-07")
        XCTAssertEqual(s.slipDays, 19)
    }

    func testWhatIfExtraDayAndStartingAhead() throws {
        let w = Assistant.Strategy.whatIf(job(), input: input(), extraDays: 1, startNow: [.panels], today: today)
        let s = try XCTUnwrap(w.scenario)
        XCTAssertEqual(s.paceFactor, 1.2)                        // 7 days over 6, shown rounded
        // 2.3 from today, its 18 days at 7/6 the pace: 16 days
        XCTAssertEqual(s.tasks.first { $0.code == "2.3" }?.finish, "2026-03-31")
        // a sixth more pace is days, not weeks, earlier
        XCTAssertEqual(s.tasks.first { $0.code == "2.1" }?.finish, "2026-05-25")   // 16 at 4/3 × 7/6 a week: 72 days
        XCTAssertTrue(s.name.contains("2.3"))
    }

    func testWhatItTakesToFinishOnTime() throws {
        let r = try XCTUnwrap(Assistant.Strategy.whatIf(job(), input: input(), today: today).toFinishOnTime)
        // 2.1 needs 16 points in 2 weeks at 4/3 a week: 6 times the pace
        XCTAssertEqual(r.paceFactor, 6)
        XCTAssertTrue(r.bottleneck.hasPrefix("2.1"))
        XCTAssertEqual(r.crew, 36)
        XCTAssertNil(r.workingDaysPerWeek)                       // more than 7
    }

    func testWhatIfWithoutCrewSaysSo() throws {
        var j = job(); j.dailies = []
        let w = Assistant.Strategy.whatIf(j, input: input(), crewChange: 4, today: today)
        XCTAssertNil(w.crewAverage)
        XCTAssertEqual(w.scenario?.paceFactor, 1)
        XCTAssertTrue(w.note.contains("ไม่มีจำนวนคน"))
        XCTAssertNil(w.toFinishOnTime?.crew)
    }

    // MARK: Priorities

    func testPrioritiesRankLoadsAndMoves() throws {
        let p = Assistant.Strategy.priorities([aheadJob(), job()], today: today)
        XCTAssertEqual(p.stations.map(\.jobID), ["job-1", "job-2"])
        let behind = try XCTUnwrap(p.stations.first)
        XCTAssertEqual(behind.projectedSlipDays, 70)
        XCTAssertEqual(behind.crewNeeded, 36)
        XCTAssertNil(behind.spareCrew)
        // 2.1 needs 1 a week of its 14/3: about a fifth of its six
        XCTAssertEqual(p.stations[1].spareCrew, 4)
        XCTAssertEqual(p.moves, [.init(crewGroup: "ผู้รับเหมา A", from: "สถานีบางไทร", to: "สถานีผลิตน้ำทุ่งน้อย", crew: 4)])
        let week = try XCTUnwrap(p.loads.first { $0.week == "2026-03-15" })
        XCTAssertEqual(week.crewGroup, "ผู้รับเหมา A")
        XCTAssertEqual(Set(week.stations), ["สถานีผลิตน้ำทุ่งน้อย", "สถานีบางไทร"])
        XCTAssertEqual(week.crewNow, 12)
        XCTAssertTrue(week.overloaded)
    }

    func testGroupsByContractorThenTeam() {
        XCTAssertEqual(job(contractor: "").crewGroup, "ไม่ระบุ")
        var j = job(contractor: ""); j.team = "TCR01"
        XCTAssertEqual(j.crewGroup, "ทีม TCR01")
    }

    // MARK: Look-ahead

    func testLookAheadWeeks() throws {
        let l = Assistant.Strategy.lookAhead(job(), input: input(), today: today)
        XCTAssertEqual(l.weeks.map(\.week), ["2026-03-15", "2026-03-22", "2026-03-29"])
        XCTAssertEqual(l.weeks[0].tasks.map(\.code), ["2.1"])
        XCTAssertEqual(l.weeks[1].inspections, ["2026-03-24 2.1 โครงสร้าง"])
        let panels = try XCTUnwrap(l.weeks[2].tasks.first { $0.code == "2.3" })
        XCTAssertEqual(panels.waitingFor, [.init(code: "2.1", actualPercent: 20)])
        XCTAssertEqual(l.weeks[2].deadlines, ["2026-03-30 ยื่น อ.1"])
        XCTAssertEqual(l.overdue.count, 1)
        XCTAssertTrue(l.overdue[0].hasPrefix("2.2"))
        XCTAssertEqual(l.weather, .init(reportedDays: 1, rainDays: 1, rainHours: 2, stoppedDays: 0))
        XCTAssertEqual(l.openProblems, ["รางเคเบิลยังไม่มา"])
    }

    // MARK: Re-plan

    func testReplanMovesLateTasksAndTheirSuccessors() throws {
        let r = Assistant.Strategy.replan(job(), input: input(), today: today)
        let s = Dictionary(uniqueKeysWithValues: r.tasks.map { ($0.code, $0) })
        XCTAssertEqual(s["2.1"]?.newEnd, "2026-06-06")
        XCTAssertEqual(s["2.1"]?.shiftDays, 70)
        XCTAssertEqual(s["2.1"]?.newStart, "2026-03-01")
        XCTAssertEqual(s["2.3"]?.newStart, "2026-06-10")      // after 2.1, 70 days on, same length
        XCTAssertEqual(s["2.3"]?.newEnd, "2026-06-27")
        XCTAssertEqual(s["2.3"]?.why, "เลื่อนตาม 2.1")
        XCTAssertNil(s["2.5"])                                  // done, stays
        XCTAssertEqual(r.newInstallEnd, "2026-06-27")
        XCTAssertEqual(r.slipDays, 70)
    }

    func testProposeReplanNeedsTheRightAndAppliesToThePlan() throws {
        let args = #"{"job":"189","reason":"โครงสร้างช้า","tasks":[{"task":"2.3","start":"2026-06-10","end":"2026-06-27"}]}"#
        let refused = Assistant.Toolbox(jobs: [job()], today: today).run("propose_replan", arguments: args)
        XCTAssertTrue(refused.text.contains("ไม่มีสิทธิ์"))

        let box = Assistant.Toolbox(jobs: [job(canReplan: true)], today: today, makeID: { "p1" })
        guard case .proposal(let a, let text) = box.run("propose_replan", arguments: args) else { return XCTFail("a proposal") }
        XCTAssertTrue(text.contains("waiting_for_user_confirmation"))
        XCTAssertTrue(a.isReplan)
        XCTAssertEqual(a.before, "วันจบติดตั้ง 2026-04-18")
        XCTAssertTrue(a.after.hasPrefix("วันจบติดตั้ง 2026-06-27"))
        XCTAssertEqual(a.apply(to: job().actual, input: input()), job().actual)   // progress untouched
        let i = try XCTUnwrap(a.replanned(input()))
        let plan = MasterSchedule.plan(i)
        XCTAssertEqual(plan.first { $0.task == .panels }?.start, d(2026, 6, 10))
        XCTAssertEqual(plan.first { $0.task == .panels }?.weight, 20)
        XCTAssertEqual(plan.first { $0.task == .structure }?.end, d(2026, 3, 28))   // the others keep theirs
        XCTAssertEqual(i.installEnd, d(2026, 6, 27))

        XCTAssertTrue(box.run("propose_replan", arguments: #"{"job":"189","tasks":[{"task":"2.3","start":"2026-06-27","end":"2026-06-10"}]}"#)
            .text.contains("ต้องไม่ก่อน"))
        XCTAssertTrue(box.run("propose_replan", arguments: #"{"job":"189","tasks":[{"task":"2.6","start":"2026-06-01","end":"2026-06-10"}]}"#)
            .text.contains("ไม่มีน้ำหนัก"))
    }

    func testAFormulaPlanBecomesFixedOnReplan() throws {
        var i = input(); i.fixed = nil
        let a = Assistant.PendingAction(id: "x", jobID: "job-1", station: "s",
                                        change: .replan(tasks: [.init(task: .panels, start: "2026-05-01", end: "2026-05-20")], reason: ""),
                                        title: "", before: "", after: "")
        let out = try XCTUnwrap(a.replanned(i))
        XCTAssertNotNil(out.fixed)
        let before = MasterSchedule.plan(i), after = MasterSchedule.plan(out)
        for (b, n) in zip(before, after) where b.task != .panels {
            XCTAssertEqual(b.start, n.start, b.task.code); XCTAssertEqual(b.weight, n.weight, b.task.code)
        }
        XCTAssertEqual(after.first { $0.task == .panels }?.end, d(2026, 5, 20))
    }

    func testStrategyToolsAnswerJSON() {
        let box = Assistant.Toolbox(jobs: [job(), aheadJob()], today: today)
        XCTAssertTrue(box.run("what_if", arguments: #"{"job":"189","crew_change":6,"start_now":["2.3"]}"#).text.contains("\"scenario\""))
        XCTAssertTrue(box.run("what_if", arguments: #"{"job":"189","start_now":["9.9"]}"#).text.contains("error"))
        XCTAssertTrue(box.run("station_priorities", arguments: "").text.contains("\"moves\""))
        XCTAssertTrue(box.run("look_ahead", arguments: #"{"job":"บางไทร","weeks":2}"#).text.contains("\"weeks\""))
        XCTAssertTrue(box.run("suggest_replan", arguments: #"{"job":"189"}"#).text.contains("newInstallEnd"))
        XCTAssertEqual(Assistant.Toolbox.definitions.count, Assistant.Toolbox.names.count)
    }
}
