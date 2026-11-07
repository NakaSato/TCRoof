import XCTest
@testable import TCRoofCore

/// `MaintenanceMock` fills only what a monitoring source left out, the same for the same plant every time.
final class MaintenanceMockTests: XCTestCase {
    private let now = DateComponents(calendar: .current, year: 2026, month: 11, day: 7, hour: 12).date!

    private func row(kWp: Double = 375, energy: Double = 990.7, status: MaintenanceStationSummary.Status = .normal) -> MaintenanceStationSummary {
        MaintenanceStationSummary(id: "growatt-web-11089901", name: "Com************t", kWp: kWp, energy: energy, status: status,
                                  note: "Growatt | 300.25 kW")
    }

    func testFillsWhatIsMissing() throws {
        let s = MaintenanceMock.fill(row(), seed: "growatt-web-11089901", now: now)
        XCTAssertEqual(s.expected, 1575)
        // 990.7 kWh / 375 kWp / 5 = 53 %, kept at 55
        XCTAssertEqual(s.pr, 55)
        XCTAssertTrue(s.reportsPR)
        let pm = try XCTUnwrap(s.nextPM)
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: pm).day ?? 0
        XCTAssertTrue((3...42).contains(days))
        XCTAssertEqual(s.openRepairs, 0)
        // what the source gave stays
        XCTAssertEqual(s.energy, 990.7)
        XCTAssertEqual(s.note, "Growatt | 300.25 kW")
    }

    func testKeepsGivenFiguresAndIsStable() {
        var given = row()
        given.expected = 1200; given.pr = 81
        let s = MaintenanceMock.fill(given, seed: "x", now: now)
        XCTAssertEqual(s.expected, 1200)
        XCTAssertEqual(s.pr, 81)
        XCTAssertEqual(MaintenanceMock.fill(row(), seed: "a", now: now).nextPM, MaintenanceMock.fill(row(), seed: "a", now: now).nextPM)
    }

    func testOfflineAndAlarm() {
        let offline = MaintenanceMock.fill(row(energy: 0, status: .offline), seed: "a", now: now)
        XCTAssertEqual(offline.pr, 0)
        XCTAssertFalse(offline.reportsPR)
        XCTAssertEqual(MaintenanceMock.fill(row(status: .alarm), seed: "a", now: now).openRepairs, 1)
    }

    func testStationPage() {
        let empty = MaintenanceStationDetail.growatt(summary: row())
        XCTAssertTrue(empty.tickets.isEmpty && empty.pmHistory.isEmpty && empty.nextPM == nil)
        let d = MaintenanceMock.fill(empty, seed: "growatt-web-11089901", now: now)
        XCTAssertEqual(d.expectedHourly.count, 13)
        XCTAssertEqual(d.expectedHourly[6], 300, accuracy: 0.001)
        XCTAssertEqual(d.expectedHourly[0], 0)
        XCTAssertEqual(d.prToday, 55)
        XCTAssertFalse(d.tickets.isEmpty)
        XCTAssertNotNil(d.nextPM)
        XCTAssertFalse(d.pmHistory.isEmpty)
        XCTAssertEqual(d.equipmentGroups.first?.title, "แผง (ตัวอย่าง)")
        XCTAssertEqual(d.equipmentGroups.first?.rows.first?.value, "658 แผง")
        // no made-up phone number to call
        XCTAssertTrue(d.contractorPhone.isEmpty)
    }

    func testThaiDate() {
        XCTAssertEqual(MaintenanceStationDetail.thaiDate("2026-02-11"), "11/2/2569")
        XCTAssertEqual(MaintenanceStationDetail.thaiDate(""), "—")
    }
}
