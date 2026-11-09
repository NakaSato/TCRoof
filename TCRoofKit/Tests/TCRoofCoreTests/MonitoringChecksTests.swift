import XCTest
@testable import TCRoofCore

/// CHA-92: `สตริงกระแสต่ำ` and `PR ต่ำ` in ตั้งค่า Monitoring raise the app's own lines in `ต้องดำเนินการ`.
final class MonitoringChecksTests: XCTestCase {
    let cal = Calendar.current
    var now: Date { Monitoring.demoNow(calendar: cal) }

    /// A station running normally, at 94 % of its forecast (so `ผลิตต่ำกว่าที่คาด` stays quiet).
    func station(_ id: String = "s", inverters: Int = 1, strings: [[[Double?]]] = [], sensor: Bool = false,
                 pr: Double? = nil, at time: Date? = nil) -> Monitoring.Station {
        Monitoring.Station(id: id, name: id, kWp: 100, inverters: inverters, invertersOnline: inverters, energyToday: 340,
                           expectedSoFar: 360, expectedToday: 450, lastReading: time ?? now, hasIrradianceSensor: sensor,
                           prToday: pr, inverterStrings: strings)
    }

    func settings(string: Int = 20, pr: Int = 70) -> Monitoring.Settings {
        var s = Monitoring.Settings()
        s.stringLowPercent = string
        s.prLowPercent = pr
        return s
    }

    /// The fleet after its conditions have held 30 minutes.
    func settled(_ stations: [Monitoring.Station], _ settings: Monitoring.Settings) -> Monitoring.Fleet {
        let first = Monitoring.Fleet(stations, now: now, settings: settings, calendar: cal)
        return Monitoring.Fleet(stations, now: now.addingTimeInterval(Monitoring.Fleet.stringHold), settings: settings,
                                raised: first.raised, calendar: cal)
    }

    func lines(_ f: Monitoring.Fleet, _ id: String = "s") -> [Monitoring.Alarm] {
        f.stations.first { $0.id == id }?.alarms ?? []
    }

    // MARK: สตริงกระแสต่ำ

    func testALowStringShowsOnceItHasHeldThirtyMinutes() throws {
        let s = station(strings: [[[10, 10], [10, 3]]])
        let first = Monitoring.Fleet([s], now: now, settings: settings(), calendar: cal)
        XCTAssertTrue(lines(first).isEmpty)
        let early = Monitoring.Fleet([s], now: now.addingTimeInterval(29 * 60), settings: settings(), raised: first.raised,
                                     calendar: cal)
        XCTAssertTrue(lines(early).isEmpty)
        XCTAssertEqual(early.needingAttention, 0)

        let f = Monitoring.Fleet([s], now: now.addingTimeInterval(30 * 60), settings: settings(), raised: early.raised,
                                 calendar: cal)
        let a = try XCTUnwrap(lines(f).first)
        XCTAssertEqual(a.source, .tcroof)
        XCTAssertEqual(a.part, "MPPT 2 b")
        XCTAssertEqual(a.detail, "สตริง 3 A จากค่ากลาง 10 A · เกณฑ์ 20%")
        // its age is from when the string first read low
        XCTAssertEqual(a.since, now)
        XCTAssertEqual(a.occurrences, 1)
        XCTAssertEqual(a.loss, .about(340 * 7 / 33))
        // the station stays `ปกติ` (nothing notified) but needs someone
        XCTAssertEqual(f.rows.first?.health, .normal)
        XCTAssertEqual(f.needingAttention, 1)
        XCTAssertEqual(f.actions.first?.alarm.id, a.id)
    }

    func testTheStringThresholdChangesWhichStationsGetALine() {
        // 8.5 A against 10 A: 15 % under
        let stations = [station("a", strings: [[[10, 10], [10, 8.5]]]), station("b", strings: [[[10, 10], [10, 9.5]]])]
        XCTAssertTrue(settled(stations, settings(string: 20)).actions.isEmpty)
        let f = settled(stations, settings(string: 10))
        XCTAssertEqual(f.actions.map(\.station.id), ["a"])
        XCTAssertEqual(f.actions.first?.alarm.detail, "สตริง 8.5 A จากค่ากลาง 10 A · เกณฑ์ 10%")
    }

    func testNoStringIsJudgedWithoutCurrentOrData() {
        let quiet = [
            // no string currents from the source
            station("none"),
            // an input with no current (unused, or a string off): not judged
            station("dead", strings: [[[10, 10], [10, 0]]]),
            // dawn: 0.6 A against 0.9 A is a third under, and means nothing
            station("dawn", strings: [[[0.9, 0.9], [0.9, 0.6]]]),
            // nothing read
            station("nil", strings: [[[nil, nil], [nil, nil]]]),
        ]
        let f = settled(quiet, settings(string: 10))
        XCTAssertTrue(f.actions.isEmpty)
        XCTAssertEqual(f.needingAttention, 0)

        // offline: the currents are the last ones read, not now's; the logger's line says so instead
        let old = station("old", strings: [[[10, 10], [10, 3]]], at: now.addingTimeInterval(-3 * 3600))
        let g = settled([old], settings())
        XCTAssertEqual(g.rows.first?.health, .offline)
        XCTAssertFalse(lines(g, "old").contains { $0.id.contains("/string/") })
    }

    func testAStationWithTwoInvertersNamesTheInverter() {
        // each inverter against its own median
        let s = station(inverters: 2, strings: [[[10, 10], [10, 10]], [[6, 6], [3, 6]]])
        let f = settled([s], settings())
        XCTAssertEqual(lines(f).map(\.part), ["INV 2 · MPPT 2 a"])
        XCTAssertEqual(lines(f).first?.detail, "สตริง 3 A จากค่ากลาง 6 A · เกณฑ์ 20%")
    }

    // MARK: PR ต่ำ

    func testLowPRRaisesALineForAStationWithASensor() throws {
        let s = station(sensor: true, pr: 64.6)
        let f = Monitoring.Fleet([s], now: now, settings: settings(pr: 70), calendar: cal)
        // at once: PR is the day's so far
        let a = try XCTUnwrap(lines(f).first)
        XCTAssertEqual(a.part, "PR")
        XCTAssertEqual(a.detail, "PR 64% · เกณฑ์ 70%")
        XCTAssertEqual(a.loss, .unknown)
        XCTAssertEqual(f.needingAttention, 1)
        // the threshold lowered: no line
        XCTAssertTrue(lines(Monitoring.Fleet([s], now: now, settings: settings(pr: 60), calendar: cal)).isEmpty)
    }

    func testNoSensorOrNoPRMeansNoLine() {
        // without a sensor there is no PR (`—` on the page), so no line
        let blind = station("blind", sensor: false, pr: 40)
        XCTAssertNil(blind.prToday)
        let unknown = station("unknown", sensor: true, pr: nil)
        let f = Monitoring.Fleet([blind, unknown], now: now, settings: settings(pr: 90), calendar: cal)
        XCTAssertTrue(f.actions.isEmpty)
        XCTAssertEqual(f.needingAttention, 0)
    }

    func testAStationInAlarmIsListedByItsCauseNotItsPR() {
        var s = station(sensor: true, pr: 40)
        s.invertersOnline = 0
        let f = Monitoring.Fleet([s], now: now, settings: settings(), calendar: cal)
        XCTAssertEqual(f.rows.first?.health, .alarm)
        XCTAssertFalse(lines(f).contains { $0.part == "PR" })
    }

    // MARK: the line's count

    func testALineCountsEachTimeItComesBackTodayAndAgainFromTomorrow() throws {
        let low = station(sensor: true, pr: 60), fine = station(sensor: true, pr: 80)
        var f = Monitoring.Fleet([low], now: now, settings: settings(), calendar: cal)
        f = Monitoring.Fleet([fine], now: now.addingTimeInterval(600), settings: settings(), raised: f.raised, calendar: cal)
        XCTAssertTrue(lines(f).isEmpty)
        f = Monitoring.Fleet([low], now: now.addingTimeInterval(1200), settings: settings(), raised: f.raised, calendar: cal)
        let again = try XCTUnwrap(lines(f).first)
        XCTAssertEqual(again.occurrences, 2)
        XCTAssertEqual(again.since, now.addingTimeInterval(1200))

        let tomorrow = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: now))
        let next = Monitoring.Fleet([station(sensor: true, pr: 60, at: tomorrow)], now: tomorrow, settings: settings(),
                                    raised: f.raised, calendar: cal)
        XCTAssertEqual(lines(next).first?.occurrences, 1)
    }

    // MARK: the demo

    func testTheDemosLowStringIsRaisedFromItsCurrents() throws {
        let stations = Monitoring.demo(now: now, calendar: cal)
        let f = Monitoring.Fleet(stations, now: now, settings: .init(),
                                 raised: Monitoring.demoRaised(stations, now: now, calendar: cal), calendar: cal)
        let mp12 = try XCTUnwrap(f.stations.first { $0.mpNumber == 12 })
        let a = try XCTUnwrap(mp12.alarms.first { $0.source == .tcroof })
        XCTAssertEqual(a.part, "INV 1 · MPPT 4 b")
        XCTAssertEqual(a.since, cal.date(bySettingHour: 11, minute: 30, second: 0, of: now))
        // the only string line of the fleet, and the station page shows the same currents
        XCTAssertEqual(f.stations.flatMap(\.alarms).filter { $0.id.contains("/string/") }.count, 1)
        let detail = Monitoring.demoDetail(mp12, now: now, calendar: cal)
        XCTAssertEqual(detail.inverters.first?.strings, mp12.inverterStrings.first)
        XCTAssertEqual(detail.inverters.first?.stringTints[3][1], .low)
    }
}
