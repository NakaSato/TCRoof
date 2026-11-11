import XCTest
@testable import TCRoofCore

/// CHA-110: `Monitoring ทุกสถานี` with a real fleet and at night. Inverters quiet at night behind a logger that still
/// reports are asleep, not alarms; `ต้องดำเนินการ` is one row per station; the chart's events cluster into pills and
/// `แยกสถานี` keeps six chips.
final class MonitoringNightTests: XCTestCase {
    typealias Map = Monitoring.GrowattMap
    let cal = Calendar.current
    let plantZone = TimeZone(secondsFromGMT: 8 * 3600)!
    var today: Date { cal.startOfDay(for: Monitoring.demoNow(calendar: cal)) }
    let base = Monitoring.Station.unpaired(id: "p13", mpNumber: nil, name: "P1_3 สถานีผลิตน้ำบ้านโป่ง", kWp: 300, inverters: 6)

    func at(_ h: Int, _ m: Int, dayOffset: Int = 0) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: dayOffset, to: today)!)!
    }

    func stamp(_ date: Date) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = plantZone
        let p = c.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", p.year!, p.month!, p.day!, p.hour!, p.minute!, p.second!)
    }

    /// The logger's last reading at `logger`; six inverters, `lost` of them out of contact since 18:40 yesterday and
    /// `faults` of them in fault.
    func reading(logger: Date, lost: Int, faults: Int = 0) -> Monitoring.GrowattReading {
        let devices: [GrowattAPI.Device] = (1...6).map { i in
            let isLost = i <= lost, isFault = !isLost && i <= lost + faults
            return GrowattAPI.Device(sn: "MAX000\(i)", type: 4, status: isFault ? 3 : isLost ? -1 : 1, lost: isLost,
                                     lastUpdate: stamp(isLost ? at(18, 40, dayOffset: -1) : logger))
        }
        let data = GrowattAPI.PlantData(todayEnergy: 0, monthlyEnergy: 0, yearlyEnergy: 0, totalEnergy: 25_650_000,
                                        currentPower: 0, lastUpdate: stamp(logger), timezone: "GMT+8")
        return .init(data: data, devices: devices)
    }

    func map(_ r: Monitoring.GrowattReading, now: Date, previous: Monitoring.Station? = nil) -> Monitoring.Station {
        Map.station(base, reading: r, previous: previous, now: now, offlineAfter: 30, forecastDailyKWhPerKWp: 4, calendar: cal)
    }

    func fleet(_ s: [Monitoring.Station], now: Date) -> Monitoring.Fleet {
        Monitoring.Fleet(s, now: now, settings: .init(), calendar: cal)
    }

    // MARK: the night rule

    func testDaylight() {
        XCTAssertTrue(Monitoring.Daylight.isNight(at(0, 25), calendar: cal))
        XCTAssertTrue(Monitoring.Daylight.isBeforeSunrise(at(5, 59), calendar: cal))
        XCTAssertFalse(Monitoring.Daylight.isNight(at(6, 0), calendar: cal))
        XCTAssertFalse(Monitoring.Daylight.isNight(at(18, 29), calendar: cal))
        XCTAssertTrue(Monitoring.Daylight.isNight(at(18, 30), calendar: cal))
        XCTAssertFalse(Monitoring.Daylight.isBeforeSunrise(at(18, 30), calendar: cal))
    }

    func testAtNightQuietInvertersBehindAReportingLoggerAreAsleep() throws {
        let now = at(0, 25)
        let s = map(reading(logger: at(0, 20), lost: 6), now: now)
        XCTAssertEqual(s.invertersOnline, 0)
        XCTAssertEqual(s.invertersAsleep, 6)
        XCTAssertTrue(s.alarms.isEmpty, "asleep is not an alarm")
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .normal)
        let f = fleet([s], now: now)
        XCTAssertTrue(f.actions.isEmpty)
        XCTAssertEqual(f.needingAttention, 0, "not in the dock's badge")
        XCTAssertEqual(f.invertersOnline, 6, "not counted against availability")
        XCTAssertEqual(try XCTUnwrap(f.availability), 1, accuracy: 1e-9)
        XCTAssertEqual(f.invertersAsleep, 6)
        // the notification sees the same: nothing changed from normal
        XCTAssertTrue(MonitoringNotification.plans(previous: [s.id: .normal], stations: [s], now: now, offlineAfter: 30).isEmpty)
    }

    func testAFaultAtNightIsStillAnAlarm() {
        let now = at(0, 25)
        let s = map(reading(logger: at(0, 20), lost: 4, faults: 1), now: now)
        XCTAssertEqual(s.invertersAsleep, 4)
        XCTAssertEqual(s.alarms.map(\.source), [.growatt])
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .alarm)
        let f = fleet([s], now: now)
        XCTAssertEqual(f.needingAttention, 1)
        XCTAssertEqual(f.invertersOnline, 5, "the asleep four and the one running; the faulted one isn't")
    }

    func testASilentLoggerAtNightIsStillAnAlarm() {
        // past the 30-minute threshold
        let now = at(0, 25)
        let s = map(reading(logger: at(23, 40, dayOffset: -1), lost: 6), now: now)
        XCTAssertNil(s.invertersAsleep)
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .offline)
        XCTAssertEqual(s.alarms.map(\.part), ["ดาต้าล็อกเกอร์"])
        let f = fleet([s], now: now)
        XCTAssertEqual(f.needingAttention, 1)
        XCTAssertEqual(f.actions.count, 1)
        XCTAssertEqual(f.actions[0].status, "ขาดการติดต่อ")
        XCTAssertEqual(f.actions[0].summary(now: now, calendar: cal), "ดาต้าล็อกเกอร์ · 6 อินเวอร์เตอร์ · ตั้งแต่ 23:40".replacingOccurrences(
            of: "23:40", with: Map.clock(at(23, 40, dayOffset: -1), today: today, calendar: cal)))
    }

    func testByDayTheSameInvertersAreLost() {
        let now = at(14, 55)
        let s = map(reading(logger: at(14, 50), lost: 6), now: now)
        XCTAssertNil(s.invertersAsleep)
        XCTAssertEqual(s.alarms.count, 6)
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .alarm)
        let f = fleet([s], now: now)
        XCTAssertEqual(f.actions.count, 1, "one row for the station, not one per inverter")
        XCTAssertEqual(f.actions[0].parts.count, 6)
        XCTAssertEqual(f.actions[0].status, "ขาดการติดต่อ")
        XCTAssertTrue(f.actions[0].summary(now: now, calendar: cal).hasPrefix("อินเวอร์เตอร์ · 6 เครื่อง · ตั้งแต่ "))
        XCTAssertEqual(f.invertersAsleep, 0)
        XCTAssertEqual(f.invertersOnline, 0)
    }

    func testANightReadWithoutTheDeviceListKeepsThemAsleep() {
        let now = at(0, 25)
        let first = map(reading(logger: at(0, 20), lost: 6), now: now)
        var r = reading(logger: at(0, 25), lost: 6)
        r.devices = nil
        let s = map(r, now: now, previous: first)
        XCTAssertEqual(s.invertersAsleep, 6)
        XCTAssertTrue(s.alarms.isEmpty)
    }

    // MARK: ต้องดำเนินการ

    func testActionsAreOnePerStationTheCostliestFirst() {
        let now = at(14, 55)
        func alarm(_ id: String, _ part: String, _ source: Monitoring.Alarm.Source, _ h: Int, loss: Double, code: String = "") -> Monitoring.Alarm {
            .init(id: id, source: source, code: code, part: part, detail: "No AC Connection", since: at(h, 0), loss: .measured(loss))
        }
        let a = Monitoring.Station(id: "a", mpNumber: 25, name: "สถานีผลิตน้ำนครชัยศรี", kWp: 220, inverters: 2,
                                   lastReading: at(14, 50),
                                   alarms: [alarm("a1", "INV 2", .growatt, 9, loss: 80, code: "124"), alarm("a2", "INV 2", .growatt, 11, loss: 20, code: "124")])
        let b = Monitoring.Station(id: "b", mpNumber: 12, name: "สถานีผลิตน้ำบางเลน", kWp: 300, inverters: 3, lastReading: at(14, 50),
                                   alarms: [alarm("b1", "INV 1", .growatt, 10, loss: 30, code: "102"),
                                            alarm("b2", "สถานี", .tcroof, 12, loss: 150)])
        let f = fleet([a, b], now: now)
        XCTAssertEqual(f.actions.map(\.id), ["b", "a"])
        XCTAssertEqual(f.actions[0].status, "TCRoof ตรวจพบ")
        XCTAssertEqual(f.actions[0].summary(now: now, calendar: cal), "สถานี · No AC Connection · อีก 1 รายการ · ตั้งแต่ 10:00")
        XCTAssertEqual(f.actions[1].status, "Error 124")
        XCTAssertEqual(f.actions[1].summary(now: now, calendar: cal), "INV 2 · No AC Connection · ตั้งแต่ 09:00 · เกิด 2 ครั้ง")
    }

    // MARK: the chart

    func testStationCodes() {
        XCTAssertEqual(Monitoring.Chart.name(base), "P1_3")
        XCTAssertEqual(Monitoring.Chart.rest(base), "สถานีผลิตน้ำบ้านโป่ง")
        let mp = Monitoring.Station(id: "m", mpNumber: 25, name: "สถานีผลิตน้ำนครชัยศรี", kWp: 1, inverters: 1)
        XCTAssertEqual(Monitoring.Chart.name(mp), "MP 25")
        XCTAssertEqual(Monitoring.Chart.rest(mp), "สถานีผลิตน้ำนครชัยศรี")
        // a Thai name has no code: it stays whole
        let thai = Monitoring.Station(id: "t", name: "สถานีผลิตน้ำ บ้านโป่ง", kWp: 1, inverters: 1)
        XCTAssertEqual(Monitoring.Chart.name(thai), "สถานีผลิตน้ำ บ้านโป่ง")
        XCTAssertEqual(Monitoring.Chart.rest(thai), "สถานีผลิตน้ำ บ้านโป่ง")
    }

    func testPastSixStationsTheFiveLargestAndTheOthers() {
        let now = at(14, 55)
        let stations = (1...8).map { i in
            Monitoring.Station(id: "s\(i)", name: "P\(i) สถานี", kWp: Double(i * 10), inverters: 1,
                               curve: Array(repeating: 1, count: Monitoring.slots), expectedCurve: Array(repeating: 2, count: Monitoring.slots))
        }
        let chart = Monitoring.Chart(stations, range: .today, now: now, calendar: cal)
        XCTAssertEqual(chart.leadIDs, ["s8", "s7", "s6", "s5", "s4"])
        XCTAssertEqual(chart.otherIDs, ["s1", "s2", "s3"])
        XCTAssertEqual(chart.series.map(\.id), ["s8", "s7", "s6", "s5", "s4", Monitoring.Chart.othersID])
        // the others' line is their sum
        let i = Monitoring.Chart.dayWindow.count / 2
        XCTAssertEqual(chart.series.last?.points[i].actual, 3)
        // hidden: the others all hidden leaves the five
        let hidden = Monitoring.Chart(stations, range: .today, now: now, calendar: cal, hidden: ["s1", "s2", "s3", "s8"])
        XCTAssertEqual(hidden.series.map(\.id), ["s7", "s6", "s5", "s4"])
        // six or fewer: each its own, in their order
        let six = Monitoring.Chart(Array(stations.prefix(6)), range: .week, now: now, calendar: cal)
        XCTAssertEqual(six.leadIDs, ["s1", "s2", "s3", "s4", "s5", "s6"])
        XCTAssertTrue(six.otherIDs.isEmpty)
    }

    func testEventsClusterIntoPills() {
        let now = at(14, 55)
        func station(_ id: String, _ times: [(Int, Int)]) -> Monitoring.Station {
            Monitoring.Station(id: id, name: id.uppercased() + " x", kWp: 100, inverters: 4, lastReading: at(14, 50),
                               alarms: times.enumerated().map { i, t in
                                   .init(id: "\(id)/\(i)", source: .growatt, part: "INV \(i + 1)", detail: "", since: at(t.0, t.1))
                               })
        }
        let stations = [station("a", [(0, 10), (3, 0), (9, 0)]), station("b", [(9, 40), (11, 0)]),
                        // the app's own lines are never marked
                        Monitoring.Station(id: "c", name: "C x", kWp: 1, inverters: 1, alarms: [
                            .init(id: "c/below", source: .tcroof, part: "สถานี", detail: "", since: at(10, 0))])]
        let chart = Monitoring.Chart(stations, range: .today, now: now, calendar: cal)
        let c = chart.clusters
        XCTAssertEqual(c.map(\.events.count), [2, 2, 1])
        XCTAssertEqual(c.map(\.early), [true, false, false])
        XCTAssertEqual(c[1].x, at(9, 0))
        XCTAssertEqual(c[2].x, at(11, 0))
        XCTAssertTrue(Monitoring.Chart(stations, range: .week, now: now, calendar: cal).clusters.isEmpty)
    }

    // MARK: night figures

    func testNightFiguresComeFromYesterday() throws {
        let now = at(0, 25)
        let y = at(0, 0, dayOffset: -1)
        var s = Monitoring.Station(id: "a", name: "A", kWp: 200, inverters: 1, lastReading: at(0, 20),
                                   expectedCurve: Monitoring.Forecast.curve(dailyKWh: 800))
        s.days = [Monitoring.Period(start: y, energy: 700, expected: 800), Monitoring.Period(start: today, energy: nil, expected: 800)]
        let f = fleet([s], now: now)
        XCTAssertTrue(f.isNight)
        XCTAssertTrue(f.isBeforeSunrise)
        XCTAssertEqual(f.yesterdayEnergy, 700)
        XCTAssertEqual(try XCTUnwrap(f.yesterdaySpecificYield), 3.5, accuracy: 1e-9)
        XCTAssertEqual(f.yesterdayLoss, 100)
        XCTAssertEqual(f.productionStart, at(6, 10))
    }
}
