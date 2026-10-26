import XCTest
@testable import TCRoofCore

/// The bundled Thai public holidays (`PublicHolidays`, from the plan workbook's `สมมติฐาน` sheet) count as days off
/// everywhere working days are counted.
final class PublicHolidaysTests: XCTestCase {
    func testTheListIsBundled() throws {
        XCTAssertGreaterThanOrEqual(PublicHolidays.all.count, 14)
        XCTAssertEqual(PublicHolidays.all.map(\.date), PublicHolidays.all.map(\.date).sorted())
        XCTAssertEqual(PublicHolidays.day("2027-04-13")?.name, "สงกรานต์")
        XCTAssertEqual(PublicHolidays.day("2027-05-20")?.toConfirm, true, "Visakha Bucha waits on the cabinet")
        XCTAssertEqual(PublicHolidays.day("2027-04-06")?.toConfirm, false)
        XCTAssertNotNil(PublicHolidays.coveredUntil)
    }

    func testRoutineReportsSkipThem() throws {
        let settings = RoutineReport.Settings()
        let cal = MasterSchedule.calendar
        let songkran = try XCTUnwrap(cal.date(from: DateComponents(year: 2027, month: 4, day: 13)))   // a Tuesday
        let next = try XCTUnwrap(cal.date(from: DateComponents(year: 2027, month: 4, day: 16)))       // a Friday
        XCTAssertFalse(RoutineReport.isWorkingDay(songkran, settings: settings))
        XCTAssertTrue(RoutineReport.isWorkingDay(next, settings: settings))
        // a report missing over Songkran is only asked for on the days around it
        let missing = RoutineReport.missingDays(reported: [], settings: settings,
                                                from: cal.date(byAdding: .day, value: -1, to: songkran)!, to: next)
        XCTAssertEqual(missing.map(RoutineReport.dayKey), ["2027-04-12", "2027-04-16"])
    }

    func testUtilityDeadlinesSkipThem() {
        // 15 working days from Monday 5 Apr 2027: วันจักรี and Songkran don't count
        var r = ERCFlow.Record()
        r.add(.designRequest, day: "2027-04-05")
        XCTAssertEqual(ERCFlow.states(r)[.designResult], .waiting(since: "2027-04-05", due: "2027-04-30"))
    }
}
