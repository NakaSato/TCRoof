import XCTest
@testable import TCRoofCore

/// `Monitoring ทุกสถานี` (issue #259): the fleet's figures, the table's filters and sorts, the action list, the chart
/// and the settings, on the board's example fleet and on small hand-made ones.
final class MonitoringTests: XCTestCase {
    let cal = Calendar.current
    var now: Date { Monitoring.demoNow(calendar: cal) }
    var demo: Monitoring.Fleet { Monitoring.Fleet(Monitoring.demo(now: now, calendar: cal), now: now, settings: .init()) }

    func testTheBoardsFleetAddsUp() throws {
        let f = demo
        XCTAssertEqual(f.kWp, 965)
        XCTAssertEqual(f.inverters, 9)
        XCTAssertEqual(try XCTUnwrap(f.totalEnergy), 1_310_000, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(f.co2Tonnes), 655, accuracy: 1)
        // no rate yet: no value, never 0
        XCTAssertNil(f.value)
        // 7 of 9 inverters working: the offline station's and MP 25's second are down
        XCTAssertEqual(f.invertersOnline, 7)
        XCTAssertEqual(try XCTUnwrap(f.availability), 7.0 / 9, accuracy: 1e-9)
        XCTAssertEqual(f.online, 5)
        XCTAssertEqual(f.backfeedReporting, 5)
        XCTAssertEqual(f.backfeedClean, 5)
        XCTAssertEqual(try XCTUnwrap(f.expectedSoFar), 3475, accuracy: 0.5)
    }

    func testHealthOfEachStation() {
        let byMP = Dictionary(uniqueKeysWithValues: demo.rows.map { ($0.station.mpNumber ?? 0, $0.health) })
        XCTAssertEqual(byMP[44], .offline)
        XCTAssertEqual(byMP[25], .alarm)
        // the app's own string check is listed, but leaves the station normal
        XCTAssertEqual(byMP[12], .normal)
        XCTAssertEqual(byMP[52], .normal)
    }

    func testLossCountsOnlyStationsNotRunningNormally() throws {
        let f = demo
        let rows = Dictionary(uniqueKeysWithValues: f.rows.map { ($0.station.mpNumber ?? 0, $0) })
        // offline: nothing read since, so at most the forecast
        XCTAssertEqual(rows[44]?.loss, .atMost(try XCTUnwrap(rows[44]?.station.shortfall)))
        XCTAssertEqual(try XCTUnwrap(rows[25]?.loss?.kWh), 380, accuracy: 0.5)
        XCTAssertNil(rows[12]?.loss)
        XCTAssertEqual(f.lossStations, 2)
        let lost = try XCTUnwrap(f.lossToday)
        XCTAssertEqual(try XCTUnwrap(f.lossShare), lost / 3475, accuracy: 1e-6)
    }

    func testSpecificYieldAgainstTheMedianOfNormalStations() throws {
        let f = demo
        // the normal stations: MP 12, 52, 7, 31 (3.40, 3.45, 3.47, 3.53): the median is the middle two's mean
        XCTAssertEqual(try XCTUnwrap(f.medianYield), (690.0 / 200 + 330.0 / 95) / 2, accuracy: 1e-6)
        let mp25 = try XCTUnwrap(f.rows.first { $0.station.mpNumber == 25 })
        XCTAssertEqual(try XCTUnwrap(mp25.yieldVsMedian), (410.0 / 220) / ((690.0 / 200 + 330.0 / 95) / 2) - 1, accuracy: 1e-3)
    }

    func testActionsArePerPartAndSortedByEnergyLost() {
        let a = demo.actions
        XCTAssertEqual(a.map { $0.station.mpNumber }, [44, 25, 12])
        // MP 25's two alarms on INV 2 are one action
        XCTAssertEqual(a[1].alarms.count, 2)
        XCTAssertEqual(a[1].alarm.code, "124")
        XCTAssertEqual(a[1].occurrences, 5)
        XCTAssertEqual(a[0].alarm.label, "Lost")
        XCTAssertEqual(a[2].alarm.label, "TCRoof")
        XCTAssertNil(a[2].alarm.workOrder)
        // the table's alarm column counts every alarm
        XCTAssertEqual(demo.alarmCount, 4)
    }

    func testFiltersAndSorts() {
        let f = demo
        XCTAssertEqual(f.count(.all), 6)
        XCTAssertEqual(f.count(.problem), 3)
        XCTAssertEqual(f.count(.offline), 1)
        XCTAssertEqual(f.rows(.all, sort: .loss).map { $0.station.mpNumber }, [44, 25, 12, 52, 7, 31])
        XCTAssertEqual(f.rows(.all, sort: .mp).map { $0.station.mpNumber }, [7, 12, 25, 31, 44, 52])
        XCTAssertEqual(f.rows(.all, sort: .specificYield).first?.station.mpNumber, 44)
        XCTAssertNil(f.rows.first { $0.station.mpNumber == 44 }?.yieldVsMedian)
    }

    func testAStationWithNoSourceIsOfflineWithNothingKnown() {
        let s = Monitoring.Station.unpaired(id: "j1", mpNumber: 9, name: "สถานีใหม่", kWp: 50, inverters: 1)
        let f = Monitoring.Fleet([s], now: now, settings: .init())
        XCTAssertEqual(f.rows[0].health, .offline)
        // nothing known: dashes on the page, not 0
        XCTAssertNil(f.powerNow)
        XCTAssertNil(f.energyToday)
        XCTAssertNil(f.totalEnergy)
        XCTAssertNil(f.lossToday)
        XCTAssertNil(f.specificYield)
        XCTAssertNil(f.rows[0].loss)
        XCTAssertEqual(f.invertersOnline, 0)
    }

    func testOfflineAfterTheLoggerThreshold() {
        var s = Monitoring.Station(id: "s", name: "s", kWp: 10, inverters: 1, invertersOnline: 1, lastReading: now.addingTimeInterval(-20 * 60))
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .normal)
        XCTAssertEqual(s.health(now: now, offlineAfter: 15), .offline)
        s.invertersOnline = 0
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .alarm)
    }

    func testPRNeedsAnIrradianceSensor() {
        XCTAssertNil(Monitoring.Station(id: "a", name: "a", kWp: 1, inverters: 1, hasIrradianceSensor: false, prToday: 80).prToday)
        XCTAssertEqual(Monitoring.Station(id: "a", name: "a", kWp: 1, inverters: 1, hasIrradianceSensor: true, prToday: 80).prToday, 80)
    }

    func testTheValueFollowsTheRate() throws {
        var settings = Monitoring.Settings()
        settings.rate = 4.2
        let f = Monitoring.Fleet(Monitoring.demo(now: now, calendar: cal), now: now, settings: settings)
        XCTAssertEqual(try XCTUnwrap(f.value), 1_310_000 * 4.2, accuracy: 1)
    }

    func testForecastCurveAddsUpToTheDay() {
        let c = Monitoring.Forecast.curve(dailyKWh: 500)
        XCTAssertEqual(c.count, Monitoring.slots)
        XCTAssertEqual(Monitoring.Forecast.energy(c, through: Monitoring.slots - 1), 500, accuracy: 1e-6)
        XCTAssertEqual(c[0], 0)
        // highest around noon
        XCTAssertEqual(c.firstIndex(of: c.max()!).map { $0 / 12 }, 12)
        XCTAssertEqual(Monitoring.Forecast.dailyKWhPerKWp(latitude: nil, longitude: nil), Monitoring.Forecast.typicalDaily)
    }

    func testTodaysChart() throws {
        let stations = Monitoring.demo(now: now, calendar: cal)
        let chart = Monitoring.Chart(stations, range: .today, now: now, calendar: cal)
        XCTAssertEqual(chart.total.count, Monitoring.Chart.dayWindow.count)
        // nothing after now
        XCTAssertNil(chart.total.last?.actual)
        XCTAssertNotNil(try XCTUnwrap(chart.current).actual)
        XCTAssertNotNil(chart.peak)
        // the column: made so far against the forecast so far, and the day at that rate
        let s = chart.summary
        XCTAssertEqual(try XCTUnwrap(s.expected), 3475, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(s.loss), 3475 - (s.produced ?? 0), accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(s.previous), stations.reduce(0) { $0 + ($1.yesterdaySoFar ?? 0) }, accuracy: 1e-6)
        XCTAssertGreaterThan(try XCTUnwrap(s.projected), try XCTUnwrap(s.produced))
        // MP 25's inverter and MP 44's logger are marked; the app's own check isn't
        // once per part, at its first alarm (MP 25's INV 2 at 09:48)
        XCTAssertEqual(chart.events.map(\.label), ["MP 44 ดาต้าล็อกเกอร์ ขาดการติดต่อ", "MP 25 INV 2 หยุด"])
        // one line per station, less those hidden
        XCTAssertEqual(Monitoring.Chart(stations, range: .today, now: now, calendar: cal, hidden: ["demo-mp44"]).series.count, 5)
    }

    func testDaysAndMonths() throws {
        let stations = Monitoring.demo(now: now, calendar: cal)
        let week = Monitoring.Chart(stations, range: .week, now: now, calendar: cal)
        XCTAssertEqual(week.total.count, 7)
        XCTAssertEqual(week.total.last?.x, cal.startOfDay(for: now))
        XCTAssertNotNil(week.summary.previous)
        XCTAssertEqual(Monitoring.Chart(stations, range: .month, now: now, calendar: cal).total.count, 30)
        let year = Monitoring.Chart(stations, range: .year, now: now, calendar: cal)
        XCTAssertEqual(year.total.count, 12)
        XCTAssertNotNil(year.total.first?.actual)
        XCTAssertNil(year.summary.projected)
    }

    func testSettingsKeepNoTokenAndReadOlderFiles() throws {
        var s = Monitoring.Settings(pollMinutes: 1)
        // never under Growatt's 5 minutes
        XCTAssertEqual(s.pollMinutes, 5)
        s.servers = [.init(name: "Growatt · บัญชีเฟส 3", url: "https://openapi.growatt.com/v1/",
                           tokenSuffix: Monitoring.Settings.Server.suffix(of: "abcdef123f2a"))]
        XCTAssertEqual(s.servers[0].tokenSuffix, "3f2a")
        XCTAssertEqual(s.servers[0].host, "openapi.growatt.com")
        let json = String(data: try JSONEncoder().encode(s), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("abcdef"))
        XCTAssertEqual(try JSONDecoder().decode(Monitoring.Settings.self, from: Data(json.utf8)), s)
        // an older file with only some fields
        let old = try JSONDecoder().decode(Monitoring.Settings.self, from: Data(#"{"pollMinutes":10}"#.utf8))
        XCTAssertEqual(old.pollMinutes, 10)
        XCTAssertNil(old.rate)
        XCTAssertEqual(old.belowExpectedPercent, 85)
    }
}
