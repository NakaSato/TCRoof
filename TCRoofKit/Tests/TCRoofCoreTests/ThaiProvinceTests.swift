import XCTest
@testable import TCRoofCore

final class ThaiProvinceTests: XCTestCase {
    func testAll77WithoutDuplicates() {
        XCTAssertEqual(ThaiProvince.all.count, 77)
        XCTAssertEqual(Set(ThaiProvince.all).count, 77)
        XCTAssertTrue(ThaiProvince.frequent.allSatisfy(ThaiProvince.all.contains))
        XCTAssertTrue(ThaiProvince.all.contains(ThaiProvince.defaultName))
    }

    func testGroupKeySkipsLeadingVowels() {
        XCTAssertEqual(ThaiProvince.groupKey("เชียงใหม่"), "ช")
        XCTAssertEqual(ThaiProvince.groupKey("แพร่"), "พ")
        XCTAssertEqual(ThaiProvince.groupKey("เพชรบุรี"), "พ")
        XCTAssertEqual(ThaiProvince.groupKey("แม่ฮ่องสอน"), "ม")
        XCTAssertEqual(ThaiProvince.groupKey("กรุงเทพมหานคร"), "ก")
        XCTAssertEqual(ThaiProvince.groupKey("อำนาจเจริญ"), "อ")
    }

    func testSearchBySubstring() {
        XCTAssertEqual(ThaiProvince.search("สมุทร"), ["สมุทรปราการ", "สมุทรสงคราม", "สมุทรสาคร"])
        XCTAssertEqual(ThaiProvince.search("  สมุทร ").count, 3)
        XCTAssertEqual(ThaiProvince.search("").count, 77)
        XCTAssertTrue(ThaiProvince.search("zzz").isEmpty)
    }

    func testGroupsAreInThaiOrderAndCoverEverything() {
        let g = ThaiProvince.grouped()
        XCTAssertEqual(g.first?.key, "ก")
        XCTAssertEqual(g.flatMap(\.names).count, 77)
        XCTAssertEqual(g.map(\.key), g.map(\.key).sorted { $0.compare($1, locale: Locale(identifier: "th_TH")) == .orderedAscending })
        XCTAssertTrue(g.first { $0.key == "ช" }?.names.contains("เชียงใหม่") ?? false)
        XCTAssertTrue(g.first { $0.key == "พ" }?.names.contains("แพร่") ?? false)
    }
}

final class NewJobRulesTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Bangkok")!; return c }()

    func testPhoneFormatting() {
        XCTAssertEqual(NewJobRules.formatPhone("0812345678"), "081-234-5678")
        XCTAssertEqual(NewJobRules.formatPhone("025551234"), "02-555-1234")
        XCTAssertEqual(NewJobRules.formatPhone("081-234-5678 99"), "081-234-5678")
        XCTAssertEqual(NewJobRules.formatPhone("0812"), "081-2")
        XCTAssertEqual(NewJobRules.formatPhone(""), "")
    }

    func testPhoneValidity() {
        XCTAssertTrue(NewJobRules.isValidPhone(""))
        XCTAssertTrue(NewJobRules.isValidPhone("02-555-1234"))
        XCTAssertTrue(NewJobRules.isValidPhone("081-234-5678"))
        XCTAssertFalse(NewJobRules.isValidPhone("081-234"))
    }

    func testPanelEstimate() {
        XCTAssertEqual(NewJobRules.panelCount(kWp: 5), 9)
        XCTAssertEqual(NewJobRules.panelCount(kWp: 3), 5)
        XCTAssertEqual(NewJobRules.panelCount(kWp: 0), 0)
    }

    func testCustomKWpChecks() {
        XCTAssertEqual(NewJobRules.checkKWp("7.5"), .ok(7.5))
        XCTAssertEqual(NewJobRules.checkKWp("100"), .ok(100))
        XCTAssertEqual(NewJobRules.checkKWp("101"), .tooHigh)
        XCTAssertEqual(NewJobRules.checkKWp("0.5"), .tooLow)
        XCTAssertEqual(NewJobRules.checkKWp("7.3"), .notStep)
        XCTAssertEqual(NewJobRules.checkKWp(""), .empty)
        XCTAssertEqual(NewJobRules.kWpMessage(.tooHigh), "เกินค่าสูงสุด 100")
        XCTAssertEqual(NewJobRules.kWpMessage(.tooLow), "ต่ำกว่าค่าต่ำสุด 1")
    }

    func testRelativeDayAndInstallRange() {
        let today = cal.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 14))!
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }
        XCTAssertEqual(NewJobRules.relativeDay(today, from: today, calendar: cal), "วันนี้")
        XCTAssertEqual(NewJobRules.relativeDay(day(1), from: today, calendar: cal), "พรุ่งนี้")
        XCTAssertEqual(NewJobRules.relativeDay(day(5), from: today, calendar: cal), "อีก 5 วัน")
        let survey = NewJobRules.surveyDate(day: day(1), hour: 9, minute: 0, calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: survey), 9)
        let r = NewJobRules.installRange(survey: survey, offsetDays: 14, days: 2, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r.start), DateComponents(month: 10, day: 15))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: r.end), DateComponents(month: 10, day: 16))
    }
}
