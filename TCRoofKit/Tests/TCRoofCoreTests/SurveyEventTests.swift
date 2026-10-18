import XCTest
@testable import TCRoofCore

/// `SurveyEvent` (docs/specs/calendar-travel-expenses-swift.md §A2) and the `tcroof://` links (§A4).
final class SurveyEventTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }()

    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))! }

    func source(start: Date, form: Bool) -> SurveyEvent.Source {
        SurveyEvent.Source(projectName: "สถานีผลิตน้ำทุ่งน้อย", code: "TCR2569-12345", customerName: "กปภ.สาขาเมืองพล",
                           phone: "043 123 456", address: "ต.ทุ่งน้อย อ.เมืองพล", province: "ขอนแก่น", team: "TCR01", capacityKW: 92.34,
                           start: start, syncID: "ABC-1", formCoordinator: form ? "คุณสมชาย" : "", formPhone: form ? "081 234 5678" : "",
                           formAddress: form ? "99 ม.3 ต.ทุ่งน้อย อ.เมืองพล จ.ขอนแก่น" : "", formGPS: form ? "16.1834, 102.6265" : "")
    }

    func testATimedSurveyFromTheJob() {
        let e = SurveyEvent(source(start: at(20, 9, 30), form: false), calendar: cal)
        XCTAssertEqual(e.title, "สำรวจ · สถานีผลิตน้ำทุ่งน้อย (TCR2569-12345)")
        XCTAssertFalse(e.isAllDay)
        XCTAssertEqual(e.start, at(20, 9, 30))
        XCTAssertEqual(e.end, at(20, 12, 30), "3 hours")
        XCTAssertEqual(e.location, "ต.ทุ่งน้อย อ.เมืองพล ขอนแก่น")
        XCTAssertNil(e.latitude)
        XCTAssertEqual(e.url?.absoluteString, "tcroof://job/ABC-1")
        XCTAssertEqual(e.alarms, [.at(at(19, 17)), .before(3600)], "17:00 the day before, and an hour before")
        let lines = e.notes.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "ผู้ประสานงาน: กปภ.สาขาเมืองพล")
        XCTAssertEqual(lines[1], "โทร: 043 123 456")
        XCTAssertEqual(lines[2], "ทีม: TCR01 · ขนาด 92.34 kW")
        XCTAssertTrue(lines[3].hasPrefix("นำทาง (Apple Maps): maps://?daddr=%E0%B8"), "to the address, encoded")
        XCTAssertEqual(lines.last, "เปิดงานใน TCRoof: tcroof://job/ABC-1")
    }

    /// The linked form's coordinator, phone, address and pin win over the job's.
    func testTheFormWins() {
        let e = SurveyEvent(source(start: at(20, 9), form: true), calendar: cal)
        XCTAssertEqual(e.location, "99 ม.3 ต.ทุ่งน้อย อ.เมืองพล จ.ขอนแก่น")
        XCTAssertEqual(e.latitude ?? 0, 16.1834, accuracy: 1e-9)
        XCTAssertEqual(e.longitude ?? 0, 102.6265, accuracy: 1e-9)
        XCTAssertTrue(e.notes.contains("ผู้ประสานงาน: คุณสมชาย\nโทร: 081 234 5678"))
        XCTAssertTrue(e.notes.contains("maps://?daddr=16.183400,102.626500"))
        XCTAssertTrue(e.notes.contains("https://www.google.com/maps/dir/?api=1&destination=16.183400,102.626500"))
    }

    func testADayWithNoTimeIsAllDay() {
        let e = SurveyEvent(source(start: at(20, 0), form: false), calendar: cal)
        XCTAssertTrue(e.isAllDay)
        XCTAssertEqual(e.start, at(20, 0))
        XCTAssertEqual(e.end, at(21, 0))
        XCTAssertEqual(e.alarms, [.at(at(19, 17))], "no hour-before alarm")
    }

    func testAPinOutsideThailandIsNotUsed() {
        var s = source(start: at(20, 9), form: true)
        s.formGPS = "102.6265, 16.1834"   // swapped
        XCTAssertNil(SurveyEvent(s, calendar: cal).latitude)
    }

    func testLinks() {
        XCTAssertEqual(DeepLink(url: URL(string: "tcroof://job/ABC-1")!), .job(job: "ABC-1"))
        XCTAssertEqual(DeepLink(url: URL(string: "tcroof://job/ABC-1/survey")!), .survey(job: "ABC-1"))
        XCTAssertNil(DeepLink(url: URL(string: "tcroof://job/")!))
        XCTAssertNil(DeepLink(url: URL(string: "tcroof://job/ABC-1/other")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://job/ABC-1")!))
        XCTAssertEqual(SurveyEvent.jobURL("ABC-1").flatMap(DeepLink.init(url:)), .job(job: "ABC-1"), "round trip")
    }
}
