import XCTest
@testable import TCRoofCore

/// `get_project`: the rest of a station besides its MP plan (papers, ERC, IEC, weekly requests, ICL, devices).
final class AssistantProjectTests: XCTestCase {
    private let cal = MasterSchedule.calendar

    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day))! }
    private var today: Date { d(2026, 3, 16) }

    private func basics(plan: Bool) -> Assistant.ProjectFacts.Basics {
        .init(code: "TC-190", status: "กำลังติดตั้ง", province: "สมุทรปราการ", capacityKW: 92.34, inverterKW: 80,
              crew: "ทีม TCR01", surveyDate: "2026-01-05", installStart: "2026-02-01", installEnd: "2026-04-18", hasMPPlan: plan)
    }

    private func facts(station: StationDocs.Station = .init(), iec: IECReport? = nil,
                       weekly: [RoutineReport.WeeklyRequest] = []) -> Assistant.ProjectFacts {
        Assistant.ProjectFacts(jobID: "job-2", station: "สถานีผลิตน้ำบางพลี", mpNumber: 190, basics: basics(plan: false),
                               stationDocs: station, docsContext: StationDocs.Context(station, inverterKW: 80),
                               iec: iec, weeklyRequests: weekly,
                               icl: .init(stepsDone: 3, steps: 8, allPassed: false, submitted: nil),
                               devices: ["แผงโซลาร์เซลล์": 162], installLogs: [d(2026, 3, 10), d(2026, 3, 14)],
                               inspections: [.init(at: d(2026, 3, 20), subject: "2.5 Inverter"), .init(at: d(2026, 3, 1))],
                               today: today)
    }

    /// A station with no MP plan, carrying its facts the way a test gives them (the app builds them on demand).
    private func unplanned() -> Assistant.Job {
        Assistant.Job(id: "job-2", station: "สถานีผลิตน้ำบางพลี", mpNumber: 190, input: nil, canEdit: true, project: facts())
    }

    func testGetProjectWorksWithoutAnMPPlan() throws {
        let box = Assistant.Toolbox(jobs: [unplanned()], today: today)
        let out = box.run("get_project", arguments: #"{"job":"190"}"#).text
        XCTAssertTrue(out.contains(#""hasMPPlan":false"#))
        XCTAssertTrue(out.contains("สถานีผลิตน้ำบางพลี"))
        XCTAssertTrue(out.contains(#""installLogs":2"#))
        XCTAssertTrue(out.contains(#""lastInstallLog":"2026-03-14""#))
        // the plan's tools still need a plan
        XCTAssertTrue(box.run("get_schedule", arguments: #"{"job":"190"}"#).text.contains("ยังไม่มีแผน MP"))
    }

    func testGetProjectNeedsOneStation() {
        let box = Assistant.Toolbox(jobs: [unplanned()], today: today)
        XCTAssertTrue(box.run("get_project", arguments: #"{"job":"999"}"#).text.contains("ไม่พบสถานี"))
        var bare = unplanned()
        bare.project = nil
        XCTAssertTrue(Assistant.Toolbox(jobs: [bare], today: today).run("get_project", arguments: #"{"job":"190"}"#)
            .text.contains("ไม่มีข้อมูลโครงการ"))
    }

    func testListStationsAddsStationsWithoutAPlanOnlyForAll() {
        let box = Assistant.Toolbox(jobs: [unplanned()], today: today)
        XCTAssertTrue(box.run("list_stations", arguments: #"{"filter":"all"}"#).text.contains(#""hasMPPlan":false"#))
        XCTAssertFalse(box.run("list_stations", arguments: "{}").text.contains("job-2"))
    }

    func testFactsCarryPapersTestAndRequests() throws {
        var inv = IECReport.Inverter(ratedKW: 80)
        inv.slots[0] = .init(modules: 18)
        inv.slots[1] = .init(modules: 18)
        let iec = IECReport(module: .init(brand: "ZNSHINE", powerW: 570), inverters: [inv])
        var older = RoutineReport.WeeklyRequest(weekStart: d(2026, 3, 1))
        older.approvedAt = d(2026, 2, 27)
        var newer = RoutineReport.WeeklyRequest(weekStart: d(2026, 3, 15))
        newer.crew = [.init(name: "ช่าง", count: 6), .init(name: "หัวหน้า", count: 1)]
        newer.risks = [.init(description: "ฝนตกช่วงบ่าย", level: .high)]
        let f = facts(iec: iec, weekly: [older, newer])

        let papers = try XCTUnwrap(f.papers)
        XCTAssertFalse(papers.packages.isEmpty)
        XCTAssertGreaterThan(papers.openCount, 0)                   // nothing filed yet
        XCTAssertEqual(papers.open.count, min(papers.openCount, Assistant.ProjectFacts.listLimit))
        XCTAssertEqual(Set(papers.open.map(\.name)).count, papers.open.count)   // a paper of two packages once
        XCTAssertNil(f.erc)                                          // no flow started

        let test = try XCTUnwrap(f.iec)
        XCTAssertEqual(test.state, "open")
        XCTAssertEqual(test.steps.map(\.number), Array(1...7))
        XCTAssertEqual(test.inverters.count, 1)
        XCTAssertEqual(test.stringCount, 2)
        XCTAssertEqual(test.installedKWp, 20.52)                     // 36 × 570 W
        XCTAssertNil(test.passed)

        XCTAssertEqual(f.weeklyRequests.map(\.week), ["2026-03-15", "2026-03-01"])
        XCTAssertEqual(f.weeklyRequests.map(\.state), ["draft", "approved"])
        XCTAssertEqual(f.weeklyRequests[0].crew, 7)
        XCTAssertEqual(f.weeklyRequests[0].risks, ["สูง: ฝนตกช่วงบ่าย"])
        XCTAssertEqual(f.inspections.count, 1)                       // the one before today is left out
        XCTAssertTrue(f.inspections[0].hasSuffix("2.5 Inverter"))
    }

    @MainActor
    func testSessionBuildsFactsOnlyForTheStationAsked() async throws {
        let stub = ProjectStub([
            .init(role: .assistant, content: nil, toolCalls: [.init(id: "c0", name: "get_project", arguments: #"{"job":"190"}"#)]),
            .init(role: .assistant, content: "เอกสารยังไม่พร้อม"),
        ])
        var bare = unplanned()
        bare.project = nil
        let other = Assistant.Job(id: "job-3", station: "สถานีผลิตน้ำบางบ่อ", mpNumber: 191, input: nil, canEdit: true)
        let asked = Asked()
        let s = Assistant.Session(transport: stub, jobs: { [bare, other] },
                                  project: { j in asked.ids.append(j.id); return self.facts() }, now: { self.today })
        _ = try await s.send("เอกสารของ MP 190 ครบหรือยัง")
        XCTAssertEqual(asked.ids, ["job-2"])
        XCTAssertTrue(s.messages[3].content!.contains(#""papers""#))
        XCTAssertTrue(s.messages[0].content!.contains("get_project"))
    }
}

@MainActor private final class Asked { var ids: [String] = [] }

private actor ProjectStub: Assistant.Transport {
    var replies: [Assistant.Message]
    init(_ replies: [Assistant.Message]) { self.replies = replies }
    func complete(_ request: Assistant.Request) async throws -> Assistant.Reply {
        guard !replies.isEmpty else { throw Assistant.Failure.emptyReply }
        return Assistant.Reply(message: replies.removeFirst(), remainingToday: nil)
    }
}
