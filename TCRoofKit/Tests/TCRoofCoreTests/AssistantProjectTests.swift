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
        XCTAssertEqual(papers.open.count, papers.openCount)          // kept whole; trimmed when sent
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

    func testSectionsKeepOnlyWhatIsAskedAndDropEmptyParts() {
        var inv = IECReport.Inverter(ratedKW: 80)
        inv.slots[0] = .init(modules: 18)
        let f = facts(iec: IECReport(module: .init(brand: "ZNSHINE", powerW: 570), inverters: [inv]))
        let box = Assistant.Toolbox(jobs: [Assistant.Job(id: "job-2", station: "สถานีผลิตน้ำบางพลี", mpNumber: 190, input: nil,
                                                          canEdit: true, project: f)], today: today)
        let iec = box.run("get_project", arguments: #"{"job":"190","sections":["iec"]}"#).text
        XCTAssertTrue(iec.contains(#""iec""#))
        XCTAssertTrue(iec.contains(#""basics""#))
        XCTAssertFalse(iec.contains(#""papers""#))
        XCTAssertFalse(iec.contains(#""icl""#))
        XCTAssertFalse(iec.contains("[]"))                           // e.g. no vocOutlierSlots, no surveys
        XCTAssertFalse(iec.contains("{}"))
        let all = box.run("get_project", arguments: #"{"job":"190","sections":["nonsense"]}"#).text
        XCTAssertTrue(all.contains(#""papers""#) && all.contains(#""icl""#))   // an unknown name gives everything
        XCTAssertLessThan(iec.count, all.count)
    }

    /// By default only each package's count and the 5 open papers due soonest go; `package` lists that package's.
    func testPapersAreShortUnlessAPackageIsAsked() throws {
        var station = StationDocs.Station()
        station.dueDates = ["handover": "2026-03-20", "grid_connection": "2026-04-30"]
        let ctx = StationDocs.Context(station, inverterKW: 80)
        let f = Assistant.ProjectFacts(jobID: "job-2", station: "สถานีผลิตน้ำบางพลี", mpNumber: 190, basics: basics(plan: false),
                                       stationDocs: station, docsContext: ctx, today: today)
        let full = try XCTUnwrap(f.papers)
        // the handover papers are due first
        XCTAssertEqual(full.open.first?.packageIDs.contains("handover"), true)
        XCTAssertEqual(full.open.first?.due, "2026-03-20")

        let short = full.listed(package: nil)
        XCTAssertEqual(short.open.count, Assistant.ProjectFacts.Papers.shortList)
        XCTAssertEqual(short.moreOpen, full.openCount - 5)
        XCTAssertEqual(short.packages, full.packages)                // every package's count still goes

        let grid = full.listed(package: .gridConnection)
        let gridKinds = Set(StationDocs.papers(in: .gridConnection, ctx).map(\.name))
        XCTAssertFalse(grid.open.isEmpty)
        XCTAssertTrue(grid.open.allSatisfy { gridKinds.contains($0.name) })
        // a paper shared with another package is found from either
        let applying = StationDocs.packages(ctx)
        let pairs = applying.flatMap { a in applying.filter { $0 != a }.map { (a, $0) } }
        let shared = pairs.lazy.compactMap { a, b in
            StationDocs.papers(in: a, ctx).first { k in StationDocs.papers(in: b, ctx).contains { $0.id == k.id } }.map { ($0.name, b) }
        }.first
        let (name, other) = try XCTUnwrap(shared, "some paper belongs to two packages")
        XCTAssertTrue(full.listed(package: other).open.contains { $0.name == name })

        let box = Assistant.Toolbox(jobs: [Assistant.Job(id: "job-2", station: "x", mpNumber: 190, input: nil, canEdit: true, project: f)],
                                    today: today)
        let sentShort = box.run("get_project", arguments: #"{"job":"190","sections":["papers"]}"#).text
        let sentGrid = box.run("get_project", arguments: #"{"job":"190","sections":["papers"],"package":"grid_connection"}"#).text
        XCTAssertTrue(sentShort.contains(#""moreOpen""#))
        XCTAssertFalse(sentShort.contains("packageIDs"))             // the internal fields aren't sent
        XCTAssertLessThan(sentShort.count, sentGrid.count)
    }

    func testOnlyAPersonsMessageCountsAsAQuestion() {
        let q = Assistant.Request(messages: [.system("s"), .user("q")], tools: [])
        XCTAssertTrue(q.isNewQuestion)
        let round = Assistant.Request(messages: [.system("s"), .user("q"),
                                                 .init(role: .assistant, content: nil, toolCalls: [.init(id: "c", name: "get_schedule", arguments: "{}")]),
                                                 .tool("c", "{}")], tools: [])
        XCTAssertFalse(round.isNewQuestion)
        XCTAssertEqual(Assistant.OpenAI.dailyRequestLimit, Assistant.OpenAI.dailyLimit * 5)
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
