import XCTest
@testable import TCRoofCore

/// docs/ui/tcroof-home-iphone-v3: the project feed, on a week of October 2026 (ต.ค. 2569).
final class ProjectFeedTests: XCTestCase {
    private let cal = FeedBuilder.calendar

    private func d(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func daily(_ day: Int, _ lines: [(MasterSchedule.Task?, String, Double)], problems: [RoutineReport.Problem] = []) -> RoutineReport.Daily {
        var r = RoutineReport.Daily(date: d(day))
        r.progress = lines.map { .init(task: $0.0, description: "", location: $0.1, percent: $0.2) }
        r.problems = problems
        return r
    }

    /// A PWA station installing 5–16 ต.ค., every day a working day.
    private func station(_ id: String = "a", team: String = "TCR01", mp: Int? = 189, reports: [FeedBuilder.Report] = []) -> FeedBuilder.Station {
        var s = FeedBuilder.Station(id: id, code: "TC-00" + id, name: "ทุ่งน้อย", project: .pwa, team: team, mpNumber: mp,
                                    installStart: d(5), installDays: 12)
        s.settings.workingWeekdays = [1, 2, 3, 4, 5, 6, 7]
        s.reports = reports
        return s
    }

    private func home(_ punches: [HomePunch]) -> FeedBuilder.Station {
        var s = FeedBuilder.Station(id: "h", code: "TC-0012", name: "บ้านตัวอย่าง", project: .home, team: "TCR02", installStart: d(11), installDays: 5)
        s.punches = punches
        s.contractor = "ช่างตัวอย่าง"
        return s
    }

    /// The feed without the daily summaries, which have their own tests.
    private func records(_ stations: [FeedBuilder.Station], now: Date, days: Int = FeedBuilder.windowDays) -> [FeedPost] {
        FeedBuilder.posts(stations, now: now, days: days).filter { $0.kind != .summary }
    }

    private func punch(_ title: String, raised: Date?, due: Date? = nil, after: [String] = [], closed: Date? = nil) -> HomePunch {
        var p = HomePunch(title: title, raised: raised)
        p.due = due; p.after = after; p.closed = closed
        return p
    }

    // MARK: Daily reports

    func testASignedReportBecomesAProgressPostAndADraftDoesNot() {
        let s = station(reports: [
            .init(daily(11, [(.panels, "หลังคา 1", 32)]), signedAt: d(11, 17), recorder: "สมชาย"),
            .init(daily(12, [(.panels, "หลังคา 1", 38)]), signedAt: d(12, 16, 35), recorder: "สมชาย", photos: ["p1", "p2"]),
            .init(daily(13, [(.panels, "หลังคา 1", 50)]), signedAt: nil),
        ])
        let posts = records([s], now: d(12, 17))
        XCTAssertEqual(posts.map(\.id), ["daily-a-2026-10-12", "daily-a-2026-10-11"])
        let p = posts[0]
        XCTAssertEqual(p.kind, .progress)
        XCTAssertEqual(p.who, "ทีม TCR01 · สมชาย")
        XCTAssertEqual(p.initials, "1")
        XCTAssertTrue(p.place.hasPrefix("MP 189 ทุ่งน้อย · 2.3 "))
        XCTAssertEqual(p.photos, ["p1", "p2"])
        XCTAssertEqual(p.chips.first, .init("+6% วันนี้", .green))
        XCTAssertEqual(p.source, .dailyReport(project: "a", day: d(12)))
        XCTAssertEqual(FeedBuilder.when(p, now: d(12, 17)), "25 นาที")
    }

    func testThePlanChipIsRedWhenTheTaskIsBehind() throws {
        let input = MasterSchedule.Input(installStart: d(5), installEnd: d(16), kickoff: d(1), engineeringStart: d(1), siteHandover: d(4), over200kVA: false)
        var s = station(reports: [.init(daily(12, [(.panels, "หลังคา 1", 5)]), signedAt: d(12, 16))])
        s.plan = MasterSchedule.plan(input)
        let planned = try XCTUnwrap(MasterSchedule.status(plan: s.plan, actual: .init(), through: d(12)).plannedByTask[.panels])
        try XCTSkipIf(planned <= 5, "the plan has not reached the panels by 12 ต.ค.")
        let chip = try XCTUnwrap(records([s], now: d(12, 17)).first?.chips.last)
        XCTAssertEqual(chip.tone, .red)
        XCTAssertEqual(chip.text, "5% / แผน \(RoutineReport.percent(planned))")
    }

    func testALineFinishedTodayWaitsForTheInspectorUntilAcknowledged() {
        let reports = [daily(11, [(.inverter, "ห้องอินเวอร์เตอร์", 60)]), daily(12, [(.inverter, "ห้องอินเวอร์เตอร์", 100)])]
        var s = station(reports: [.init(reports[0], signedAt: d(11, 17)), .init(reports[1], signedAt: d(12, 15))])
        XCTAssertEqual(records([s], now: d(12, 17)).map(\.kind), [.waitingInspector, .progress])
        s.reports[1].inspectorAckAt = d(12, 16)
        XCTAssertEqual(records([s], now: d(12, 17)).map(\.kind), [.progress, .progress])
    }

    func testAStoppedDayShowsItsReason() {
        var r = daily(12, [])
        r.stopReason = "ฝนตกทั้งวัน"
        let p = records([station(reports: [.init(r, signedAt: d(12, 12))])], now: d(12, 13))[0]
        XCTAssertEqual(p.text, "หยุดงาน: ฝนตกทั้งวัน")
        XCTAssertTrue(p.chips.isEmpty)
    }

    // MARK: Tests and issues

    func testATestRecordBecomesAnAutomaticPostWithTiles() {
        var s = station(mp: 77)
        s.tests = [.init(id: "t", date: d(12, 16), title: "ผลทดสอบ IEC 62446", unit: "สตริง", passed: 12, total: 12,
                         extra: [.init("> 40 MΩ", "ฉนวน", .blue), .init("171 kWp", "กำลังติดตั้ง", .blue), .init("x", "y", .blue)])]
        let p = records([s], now: d(12, 17))[0]
        XCTAssertEqual(p.kind, .testResult)
        XCTAssertEqual(p.text, "ผลทดสอบ IEC 62446 ผ่านครบ 12 สตริง")
        XCTAssertEqual(p.stats.map(\.value), ["12/12", "> 40 MΩ", "171 kWp"])
        XCTAssertEqual(p.stats[0].tone, .green)
        XCTAssertEqual(p.kind.link, "ดูผลทดสอบ")
    }

    func testAReportProblemIsAnIssueDatedByTheReportThatRaisedIt() {
        let problem = RoutineReport.Problem(description: "ท่อร้อยสายไม่พอ", since: d(11))
        var s = station(reports: [.init(daily(11, [(.dcSide, "หลังคา 1", 10)], problems: [problem]), signedAt: d(11, 17), recorder: "สมชาย"),
                                  .init(daily(12, [(.dcSide, "หลังคา 1", 20)], problems: [problem]), signedAt: d(12, 16), recorder: "สมชาย")])
        s.settings.siteEngineer = "วิศวกรตัวอย่าง"
        let issues = FeedBuilder.posts([s], now: d(12, 17)).filter { $0.kind == .issue }
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].date, d(11, 17))
        XCTAssertEqual(issues[0].issue, .init(owner: "วิศวกรตัวอย่าง", fixed: false))
        XCTAssertEqual(issues[0].source, .problem(project: "a", id: problem.id))
    }

    func testFixingAProblemWritesTheLatestReportOnlyAndReopens() {
        let problem = RoutineReport.Problem(description: "ท่อร้อยสายไม่พอ", since: d(11))
        var reports = [daily(11, [], problems: [problem]), daily(12, [], problems: [problem])]
        XCTAssertTrue(FeedBuilder.setProblem(problem.id, fixed: true, in: &reports))
        XCTAssertEqual(reports.map { $0.problems[0].closed }, [false, true])
        var s = station(reports: reports.map { .init($0, signedAt: $0.date.addingTimeInterval(17 * 3600)) })
        XCTAssertEqual(FeedBuilder.posts([s], now: d(12, 17)).first { $0.kind == .issue }?.issue?.fixed, true)
        XCTAssertTrue(FeedBuilder.setProblem(problem.id, fixed: false, in: &reports))
        s.reports = reports.map { .init($0, signedAt: $0.date.addingTimeInterval(17 * 3600)) }
        XCTAssertEqual(FeedBuilder.posts([s], now: d(12, 17)).first { $0.kind == .issue }?.issue?.fixed, false)
        XCTAssertFalse(FeedBuilder.setProblem(UUID(), fixed: true, in: &reports))
    }

    func testAHomePunchIsAnIssueWithItsOwnerAndDueDate() {
        let s = home([punch("รอยรั่วที่ครอบหลังคา", raised: d(12, 14), due: d(13)), punch("", raised: d(12, 14)), punch("เก่า", raised: nil)])
        let posts = records([s], now: d(12, 17))
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts[0].who, "ทีม TCR02 · งานบ้าน")
        XCTAssertEqual(posts[0].place, "TC-0012 · ติดตั้ง Day 2/5")
        XCTAssertEqual(posts[0].issue, .init(owner: "ช่างตัวอย่าง", due: d(13), fixed: false, canFix: false))
        XCTAssertEqual(FeedBuilder.when(posts[0], now: d(12, 17)), "3 ชม.")
    }

    func testClosingAPunchNeedsAPhotoOfTheFix() {
        var site = HomeSite()
        site.punches = [punch("รอยรั่ว", raised: d(12)), punch("ท่อ", raised: d(12), after: ["a.jpg"])]
        XCTAssertFalse(FeedBuilder.setPunch(site.punches[0].id, fixed: true, in: &site, at: d(13)))
        XCTAssertNil(site.punches[0].closed)
        XCTAssertTrue(FeedBuilder.setPunch(site.punches[1].id, fixed: true, in: &site, at: d(13)))
        XCTAssertEqual(site.punches[1].closed, d(13))
        XCTAssertTrue(FeedBuilder.setPunch(site.punches[1].id, fixed: false, in: &site, at: d(13)))
        XCTAssertNil(site.punches[1].closed)
    }

    func testAnOldPunchWithoutARaisedDateStillDecodes() throws {
        let p = try JSONDecoder().decode(HomePunch.self, from: Data(#"{"id":"x","title":"ท่อ"}"#.utf8))
        XCTAssertNil(p.raised)
    }

    // MARK: Summary and order

    private var week: [FeedBuilder.Station] {
        [station("a", reports: [.init(daily(11, [(.panels, "หลังคา 1", 30)]), signedAt: d(11, 17)),
                                .init(daily(12, [(.panels, "หลังคา 1", 40)]), signedAt: d(12, 16))]),
         station("b", team: "TCR03", mp: 154, reports: [.init(daily(12, [(.panels, "หลังคา 1", 10)]), signedAt: nil)]),
         home([punch("รอยรั่ว", raised: d(12, 14), due: d(13))])]
    }

    func testNoSummaryBeforeSixInTheEvening() {
        XCTAssertFalse(FeedBuilder.posts(week, now: d(12, 17, 59)).contains { $0.id == "summary-2026-10-12" })
        XCTAssertTrue(FeedBuilder.posts(week, now: d(12, 18)).contains { $0.id == "summary-2026-10-12" })
    }

    func testTheSummaryCountsReportsProgressAndOpenIssuesAndStaysOnTop() throws {
        let posts = FeedBuilder.posts(week, now: d(12, 19))
        let top = try XCTUnwrap(posts.first)
        XCTAssertEqual(top.kind, .summary)
        XCTAssertTrue(top.pinned)
        XCTAssertNil(top.project)
        // a sent, b only drafted; a moved 10 points and b none
        XCTAssertEqual(top.stats.map(\.value), ["1/2", "+5%", "1"])
        XCTAssertEqual(top.stats.map(\.tone), [.blue, .green, .red])
        XCTAssertEqual(top.text, "สรุปวันที่ 12 ต.ค. — ส่งรายงานแล้ว 1/2 สถานี กปภ. ความคืบหน้ารวม +5% ปัญหาค้าง 1 เรื่อง (งานบ้าน TC-0012)")
        XCTAssertEqual(FeedBuilder.when(top, now: d(12, 19)), "18:00")
        XCTAssertEqual(posts.filter { $0.kind == .summary }.count, 1)
        let rest = Array(posts.dropFirst())
        XCTAssertEqual(rest.map(\.date), rest.map(\.date).sorted(by: >))
    }

    func testTheNextMorningShowsYesterdaysSummaryInDateOrder() throws {
        let posts = FeedBuilder.posts(week, now: d(13, 9))
        let summary = try XCTUnwrap(posts.first { $0.kind == .summary })
        XCTAssertEqual(summary.id, "summary-2026-10-12")
        XCTAssertFalse(summary.pinned)
        XCTAssertEqual(posts.map(\.date), posts.map(\.date).sorted(by: >))
        XCTAssertEqual(FeedBuilder.when(summary, now: d(13, 9)), "12 ต.ค. 18:00")
    }

    func testOnlyTheLastSevenDaysUnlessMoreAreAsked() {
        let s = station(reports: [.init(daily(5, [(.structure, "หลังคา 1", 10)]), signedAt: d(5, 17)),
                                  .init(daily(6, [(.structure, "หลังคา 1", 20)]), signedAt: d(6, 17))])
        let now = d(12, 12)
        let ids = { (days: Int) in FeedBuilder.posts([s], now: now, days: days).filter { $0.kind == .progress }.map(\.id) }
        XCTAssertEqual(ids(7), ["daily-a-2026-10-06"])
        XCTAssertEqual(ids(14), ["daily-a-2026-10-06", "daily-a-2026-10-05"])
    }

    // MARK: Filters and text

    func testFiltersKeepTheSummaryAndCountWhatTheyShow() {
        let posts = FeedBuilder.posts(week, now: d(12, 19), days: 1)
        XCTAssertEqual(posts.map(\.kind), [.summary, .progress, .issue])
        XCTAssertEqual(FeedBuilder.filter(posts, by: .pwa).map(\.kind), [.summary, .progress])
        XCTAssertEqual(FeedBuilder.filter(posts, by: .home).map(\.kind), [.summary, .issue])
        XCTAssertEqual(FeedBuilder.filter(posts, by: .mine, myTeams: ["TCR02"]).map(\.kind), [.summary, .issue])
        XCTAssertEqual(FeedBuilder.counts(posts, myTeams: ["TCR01"]), [.all: 3, .pwa: 2, .home: 2, .mine: 2])
        XCTAssertEqual(FeedBuilder.filter(posts, by: .all, hidden: [posts[1].id]).map(\.kind), [.summary, .issue])
    }

    func testAcknowledgementLine() {
        XCTAssertEqual(FeedBuilder.ackLine(count: 5, mine: false), "5 คนรับทราบ")
        XCTAssertEqual(FeedBuilder.ackLine(count: 6, mine: true), "คุณและอีก 5 คนรับทราบ")
        XCTAssertEqual(FeedBuilder.ackLine(count: 1, mine: true), "คุณรับทราบแล้ว")
        XCTAssertEqual(FeedBuilder.ackLine(count: 0, mine: false), "ยังไม่มีคนรับทราบ")
    }

    func testAgeAndInitials() {
        let post = records([home([punch("รอยรั่ว", raised: d(10, 9))])], now: d(12, 12))[0]
        XCTAssertEqual(FeedBuilder.when(post, now: d(12, 12)), "10 ต.ค.")
        XCTAssertEqual(FeedBuilder.when(post, now: d(10, 9)), "เมื่อสักครู่")
        XCTAssertEqual(FeedBuilder.initials(team: "TCR03"), "3")
        XCTAssertEqual(FeedBuilder.initials(team: "TCR10"), "10")
        XCTAssertEqual(FeedBuilder.initials(team: "bravo"), "B")
        XCTAssertEqual(FeedBuilder.initials(team: ""), "TC")
    }
}
