import XCTest
@testable import TCRoofCore

final class SystemNotificationsTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: ids

    func testSurveyIDMatchesTheBell() {
        let at = date(2026, 10, 4, 10, 30)
        XCTAssertEqual(NotificationPlan.surveyID(jobKey: "abc", appointment: at), "survey-abc-2026-10-04")
        let plan = NotificationPlan.survey(jobKey: "abc", name: "NO.224 สถานีผลิตน้ำ 1", area: "ต.หนองบัว อ.เมือง", appointment: at)
        XCTAssertEqual(plan.id, "survey-abc-2026-10-04")
        XCTAssertEqual(plan.bellID, plan.id)
        XCTAssertEqual(plan.fire, .at(date(2026, 10, 4, 10, 0)))
        XCTAssertEqual(plan.title, "นัดสำรวจในอีก 30 นาที")
        XCTAssertEqual(plan.text, "NO.224 สถานีผลิตน้ำ 1\nต.หนองบัว อ.เมือง · 10:30")
        XCTAssertEqual(plan.info[NotificationInfo.job], "abc")
    }

    func testSurveySnoozeKeepsIDAndCountsDown() {
        let at = date(2026, 10, 4, 10, 30)
        let plan = NotificationPlan.survey(jobKey: "abc", name: "n", area: "", appointment: at, fireAt: date(2026, 10, 4, 10, 10))
        XCTAssertEqual(plan.id, "survey-abc-2026-10-04")
        XCTAssertEqual(plan.title, "นัดสำรวจในอีก 20 นาที")
        XCTAssertEqual(plan.sub, "10:30")
        XCTAssertEqual(NotificationPlan.surveyTitle(minutes: 0), "ถึงเวลานัดสำรวจ")
    }

    func testSavedIDMatchesTheBell() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let at = Date(timeIntervalSince1970: 1_790_000_000.1234)
        XCTAssertEqual(NotificationPlan.savedID(report: id, savedAt: at), "saved-00000000-0000-0000-0000-000000000001-1790000000123")
        let plan = NotificationPlan.driveSaved(report: id, savedAt: at, name: "NO.224", files: ["PDF", "Excel", "ข้อมูล", "รูป"],
                                               folder: "TCRoof/NO.224", url: "https://drive.google.com/drive/folders/x")
        XCTAssertEqual(plan.body, "NO.224 แบบสำรวจ · 4 ไฟล์ (PDF · Excel · ข้อมูล · รูป)")
        XCTAssertEqual(plan.sub, "โฟลเดอร์ TCRoof/NO.224")
        XCTAssertEqual(plan.fire, .after(1))
    }

    // MARK: sync

    func testSyncWaitsTwoHoursThenShowsOnceThenEvening() {
        let now = date(2026, 10, 4, 15, 0)
        let fresh = NotificationPlan.syncPending(names: ["NO.224", "NO.221"], oldest: date(2026, 10, 4, 14, 0), now: now, alreadyShown: false)
        XCTAssertEqual(fresh.id, "sync-pending")
        XCTAssertEqual(fresh.fire, .at(date(2026, 10, 4, 16, 0)))
        XCTAssertEqual(fresh.title, "รอซิงก์ 2 งาน")
        XCTAssertEqual(fresh.text, "ยังไม่ได้บันทึกขึ้น Google Drive\nNO.224 · NO.221 · จะซิงก์เองเมื่อมีสัญญาณ")
        XCTAssertEqual(fresh.bellID, "sync-2026-10-04-2")

        let old = NotificationPlan.syncPending(names: ["NO.224"], oldest: date(2026, 10, 4, 9, 0), now: now, alreadyShown: false)
        XCTAssertEqual(old.fire, .after(1))
        let shown = NotificationPlan.syncPending(names: ["NO.224"], oldest: date(2026, 10, 4, 9, 0), now: now, alreadyShown: true)
        XCTAssertEqual(shown.fire, .at(date(2026, 10, 4, 20, 0)))
        let late = NotificationPlan.syncPending(names: ["NO.224"], oldest: date(2026, 10, 4, 9, 0), now: date(2026, 10, 4, 21, 0), alreadyShown: true)
        XCTAssertEqual(late.fire, .at(date(2026, 10, 5, 20, 0)))
        XCTAssertEqual(late.bellID, "sync-2026-10-05-1")
    }

    func testSyncListsAtMostThreeNames() {
        let p = NotificationPlan.syncPending(names: ["A", "B", "C", "D", "E"], oldest: .now, now: .now, alreadyShown: false)
        XCTAssertEqual(p.sub, "A · B · C +2 · จะซิงก์เองเมื่อมีสัญญาณ")
    }

    // MARK: tools

    func testQueueReached() {
        let p = ToolNotification.notifyQueueReached(toolID: "t1", tool: "DJI Mavic 3T", from: "สมชาย", place: "ห้องเก็บเครื่องมือ",
                                                    job: "NO.230", until: date(2026, 10, 9))
        XCTAssertEqual(p.id, "queue-t1")
        XCTAssertEqual(p.title, "ถึงคิวคุณ · DJI Mavic 3T")
        XCTAssertEqual(p.body, "สมชายคืนเครื่องและส่งต่อให้คุณ รับได้ที่ห้องเก็บเครื่องมือ")
        XCTAssertEqual(p.sub, "งาน NO.230 · ใช้ได้ถึง 9/10")
    }

    func testOverdueAt8EachDay() {
        let plans = ToolNotification.notifyOverdue(toolID: "f", tool: "Fluke 376 FC", due: date(2026, 9, 29), waiting: "สมชาย",
                                                   waitingFrom: date(2026, 10, 1), now: date(2026, 9, 29, 12, 0), days: 3)
        XCTAssertEqual(plans.map(\.id), ["late-f-2026-09-30", "late-f-2026-10-01", "late-f-2026-10-02"])
        XCTAssertEqual(plans[0].fire, .at(date(2026, 9, 30, 8, 0)))
        XCTAssertEqual(plans[0].title, "เกินกำหนดคืน · Fluke 376 FC")
        XCTAssertEqual(plans[0].body, "เกิน 1 วัน (กำหนด 29/9) · สมชายรอใช้ต่อ 1/10")
        XCTAssertEqual(plans[0].sub, "แตะเพื่อคืนพร้อมถ่ายภาพ 3 ภาพ")
        XCTAssertEqual(plans[2].body, "เกิน 3 วัน (กำหนด 29/9) · สมชายรอใช้ต่อ 1/10")
    }

    func testCalibration30And7DaysBefore() {
        let due = date(2026, 12, 20)
        let plans = ToolNotification.scheduleCalibration(toolID: "c", tool: "Fluke 1587 FC", kind: "เครื่องวัดฉนวน", due: due, now: date(2026, 10, 1))
        XCTAssertEqual(plans.map(\.fire), [.at(date(2026, 11, 20, 9, 0)), .at(date(2026, 12, 13, 9, 0))])
        XCTAssertEqual(plans[0].body, "Fluke 1587 FC เครื่องวัดฉนวน · ครบ 20/12/2569")
        XCTAssertEqual(plans[0].sub, "เหลือ 30 วัน · จองส่งสอบเทียบล่วงหน้า")
        XCTAssertEqual(plans[1].sub, "เหลือ 7 วัน · จองส่งสอบเทียบล่วงหน้า")
        // the 30-day reminder has passed
        XCTAssertEqual(ToolNotification.scheduleCalibration(toolID: "c", tool: "x", kind: "", due: due, now: date(2026, 12, 1)).count, 1)
    }

    // MARK: categories

    func testCategoriesAndLevels() {
        XCTAssertEqual(NotificationType.survey.actions.map(\.title), ["นำทาง", "เปิดแบบสำรวจ", "เตือนอีก 10 นาที"])
        XCTAssertEqual(NotificationType.queue.actions.map(\.title), ["รับเครื่อง · ถ่ายภาพตอนยืม", "ดูคิว", "สละคิว"])
        XCTAssertEqual(NotificationType.late.actions.map(\.title), ["คืนอุปกรณ์", "ขอขยายเวลา 1 วัน", "โทรหาผู้รอคิว"])
        XCTAssertEqual(NotificationType.cal.actions.map(\.title), ["เปิดทะเบียนเครื่อง", "เตือนอีก 7 วัน"])
        XCTAssertEqual(NotificationType.sync.actions.map(\.title), ["ซิงก์ตอนนี้", "ดูรายการ"])
        XCTAssertEqual(NotificationType.done.actions.map(\.title), ["เปิดใน Drive", "แชร์ลิงก์"])
        XCTAssertEqual(NotificationAction.leaveQueue.mode, .destructive)
        XCTAssertEqual([NotificationAction.remind10Minutes, .remind7Days, .syncNow].map(\.mode), [.background, .background, .background])
        XCTAssertEqual(NotificationAction.navigate.mode, .foreground)
        XCTAssertEqual(NotificationType.late.level, .timeSensitive)
        XCTAssertEqual(NotificationType.done.level, .passive)
        XCTAssertEqual(NotificationGroup.tools.types, [.queue, .late])
        XCTAssertEqual(NotificationGroup.syncExport.types, [.sync, .done])
    }

    // MARK: deep links

    func testDefaultTapRoutes() {
        let info = [NotificationInfo.job: "j", NotificationInfo.tool: "t", NotificationInfo.url: "https://drive.google.com/x"]
        XCTAssertEqual(DeepLink.route(type: .survey, action: nil, info: info), .survey(job: "j"))
        XCTAssertEqual(DeepLink.route(type: .survey, action: nil, info: [:]), .home)
        XCTAssertEqual(DeepLink.route(type: .queue, action: nil, info: info), .toolQueue(tool: "t"))
        XCTAssertEqual(DeepLink.route(type: .late, action: nil, info: info), .toolCamera(tool: "t", .giveBack))
        XCTAssertEqual(DeepLink.route(type: .cal, action: nil, info: info), .toolRecord(tool: "t"))
        XCTAssertEqual(DeepLink.route(type: .sync, action: "com.apple.UNNotificationDefaultActionIdentifier", info: info), .pendingList)
        XCTAssertEqual(DeepLink.route(type: .done, action: nil, info: info), .driveFolder(URL(string: "https://drive.google.com/x")!))
    }

    func testEveryActionRoutes() {
        let url = URL(string: "https://drive.google.com/x")!
        let info = [NotificationInfo.job: "j", NotificationInfo.tool: "t", NotificationInfo.url: url.absoluteString, NotificationInfo.phone: "0812345678"]
        let expected: [NotificationAction: DeepLink] = [
            .navigate: .navigate(job: "j"), .openSurvey: .survey(job: "j"), .remind10Minutes: .remindLater(600),
            .pickUp: .toolCamera(tool: "t", .borrow), .viewQueue: .toolQueue(tool: "t"), .leaveQueue: .leaveQueue(tool: "t"),
            .returnTool: .toolCamera(tool: "t", .giveBack), .extendDay: .extendLoan(tool: "t"), .callWaiting: .call(phone: "0812345678"),
            .toolRecord: .toolRecord(tool: "t"), .remind7Days: .remindLater(7 * 86_400),
            .syncNow: .syncNow, .viewPending: .pendingList, .openDrive: .driveFolder(url), .shareLink: .share(url),
        ]
        XCTAssertEqual(Set(expected.keys), Set(NotificationAction.allCases))
        for (action, link) in expected {
            let type = NotificationType.allCases.first { $0.actions.contains(action) }!
            XCTAssertEqual(DeepLink.route(type: type, action: action.rawValue, info: info), link, action.rawValue)
        }
        XCTAssertEqual(DeepLink.route(type: .late, action: NotificationAction.callWaiting.rawValue, info: [NotificationInfo.tool: "t"]), .toolQueue(tool: "t"))
        XCTAssertEqual(DeepLink.route(type: .done, action: NotificationAction.shareLink.rawValue, info: [:]), .home)
    }
}
