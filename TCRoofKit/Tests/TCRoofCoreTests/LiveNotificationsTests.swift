import XCTest
@testable import TCRoofCore

/// Install days, the MP plan and the project feed's events as notifications, on a week of October 2026.
final class LiveNotificationsTests: XCTestCase {
    private let cal = FeedBuilder.calendar

    private func d(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func post(_ id: String, _ kind: FeedPost.Kind, at date: Date, recorder: String = "", issue: FeedPost.Issue? = nil,
                      source: FeedPost.Source? = nil) -> FeedPost {
        FeedPost(id: id, kind: kind, project: .pwa, team: "TCR01", recorder: recorder, initials: "1", who: "ทีม TCR01", place: "MP 189 ทุ่งน้อย",
                 date: date, text: "ติดตั้งแผง 40%", issue: issue, source: source ?? .dailyReport(project: "j", day: d(13)))
    }

    // MARK: install days

    func testInstallDaysFireBeforeTheStartAndShareTheBellID() {
        // five days from Tuesday 13 ต.ค. 08:00, seen on Monday morning
        let plans = InstallNotification.plans(jobKey: "j", name: "TC-0012 บ้านตัวอย่าง", team: "TCR01", start: d(13, 8), days: 5, now: d(12, 9), calendar: cal)
        XCTAssertEqual(plans.map(\.id), ["install-eve-j-2026-10-13", "install-j-2026-10-13"])
        XCTAssertEqual(plans[0].title, "เริ่มติดตั้งพรุ่งนี้")
        XCTAssertEqual(plans[0].fire, .at(d(12, 18)))
        XCTAssertEqual(plans[1].title, "ติดตั้ง Day 1/5")
        XCTAssertEqual(plans[1].fire, .at(d(13, 7, 30)))
        XCTAssertEqual(plans[1].sub, "ทีม TCR01 · เริ่ม 08:00")
        XCTAssertEqual(plans[1].bellID, "install-j-2026-10-13")
        XCTAssertEqual(plans.map(\.type), [.install, .install])
    }

    func testInstallDaysStopAfterTheLastDayAndSkipAPastReminder() {
        // day 2 has started: only tomorrow's day 3 is left to announce
        let mid = InstallNotification.plans(jobKey: "j", name: "n", team: "", start: d(13, 8), days: 3, now: d(14, 9), calendar: cal)
        XCTAssertEqual(mid.map(\.title), ["ติดตั้ง Day 3/3"])
        XCTAssertEqual(mid[0].sub, "เริ่ม 08:00")
        XCTAssertTrue(InstallNotification.plans(jobKey: "j", name: "n", team: "", start: d(13, 8), days: 3, now: d(15, 9), calendar: cal).isEmpty)
        XCTAssertEqual(DeepLink.route(type: .install, action: nil, info: mid[0].info), .job(job: "j"))
        XCTAssertEqual(DeepLink.route(type: .install, action: NotificationAction.navigate.rawValue, info: mid[0].info), .navigate(job: "j"))
    }

    // MARK: MP plan

    private var input: MasterSchedule.Input {
        MasterSchedule.Input(installStart: d(13), installEnd: d(13).addingTimeInterval(59 * 86_400), kickoff: d(1), engineeringStart: d(2),
                             siteHandover: d(6), over200kVA: false)
    }

    func testMPAnnouncesTasksStartingTomorrow() throws {
        let plan = MasterSchedule.plan(input, calendar: cal)
        let starting = plan.filter { $0.start == d(13) }
        XCTAssertFalse(starting.isEmpty)
        let plans = MPNotification.plans(jobKey: "j", station: "ทุ่งน้อย", plan: plan, actual: .init(), now: d(12, 9), calendar: cal)
        let start = try XCTUnwrap(plans.first { $0.id.hasPrefix("mp-start-j-") })
        XCTAssertEqual(start.title, "เริ่มงานพรุ่งนี้ตามแผน MP")
        XCTAssertEqual(start.fire, .at(d(12, 17)))
        XCTAssertTrue(start.sub.hasPrefix("\(starting[0].task.code) \(starting[0].task.title)"))
        // after 17:00 it is too late for the eve
        XCTAssertFalse(MPNotification.plans(jobKey: "j", station: "", plan: plan, actual: .init(), now: d(12, 18), calendar: cal)
            .contains { $0.id.hasPrefix("mp-start") })
        XCTAssertEqual(DeepLink.route(type: .mp, action: nil, info: start.info), .job(job: "j"))
    }

    func testMPWarnsOnceAWeekWhileBehindThePlan() throws {
        let plan = MasterSchedule.plan(input, calendar: cal)
        // Wednesday 28 ต.ค., the third week of the install, nothing recorded
        let now = d(28, 9)
        let behind = try XCTUnwrap(MPNotification.plans(jobKey: "j", station: "ทุ่งน้อย", plan: plan, actual: .init(), now: now, calendar: cal)
            .first { $0.id.hasPrefix("mp-behind-j-") })
        XCTAssertTrue(behind.title.hasPrefix("ช้ากว่าแผน MP "))
        XCTAssertEqual(behind.fire, .at(cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8))!))
        // the same id all week, so it is posted once
        let later = MPNotification.plans(jobKey: "j", station: "ทุ่งน้อย", plan: plan, actual: .init(), now: d(30, 9), calendar: cal)
        XCTAssertEqual(later.first { $0.id.hasPrefix("mp-behind") }?.id, behind.id)
        // nothing planned yet: no warning
        XCTAssertFalse(MPNotification.plans(jobKey: "j", station: "", plan: [], actual: .init(), now: now, calendar: cal).contains { $0.type == .mp })
    }

    // MARK: feed

    func testANewPostIsAnnouncedOnceWithItsOwnID() {
        let now = d(13, 15)
        let posts = [post("daily-j-2026-10-13", .progress, at: d(13, 14)), post("old", .progress, at: d(11, 14)),
                     post("mine", .progress, at: d(13, 14, 30), recorder: "สมชาย"), post("summary-2026-10-12", .summary, at: d(12, 18))]
        let fresh = FeedNotification.fresh(posts, seen: [], me: "สมชาย", now: now)
        XCTAssertEqual(fresh.map(\.id), ["daily-j-2026-10-13"])
        XCTAssertEqual(fresh[0].type, .feed)
        XCTAssertEqual(fresh[0].title, "ส่งรายงานประจำวันแล้ว")
        XCTAssertEqual(fresh[0].text, "MP 189 ทุ่งน้อย\nติดตั้งแผง 40%")
        XCTAssertEqual(fresh[0].fire, .after(1))
        XCTAssertEqual(fresh[0].bellID, "daily-j-2026-10-13")
        XCTAssertTrue(FeedNotification.fresh(posts, seen: ["daily-j-2026-10-13"], me: "สมชาย", now: now).isEmpty)
        // nobody named: every recent post counts
        XCTAssertEqual(FeedNotification.fresh(posts, seen: [], me: "", now: now).map(\.id), ["mine", "daily-j-2026-10-13"])
    }

    func testKindsPickTheTypeAndABurstIsCapped() {
        XCTAssertEqual(FeedNotification.type(.issue), .issue)
        XCTAssertEqual(FeedNotification.type(.waitingInspector), .inspect)
        XCTAssertEqual(FeedNotification.type(.testResult), .feed)
        // a banner without a sound
        XCTAssertEqual(NotificationType.feed.level, .active)
        XCTAssertTrue(NotificationType.feed.silent)
        XCTAssertFalse(NotificationType.issue.silent)
        XCTAssertEqual(NotificationGroup.feed.types, [.feed, .issue, .inspect])
        XCTAssertEqual(NotificationGroup.plan.types, [.install, .mp])
        let many = (0..<8).map { post("p\($0)", .progress, at: d(13, 10, $0)) }
        XCTAssertEqual(FeedNotification.fresh(many, seen: [], me: "", now: d(13, 15)).map(\.id), ["p7", "p6", "p5", "p4", "p3"])
        // an issue first seen already fixed says nothing
        let fixed = post("x", .issue, at: d(13, 10), issue: .init(owner: "", fixed: true))
        XCTAssertTrue(FeedNotification.fresh([fixed], seen: [], me: "", now: d(13, 15)).isEmpty)
    }

    func testAnOpenIssueRemindsOnItsDueDay() {
        let open = post("punch-h-1", .issue, at: d(12, 10), issue: .init(owner: "ช่าง", due: d(14), fixed: false), source: .punch(project: "h", id: "1"))
        let fixed = post("punch-h-2", .issue, at: d(12, 10), issue: .init(owner: "ช่าง", due: d(14), fixed: true), source: .punch(project: "h", id: "2"))
        let due = FeedNotification.due([open, fixed], now: d(13, 9))
        XCTAssertEqual(due.map(\.id), ["due-punch-h-1"])
        XCTAssertEqual(due[0].fire, .at(d(14, 8)))
        XCTAssertEqual(due[0].title, "ครบกำหนดแก้วันนี้")
        XCTAssertEqual(due[0].bellID, "punch-h-1")
        XCTAssertEqual(due[0].type, .issue)
        XCTAssertTrue(FeedNotification.due([open], now: d(14, 9)).isEmpty)
    }

    func testTheSummaryIsScheduledForSixWithTheFeedPostsID() {
        var s = FeedBuilder.Station(id: "a", code: "TC-00a", name: "ทุ่งน้อย", project: .pwa, team: "TCR01", mpNumber: 189, installStart: d(5), installDays: 12)
        s.settings.workingWeekdays = [1, 2, 3, 4, 5, 6, 7]
        let plan = FeedNotification.summary([s], now: d(13, 9))
        XCTAssertEqual(plan?.id, "summary-2026-10-13")
        XCTAssertEqual(plan?.fire, .at(d(13, 18)))
        XCTAssertEqual(plan?.title, "สรุปวันนี้")
        XCTAssertTrue(plan?.body.hasPrefix("สรุปวันที่ 13 ต.ค.") == true)
        XCTAssertNil(FeedNotification.summary([s], now: d(13, 19)))
        XCTAssertNil(FeedNotification.summary([], now: d(13, 9)))
    }

    func testAFeedNotificationOpensThePostsRecord() {
        func link(_ p: FeedPost) -> DeepLink { DeepLink.route(type: FeedNotification.type(p.kind), action: nil, info: FeedNotification.plan(p).info) }
        XCTAssertEqual(link(post("a", .progress, at: d(13, 10))), .daily(job: "j", day: d(13)))
        XCTAssertEqual(link(post("b", .waitingInspector, at: d(13, 10))), .job(job: "j"))
        XCTAssertEqual(link(post("c", .testResult, at: d(13, 10), source: .test(project: "j", id: "icl"))), .inspection(job: "j"))
        XCTAssertEqual(link(post("d", .issue, at: d(13, 10), source: .problem(project: "j", id: UUID()))), .job(job: "j"))
        XCTAssertEqual(link(post("e", .issue, at: d(13, 10), source: .punch(project: "h", id: "1"))), .homework(job: "h"))
        XCTAssertEqual(link(post("f", .summary, at: d(13, 18), source: .summary(day: d(13)))), .records)
        XCTAssertEqual(DeepLink.route(type: .feed, action: nil, info: [:]), .home)
    }

    func testCalibrationRemindersShareOneBellRow() {
        let due = d(30)
        let plans = ToolNotification.scheduleCalibration(toolID: "t", tool: "Fluke 1587 FC", kind: "เครื่องวัดฉนวน", due: due, now: d(1))
        XCTAssertEqual(plans.count, 1)   // 30 days before is 30 ก.ย., already past
        XCTAssertEqual(plans[0].bellID, ToolNotification.calibrationBellID(toolID: "t", due: due))
        XCTAssertEqual(plans[0].bellID, "cal-t-2026-10-30")
    }
}
