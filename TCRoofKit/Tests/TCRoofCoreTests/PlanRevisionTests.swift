import XCTest
@testable import TCRoofCore

/// The MP plan's revisions (CHA-79): each confirmed re-plan keeps the plan it approved as the next REV with who
/// approved it, when, why and its change request; REV 00 is the plan before the first, and the baseline stays.
final class PlanRevisionTests: XCTestCase {
    private let cal = MasterSchedule.calendar
    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day))! }

    private func input() -> MasterSchedule.Input {
        var i = MasterSchedule.Input(installStart: d(2026, 2, 1), installEnd: d(2026, 4, 18),
                                     kickoff: d(2026, 1, 5), engineeringStart: d(2026, 1, 5), siteHandover: d(2026, 1, 12),
                                     over200kVA: false)
        i.fixed = [
            "structure": .init(start: d(2026, 3, 1), end: d(2026, 3, 28), weight: 20),
            "panels": .init(start: d(2026, 4, 1), end: d(2026, 4, 18), weight: 20),
        ]
        return i
    }

    private func replan(_ task: MasterSchedule.Task, _ start: String, _ end: String, reason: String = "โครงสร้างช้า",
                        cr: String? = nil) -> Assistant.PendingAction {
        Assistant.PendingAction(id: "p", jobID: "job-1", station: "s", change: .replan(tasks: [.init(task: task, start: start, end: end)], reason: reason),
                                title: "", before: "", after: "", changeRequest: cr)
    }

    func testTheFirstReplanKeepsREV00AndRecordsREV01() throws {
        let before = input()
        let i = try XCTUnwrap(replan(.panels, "2026-05-01", "2026-05-20", cr: " CR-014 ").revised(before, by: "pm@tc.co", at: d(2026, 3, 16)))
        let revs = try XCTUnwrap(i.revisions)
        XCTAssertEqual(revs.map(\.number), [0, 1])
        XCTAssertEqual(revs[0].tasks, before.fixed, "REV 00 is the plan before")
        XCTAssertNil(revs[0].by)
        XCTAssertNil(revs[0].at)
        XCTAssertEqual(revs[0].installEnd, d(2026, 4, 18))
        XCTAssertEqual(revs[1].by, "pm@tc.co")
        XCTAssertEqual(revs[1].at, d(2026, 3, 16))
        XCTAssertEqual(revs[1].reason, "โครงสร้างช้า")
        XCTAssertEqual(revs[1].changeRequest, "CR-014", "trimmed")
        XCTAssertEqual(revs[1].tasks, i.fixed, "the last revision is the plan itself")
        XCTAssertEqual(revs[1].installEnd, d(2026, 5, 20))
        XCTAssertEqual(revs[1].label, "REV 01")
        XCTAssertEqual(i.revisionNumber(), 1)
        XCTAssertEqual(i.baseline, before.fixed, "the baseline stays REV 00, so originalInstallEnd reads as before")
    }

    func testLaterReplansAddTheNextREVAndKeepTheFirst() throws {
        let one = try XCTUnwrap(replan(.panels, "2026-05-01", "2026-05-20").revised(input(), by: "a@tc.co", at: d(2026, 3, 16)))
        let two = try XCTUnwrap(replan(.structure, "2026-03-01", "2026-04-10", reason: " ฝนตก ", cr: "  ")
            .revised(one, replans: 1, by: "b@tc.co", at: d(2026, 3, 30)))
        let revs = try XCTUnwrap(two.revisions)
        XCTAssertEqual(revs.map(\.number), [0, 1, 2])
        XCTAssertEqual(Array(revs.prefix(2)), one.revisions)
        XCTAssertEqual(revs[2].reason, "ฝนตก")
        XCTAssertNil(revs[2].changeRequest, "a blank change request is none")
        XCTAssertEqual(two.baseline, input().fixed)
        XCTAssertEqual(two.original?.revisions, nil, "the original plan is the plan before any revision")
    }

    /// A station re-planned twice before revisions were recorded: its next re-plan is REV 03, and REV 00 its baseline.
    func testAPlanReplannedBeforeRevisionsCountsOn() throws {
        let first = try XCTUnwrap(replan(.panels, "2026-05-01", "2026-05-20").replanned(input()))
        let second = try XCTUnwrap(replan(.panels, "2026-05-04", "2026-05-25").replanned(first))
        XCTAssertNil(second.revisions)
        XCTAssertEqual(second.revisionNumber(replans: 2), 2)
        let third = try XCTUnwrap(replan(.panels, "2026-05-10", "2026-05-30").revised(second, replans: 2, by: "a@tc.co"))
        XCTAssertEqual(third.revisions?.map(\.number), [0, 3])
        XCTAssertEqual(third.revisions?.first?.tasks, input().fixed)
        XCTAssertEqual(third.revisionNumber(replans: 2), 3)
    }

    func testOtherChangesMakeNoRevision() {
        let a = Assistant.PendingAction(id: "p", jobID: "job-1", station: "s", change: .lateCause(task: .panels, cause: nil),
                                        title: "", before: "", after: "")
        XCTAssertNil(a.revised(input(), by: "a@tc.co"))
    }

    func testRevisionsTravelInThePlanAndOlderPlansRead() throws {
        let i = try XCTUnwrap(replan(.panels, "2026-05-01", "2026-05-20", cr: "CR-1").revised(input(), by: "a@tc.co", at: d(2026, 3, 16)))
        let back = try JSONDecoder().decode(MasterSchedule.Input.self, from: JSONEncoder().encode(i))
        XCTAssertEqual(back, i)

        // a plan saved before revisions has no key for them
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input())) as? [String: Any])
        old["revisions"] = nil
        let read = try JSONDecoder().decode(MasterSchedule.Input.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(read.revisions)
        XCTAssertEqual(read.revisionNumber(), 0)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(input()), as: UTF8.self).contains("revisions"),
                       "a plan without revisions writes none")
    }

    func testAMovedPlanMovesItsRevisions() throws {
        let i = try XCTUnwrap(replan(.panels, "2026-05-01", "2026-05-20").revised(input(), by: "a@tc.co", at: d(2026, 3, 16)))
        let moved = i.shifted(days: 7)
        XCTAssertEqual(moved.revisions?.last?.installEnd, d(2026, 5, 27))
        XCTAssertEqual(moved.revisions?.first?.installEnd, d(2026, 4, 25))
        XCTAssertEqual(moved.revisions?.last?.at, d(2026, 3, 16), "the approval day stays")
    }

    func testTheBriefNamesTheRevision() throws {
        let i = try XCTUnwrap(replan(.panels, "2026-05-01", "2026-05-20", cr: "CR-014").revised(input(), by: "a@tc.co", at: d(2026, 3, 16)))
        var actual = MasterSchedule.Actual()
        actual.confirmations = [.init(task: "panels", by: "a@tc.co", at: d(2026, 3, 16), before: "", after: "", replan: true)]
        let brief = ScheduleBrief(jobID: "j", station: "s", input: i, actual: actual, today: d(2026, 3, 16))
        XCTAssertEqual(brief.revision, "REV 01")
        XCTAssertEqual(brief.revisionReason, "โครงสร้างช้า")
        XCTAssertEqual(brief.revisionChangeRequest, "CR-014")
        XCTAssertEqual(brief.originalInstallEnd, "2026-04-18")

        let plain = ScheduleBrief(jobID: "j", station: "s", input: input(), actual: .init(), today: d(2026, 3, 16))
        XCTAssertNil(plain.revision)
    }

    func testProposeReplanCarriesTheChangeRequestAndNextREV() throws {
        var a = MasterSchedule.Actual()
        a.points = ["structure": ["2026-03-01": 2]]
        let job = Assistant.Job(id: "job-1", station: "สถานีทดสอบ", mpNumber: 189, input: input(), actual: a,
                                dailies: [], canEdit: true, canReplan: true, contractor: "A")
        let box = Assistant.Toolbox(jobs: [job], today: d(2026, 3, 16), makeID: { "p1" })
        let args = #"{"job":"189","reason":"ผู้ว่าจ้างขอเพิ่มจุด","change_request":"CR-014","tasks":[{"task":"2.3","start":"2026-05-01","end":"2026-05-20"}]}"#
        guard case .proposal(let p, _) = box.run("propose_replan", arguments: args) else { return XCTFail("a proposal") }
        XCTAssertEqual(p.changeRequest, "CR-014")
        XCTAssertTrue(p.title.contains("REV 01"), p.title)
        XCTAssertTrue(p.title.contains("CR CR-014"), p.title)
        XCTAssertEqual(try XCTUnwrap(p.revised(input(), by: "a@tc.co")).revisions?.last?.changeRequest, "CR-014")
    }
}
