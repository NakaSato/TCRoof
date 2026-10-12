import XCTest
@testable import TCRoofCore

/// The tools register behind the iPhone `เครื่องมือ` tab's badge.
final class InstrumentsTests: XCTestCase {
    private let cal = MasterSchedule.calendar
    private func d(_ day: Int, _ month: Int = 10, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func tool(_ name: String, due: Date?) -> Instrument { Instrument(name: name, calibrationDue: due) }

    func testCalibrationStates() {
        let now = d(13)
        XCTAssertEqual(tool("a", due: nil).calibration(on: now), Instrument.Calibration.none)
        XCTAssertEqual(tool("a", due: d(28, 12)).calibration(on: now), .ok(daysLeft: 76))
        XCTAssertEqual(tool("a", due: d(13, 11)).calibration(on: now), .ok(daysLeft: 31))
        XCTAssertEqual(tool("a", due: d(12, 11)).calibration(on: now), .dueSoon(daysLeft: 30))
        XCTAssertEqual(tool("a", due: d(13, hour: 0)).calibration(on: now), .dueSoon(daysLeft: 0))
        XCTAssertEqual(tool("a", due: d(3)).calibration(on: now), .overdue(days: 10))
        XCTAssertEqual(Instrument.Calibration.overdue(days: 10).title, "เกิน 10 วัน")
        XCTAssertEqual(Instrument.Calibration.dueSoon(daysLeft: 0).title, "ครบวันนี้")
        XCTAssertEqual(Instrument.Calibration.ok(daysLeft: 76).title, "เหลือ 76 วัน")
    }

    func testTheBadgeCountsDueSoonAndOverdueOnly() {
        let all = [tool("ok", due: d(28, 12)), tool("soon", due: d(20)), tool("late", due: d(1)), tool("none", due: nil)]
        XCTAssertEqual(Instrument.dueCount(all, on: d(13)), 2)
        XCTAssertEqual(Instrument.dueCount([], on: d(13)), 0)
    }

    func testOverdueFirstAndUncalibratedLast() {
        let all = [tool("none", due: nil), tool("ok", due: d(28, 12)), tool("late", due: d(1)), tool("soon", due: d(20))]
        XCTAssertEqual(Instrument.sorted(all, on: d(13)).map(\.name), ["late", "soon", "ok", "none"])
    }

    func testAnEntryWithOnlyAnIDDecodes() throws {
        let t = try JSONDecoder().decode(Instrument.self, from: Data(#"{"id":"x"}"#.utf8))
        XCTAssertEqual(t.name, "")
        XCTAssertNil(t.calibrationDue)
    }
}
