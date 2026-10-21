import XCTest
@testable import TCRoofCore

/// docs/ui/daily-report-ipad-v3: the date picker's dots and grid, and the working-time steppers.
final class RoutineDayPickerTests: XCTestCase {
    typealias R = RoutineReport
    private func d(_ day: Int, month: Int = 7) -> Date {
        R.calendar.date(from: DateComponents(year: 2025, month: month, day: day))!
    }

    func testDayStatus() {
        let s = R.Settings()   // จ.–ส.
        let today = d(3)
        XCTAssertEqual(R.dayStatus(d(1), signed: true, settings: s, today: today), .sent)
        XCTAssertEqual(R.dayStatus(d(2), signed: false, settings: s, today: today), .draft)
        // a working day before today with nothing
        XCTAssertEqual(R.dayStatus(d(1), signed: nil, settings: s, today: today), .missing)
        // today, a later day and a Sunday (29 มิ.ย.) have no dot
        XCTAssertEqual(R.dayStatus(d(3), signed: nil, settings: s, today: today), .none)
        XCTAssertEqual(R.dayStatus(d(4), signed: nil, settings: s, today: today), .none)
        XCTAssertEqual(R.dayStatus(d(29, month: 6), signed: nil, settings: s, today: today), .none)
        // a report on a Sunday still shows
        XCTAssertEqual(R.dayStatus(d(29, month: 6), signed: true, settings: s, today: today), .sent)
        // a holiday, and a day before the install start
        var h = s; h.holidays = ["2025-07-01"]
        XCTAssertEqual(R.dayStatus(d(1), signed: nil, settings: h, today: today), .none)
        XCTAssertEqual(R.dayStatus(d(1), signed: nil, settings: s, today: today, from: d(2)), .none)
    }

    func testMonthGrid() {
        // 1 ก.ค. 2568 is a Tuesday: two blanks, 31 days
        let g = R.monthGrid(d(15))
        XCTAssertEqual(g.leading, 2)
        XCTAssertEqual(g.days.count, 31)
        XCTAssertEqual(R.dayKey(g.days[0]), "2025-07-01")
        XCTAssertEqual(R.monthGrid(d(10, month: 2)).days.count, 28)
    }

    func testWorkHoursSteps() {
        typealias W = R.WorkHours
        XCTAssertEqual(W.text(7), "07.00")
        XCTAssertTrue(W.step(start: 8, end: 18, moveEnd: true, by: 1)! == (8, 19))
        XCTAssertTrue(W.step(start: 8, end: 17, moveEnd: false, by: -1)! == (7, 17))
        XCTAssertNil(W.step(start: 6, end: 17, moveEnd: false, by: -1))   // start below 06
        XCTAssertNil(W.step(start: 8, end: 20, moveEnd: true, by: 1))     // end past 20
        XCTAssertNil(W.step(start: 10, end: 15, moveEnd: false, by: 1))   // start past 10
        XCTAssertNil(W.step(start: 10, end: 15, moveEnd: true, by: -1))   // end below 15
        XCTAssertEqual(W.presets.map { "\($0.start)–\($0.end)" }, ["08.00–17.00", "08.00–18.00", "07.00–16.00"])
    }
}
