import XCTest
@testable import TCRoofCore

/// The crew each contractor said it has, set against its stations' demand (CHA-78). Seen on Monday 16 มี.ค. 2569 (the
/// plan's weeks start on Sunday): each station has 2.5 (20 pts) planned 23–28 มี.ค., then 2.1 from 27 เม.ย. to the
/// install end, so 2.5 has 29 working days of float; four people on site, two needed each.
final class CrewSupplyTests: XCTestCase {
    private let cal = MasterSchedule.calendar
    private let group = "ผู้รับเหมา A"
    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day))! }
    private var today: Date { d(2026, 3, 16) }

    private func station(_ id: String, contractor: String = "A", inverterEnd: Date? = nil) -> Assistant.Job {
        var i = MasterSchedule.Input(installStart: d(2026, 3, 1), installEnd: d(2026, 5, 30), kickoff: d(2026, 1, 5),
                                     engineeringStart: d(2026, 1, 5), siteHandover: d(2026, 1, 12), over200kVA: false)
        i.fixed = ["inverter": .init(start: d(2026, 3, 23), end: inverterEnd ?? d(2026, 3, 28), weight: 20),
                   "structure": .init(start: d(2026, 4, 27), end: d(2026, 5, 30), weight: 80)]
        var r = RoutineReport.Daily(date: d(2026, 3, 14))
        r.crew = [.init(name: "ช่าง", count: 4)]
        return Assistant.Job(id: id, station: "สถานี \(id)", kWp: 100, input: i, dailies: [r], canEdit: true, contractor: contractor)
    }

    private func supply(_ crew: Int) -> CrewSupply {
        var s = CrewSupply(); s.set(usual: crew, group: group); return s
    }

    func testTwoStationsOfOneContractorInOneWeekAreOneOverload() throws {
        let p = Assistant.Strategy.priorities([station("1"), station("2")], supply: supply(3), today: today)
        let over = p.loads.filter { $0.overSupply == true }
        XCTAssertEqual(over.count, 1)
        let w = try XCTUnwrap(over.first)
        XCTAssertEqual(w.week, "2026-03-22")
        XCTAssertEqual(w.crewNeeded, 4)
        XCTAssertEqual(w.crewSupply, 3)
        XCTAssertEqual(w.stations.sorted(), ["สถานี 1", "สถานี 2"])
    }

    func testEnoughPeopleIsNoOverload() {
        let p = Assistant.Strategy.priorities([station("1"), station("2")], supply: supply(4), today: today)
        XCTAssertEqual(p.loads.map(\.overSupply), [false])
        XCTAssertTrue(p.leveling.isEmpty)
    }

    func testWithoutASupplyNothingIsSaidOfIt() {
        let p = Assistant.Strategy.priorities([station("1"), station("2")], today: today)
        XCTAssertEqual(p.loads.map(\.crewSupply), [nil])
        XCTAssertEqual(p.loads.map(\.overSupply), [nil])
        XCTAssertTrue(p.leveling.isEmpty)
    }

    func testOtherContractorsDontShareTheSupply() {
        let p = Assistant.Strategy.priorities([station("1"), station("2", contractor: "B")], supply: supply(2), today: today)
        XCTAssertEqual(p.loads.filter { $0.crewGroup == group }.map(\.overSupply), [false])
        XCTAssertEqual(p.loads.filter { $0.crewGroup == "ผู้รับเหมา B" }.map(\.overSupply), [nil])
    }

    func testLevelingMovesOneStationsTaskInsideItsFloat() throws {
        let p = Assistant.Strategy.priorities([station("1"), station("2")], supply: supply(3), today: today)
        XCTAssertEqual(p.leveling.count, 1)
        let l = try XCTUnwrap(p.leveling.first)
        XCTAssertEqual(l.crewGroup, group)
        XCTAssertEqual(l.week, "2026-03-22")
        XCTAssertEqual(l.jobID, "1")
        XCTAssertEqual(l.crew, 2)
        let t = try XCTUnwrap(l.tasks.first)
        XCTAssertEqual(l.tasks.count, 1)
        XCTAssertEqual(t.code, "2.5")
        XCTAssertEqual([t.plannedStart, t.plannedEnd, t.newStart, t.newEnd], ["2026-03-23", "2026-03-28", "2026-03-29", "2026-04-03"])
        XCTAssertEqual(t.shiftDays, 6)
    }

    func testAMoveOutsideFloatIsNeverProposed() {
        // 2.5 runs to 25 เม.ย., a day of float before 2.1: a week's move is more than that
        let p = Assistant.Strategy.priorities([station("1", inverterEnd: d(2026, 4, 25)), station("2", inverterEnd: d(2026, 4, 25))],
                                              supply: supply(3), today: today)
        XCTAssertTrue(p.loads.contains { $0.overSupply == true })
        XCTAssertTrue(p.leveling.isEmpty)
    }

    func testAMoveIntoAWeekWithoutPeopleIsNotProposed() {
        var s = supply(3)
        s.set(0, group: group, week: d(2026, 3, 29))
        let p = Assistant.Strategy.priorities([station("1"), station("2")], supply: s, today: today)
        XCTAssertTrue(p.leveling.isEmpty)
    }

    func testTheLevelingDatesAreAcceptedByProposeReplan() throws {
        var a = station("1"); a.canReplan = true
        let box = Assistant.Toolbox(jobs: [a, station("2")], today: today, crewSupply: supply(3))
        let json = box.run("station_priorities", arguments: "").text
        XCTAssertTrue(json.contains("\"leveling\":[{"))
        let out = box.run("propose_replan", arguments: #"{"job":"1","reason":"คนไม่พอ","tasks":[{"task":"2.5","start":"2026-03-29","end":"2026-04-03"}]}"#)
        guard case .proposal(let action, _) = out else { return XCTFail(out.text) }
        let input = try XCTUnwrap(a.input)
        let plan = MasterSchedule.plan(try XCTUnwrap(action.replanned(input)))
        XCTAssertEqual(plan.first { $0.task == .inverter }?.start, d(2026, 3, 29))
        XCTAssertEqual(MasterSchedule.plan(try XCTUnwrap(action.replanned(input))).compactMap(\.end).max(), d(2026, 5, 30), "handover stays")
    }

    // MARK: the supply

    func testAWeekOfItsOwnAndBackToTheUsual() {
        var s = supply(5)
        XCTAssertEqual(s.crew(group, week: d(2026, 3, 25)), 5)
        s.set(8, group: group, week: d(2026, 3, 25))
        XCTAssertEqual(s.crew(group, week: d(2026, 3, 22)), 8)
        XCTAssertEqual(s.crew(group, week: d(2026, 3, 29)), 5)
        s.set(5, group: group, week: d(2026, 3, 25))
        XCTAssertEqual(s.groups[group]?.weeks, [:])
        XCTAssertNil(s.crew("ทีม X", week: today))
        s.set(usual: 0, group: group)
        XCTAssertTrue(s.groups.isEmpty)
    }

    func testJSONRoundTripAndOldFields() throws {
        var s = supply(6); s.set(2, group: group, week: today); s.revision = 3; s.savedBy = "a@b.c"
        s.savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(CrewSupply.decode(s.json), s)
        XCTAssertEqual(CrewSupply.decode(#"{"groups":{"ทีม X":{}}}"#)?.groups["ทีม X"], .init(crew: 0))
    }

    func testTheStoreKeepsTheHigherRevision() {
        let store = CrewSupply.Store()
        var sent: [Int] = []
        store.onChange = { sent.append($0.revision) }
        XCTAssertEqual(store.save(supply(4), by: "a@b.c")?.revision, 1)
        var older = supply(9); older.revision = 1; older.savedAt = .distantPast
        XCTAssertFalse(store.receive(older))
        var newer = supply(9); newer.revision = 2
        XCTAssertTrue(store.receive(newer))
        XCTAssertEqual(store.current?.groups[group]?.crew, 9)
        XCTAssertEqual(sent, [1], "a received supply is not sent back")
        XCTAssertNil(store.save(supply(2000), by: nil))
    }
}
