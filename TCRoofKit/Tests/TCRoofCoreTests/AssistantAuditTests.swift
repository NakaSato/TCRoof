import XCTest
@testable import TCRoofCore

/// What a confirmed assistant card leaves behind: the plan before the first re-plan (`Input.baseline`) and who confirmed
/// each change (`Actual.confirmations`). Same plan as `AssistantStrategyTests`.
final class AssistantAuditTests: XCTestCase {
    private let cal = MasterSchedule.calendar
    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day))! }

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

    private func replan(_ task: MasterSchedule.Task, _ start: String, _ end: String) -> Assistant.PendingAction {
        .init(id: "r", jobID: "job-1", station: "s", change: .replan(tasks: [.init(task: task, start: start, end: end)], reason: "ช้า"),
              title: "ปรับแผน", before: "วันจบติดตั้ง 2026-04-18", after: "วันจบติดตั้ง 2026-06-27")
    }

    func testTheFirstReplanKeepsTheOriginalPlan() throws {
        let first = try XCTUnwrap(replan(.panels, "2026-06-10", "2026-06-27").replanned(input()))
        XCTAssertEqual(first.baseline, input().fixed)
        let original = try XCTUnwrap(first.original)
        XCTAssertEqual(MasterSchedule.plan(original), MasterSchedule.plan(input()))
        XCTAssertNil(original.baseline)

        // a second re-plan keeps the first plan, not the one it replaces
        let second = try XCTUnwrap(replan(.structure, "2026-03-01", "2026-04-30").replanned(first))
        XCTAssertEqual(second.baseline, input().fixed)
        XCTAssertEqual(MasterSchedule.plan(second).first { $0.task == .panels }?.start, d(2026, 6, 10))
        XCTAssertEqual(MasterSchedule.plan(second).first { $0.task == .structure }?.end, d(2026, 4, 30))
    }

    func testAFormulaPlansOriginalIsItsWorkedOutDates() throws {
        var i = input(); i.fixed = nil
        let out = try XCTUnwrap(replan(.panels, "2026-05-01", "2026-05-20").replanned(i))
        XCTAssertEqual(MasterSchedule.plan(try XCTUnwrap(out.original)), MasterSchedule.plan(i))
        XCTAssertNil(i.original)
    }

    func testAConfirmedCardNamesWhoConfirmedIt() {
        let at = d(2026, 3, 16)
        let card = Assistant.PendingAction(id: "p", jobID: "job-1", station: "s", change: .progress(task: .structure, week: "2026-03-15", percent: 60),
                                           title: "2.1", before: "40%", after: "60%")
        var a = card.apply(to: .init(), input: input())
        a.confirmations.append(card.confirmation(by: "somchai@tcroof.co.th", at: at))
        let c = a.lastConfirmation(.structure)
        XCTAssertEqual(c?.by, "somchai@tcroof.co.th")
        XCTAssertEqual(c?.after, "60%")
        XCTAssertEqual(c?.at, at)
        XCTAssertEqual(c?.replan, false)
        XCTAssertNil(a.lastConfirmation(.panels))
        XCTAssertEqual(replan(.panels, "2026-06-10", "2026-06-27").confirmation(by: "x@y").replan, true)
    }

    func testOldPlansStillLoadAndUnconfirmedOnesEncodeAsBefore() throws {
        let old = #"{"points":{"structure":{"2026-03-01":2}},"started":{},"finished":{},"lateCauses":{}}"#
        let a = try JSONDecoder().decode(MasterSchedule.Actual.self, from: Data(old.utf8))
        XCTAssertTrue(a.confirmations.isEmpty)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(a), as: UTF8.self).contains("confirmations"))

        var b = a
        b.confirmations = [.init(task: "structure", by: "a@b", at: d(2026, 3, 16), before: "40%", after: "60%")]
        XCTAssertEqual(try JSONDecoder().decode(MasterSchedule.Actual.self, from: JSONEncoder().encode(b)), b)

        let oldInput = try JSONEncoder().encode(input())
        XCTAssertNil(try JSONDecoder().decode(MasterSchedule.Input.self, from: oldInput).baseline)
    }

    func testTheMeetingPageAndTheBriefShowTheOriginalPlan() throws {
        let i = try XCTUnwrap(replan(.panels, "2026-06-10", "2026-06-27").replanned(input()))
        let texts = { (input: MasterSchedule.Input) in
            MasterScheduleSheet.page(input: input, actual: .init(), week: self.d(2026, 3, 16), title: "MP 189").ops.compactMap { op -> String? in
                if case let .text(s, _, _, _, _, _, _) = op { return s }
                return nil
            }
        }
        XCTAssertTrue(texts(i).contains { $0.contains("แผนเดิม") })
        XCTAssertFalse(texts(input()).contains { $0.contains("แผนเดิม") })

        let brief = ScheduleBrief(jobID: "job-1", station: "s", input: i, actual: .init(), today: d(2026, 3, 16))
        XCTAssertEqual(brief.originalInstallEnd, "2026-04-18")
        XCTAssertNotNil(brief.originalPlannedPercent)
        XCTAssertNil(ScheduleBrief(jobID: "job-1", station: "s", input: input(), actual: .init(), today: d(2026, 3, 16)).originalInstallEnd)
    }

    /// `floatDays` come from the plan's WBS links when it has them (CHA-77), else from the dates.
    func testTheBriefsFloatFollowsTheLinks() throws {
        func line(_ code: String, _ a: Date, _ b: Date, after links: [MasterSchedule.WBSDependency] = []) -> MasterSchedule.WorkItem {
            var item = MasterSchedule.WorkItem(code: code, title: code, level: 1)
            item.baselineStart = a; item.baselineEnd = b
            item.dependencies = links.isEmpty ? nil : links
            return item
        }
        let today = d(2026, 1, 20)
        let dated = ScheduleBrief(jobID: "job-1", station: "s", input: input(), actual: .init(), today: today)
        XCTAssertNil(dated.floatFromLinks)
        let wbs = [line("2.1", d(2026, 3, 1), d(2026, 3, 28)),
                   line("2.3", d(2026, 4, 1), d(2026, 4, 18), after: [.init(predecessor: "2.1", lagDays: 3, type: .startToStart)])]
        let linked = ScheduleBrief(jobID: "job-1", station: "s", input: input(), actual: .init(), today: today, wbs: wbs)
        XCTAssertEqual(linked.floatFromLinks, true)
        func float(_ b: ScheduleBrief, _ code: String) -> Int? { b.tasks.first { $0.code == code }?.floatDays }
        XCTAssertEqual(float(linked, "2.3"), 0)
        XCTAssertNotEqual(float(linked, "2.1"), float(dated, "2.1"), "SS+3 leaves the structure weeks of float, not the days to panels")
        XCTAssertEqual(float(linked, "2.2"), float(dated, "2.2"), "a task without WBS rows keeps the dates' float")
    }
}
