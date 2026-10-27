import XCTest
@testable import TCRoofCore

/// The project assistant's numbers, tools and conversation loop (no network: the transport is stubbed).
final class AssistantTests: XCTestCase {
    private let cal = MasterSchedule.calendar

    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day))! }

    /// Four tasks on an imported plan, seen on Monday 16 มี.ค. 2569 (week of Sunday 15 มี.ค.):
    /// 2.1 half way and slow, 2.2 past its end, 2.3 not started, 2.5 done.
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

    private func actual() -> MasterSchedule.Actual {
        var a = MasterSchedule.Actual()
        a.points = ["structure": ["2026-03-01": 2, "2026-03-08": 2], "dcSide": ["2026-02-08": 5],
                    "inverter": ["2026-03-08": 15]]
        a.lateCauses["dcSide"] = .material
        return a
    }

    private var today: Date { d(2026, 3, 16) }

    private func job(id: String = "job-1", station: String = "สถานีผลิตน้ำทุ่งน้อย", mp: Int = 189, canEdit: Bool = true) -> Assistant.Job {
        var day = RoutineReport.Daily(date: d(2026, 3, 14))
        day.crew = [.init(name: "ช่าง", count: 6)]
        day.weather[3] = .rain; day.weather[4] = .rain
        day.problems = [.init(description: "รางเคเบิลยังไม่มา", since: d(2026, 3, 12))]
        let old = RoutineReport.Daily(date: d(2026, 2, 20))
        return Assistant.Job(id: id, station: station, mpNumber: mp, kWp: 92.34, input: input(), actual: actual(),
                             dailies: [day, old], canEdit: canEdit)
    }

    // MARK: Recovery

    func testRecoveryNumbers() throws {
        let r = MasterSchedule.recovery(plan: MasterSchedule.plan(input()), actual: actual(), today: today)
        XCTAssertEqual(r.map(\.task), [.structure, .dcSide, .panels, .inverter])

        let s = try XCTUnwrap(r.first { $0.task == .structure })
        XCTAssertEqual(s.done, 4)
        XCTAssertEqual(s.remaining, 16)
        XCTAssertEqual(s.weeksLeft, 2)                       // weeks of 15 and 22 มี.ค.
        XCTAssertEqual(s.neededPerWeek, 8)
        XCTAssertEqual(try XCTUnwrap(s.pacePerWeek), 4.0 / 3, accuracy: 1e-9)   // 3 weeks since 1 มี.ค.
        XCTAssertEqual(s.projectedFinish, d(2026, 6, 6))     // 12 weeks from 15 มี.ค., the Saturday
        XCTAssertEqual(s.slipDays, 70)
        XCTAssertEqual(s.state, .atRisk)

        XCTAssertEqual(r.first { $0.task == .dcSide }?.state, .overdue)
        // past its planned end: everything left is needed now
        let dc = try XCTUnwrap(r.first { $0.task == .dcSide })
        XCTAssertEqual(dc.neededPerWeek, dc.remaining)
        XCTAssertEqual(r.first { $0.task == .panels }?.state, .upcoming)
        XCTAssertEqual(r.first { $0.task == .panels }?.pacePerWeek, nil)
        XCTAssertEqual(r.first { $0.task == .inverter }?.state, .done)
    }

    func testOnTrackWhenThePaceFinishesInTime() {
        var a = actual()
        a.points["structure"] = ["2026-03-01": 5, "2026-03-08": 5, "2026-03-15": 5]
        let s = MasterSchedule.recovery(plan: MasterSchedule.plan(input()), actual: a, today: today).first { $0.task == .structure }!
        XCTAssertEqual(s.pacePerWeek, 5)
        XCTAssertEqual(s.projectedFinish, d(2026, 3, 21))
        XCTAssertEqual(s.slipDays, -7)
        XCTAssertEqual(s.state, .onTrack)
    }

    // MARK: Brief

    func testBriefCarriesThePlanAndRecentDays() throws {
        let b = try XCTUnwrap(job().brief(today: today))
        XCTAssertEqual(b.today, "2026-03-16")
        XCTAssertEqual(b.tasks.map(\.code), ["2.1", "2.2", "2.3", "2.5"])
        let s = try XCTUnwrap(b.tasks.first { $0.code == "2.1" })
        XCTAssertEqual(s.neededPointsPerWeek, 8)
        XCTAssertEqual(s.pacePointsPerWeek, 1.3)
        XCTAssertEqual(s.slipDays, 70)
        XCTAssertEqual(b.tasks.first { $0.code == "2.2" }?.lateCause, "วัสดุ")
        XCTAssertEqual(b.thisWeek, ["2.1"])
        XCTAssertEqual(b.nextTwoWeeks, ["2.1", "2.3"])
        // task by task: 2.1 ends 6 มิ.ย., 2.3 after it
        XCTAssertEqual(b.projectedFinish, "2026-06-27")
        XCTAssertEqual(b.projectedSlipDays, 70)              // after the install end of 18 เม.ย.
        // the install tracking page's figure: the due date moved by the days behind (earned schedule)
        let spi = try XCTUnwrap(b.spi)
        XCTAssertEqual(spi, (b.actualPercent / b.plannedPercent * 100).rounded() / 100, accuracy: 0.011)
        let t = InstallTracking(actual: MasterSchedule.status(plan: MasterSchedule.plan(job().input!), actual: job().actual, through: today).actual,
                                planned: MasterSchedule.status(plan: MasterSchedule.plan(job().input!), actual: job().actual, through: today).planned,
                                start: d(2026, 2, 1), due: d(2026, 4, 18), today: today,
                                earned: InstallTracking.earnedDate(plan: MasterSchedule.plan(job().input!, calendar: cal), actual: job().actual,
                                                                   done: MasterSchedule.status(plan: MasterSchedule.plan(job().input!), actual: job().actual, through: today).actual,
                                                                   start: d(2026, 2, 1), calendar: cal))
        XCTAssertEqual(b.handoverForecast, ScheduleBrief.day(t.forecastEnd(calendar: cal), calendar: cal))
        XCTAssertEqual(b.handoverSlipDays, -t.slackDays(calendar: cal))
        XCTAssertTrue(b.handoverSlipDays > 0)
        // only the last 14 days of reports
        XCTAssertEqual(b.recentDays.map(\.date), ["2026-03-14"])
        XCTAssertEqual(b.recentDays.first?.crew, 6)
        XCTAssertEqual(b.recentDays.first?.rainHours, 2)
        XCTAssertEqual(b.recentDays.first?.openProblems, ["รางเคเบิลยังไม่มา"])
        XCTAssertTrue(b.variance < 0)
        XCTAssertNotNil(JSONValue.parse(b.json()))
    }

    // MARK: Tools

    private func box(_ jobs: [Assistant.Job]? = nil) -> Assistant.Toolbox {
        Assistant.Toolbox(jobs: jobs ?? [job(), job(id: "job-2", station: "สถานีบ้านไผ่", mp: 190)], today: today, makeID: { "p1" })
    }

    private func object(_ outcome: Assistant.Toolbox.Outcome) -> JSONValue { JSONValue.parse(outcome.text) ?? .null }

    func testBriefMarksTheCriticalPath() throws {
        let b = try XCTUnwrap(job().brief(today: today))
        let floats = b.tasks.compactMap(\.floatDays)
        XCTAssertFalse(floats.isEmpty)
        XCTAssertTrue(floats.contains(0))                          // the last task to end has none
        XCTAssertTrue(floats.allSatisfy { $0 >= 0 })
        XCTAssertTrue(b.tasks.filter { $0.code.hasPrefix("1.") }.allSatisfy { $0.floatDays == nil })   // permits
    }

    func testFindsAJobByIdNumberOrName() {
        let b = box()
        XCTAssertEqual(b.find("job-2").map(\.id), ["job-2"])
        XCTAssertEqual(b.find("189").map(\.id), ["job-1"])
        XCTAssertEqual(b.find("MP 190").map(\.id), ["job-2"])
        XCTAssertEqual(b.find("บ้านไผ่").map(\.id), ["job-2"])
        XCTAssertEqual(b.find("สถานี").count, 2)
        XCTAssertTrue(b.find("").isEmpty)
    }

    func testListStationsSortsTheMostBehindFirst() {
        var ahead = job(id: "job-3", station: "สถานีเร็ว", mp: 191)
        ahead.actual.points["structure"] = ["2026-03-01": 20]
        ahead.actual.points["dcSide"] = ["2026-02-08": 10]
        ahead.actual.points["panels"] = ["2026-03-15": 20]
        let out = object(box([ahead, job()]).run("list_stations", arguments: "{}"))
        guard case .array(let rows)? = out["stations"] else { return XCTFail("no stations") }
        XCTAssertEqual(rows.map { $0["jobID"]?.string }, ["job-1"])
        let all = object(box([ahead, job()]).run("list_stations", arguments: #"{"filter":"all"}"#))
        guard case .array(let both)? = all["stations"] else { return XCTFail("no stations") }
        XCTAssertEqual(both.map { $0["jobID"]?.string }, ["job-1", "job-3"])
    }

    func testGetScheduleNeedsOneStation() {
        XCTAssertEqual(object(box().run("get_schedule", arguments: #"{"job":"189"}"#))["jobID"]?.string, "job-1")
        XCTAssertNotNil(object(box().run("get_schedule", arguments: #"{"job":"สถานี"}"#))["error"])
        XCTAssertNotNil(object(box().run("get_schedule", arguments: #"{"job":"999"}"#))["error"])
        XCTAssertNotNil(object(box().run("no_such_tool", arguments: "{}"))["error"])
        XCTAssertNotNil(object(box().run("get_schedule", arguments: "not json"))["error"])
    }

    func testWeekTasks() {
        let out = object(box().run("get_week_tasks", arguments: #"{"job":"189","week":"2026-03-10"}"#))
        XCTAssertEqual(out["week"]?.string, "2026-03-08")
        guard case .array(let rows)? = out["tasks"] else { return XCTFail("no tasks") }
        let s = rows.first { $0["code"]?.string == "2.1" }
        XCTAssertEqual(s?["plannedPoints"]?.number, 5)
        XCTAssertEqual(s?["actualPoints"]?.number, 2)
    }

    func testProposeProgressSavesNothingAndAppliesOnConfirm() throws {
        let j = job()
        let outcome = box([j]).run("propose_progress", arguments: #"{"job":"189","task":"2.1","percent":"45%"}"#)
        guard case .proposal(let a, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(a.change, .progress(task: .structure, week: "2026-03-15", percent: 45))
        XCTAssertEqual(a.before, "20%")
        XCTAssertEqual(a.after, "45% (สัปดาห์ 2026-03-15)")
        XCTAssertEqual(object(outcome)["status"]?.string, "waiting_for_user_confirmation")

        let saved = a.apply(to: j.actual, input: j.input!)
        XCTAssertEqual(saved.points["structure"]?["2026-03-15"], 5)   // 45% of 20 = 9, 4 booked before
        XCTAssertEqual(j.actual.points["structure"]?["2026-03-15"], nil)
    }

    func testProposalsAreChecked() {
        let b = box()
        XCTAssertNotNil(object(b.run("propose_progress", arguments: #"{"job":"189","task":"9.9","percent":10}"#))["error"])
        XCTAssertNotNil(object(b.run("propose_progress", arguments: #"{"job":"189","task":"2.1","percent":120}"#))["error"])
        XCTAssertNotNil(object(b.run("propose_progress", arguments: #"{"job":"189","task":"2.1","percent":50,"week":"2026-03-22"}"#))["error"])
        XCTAssertNotNil(object(b.run("propose_progress", arguments: #"{"job":"189","task":"1.1","percent":50}"#))["error"])   // no weight here
        let viewer = box([job(canEdit: false)])
        XCTAssertNotNil(object(viewer.run("propose_progress", arguments: #"{"job":"189","task":"2.1","percent":50}"#))["error"])
    }

    func testProposeDatesKeepsWhatIsLeftOut() {
        var j = job()
        j.actual.started["structure"] = d(2026, 3, 2)
        let b = box([j])
        guard case .proposal(let a, _) = b.run("propose_dates", arguments: #"{"job":"189","task":"2.1","finished":"2026-03-14"}"#) else {
            return XCTFail()
        }
        XCTAssertEqual(a.change, .dates(task: .structure, started: "2026-03-02", finished: "2026-03-14"))
        guard case .proposal(let c, _) = b.run("propose_dates", arguments: #"{"job":"189","task":"2.1","started":""}"#) else {
            return XCTFail()
        }
        XCTAssertEqual(c.change, .dates(task: .structure, started: nil, finished: nil))
        XCTAssertNotNil(object(b.run("propose_dates", arguments: #"{"job":"189","task":"2.1","finished":"2026-04-01"}"#))["error"])
        let applied = a.apply(to: j.actual, input: j.input!)
        XCTAssertEqual(applied.finished["structure"], d(2026, 3, 14))
    }

    func testProposeLateCause() {
        let j = job()
        guard case .proposal(let a, _) = box([j]).run("propose_late_cause", arguments: #"{"job":"189","task":"2.2","cause":"none"}"#) else {
            return XCTFail()
        }
        XCTAssertEqual(a.before, "วัสดุ")
        XCTAssertNil(a.apply(to: j.actual, input: j.input!).lateCauses["dcSide"])
        XCTAssertNotNil(object(box([j]).run("propose_late_cause", arguments: #"{"job":"189","task":"2.2","cause":"rain"}"#))["error"])
    }

    /// The function refuses tools not in functions/src/allowed-tools.json.
    func testToolNamesMatchTheFunctionsAllowList() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../functions/src/allowed-tools.json")
        let names = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        XCTAssertEqual(Set(names), Set(Assistant.Toolbox.names))
        let defined = Assistant.Toolbox.definitions.compactMap { $0["function"]?["name"]?.string }
        XCTAssertEqual(defined, Assistant.Toolbox.names)
    }

    // MARK: Session

    private actor Stub: Assistant.Transport {
        var replies: [Assistant.Message]
        var requests: [Assistant.Request] = []
        init(_ replies: [Assistant.Message]) { self.replies = replies }
        func push(_ more: [Assistant.Message]) { replies += more }
        func complete(_ request: Assistant.Request) async throws -> Assistant.Reply {
            requests.append(request)
            guard !replies.isEmpty else { throw Assistant.Failure.emptyReply }
            return Assistant.Reply(message: replies.removeFirst(), remainingToday: 49 - requests.count + 1)
        }
    }

    private func calls(_ list: [(String, String)]) -> Assistant.Message {
        Assistant.Message(role: .assistant, content: nil,
                          toolCalls: list.enumerated().map { .init(id: "c\($0.offset)", name: $0.element.0, arguments: $0.element.1) })
    }

    @MainActor
    func testSessionRunsToolsAndCollectsProposals() async throws {
        let stub = Stub([
            calls([("get_schedule", #"{"job":"189"}"#)]),
            calls([("propose_progress", #"{"job":"189","task":"2.1","percent":45}"#)]),
            .init(role: .assistant, content: "เสนอบันทึก 2.1 เป็น 45% รอยืนยัน"),
        ])
        let j = job()
        let s = Assistant.Session(transport: stub, focus: j, jobs: { [j] }, now: { self.today })
        let reply = try await s.send("อัปเดต 2.1 เป็น 45%")
        XCTAssertEqual(reply.content, "เสนอบันทึก 2.1 เป็น 45% รอยืนยัน")
        XCTAssertEqual(s.proposals.count, 1)
        XCTAssertEqual(s.remainingToday, 47)
        XCTAssertEqual(s.messages.map(\.role), [.system, .user, .assistant, .tool, .assistant, .tool, .assistant])
        XCTAssertEqual(s.messages[3].toolCallID, "c0")
        XCTAssertTrue(s.messages[0].content!.contains("2026-03-16"))
        XCTAssertTrue(s.messages[0].content!.contains("MP 189"))
        let sent = await stub.requests
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent[0].tools.count, Assistant.Toolbox.names.count)

        s.resolve(s.proposals[0].id, confirmed: true)
        XCTAssertTrue(s.proposals.isEmpty)
        XCTAssertTrue(s.messages.last!.content!.contains("ผู้ใช้ยืนยันและบันทึกแล้ว"))
    }

    @MainActor
    func testANewerProposalForTheSameTaskReplacesTheOlder() async throws {
        let stub = Stub([
            calls([("propose_progress", #"{"job":"189","task":"2.1","percent":30}"#),
                   ("propose_progress", #"{"job":"189","task":"2.1","percent":40}"#),
                   ("propose_late_cause", #"{"job":"189","task":"2.1","cause":"weather"}"#)]),
            .init(role: .assistant, content: "ok"),
        ])
        let j = job()
        let s = Assistant.Session(transport: stub, jobs: { [j] }, now: { self.today })
        try await s.send("x")
        XCTAssertEqual(s.proposals.map(\.after), ["40% (สัปดาห์ 2026-03-15)", "สภาพอากาศ"])
    }

    @MainActor
    func testSessionStopsAfterTheRoundLimit() async {
        let stub = Stub(Array(repeating: calls([("list_stations", "{}")]), count: 6))
        let s = Assistant.Session(transport: stub, jobs: { [] }, now: { self.today })
        do { try await s.send("x"); XCTFail("no error") }
        catch { XCTAssertEqual(error as? Assistant.Failure, .tooManyRounds) }
    }

    @MainActor
    func testEarlierToolResultsAreSentAsANote() async throws {
        let stub = Stub([])
        let j = job()
        let s = Assistant.Session(transport: stub, jobs: { [j] }, now: { self.today })
        for i in 0..<2 {
            await stub.push([calls([("get_schedule", #"{"job":"189"}"#)]), .init(role: .assistant, content: "a\(i)")])
            try await s.send("q\(i)")
        }
        let sent = s.trimmed()
        let tools = sent.filter { $0.role == .tool }
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools[0].content, Assistant.Session.droppedResult)      // the first question's
        XCTAssertTrue(tools[1].content!.contains("structure") || tools[1].content!.contains("2.1"))   // this question's, whole
        XCTAssertGreaterThan(s.messages.filter { $0.role == .tool }[0].content!.count, 1_000)          // kept on the device
        // the model's answers and the questions are all still sent
        XCTAssertEqual(sent.filter { $0.role == .user }.map(\.content), ["q0", "q1"])
    }

    @MainActor
    func testHistoryIsTrimmedAtAPersonsMessage() async throws {
        let stub = Stub([])
        let s = Assistant.Session(transport: stub, jobs: { [] }, now: { self.today })
        s.historyLimit = 4
        for i in 0..<3 {
            await stub.push([calls([("list_stations", "{}")]), .init(role: .assistant, content: "a\(i)")])
            try await s.send("q\(i)")
        }
        let t = s.trimmed()
        XCTAssertEqual(t.first?.role, .system)
        XCTAssertEqual(t[1].role, .user)
        XCTAssertEqual(t[1].content, "q2")
        XCTAssertLessThanOrEqual(t.count - 1, 4)

        s.historyLimit = 30
        s.charLimit = 10
        XCTAssertEqual(s.trimmed()[1].content, "q2")      // the latest turn stays, however long
        s.charLimit = 60_000
        XCTAssertEqual(s.trimmed().count, s.messages.count)
    }
}

// MARK: History kept on the device

extension AssistantTests {
    private func folder() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-history-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }

    @MainActor
    func testAConversationIsSavedAndCarriesOnInANewSession() async throws {
        let stub = Stub([
            calls([("get_schedule", #"{"job":"189"}"#)]),
            .init(role: .assistant, content: "2.1 ช้ากว่าแผน"),
            .init(role: .assistant, content: "ต้องเพิ่มช่างอีก 2 คน"),
        ])
        let j = job()
        let s = Assistant.Session(transport: stub, focus: j, jobs: { [j] }, now: { self.today })
        try await s.send("MP 189 เป็นอย่างไร")
        let h = Assistant.History(folder: folder())
        h.save(s.history, account: "A@tc.test", focus: j.id, now: today)

        // nothing saved for another account or the all-stations chat
        XCTAssertNil(h.load(account: "b@tc.test", focus: j.id, now: today))
        XCTAssertNil(h.load(account: "a@tc.test", focus: nil, now: today))
        let saved = try XCTUnwrap(h.load(account: "a@tc.test", focus: j.id, now: today))
        XCTAssertEqual(saved.messages.map(\.role), [.user, .assistant, .tool, .assistant])
        // the tool result is kept short, as a later question sends it
        XCTAssertEqual(saved.messages[2].content, Assistant.Session.droppedResult)
        XCTAssertEqual(saved.messages[1].toolCalls?.first?.function.name, "get_schedule")

        let next = Assistant.Session(transport: stub, focus: j, jobs: { [j] }, now: { self.today })
        next.restore(saved.messages)
        try await next.send("ต้องทำอะไร")
        let sent = await stub.requests
        XCTAssertEqual(sent.last?.messages.map(\.role), [.system, .user, .assistant, .tool, .assistant, .user])
        XCTAssertEqual(sent.last?.messages[1].content, "MP 189 เป็นอย่างไร")

        // too old: starts over; cleared: gone
        XCTAssertNil(h.load(account: "a@tc.test", focus: j.id, now: today.addingTimeInterval(31 * 86_400)))
        h.clear(account: "a@tc.test", focus: j.id)
        XCTAssertNil(h.load(account: "a@tc.test", focus: j.id, now: today))
    }

    @MainActor
    func testAnOpenCardIsSavedAsNotSaved() async throws {
        let stub = Stub([
            calls([("propose_progress", #"{"job":"189","task":"2.1","percent":45}"#)]),
            .init(role: .assistant, content: "เสนอ 45% รอยืนยัน"),
        ])
        let j = job()
        let s = Assistant.Session(transport: stub, jobs: { [j] }, now: { self.today })
        try await s.send("อัปเดต 2.1")
        let last = try XCTUnwrap(s.history.last)
        XCTAssertEqual(last.role, .user)
        XCTAssertTrue(last.content!.hasPrefix("[ระบบ]"))
        XCTAssertTrue(last.content!.hasSuffix("ไม่ได้บันทึก"))

        // a restored session has no cards, and doesn't take a history once asked
        let next = Assistant.Session(transport: stub, jobs: { [j] }, now: { self.today })
        next.restore(s.history)
        XCTAssertTrue(next.proposals.isEmpty)
        XCTAssertEqual(next.messages.count, 1 + s.history.count)
        next.restore(s.history)
        XCTAssertEqual(next.messages.count, 1 + s.history.count)
    }

    @MainActor
    func testHistoryKeepsWholeTurnsUpToTheLimit() {
        let s = Assistant.Session(transport: Stub([]), jobs: { [] }, now: { self.today })
        var old: [Assistant.Message] = []
        for i in 0..<120 {
            old.append(.user("q\(i)"))
            old.append(.init(role: .assistant, content: nil, toolCalls: [.init(id: "c\(i)", name: "list_stations", arguments: "{}")]))
            old.append(.tool("c\(i)", "{}"))
            old.append(.init(role: .assistant, content: "a\(i)"))
        }
        s.restore(old)
        let h = s.history
        XCTAssertLessThanOrEqual(h.count, Assistant.History.maxMessages)
        XCTAssertEqual(h.first?.role, .user)
        XCTAssertEqual(h.last?.content, "a119")
    }
}
