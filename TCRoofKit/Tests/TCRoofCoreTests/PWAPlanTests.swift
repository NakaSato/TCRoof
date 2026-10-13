import XCTest
@testable import TCRoofCore

final class PWAPlanTests: XCTestCase {
    let cal = MasterSchedule.calendar
    /// Monday 12 Oct 2026, the board's "today" (ISO week 42).
    var today: Date { day(2026, 10, 12) }

    func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    func input(start: Date, end: Date, over200: Bool = false) -> MasterSchedule.Input {
        MasterSchedule.Input(installStart: start, installEnd: end, kickoff: cal.date(byAdding: .day, value: -21, to: start)!,
                             engineeringStart: cal.date(byAdding: .day, value: -14, to: start)!,
                             siteHandover: cal.date(byAdding: .day, value: -3, to: start)!, over200kVA: over200)
    }

    func station(_ id: String, mp: Int? = nil, kWp: Double = 100, start: Date, end: Date, over200: Bool = false,
                 contractor: String = "", team: String = "TCR01") -> PWAPlan.Station {
        PWAPlan.Station(id: id, mpNumber: mp, code: id, name: "สถานีผลิตน้ำ" + id, kWp: kWp, contractor: contractor, team: team,
                        input: input(start: start, end: end, over200: over200))
    }

    // MARK: S-curve

    func testCurveWeightsStationsByKWp() {
        var a = station("a", kWp: 300, start: day(2026, 9, 1), end: day(2026, 11, 15))
        var b = station("b", kWp: 100, start: day(2026, 9, 20), end: day(2026, 12, 20))
        a.actual.set(10, task: .structure, week: day(2026, 9, 8), over200kVA: false)
        b.actual.set(20, task: .structure, week: day(2026, 9, 29), over200kVA: false)
        let curve = PWAPlan.curve([a, b], today: today)
        let sa = MasterSchedule.status(plan: MasterSchedule.plan(a.input!), actual: a.actual, through: today)
        let sb = MasterSchedule.status(plan: MasterSchedule.plan(b.input!), actual: b.actual, through: today)

        XCTAssertEqual(curve.planned, (300 * sa.planned + 100 * sb.planned) / 400, accuracy: 1e-9)
        XCTAssertEqual(curve.done, (300 * 10 + 100 * 20) / 400.0, accuracy: 1e-9)
        // the point of this week is the header's figure
        let i = try! XCTUnwrap(curve.todayIndex)
        XCTAssertEqual(curve.plan[i], curve.planned, accuracy: 1e-9)
        XCTAssertEqual(curve.actual.count, i + 1)
        XCTAssertEqual(curve.actual.last!, curve.done, accuracy: 1e-9)
    }

    func testCurveRunsFromFirstPlannedWeekToLastAndEndsAt100() {
        let a = station("a", start: day(2026, 9, 1), end: day(2026, 11, 15))
        let b = station("b", start: day(2026, 9, 20), end: day(2026, 12, 20))
        let curve = PWAPlan.curve([a, b], today: today)
        XCTAssertEqual(curve.weeks.first, MasterSchedule.weekStart(a.input!.kickoff))
        XCTAssertEqual(curve.weeks.last, MasterSchedule.weekStart(day(2026, 12, 20)))
        XCTAssertEqual(curve.plan.last!, 100, accuracy: 1e-9)
        XCTAssertEqual(curve.plan, curve.plan.sorted())
        XCTAssertEqual(curve.totalWeeks, curve.weeks.count - 1)
    }

    func testCurveWeightsEquallyWithoutKWpAndIsEmptyWithoutPlans() {
        var a = station("a", kWp: 0, start: day(2026, 9, 1), end: day(2026, 11, 15))
        let b = station("b", kWp: 0, start: day(2026, 9, 1), end: day(2026, 11, 15))
        a.actual.set(20, task: .structure, week: day(2026, 9, 8), over200kVA: false)
        XCTAssertEqual(PWAPlan.curve([a, b], today: today).done, 10, accuracy: 1e-9)
        XCTAssertEqual(PWAPlan.curve([PWAPlan.Station(id: "x", name: "x")], today: today), .empty)
    }

    func testCurveHasNoActualBeforeTheFirstWeek() {
        let a = station("a", start: day(2027, 1, 10), end: day(2027, 3, 10))
        let curve = PWAPlan.curve([a], today: today)
        XCTAssertNil(curve.todayIndex)
        XCTAssertTrue(curve.actual.isEmpty)
        XCTAssertEqual(curve.planned, 0)
    }

    func testBehindByComparesWholePercents() {
        var c = PWAPlan.Curve.empty
        c.planned = 48.4; c.done = 46.6
        XCTAssertEqual(c.behindBy, 1)
        c.done = 49
        XCTAssertEqual(c.behindBy, 0)
    }

    // MARK: deadlines

    func testOverdueHandoverGoesIntoThisWeek() {
        let late = station("late", mp: 77, start: day(2026, 8, 1), end: day(2026, 10, 8))
        let soon = station("soon", start: day(2026, 8, 10), end: day(2026, 10, 14))
        let next = station("next", start: day(2026, 8, 20), end: day(2026, 10, 20))
        let far = station("far", start: day(2026, 9, 1), end: day(2026, 11, 20))
        let all = PWAPlan.deadlines([far, next, soon, late], today: today).filter { $0.kind == .handover }
        let g = PWAPlan.groups(all, today: today)

        XCTAssertEqual(g.thisWeek.map(\.station), ["late", "soon"])
        XCTAssertEqual(g.nextWeek.map(\.station), ["next"])
        XCTAssertEqual(g.thisWeek[0].chip, "เลยกำหนด 4 วัน")
        XCTAssertEqual(g.thisWeek[0].tone, .late)
        XCTAssertEqual(g.thisWeek[0].subtitle.hasPrefix("MP 77 late"), true)
        XCTAssertTrue(g.hasLate)
        XCTAssertEqual(g.thisStart, day(2026, 10, 12))
        XCTAssertEqual(g.nextStart, day(2026, 10, 19))
    }

    func testWeekRunsMondayToSunday() {
        let sunday = station("sun", start: day(2026, 8, 1), end: day(2026, 10, 18))
        let monday = station("mon", start: day(2026, 8, 1), end: day(2026, 10, 19))
        let g = PWAPlan.groups(PWAPlan.deadlines([sunday, monday], today: today).filter { $0.kind == .handover }, today: today)
        XCTAssertEqual(g.thisWeek.map(\.station), ["sun"])
        XCTAssertEqual(g.nextWeek.map(\.station), ["mon"])
    }

    func testHandoverToneFollowsThePlan() {
        func tone(_ percentOfPlan: Double) -> (String, PWAPlan.Tone) {
            var s = station("s", start: day(2026, 8, 1), end: day(2026, 10, 30))
            let planned = MasterSchedule.status(plan: MasterSchedule.plan(s.input!), actual: s.actual, through: today).planned
            // book the progress task by task, since each one is capped at its weight
            var left = planned * percentOfPlan
            for t in MasterSchedule.Task.allCases where left > 0 {
                let v = min(left, t.weight(over200kVA: false))
                s.actual.set(v, task: t, week: day(2026, 9, 1), over200kVA: false)
                left -= v
            }
            let d = PWAPlan.deadlines([s], today: today).first { $0.kind == .handover }!
            return (d.chip, d.tone)
        }
        XCTAssertEqual(tone(1).0, "ตามแผน")
        XCTAssertEqual(tone(1).1, .ok)
        XCTAssertEqual(tone(0.99).0, "เสี่ยงช้า")
        XCTAssertEqual(tone(0.99).1, .risk)
        XCTAssertEqual(tone(0.5).0, "ช้ากว่าแผน")
        XCTAssertEqual(tone(0.5).1, .late)
    }

    func testHandedOverStationHasNoDeadlines() {
        var s = station("s", start: day(2026, 8, 1), end: day(2026, 10, 8))
        s.handedOver = true
        XCTAssertTrue(PWAPlan.deadlines([s], today: today).isEmpty)
    }

    func testSubmissionsComeFromThePlanAndClearWhenSubmitted() {
        var s = station("s", mp: 154, start: day(2026, 10, 1), end: day(2026, 12, 20), over200: true)
        s.docs.buildingRoute = .notify
        s.docsContext = StationDocs.Context(s.docs, inverterKW: 210)
        let plan = MasterSchedule.plan(s.input!)
        func docs(_ s: PWAPlan.Station, _ library: StationDocs.Library = .init()) -> [PWAPlan.Deadline] {
            PWAPlan.deadlines([s], library: library, today: today).filter { $0.kind == .document }
        }

        let open = docs(s)
        XCTAssertEqual(Set(open.map(\.title)), ["แจ้งเทศบาล (ยกเว้น ข.1)", "ยื่น พค.2 (กกพ.)", "ยื่นขอขนานไฟ"])
        XCTAssertEqual(open.first { $0.title.contains("พค.2") }?.date, plan.first { $0.task == .pk2 }?.start)
        // the building notice was due on the site handover day, before today
        XCTAssertEqual(open.first { $0.title.hasPrefix("แจ้งเทศบาล") }?.tone, .late)
        XCTAssertEqual(open.allSatisfy { $0.opens == .docs }, true)

        // a station under 200 kVA has no พค.2
        let small = station("small", start: day(2026, 10, 1), end: day(2026, 12, 20))
        XCTAssertFalse(docs(small).contains { $0.title.contains("พค.2") })

        // every paper of the grid package submitted: that deadline is closed
        var library = StationDocs.Library()
        for k in StationDocs.papers(in: .gridConnection, s.docsContext) {
            if k.scope.isShared { library.docs[k.id] = .init(status: .submitted) } else { s.docs.docs[k.id] = .init(status: .approved) }
        }
        XCTAssertFalse(docs(s, library).contains { $0.title == "ยื่นขอขนานไฟ" })

        // the task booked as done closes it too
        s.actual.setPercent(100, task: .pk2, week: today, over200kVA: true)
        XCTAssertFalse(docs(s, library).contains { $0.title.contains("พค.2") })
    }

    func testReadyPackageSaysSo() {
        var s = station("s", start: day(2026, 8, 1), end: day(2026, 10, 30))
        var library = StationDocs.Library()
        for k in StationDocs.papers(in: .gridConnection, s.docsContext) {
            if k.scope.isShared { library.docs[k.id] = .init(status: .signed) } else { s.docs.docs[k.id] = .init(status: .signed) }
        }
        let d = PWAPlan.deadlines([s], library: library, today: today).first { $0.title == "ยื่นขอขนานไฟ" }!
        XCTAssertEqual(d.chip, "พร้อมยื่น")
        XCTAssertEqual(d.tone, .ok)
    }

    // MARK: agenda

    func testAgendaHasOneInstallRowPerStationOnWorkingDays() {
        let a = station("a", mp: 189, start: day(2026, 9, 1), end: day(2026, 11, 15), contractor: "A")
        let week = (0..<7).map { cal.date(byAdding: .day, value: $0, to: today)! }
        let items = PWAPlan.agenda([a], deadlines: [], days: week, today: today)
        let installs = items.filter { $0.type == .install }
        // Monday to Saturday: Sunday is not a working day by default
        XCTAssertEqual(installs.count, 6)
        XCTAssertEqual(installs.first?.status, .doing)
        XCTAssertEqual(installs.last?.status, .onPlan)
        XCTAssertEqual(installs.first?.ref, "MP 189")
        XCTAssertEqual(installs.first?.title.hasPrefix("2."), true)
        XCTAssertEqual(installs.first?.subtitle.hasPrefix("a · ผู้รับเหมา A · TCR01"), true)
    }

    func testAgendaRemindsOnlyTodayAboutUnsentReports() {
        var a = station("a", start: day(2026, 9, 1), end: day(2026, 11, 15))
        var b = station("b", start: day(2026, 9, 1), end: day(2026, 11, 15))
        a.reportSentToday = false
        b.reportSentToday = true
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let items = PWAPlan.agenda([a, b], deadlines: [], days: [today, tomorrow], today: today)
        let notices = items.filter { $0.type == .notice }
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].day, today)
        XCTAssertEqual(notices[0].start, 16 * 60)
        XCTAssertEqual(notices[0].subtitle, "ยังไม่ส่ง 1 สถานี · a")
        XCTAssertEqual(notices[0].opens, .dailies)
        XCTAssertEqual(notices[0].station, "a")
        // the timed reminder comes after the day's untimed rows
        XCTAssertEqual(items.filter { $0.day == today }.last?.type, .notice)
    }

    func testAgendaShowsSurveyAppointmentAndDocumentDeadline() {
        var s = PWAPlan.Station(id: "s", code: "TC-0012", name: "สถานีผลิตน้ำ 1", team: "TCR02")
        s.surveyAt = day(2026, 10, 12, hour: 9, minute: 30)
        let due = PWAPlan.Deadline(id: "d", date: today, kind: .document, title: "ยื่น พค.2 (กกพ.)", subtitle: "", chip: "เอกสาร 1/3",
                                   tone: .risk, station: "s", opens: .docs)
        let items = PWAPlan.agenda([s], deadlines: [due], days: [today], today: today)
        XCTAssertEqual(items.map(\.type), [.document, .survey])
        XCTAssertEqual(items[1].start, 9 * 60 + 30)
        XCTAssertEqual(items[1].ref, "TC-0012")
        XCTAssertEqual(items[1].opens, .survey)
        XCTAssertEqual(items[0].status, .mustSubmit)
        XCTAssertEqual(items[0].subtitle, "1 · ครบกำหนดวันนี้")
    }

    func testTeamKeysAndFilter() {
        func item(_ contractor: String, _ team: String) -> PWAPlan.AgendaItem {
            .init(id: contractor + team, day: today, type: .install, ref: "", title: "", subtitle: "", status: .doing, contractor: contractor, team: team)
        }
        let items = [item("B", "TCR03"), item("A", "TCR01"), item("C", ""), item("", "")]
        XCTAssertEqual(PWAPlan.teamKeys(items), ["A", "B", "C", "TC"])
        XCTAssertEqual(items.filter { PWAPlan.matches($0, team: "A") }.count, 1)
        XCTAssertEqual(items.filter { PWAPlan.matches($0, team: "TC") }.count, 2)
        XCTAssertEqual(items.filter { PWAPlan.matches($0, team: nil) }.count, 4)
    }

    func testShortNameAndSearch() {
        XCTAssertEqual(PWAPlan.shortName("สถานีผลิตน้ำทุ่งน้อย · สาขาเมืองพล"), "ทุ่งน้อย")
        XCTAssertEqual(PWAPlan.shortName("การประปาวัดชัย"), "วัดชัย")
        XCTAssertEqual(PWAPlan.shortName("สถานี"), "สถานี")
        XCTAssertEqual(PWAPlan.clock(8 * 60 + 5), "08:05")
        let bar = PWAPlan.bars([station("a", mp: 189, start: day(2026, 9, 1), end: day(2026, 11, 15))], today: today)[0]
        XCTAssertTrue(bar.matches(search: "189"))
        XCTAssertTrue(bar.matches(search: " "))
        XCTAssertFalse(bar.matches(search: "วัดชัย"))
    }

    func testBarsSortByDueDate() {
        let a = station("a", start: day(2026, 9, 1), end: day(2026, 11, 15))
        let b = station("b", start: day(2026, 8, 1), end: day(2026, 10, 15))
        XCTAssertEqual(PWAPlan.bars([a, b, PWAPlan.Station(id: "x", name: "x")], today: today).map(\.id), ["b", "a"])
    }
}
