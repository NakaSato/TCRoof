import XCTest
@testable import TCRoofCore

final class SurveyDraftProgressTests: XCTestCase {
    /// The app's 11 required items in `SurveyOptions.missing` order: roof 4, electrical 3, bill 1, photos 3.
    private let groupOfItem = [0, 0, 0, 0, 1, 1, 1, 2, 3, 3, 3]

    private func progress(filledGroups: Set<Int>) -> SurveyDraftProgress {
        SurveyDraftProgress(items: groupOfItem.map { .init(group: $0, filled: filledGroups.contains($0)) })
    }

    func testEmptyDraft() {
        let p = progress(filledGroups: [])
        XCTAssertEqual(p.done, 0)
        XCTAssertEqual(p.total, 11)
        XCTAssertEqual(p.groups, [false, false, false, false])
        XCTAssertEqual(p.current, 0)
        XCTAssertEqual(p.percent, 0)
    }

    func testRoofFilled() {
        let p = progress(filledGroups: [0])
        XCTAssertEqual(p.done, 4)
        XCTAssertEqual(p.current, 1)
        XCTAssertEqual(p.percent, 36)
    }

    func testAllButPhotos() {
        let p = progress(filledGroups: [0, 1, 2])
        XCTAssertEqual(p.done, 8)
        XCTAssertEqual(p.groups, [true, true, true, false])
        XCTAssertEqual(p.current, 3)
        XCTAssertEqual(p.percent, 73)
    }

    func testEverythingFilled() {
        let p = progress(filledGroups: [0, 1, 2, 3])
        XCTAssertEqual(p.done, 11)
        XCTAssertNil(p.current)
        XCTAssertEqual(p.percent, 100)
    }

    func testPartlyFilledGroupIsNotDone() {
        var items = groupOfItem.map { SurveyDraftProgress.Item(group: $0, filled: $0 == 0) }
        items[4] = .init(group: 1, filled: true)  // one electrical item of three
        let p = SurveyDraftProgress(items: items)
        XCTAssertEqual(p.done, 5)
        XCTAssertEqual(p.groups, [true, false, false, false])
        XCTAssertEqual(p.current, 1)
    }

    func testCardLabels() {
        let none = SurveyCardProgress(draft: nil, hasSaved: false)
        XCTAssertEqual([none.key, none.value], ["ยังไม่เริ่ม", "เริ่มที่ หลังคา"])
        XCTAssertEqual(none.percent, 0)
        XCTAssertEqual(none.segments, [.todo, .todo, .todo, .todo])

        let saved = SurveyCardProgress(draft: nil, hasSaved: true)
        XCTAssertEqual([saved.key, saved.value], ["สำรวจครบ", "มีแบบสำรวจแล้ว"])
        XCTAssertEqual(saved.percent, 100)
        XCTAssertEqual(saved.segments, [.done, .done, .done, .done])

        let draft = SurveyCardProgress(draft: progress(filledGroups: [0, 1]), hasSaved: true)
        XCTAssertEqual([draft.key, draft.value], ["ทำต่อ 3/4", "ค่าไฟ"])
        XCTAssertEqual(draft.percent, 64)
        XCTAssertEqual(draft.tone, .draft)
        XCTAssertEqual(draft.segments, [.done, .done, .current, .todo])

        let fresh = SurveyCardProgress(draft: progress(filledGroups: []), hasSaved: false)
        XCTAssertEqual([fresh.key, fresh.value], ["ทำต่อ 1/4", "หลังคา"])
        XCTAssertEqual(fresh.segments, [.current, .todo, .todo, .todo])
    }

    /// The iPhone card's pair (docs/ui/tcroof-survey-list-iphone).
    func testCardShortLabels() {
        let none = SurveyCardProgress(draft: nil, hasSaved: false)
        XCTAssertEqual([none.shortKey, none.shortValue], ["ยังไม่เริ่ม", "เริ่มสำรวจ"])

        let saved = SurveyCardProgress(draft: nil, hasSaved: true)
        XCTAssertEqual([saved.shortKey, saved.shortValue], ["สำรวจครบ", "ดูแบบสำรวจ"])

        let draft = SurveyCardProgress(draft: progress(filledGroups: [0, 1]), hasSaved: false)
        XCTAssertEqual([draft.shortKey, draft.shortValue], ["ทำต่อ", "ค่าไฟ"])

        let finished = SurveyCardProgress(draft: progress(filledGroups: [0, 1, 2, 3]), hasSaved: false)
        XCTAssertEqual([finished.shortKey, finished.shortValue], ["สำรวจครบ", "รอบันทึก"])
        XCTAssertEqual(finished.tone, .complete)
    }

    func testInstallWhenLabel() {
        let l = { (d: Int, day: Int?, total: Int) in InstallWhen.label(daysToStart: d, day: day, total: total, start: "9 ต.ค. 69", end: "12 ต.ค. 69") }
        XCTAssertEqual(l(-1, 2, 4), "กำลังติดตั้ง | วันที่ 2/4")
        XCTAssertEqual(l(0, 1, 1), "เริ่มวันนี้ | 9 ต.ค. 69")
        XCTAssertEqual(l(1, nil, 3), "เริ่มพรุ่งนี้ | 9 ต.ค. 69")
        XCTAssertEqual(l(3, nil, 3), "เริ่มอีก 3 วัน | 9 ต.ค. 69")
        XCTAssertEqual(l(-10, nil, 3), "ติดตั้งเสร็จ | 12 ต.ค. 69")
    }

    func testRelativeDayLabel() {
        XCTAssertEqual(RelativeDay.label(days: -2, time: "14:00"), "2 วันที่แล้ว | 14:00 น.")
        XCTAssertEqual(RelativeDay.label(days: -1, time: "08:30"), "เมื่อวาน 08:30 น.")
        XCTAssertEqual(RelativeDay.label(days: 0, time: "09:30"), "วันนี้ 09:30 น.")
        XCTAssertEqual(RelativeDay.label(days: 1, time: "13:30"), "พรุ่งนี้ 13:30 น.")
        XCTAssertEqual(RelativeDay.label(days: 5, time: "13:00"), "อีก 5 วัน | 13:00 น.")
    }

    func testRelativeDayCountsCalendarDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let at = { (d: Int, h: Int) in cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))! }
        let now = at(30, 23)
        XCTAssertEqual(RelativeDay.days(from: now, to: at(30, 0), calendar: cal), 0)
        XCTAssertEqual(RelativeDay.days(from: now, to: cal.date(byAdding: .hour, value: 2, to: now)!, calendar: cal), 1)
        XCTAssertEqual(RelativeDay.days(from: now, to: at(28, 23), calendar: cal), -2)
        XCTAssertEqual(RelativeDay.days(from: now, to: at(25, 9), calendar: cal), -5)
    }
}
