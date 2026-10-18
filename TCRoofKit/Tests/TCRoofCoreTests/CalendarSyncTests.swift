import XCTest
@testable import TCRoofCore

/// ซิงก์นัดอัตโนมัติ: what the sync creates, moves, removes and leaves alone (spec §A1).
final class CalendarSyncTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func date(_ d: Int, _ h: Int = 9) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))! }
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!

    private func event(_ start: Date, phone: String = "081") -> SurveyEvent {
        SurveyEvent(.init(projectName: "สถานีผลิตน้ำ", code: "TC-1", customerName: "ลูกค้า", phone: phone, address: "ต.หนองบัว",
                          province: "ชลบุรี", team: "TCR01", capacityKW: 50, start: start, syncID: "J1"), calendar: cal)
    }

    private func link(_ e: SurveyEvent, deleted: Bool = false) -> CalendarSync.Link {
        .init(eventID: "E1", fingerprint: CalendarSync.fingerprint(e), deletedInCalendar: deleted)
    }

    func testAnUpcomingAppointmentIsCreatedOnce() {
        let e = event(date(20))
        XCTAssertEqual(CalendarSync.plan([.init(jobKey: "J1", event: e)], links: [:], exists: { _ in false }, now: now),
                       [.create(jobKey: "J1", event: e)])
        XCTAssertEqual(CalendarSync.plan([.init(jobKey: "J1", event: e)], links: ["J1": link(e)], exists: { _ in true }, now: now), [])
    }

    func testAChangedDateOrPhoneUpdatesTheEvent() {
        let old = event(date(20)), moved = event(date(21)), phone = event(date(20), phone: "089")
        XCTAssertEqual(CalendarSync.plan([.init(jobKey: "J1", event: moved)], links: ["J1": link(old)], exists: { _ in true }, now: now),
                       [.update(jobKey: "J1", eventID: "E1", event: moved)])
        XCTAssertEqual(CalendarSync.plan([.init(jobKey: "J1", event: phone)], links: ["J1": link(old)], exists: { _ in true }, now: now),
                       [.update(jobKey: "J1", eventID: "E1", event: phone)])
    }

    func testAnEventDeletedInCalendarIsNotRecreated() {
        let e = event(date(20))
        XCTAssertEqual(CalendarSync.plan([.init(jobKey: "J1", event: e)], links: ["J1": link(e)], exists: { _ in false }, now: now),
                       [.markDeleted(jobKey: "J1")])
        // once flagged, nothing happens, even when the date moves
        XCTAssertEqual(CalendarSync.plan([.init(jobKey: "J1", event: event(date(22)))], links: ["J1": link(e, deleted: true)],
                                         exists: { _ in false }, now: now), [])
    }

    func testACompletedOrClearedJobLosesItsEvent() {
        let e = event(date(20))
        XCTAssertEqual(CalendarSync.plan([.init(jobKey: "J1", event: nil)], links: ["J1": link(e)], exists: { _ in true }, now: now),
                       [.delete(jobKey: "J1", eventID: "E1")])
        // a job gone from the device too
        XCTAssertEqual(CalendarSync.plan([], links: ["J1": link(e)], exists: { _ in true }, now: now), [.delete(jobKey: "J1", eventID: "E1")])
        // already gone from Calendar: just forget it
        XCTAssertEqual(CalendarSync.plan([.init(jobKey: "J1", event: nil)], links: ["J1": link(e)], exists: { _ in false }, now: now),
                       [.forget(jobKey: "J1")])
    }

    func testPastAppointmentsAreLeftAlone() {
        let past = event(date(15))
        XCTAssertEqual(CalendarSync.plan([.init(jobKey: "J1", event: past)], links: ["J1": link(past)], exists: { _ in true }, now: now),
                       [.forget(jobKey: "J1")])
        XCTAssertEqual(CalendarSync.plan([.init(jobKey: "J1", event: past)], links: [:], exists: { _ in false }, now: now), [])
    }

    func testLinksRoundTrip() {
        let links = ["J1": link(event(date(20)), deleted: true)]
        XCTAssertEqual(CalendarSync.decode(CalendarSync.encode(links)), links)
        XCTAssertEqual(CalendarSync.decode(nil), [:])
    }
}
