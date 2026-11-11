import XCTest
@testable import TCRoofCore

/// `Monitoring ทุกสถานี` (issue #259): the fleet's figures, the table's filters and sorts, the action list, the chart
/// and the settings, on the board's example fleet and on small hand-made ones.
final class MonitoringTests: XCTestCase {
    let cal = Calendar.current
    var now: Date { Monitoring.demoNow(calendar: cal) }
    var demo: Monitoring.Fleet {
        let stations = Monitoring.demo(now: now, calendar: cal)
        return Monitoring.Fleet(stations, now: now, settings: .init(),
                                raised: Monitoring.demoRaised(stations, now: now, calendar: cal), calendar: cal)
    }

    func testTheBoardsFleetAddsUp() throws {
        let f = demo
        XCTAssertEqual(f.kWp, 965)
        XCTAssertEqual(f.inverters, 9)
        XCTAssertEqual(try XCTUnwrap(f.totalEnergy), 1_310_000, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(f.co2Tonnes), 655, accuracy: 1)
        // the default rate until a manager sets one (issue #259 decision 1); none set: no value, never 0
        XCTAssertEqual(try XCTUnwrap(f.value), 1_310_000 * Monitoring.Settings.defaultRate, accuracy: 1)
        var unset = Monitoring.Settings()
        unset.rate = nil
        XCTAssertNil(Monitoring.Fleet(f.stations, now: now, settings: unset).value)
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
        // against the median kWh/kWp of the normal stations (issue #259 decision 2), the weather being the same
        let median = (690.0 / 200 + 330.0 / 95) / 2
        XCTAssertEqual(try XCTUnwrap(f.reference), median, accuracy: 1e-9)
        // offline: nothing read since, so at most what it should have made
        XCTAssertEqual(rows[44]?.loss, .atMost(try XCTUnwrap(rows[44]?.shortfall)))
        let kWp44 = try XCTUnwrap(rows[44]?.station.kWp)
        XCTAssertEqual(try XCTUnwrap(rows[44]?.shortfall), median * kWp44, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(rows[25]?.loss?.kWh), median * 220 - 410, accuracy: 0.01)
        // the offline station's Lost line in ต้องดำเนินการ gives the same figure
        let lostLine = try XCTUnwrap(rows[44]?.station.alarms.first { $0.source == .lost })
        XCTAssertEqual(lostLine.loss, rows[44]?.loss)
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

    func testActionsArePerStationAndSortedByEnergyLost() {
        let a = demo.actions
        XCTAssertEqual(a.map { $0.station.mpNumber }, [44, 25, 12])
        // MP 25's two alarms on INV 2 are one action
        XCTAssertEqual(a[1].alarms.count, 2)
        XCTAssertEqual(a[1].alarm.code, "124")
        XCTAssertEqual(a[1].occurrences, 5)
        XCTAssertEqual(a[0].alarm.label, "ขาดการติดต่อ")
        XCTAssertEqual(a[0].status, "ขาดการติดต่อ")
        XCTAssertEqual(a[2].status, "TCRoof ตรวจพบ")
        XCTAssertEqual(a[2].alarm.label, "TCRoof")
        XCTAssertNil(a[2].alarm.workOrder)
        // the table's alarm column counts every alarm
        XCTAssertEqual(demo.alarmCount, 4)
    }

    func testTheDockCountsStationsInAlarmOrOffline() {
        // MP 44 offline and MP 25 in alarm; MP 12 stays normal, but its low string needs someone too (CHA-92)
        XCTAssertEqual(demo.needingAttention, 3)
        // a station not paired yet reads offline in the table but has no feed to fall silent: the badge stays 0
        let unpaired = Monitoring.Station.unpaired(id: "a", mpNumber: 1, name: "A", kWp: 100, inverters: 1)
        let fleet = Monitoring.Fleet([unpaired], now: now, settings: .init())
        XCTAssertEqual(fleet.rows.first?.health, .offline)
        XCTAssertEqual(fleet.needingAttention, 0)
        // paired but never heard from is offline, and counts
        let silent = Monitoring.Station(id: "b", name: "B", kWp: 100, inverters: 1)
        XCTAssertEqual(Monitoring.Fleet([unpaired, silent], now: now, settings: .init()).needingAttention, 1)
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
        XCTAssertEqual(old.rate, Monitoring.Settings.defaultRate)
        // a rate a manager cleared stays cleared through a save and a reload
        var cleared = Monitoring.Settings()
        cleared.rate = nil
        let back = try JSONDecoder().decode(Monitoring.Settings.self, from: JSONEncoder().encode(cleared))
        XCTAssertNil(back.rate)
        XCTAssertEqual(back, cleared)
        XCTAssertEqual(old.belowExpectedPercent, 85)
    }

    func testPairingSuggestsByNameOrBySize() {
        typealias P = Monitoring.Pairing.Plant
        let plants = Monitoring.Pairing.demoPlants()
        // MP 44 สถานีผลิตน้ำสามพราน 120 kWp: the plant named after it, and nothing else near 120 kWp
        let mp44 = Monitoring.Pairing.suggest(station: "สถานีผลิตน้ำสามพราน", kWp: 120, in: plants)
        XCTAssertEqual(mp44.map(\.id), ["9001"])
        // MP 52 กำแพงแสน 200 kWp: its plant says 199.5, within 10 %, and nothing else is named like it
        XCTAssertEqual(Monitoring.Pairing.suggest(station: "สถานีผลิตน้ำกำแพงแสน", kWp: 200, in: plants).map(\.id), ["9004"])
        // name matches come before size matches; the station words don't count
        let near = [P(id: "a", name: "Solar 118 kWp site", kWp: 118), P(id: "b", name: "กปภ. สามพราน เฟส 2", kWp: 60)]
        XCTAssertEqual(Monitoring.Pairing.suggest(station: "สถานีผลิตน้ำสามพราน", kWp: 120, in: near).map(\.id), ["b", "a"])
        XCTAssertTrue(Monitoring.Pairing.matchesName(P(id: "c", name: "สามพราน", kWp: 0), station: "สถานี สามพราน"))
        // under 10 %: 108.5 and 131.5 are in, 108 and 132 (the edge) and 107 are out; a plant or a station without a
        // size never matches by size
        XCTAssertTrue(Monitoring.Pairing.matchesSize(P(id: "d", name: "x", kWp: 108.5), kWp: 120))
        XCTAssertTrue(Monitoring.Pairing.matchesSize(P(id: "d", name: "x", kWp: 131.5), kWp: 120))
        XCTAssertFalse(Monitoring.Pairing.matchesSize(P(id: "d", name: "x", kWp: 108), kWp: 120))
        XCTAssertFalse(Monitoring.Pairing.matchesSize(P(id: "d", name: "x", kWp: 132), kWp: 120))
        XCTAssertFalse(Monitoring.Pairing.matchesSize(P(id: "d", name: "x", kWp: 107), kWp: 120))
        XCTAssertFalse(Monitoring.Pairing.matchesSize(P(id: "d", name: "x", kWp: 0), kWp: 120))
        XCTAssertFalse(Monitoring.Pairing.matchesSize(P(id: "d", name: "x", kWp: 120), kWp: 0))
        // a one-letter core (`PV`, `A`) is never a name match
        XCTAssertFalse(Monitoring.Pairing.matchesName(P(id: "e", name: "A", kWp: 0), station: "สถานี A"))
        // the picker's order: suggestions first, the rest as listed; the search looks at name, city and id
        let ordered = Monitoring.Pairing.ordered(plants, station: "สถานีผลิตน้ำดอนตูม", kWp: 95)
        XCTAssertEqual(ordered.first?.id, "9005")
        XCTAssertEqual(ordered.count, plants.count)
        XCTAssertEqual(Monitoring.Pairing.search(plants, "bangkok").map(\.id), ["9007"])
        XCTAssertEqual(Monitoring.Pairing.search(plants, "9002").map(\.id), ["9002"])
        XCTAssertEqual(Monitoring.Pairing.search(plants, "  ").count, plants.count)
        // a Growatt row becomes a picker row
        let g = GrowattAPI.Plant(id: 77, name: "P", peakPower: 12.5, currentPower: 1, totalEnergy: 2, status: nil, city: "เมือง", country: "TH",
                                 latitude: nil, longitude: nil)
        XCTAssertEqual(P(g), P(id: "77", name: "P", kWp: 12.5, city: "เมือง"))
        XCTAssertEqual(P(g).detail, "12.5 kWp · เมือง")
    }

    func testSettingsKeepThePairingsAndTheirServers() throws {
        let a = Monitoring.Settings.Server(name: "เฟส 3", url: "https://openapi.growatt.com/v1/")
        let b = Monitoring.Settings.Server(name: "เฟส 4", url: "https://openapi.growatt.com/v1/")
        var s = Monitoring.Settings(servers: [a, b])
        s.pair("demo-mp44", plant: "9001", server: b.id)
        s.pair("demo-mp25", plant: "9002", server: nil)
        XCTAssertEqual(s.paired(of: ["demo-mp44", "demo-mp25", "demo-mp12"]), 2)
        XCTAssertEqual(s.server(for: "demo-mp44")?.id, b.id)
        // not recorded: the first server
        XCTAssertEqual(s.server(for: "demo-mp25")?.id, a.id)
        XCTAssertEqual(s.server(for: "demo-mp12")?.id, a.id)
        // a server taken out: back to the first
        s.servers.removeAll { $0.id == b.id }
        XCTAssertEqual(s.server(for: "demo-mp44")?.id, a.id)
        // the round trip keeps both, and an older file without `pairingServers` reads
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(Monitoring.Settings.self, from: data), s)
        let old = try JSONDecoder().decode(Monitoring.Settings.self, from: Data(#"{"pairings":{"j1":"5"}}"#.utf8))
        XCTAssertEqual(old.pairings, ["j1": "5"])
        XCTAssertTrue(old.pairingServers.isEmpty)
        XCTAssertNil(old.server(for: "j1"))
        s.unpair("demo-mp44")
        XCTAssertNil(s.pairings["demo-mp44"])
        XCTAssertNil(s.pairingServers["demo-mp44"])
        XCTAssertEqual(s.paired(of: ["demo-mp44", "demo-mp25"]), 1)
    }

    // MARK: ผลิตต่ำกว่าที่คาด

    /// A normal station `kWp` making `kWh` by 14:55, its forecast so far 3.6 kWh/kWp of a 4.5 kWh/kWp day.
    func normal(_ id: String, kWp: Double, kWh: Double) -> Monitoring.Station {
        Monitoring.Station(id: id, name: id, kWp: kWp, inverters: 1, invertersOnline: 1, energyToday: kWh,
                           expectedSoFar: 3.6 * kWp, expectedToday: 4.5 * kWp, lastReading: now)
    }

    func below(_ f: Monitoring.Fleet, _ id: String) -> Monitoring.Alarm? {
        f.stations.first { $0.id == id }?.alarms.first { $0.id == id + "/below" }
    }

    /// Against the median of the normal stations: a station at 70 % of it is raised, one at 95 % isn't, and a cloudy
    /// day (every station well under the forecast) raises nothing.
    func testBelowTheMedianRaisesTheAppsOwnLine() throws {
        // a cloudy day: 2.0 kWh/kWp against a forecast of 3.6
        let f = Monitoring.Fleet([normal("a", kWp: 100, kWh: 200), normal("b", kWp: 100, kWh: 200),
                                  normal("c", kWp: 100, kWh: 190), normal("d", kWp: 100, kWh: 140)],
                                 now: now, settings: .init())
        XCTAssertEqual(try XCTUnwrap(f.reference), 1.95, accuracy: 1e-9)
        XCTAssertNil(below(f, "a"))
        XCTAssertNil(below(f, "c"))
        let a = try XCTUnwrap(below(f, "d"))
        XCTAssertEqual(a.source, .tcroof)
        XCTAssertEqual(a.detail, "ผลิต 71% ของค่ากลาง · เกณฑ์ 85%")
        XCTAssertEqual(a.loss.kWh, 195 - 140, accuracy: 1e-9)
        // listed, but the station stays normal and the dock doesn't count it
        XCTAssertEqual(f.rows.first { $0.id == "d" }?.health, .normal)
        XCTAssertEqual(f.needingAttention, 0)
        XCTAssertEqual(f.actions.first?.station.id, "d")
    }

    /// With fewer than 3 normal stations, the forecast stands in.
    func testFewNormalStationsUseTheForecast() throws {
        let f = Monitoring.Fleet([normal("a", kWp: 100, kWh: 340), normal("b", kWp: 100, kWh: 200)],
                                 now: now, settings: .init())
        XCTAssertNil(f.reference)
        XCTAssertNil(below(f, "a"))
        XCTAssertEqual(try XCTUnwrap(below(f, "b")).detail, "ผลิต 55% ของที่คาด · เกณฑ์ 85%")
    }

    /// Not before 15 % of the day's forecast; the line keeps when it was first raised.
    func testEarlyMorningRaisesNothingAndALineKeepsItsAge() throws {
        var early = normal("b", kWp: 100, kWh: 10)
        early.expectedSoFar = 40
        XCTAssertNil(below(Monitoring.Fleet([normal("a", kWp: 100, kWh: 340), early], now: now, settings: .init()), "b"))

        let stations = [normal("a", kWp: 100, kWh: 340), normal("b", kWp: 100, kWh: 200)]
        let first = Monitoring.Fleet(stations, now: now, settings: .init(), calendar: cal)
        XCTAssertEqual(Set(first.raised.keys), ["b/below"])
        let later = now.addingTimeInterval(600)
        let next = Monitoring.Fleet(stations, now: later, settings: .init(), raised: first.raised, calendar: cal)
        XCTAssertEqual(below(next, "b")?.since, now)
        XCTAssertEqual(below(next, "b")?.occurrences, 1)
        XCTAssertEqual(next.raised["b/below"]?.since, now)
    }
}
