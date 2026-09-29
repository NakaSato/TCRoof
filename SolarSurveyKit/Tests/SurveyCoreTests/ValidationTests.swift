import XCTest
@testable import SurveyCore

final class ValidationTests: XCTestCase {
    func testNumberClean() {
        XCTAssertEqual(NumberInput.clean("1,200"), "1200")
        XCTAssertEqual(NumberInput.clean("50 ซม."), "50")
        XCTAssertEqual(NumberInput.clean("12 m2"), "12")
        XCTAssertEqual(NumberInput.clean("๑๒.๕"), "12.5")
        XCTAssertEqual(NumberInput.clean("ประมาณ 80"), "80")
        XCTAssertEqual(NumberInput.clean("-3.5"), "-3.5")
        XCTAssertEqual(NumberInput.clean("1.2.3"), "1.23")
        XCTAssertTrue(NumberInput.isValid(""))
        XCTAssertTrue(NumberInput.isValid("12.5"))
        XCTAssertFalse(NumberInput.isValid("1,200"))
    }

    func testGPS() {
        XCTAssertEqual(GPS.check(""), .empty)
        XCTAssertEqual(GPS.check("17.0062, 99.8235"), .ok)
        XCTAssertEqual(GPS.check("17.0062,99.8235"), .ok)
        XCTAssertEqual(GPS.check("99.8235, 17.0062"), .swapped("17.006200, 99.823500"))
        XCTAssertEqual(GPS.check("35.68, 139.69"), .outsideThailand)
        XCTAssertEqual(GPS.check("abc"), .invalid)
        XCTAssertEqual(GPS.check("17.0062"), .invalid)
    }

    func testMissingGroups() {
        var j = Job.new(template: JobTemplate.all[0])
        let groups = j.missingGroups
        XCTAssertEqual(groups.first?.target, .info)
        XCTAssertEqual(groups.last?.target, .final)
        XCTAssertTrue(groups.contains { if case .module = $0.target { return true } else { return false } })
        XCTAssertEqual(j.missingCount, groups.reduce(0) { $0 + $1.items.count })

        // bad input is reported, not just empty input
        j.values["gps"] = .text("99.8235, 17.0062")
        j.values["capacity"] = .text("1,200")
        let info = j.missingGroups.first { $0.target == .info }?.items ?? []
        XCTAssertTrue(info.contains("พิกัด GPS สลับละติจูด/ลองจิจูด"))
        XCTAssertTrue(info.contains { $0.hasPrefix("ตัวเลขไม่ถูกต้อง") })
        XCTAssertFalse(info.contains { $0.hasPrefix("*") })
    }

    func testMissingItemsFollowGroups() {
        let j = Job.new(template: JobTemplate.all[0])
        XCTAssertEqual(j.missingItems.count, j.missingCount)
        XCTAssertTrue(j.missingItems.contains { $0.hasPrefix("E1 สรุปผลและลงนาม: ผลการประเมิน") })
    }

    func testMissingSignatures() {
        var j = Job.new(template: JobTemplate.all[0])
        XCTAssertEqual(j.missingSignatures.count, 2)
        j.values["surveyorSign"] = .photo(Photo(fileName: "s.png", width: 10, height: 10))
        XCTAssertEqual(j.missingSignatures, ["ลายเซ็นผู้ประสานงาน / เจ้าของสถานที่"])
        j.values["customerSign"] = .photo(Photo(fileName: "c.png", width: 10, height: 10))
        XCTAssertTrue(j.missingSignatures.isEmpty)
    }
}
