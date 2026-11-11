import XCTest
@testable import TCRoofCore

/// A paired station's Growatt reading (`Monitoring.Station`, from `MonitoringStore`'s poll) on the `บำรุงรักษา`
/// overview's row and station page. An unpaired or unread station keeps its row.
final class MonitoringMaintenanceTests: XCTestCase {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 14, minute: 55))! }
    let row = MaintenanceStationSummary(id: "st1", mpNumber: 25, name: "สถานีผลิตน้ำ", kWp: 220, status: .normal,
                                        note: "ยังไม่มีข้อมูลการผลิต")

    /// 150 kW from 06:00 to 14:50, then nothing read.
    var curve: [Double?] { (0..<Monitoring.slots).map { i in i >= 72 && i < 178 ? 150 : nil } }

    func station(lastReading: Date?, paired: Bool = true, alarms: [Monitoring.Alarm] = [], online: Int? = 2) -> Monitoring.Station {
        Monitoring.Station(id: "st1", mpNumber: 25, name: "สถานีผลิตน้ำ", kWp: 220, inverters: 2, invertersOnline: online,
                           paired: paired, powerNow: 150, energyToday: 410, expectedToday: 880, totalEnergy: 290_000,
                           lastReading: lastReading, alarms: alarms, curve: curve,
                           expectedCurve: Array(repeating: 100, count: Monitoring.slots),
                           months: [Monitoring.Period(start: now, energy: 17_600, expected: 21_400)])
    }

    func testUnpairedOrUnreadKeepsTheRow() {
        XCTAssertEqual(row.monitored(by: station(lastReading: now, paired: false), now: now, offlineAfter: 30, calendar: cal), row)
        XCTAssertEqual(row.monitored(by: station(lastReading: nil), now: now, offlineAfter: 30, calendar: cal), row)
    }

    func testReadingFillsTheRow() {
        let last = now.addingTimeInterval(-5 * 60)
        let r = row.monitored(by: station(lastReading: last), now: now, offlineAfter: 30, calendar: cal)
        XCTAssertEqual(r.status, .normal)
        XCTAssertEqual(r.energy, 410)
        XCTAssertEqual(r.expected, 880)
        XCTAssertEqual(r.powerNow, 150)
        XCTAssertEqual(r.invertersOnline, 2)
        XCTAssertEqual(r.invertersTotal, 2)
        XCTAssertEqual(r.updated, "14:50")
        XCTAssertEqual(r.hourly.count, 13)
        XCTAssertEqual(r.hourly[0], 150)
        XCTAssertEqual(r.hourly[12], 0)
        // no irradiance sensor: no PR
        XCTAssertEqual(r.pr, 0)
        XCTAssertEqual(r.note, "Growatt")
    }

    func testSilentPastTheThresholdIsOffline() {
        let last = now.addingTimeInterval(-90 * 60)
        let r = row.monitored(by: station(lastReading: last), now: now, offlineAfter: 30, calendar: cal)
        XCTAssertEqual(r.status, .offline)
        XCTAssertNil(r.powerNow)
        XCTAssertEqual(r.note, "Growatt | ไม่มีข้อมูลตั้งแต่ 13:25")
    }

    func testFaultIsAnAlarmOnTheRowAndItsInverter() {
        let fault = Monitoring.Alarm(id: "f", source: .growatt, part: "INV 2", detail: "Fault · MAX 125KTL3", since: now)
        let s = station(lastReading: now, alarms: [fault], online: 1)
        let r = row.monitored(by: s, now: now, offlineAfter: 30, calendar: cal)
        XCTAssertEqual(r.status, .alarm)
        XCTAssertEqual(r.note, "Growatt | INV 2 Error")

        let d = MaintenanceStationDetail.monitored(summary: row, station: s, now: now, offlineAfter: 30, calendar: cal)
        XCTAssertEqual(d.issueTitle, "INV 2 Error")
        XCTAssertEqual(d.issueSubtitle, "จาก Growatt | Fault · MAX 125KTL3")
        XCTAssertEqual(d.inverters.map(\.statusText), ["ปกติ", "Error"])
        XCTAssertEqual(d.inverters.map(\.isError), [false, true])
    }

    func testDetailTakesTheReading() {
        let d = MaintenanceStationDetail.monitored(summary: row, station: station(lastReading: now), now: now,
                                                   offlineAfter: 30, calendar: cal)
        XCTAssertNil(d.issueTitle)
        XCTAssertEqual(d.lastUpdated, "14:55")
        XCTAssertEqual(d.actualHourly[0], 150)
        XCTAssertEqual(d.expectedHourly, Array(repeating: 100, count: 13))
        XCTAssertEqual(d.energyThisMonth, "17.6 MWh")
        XCTAssertEqual(d.energyExpectedThisMonth, "คาด 21.4 MWh")
        XCTAssertEqual(d.co2SavedThisMonth, "8.8 t")
        XCTAssertEqual(d.energyTotal, "290.0 MWh")
        XCTAssertEqual(d.prToday, 0)
        XCTAssertEqual(d.inverters.count, 2)
    }

    func testDetailOfAnUnreadStationIsTheSample() {
        let d = MaintenanceStationDetail.monitored(summary: row, station: station(lastReading: nil), now: now,
                                                   offlineAfter: 30, calendar: cal)
        XCTAssertEqual(d, .mock(for: row))
    }
}
