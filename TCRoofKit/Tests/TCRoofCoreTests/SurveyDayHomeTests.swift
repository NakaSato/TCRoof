import XCTest
@testable import TCRoofCore

final class SurveyDayHomeTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }

    /// Wednesday 30 Sep 2026 is the board's today; `day` counts from it.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 30 + day, hour: hour, minute: minute))!
    }

    func testGreetingByHour() {
        XCTAssertEqual(SurveyGreeting.text(hour: 11), "สวัสดีตอนเช้า")
        XCTAssertEqual(SurveyGreeting.text(hour: 12), "สวัสดีตอนบ่าย")
        XCTAssertEqual(SurveyGreeting.text(hour: 16), "สวัสดีตอนบ่าย")
        XCTAssertEqual(SurveyGreeting.text(hour: 17), "สวัสดีตอนเย็น")
        XCTAssertEqual(SurveyGreeting.text(hour: 0), "สวัสดีตอนเช้า")
    }

    func testWeekRollsFromToday() {
        let week = SurveyDayHome.week(now: at(0, 8, 10), dates: [at(0, 9, 30), at(1, 13, 30), at(1, 15), at(3, 10), at(7, 9), at(-5, 11)], calendar: cal)
        XCTAssertEqual(week.map(\.label), ["วันนี้", "พฤ", "ศ", "ส", "อา", "จ", "อ"])
        XCTAssertEqual(week.map(\.number), [30, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(week.map(\.count), [1, 2, 0, 1, 0, 0, 0])
        XCTAssertTrue(week[0].isToday)
        XCTAssertFalse(week[1].isToday)
        XCTAssertTrue(week[1].hasAppointments)
        XCTAssertFalse(week[2].hasAppointments)
    }

    func testNextIsEarliestAhead() {
        let dates = [at(1, 13, 30), at(0, 9, 30), at(0, 8), at(-3, 10)]
        XCTAssertEqual(SurveyDayHome.next(dates: dates, now: at(0, 8, 10)), 1)
        // an appointment at this very minute still counts
        XCTAssertEqual(SurveyDayHome.next(dates: dates, now: at(0, 9, 30)), 1)
        // today's has passed: tomorrow's is next
        XCTAssertEqual(SurveyDayHome.next(dates: dates, now: at(0, 12)), 0)
        XCTAssertNil(SurveyDayHome.next(dates: dates, now: at(2, 0)))
        XCTAssertNil(SurveyDayHome.next(dates: [], now: at(0, 8)))
    }

    func testNextTieKeepsTheFirst() {
        XCTAssertEqual(SurveyDayHome.next(dates: [at(1, 9), at(0, 10), at(0, 10)], now: at(0, 8)), 1)
    }

    func testAgendaExcludesNextAndSortsByTime() {
        let dates = [at(0, 14), at(0, 9, 30), at(0, 11), at(1, 9), at(0, 7)]
        let now = at(0, 8, 10)
        let next = SurveyDayHome.next(dates: dates, now: now)
        XCTAssertEqual(next, 1)
        // the 07:00 one has passed but is still on today's agenda
        XCTAssertEqual(SurveyDayHome.agenda(dates: dates, offset: 0, now: now, excluding: next, calendar: cal), [4, 2, 0])
        XCTAssertEqual(SurveyDayHome.agenda(dates: dates, offset: 1, now: now, excluding: next, calendar: cal), [3])
        XCTAssertEqual(SurveyDayHome.agenda(dates: dates, offset: 2, now: now, excluding: next, calendar: cal), [])
    }

    func testListOrderNearestDayFirst() {
        // offsets -14, 0, 1, -5, 3, -1
        let dates = [at(-14, 9), at(0, 9, 30), at(1, 13, 30), at(-5, 11), at(3, 10), at(-1, 15)]
        XCTAssertEqual(SurveyDayHome.listOrder(dates: dates, now: at(0, 8), calendar: cal), [1, 5, 2, 4, 3, 0])
    }

    func testListOrderTieTakesEarlierDate() {
        let dates = [at(2, 9), at(-2, 9), at(2, 8)]
        XCTAssertEqual(SurveyDayHome.listOrder(dates: dates, now: at(0, 8), calendar: cal), [1, 2, 0])
    }

    func testCounts() {
        XCTAssertEqual(SurveyDayHome.counts(["a", "b", "a", "a"]), ["a": 3, "b": 1])
        XCTAssertEqual(SurveyDayHome.counts([String]()), [:])
    }

    func testInitialStripsPrefix() {
        XCTAssertEqual(SurveyDayHome.initial(of: "คุณนพพร วีระโชติ"), "น")
        XCTAssertEqual(SurveyDayHome.initial(of: "บริษัท คิดดี จำกัด"), "ค")
        XCTAssertEqual(SurveyDayHome.initial(of: "ร้านกาแฟบ้านสวน"), "ก")
        XCTAssertEqual(SurveyDayHome.initial(of: "โรงงานสยามแพ็คกิ้ง"), "ส")
        XCTAssertEqual(SurveyDayHome.initial(of: "หอพักกรีนเพลส"), "ก")
        XCTAssertEqual(SurveyDayHome.initial(of: "Solar Home"), "S")
        XCTAssertEqual(SurveyDayHome.initial(of: "คุณ"), "?")
        XCTAssertEqual(SurveyDayHome.initial(of: "  "), "?")
    }

    func testUntil() {
        XCTAssertEqual(SurveyDayHome.until(now: at(0, 8, 10), date: at(0, 9, 30), calendar: cal), "อีก 1 ชม. 20 นาที")
        XCTAssertEqual(SurveyDayHome.until(now: at(0, 9, 10), date: at(0, 9, 30), calendar: cal), "อีก 20 นาที")
        XCTAssertEqual(SurveyDayHome.until(now: at(0, 9, 30), date: at(0, 9, 30), calendar: cal), "อีก 0 นาที")
        XCTAssertEqual(SurveyDayHome.until(now: at(0, 23), date: at(3, 9), calendar: cal), "อีก 3 วัน")
        XCTAssertEqual(SurveyDayHome.until(now: at(0, 23), date: at(1, 1), calendar: cal), "อีก 1 วัน")
    }

    func testDrive() {
        XCTAssertEqual(SurveyDayHome.drive(meters: 12_000, seconds: 25 * 60), "12 กม. - ขับ 25 นาที")
        XCTAssertEqual(SurveyDayHome.drive(meters: 3_400, seconds: 8 * 60), "3.4 กม. - ขับ 8 นาที")
        XCTAssertEqual(SurveyDayHome.drive(meters: 2_000, seconds: 20), "2 กม. - ขับ 1 นาที")
        XCTAssertEqual(SurveyDayHome.drive(meters: 86_400, seconds: 65 * 60), "86 กม. - ขับ 1 ชม. 5 นาที")
    }
}
