import XCTest
@testable import TCRoofCore

/// `Monitoring.GrowattMap` (issue #259): Growatt's answers as a station, on fixture JSON. What Growatt didn't say
/// is nil, never 0; a failed part keeps the previous reading; silence past the logger threshold is offline.
final class MonitoringGrowattTests: XCTestCase {
    typealias Map = Monitoring.GrowattMap
    let cal = Calendar.current
    /// Today 14:55 on the device's clock; the plant writes GMT+8.
    var now: Date { Monitoring.demoNow(calendar: cal) }
    var today: Date { cal.startOfDay(for: now) }
    let plantZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let base = Monitoring.Station.unpaired(id: "mp25", mpNumber: 25, name: "สถานีผลิตน้ำนครชัยศรี", kWp: 220, inverters: 2)

    /// `plant/data` as the plant writes it, with its last reading `at` (a local time) on its own clock.
    func data(at date: Date, power: Double = 150, today: Double = 410, total: Double = 290_000) -> GrowattAPI.PlantData {
        GrowattAPI.PlantData(todayEnergy: today, monthlyEnergy: 0, yearlyEnergy: 0, totalEnergy: total, currentPower: power,
                             lastUpdate: stamp(date), timezone: "GMT+8")
    }

    /// `yyyy-MM-dd HH:mm:ss` of a local instant on the plant's clock.
    func stamp(_ date: Date, seconds: Bool = true) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = plantZone
        let p = c.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let head = String(format: "%04d-%02d-%02d %02d:%02d", p.year!, p.month!, p.day!, p.hour!, p.minute!)
        return seconds ? head + String(format: ":%02d", p.second!) : head
    }

    func at(_ h: Int, _ m: Int, dayOffset: Int = 0) -> Date {
        let day = cal.date(byAdding: .day, value: dayOffset, to: today)!
        return cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
    }

    /// A day's `plant/power` in W: the forecast's shape at `kW` peak from 06:00 to `until`.
    func powers(until: Date, peakKW: Double = 150, dayOffset: Int = 0) -> [GrowattAPI.PowerPoint] {
        stride(from: 0, to: Monitoring.slots, by: 1).compactMap { i in
            let t = at(0, 0, dayOffset: dayOffset).addingTimeInterval(TimeInterval(i * 5 * 60))
            guard t <= until else { return nil }
            let h = Double(i) * 5 / 60
            let v = h > 6 && h < 18.5 ? peakKW * 1000 * sin(Double.pi * (h - 6) / 12.5) : 0
            return GrowattAPI.PowerPoint(time: stamp(t, seconds: false), power: v)
        }
    }

    func map(_ reading: Monitoring.GrowattReading, previous: Monitoring.Station? = nil, offlineAfter: Int = 30) -> Monitoring.Station {
        Map.station(base, reading: reading, previous: previous, now: now, offlineAfter: offlineAfter,
                    forecastDailyKWhPerKWp: 4.0, calendar: cal)
    }

    // MARK: times

    func testZonesAndStamps() throws {
        XCTAssertEqual(Map.timeZone("GMT+8").secondsFromGMT(), 8 * 3600)
        XCTAssertEqual(Map.timeZone("GMT+07:00").secondsFromGMT(), 7 * 3600)
        XCTAssertEqual(Map.timeZone("GMT-3").secondsFromGMT(), -3 * 3600)
        XCTAssertEqual(Map.timeZone("UTC").secondsFromGMT(), 0)
        XCTAssertEqual(Map.timeZone("Asia/Bangkok").identifier, "Asia/Bangkok")
        // nothing readable: the guide's GMT+8
        XCTAssertEqual(Map.timeZone("").secondsFromGMT(), 8 * 3600)
        XCTAssertEqual(Map.timeZone("tomorrow").secondsFromGMT(), 8 * 3600)

        let d = try XCTUnwrap(Map.date("2026-09-09 15:41:34", zone: Map.timeZone("GMT+8")))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(utc.dateComponents([.hour, .minute], from: d).hour, 7)
        XCTAssertNotNil(Map.date("2026-09-09 15:41", zone: plantZone))
        XCTAssertNotNil(Map.date("2026-09-09", zone: plantZone))
        XCTAssertNil(Map.date("", zone: plantZone))
        XCTAssertNil(Map.date("2026-13-09 15:41", zone: plantZone))
        XCTAssertNil(Map.date("yesterday", zone: plantZone))
        XCTAssertEqual(Map.dayText(d, zone: plantZone), "2026-09-09")
        XCTAssertEqual(Map.monthText(d, zone: plantZone), "2026-09")
    }

    // MARK: the live station

    func testALiveReadingFillsTheStation() throws {
        let last = at(14, 52)
        let devices = [GrowattAPI.Device(sn: "MAX0002", type: 4, model: "MAX 80KTL3 LV", status: 1, lost: false, lastUpdate: stamp(last)),
                       GrowattAPI.Device(sn: "MAX0001", type: 4, model: "MAX 125KTL3-X LV", status: 1, lost: false, lastUpdate: stamp(last)),
                       GrowattAPI.Device(sn: "MTR01", type: 3, model: "meter", status: 1, lost: false)]
        let s = map(.init(data: data(at: last), power: powers(until: last), devices: devices))
        XCTAssertTrue(s.paired)
        XCTAssertEqual(s.powerNow, 150)
        XCTAssertEqual(s.energyToday, 410)
        XCTAssertEqual(s.totalEnergy, 290_000)
        XCTAssertEqual(try XCTUnwrap(s.lastReading).timeIntervalSince(last), 0, accuracy: 1)
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .normal)
        XCTAssertEqual(s.inverters, 2)
        XCTAssertEqual(s.invertersOnline, 2)
        XCTAssertTrue(s.alarms.isEmpty)
        // the forecast: 220 kWp × 4 kWh/kWp, its part to 14:55
        XCTAssertEqual(try XCTUnwrap(s.expectedToday), 880, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(s.expectedSoFar), Monitoring.Forecast.energy(s.expectedCurve, through: Monitoring.Forecast.slot(of: now, calendar: cal)), accuracy: 1e-9)
        XCTAssertLessThan(try XCTUnwrap(s.expectedSoFar), 880)
        // the curve: W read as kW, one value per slot to 14:52, nothing after
        XCTAssertEqual(s.curve.count, Monitoring.slots)
        let slot = Monitoring.Forecast.slot(of: last, calendar: cal)
        XCTAssertNotNil(s.curve[slot])
        XCTAssertNil(s.curve[slot + 1])
        XCTAssertEqual(try XCTUnwrap(s.curve.compactMap { $0 }.max()), 150, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(s.curve[6 * 12 + 1]), 150 * sin(Double.pi * (5.0 / 60) / 12.5), accuracy: 1e-6)
        // nothing here reads the meter or a sensor
        XCTAssertNil(s.backfeedToday)
        XCTAssertNil(s.prToday)
        XCTAssertNil(s.yesterdaySoFar)
        XCTAssertTrue(s.days.isEmpty)
    }

    func testPowerUnitIsCheckedAgainstThePlantsPower() {
        // the guide's W
        XCTAssertEqual(Map.powerScale([.init(time: "t", power: 150_000)], currentKW: 150), 0.001)
        // a server already answering in kW
        XCTAssertEqual(Map.powerScale([.init(time: "t", power: 149.5)], currentKW: 150), 1)
        // too little power to tell: W
        XCTAssertEqual(Map.powerScale([.init(time: "t", power: 120)], currentKW: 0.1), 0.001)
        XCTAssertEqual(Map.powerScale([], currentKW: 150), 0.001)
    }

    func testYesterdayByTheSameTime() throws {
        let last = at(14, 52)
        let s = map(.init(data: data(at: last), power: powers(until: last), yesterdayPower: powers(until: at(23, 55, dayOffset: -1), dayOffset: -1)))
        let y = try XCTUnwrap(s.yesterdaySoFar)
        // yesterday's whole day is more than its part to 14:55
        let whole = Monitoring.Forecast.energy(Map.curve(powers(until: at(23, 55, dayOffset: -1), dayOffset: -1), day: at(0, 0, dayOffset: -1),
                                                         zone: plantZone, scale: 0.001, calendar: cal), through: Monitoring.slots - 1) ?? 0
        XCTAssertGreaterThan(y, 0)
        XCTAssertLessThan(y, whole)
    }

    // MARK: nothing known is nil

    func testAPlantThatNeverReportedKnowsNothing() {
        let never = GrowattAPI.PlantData(todayEnergy: 0, monthlyEnergy: 0, yearlyEnergy: 0, totalEnergy: 0, currentPower: -1, lastUpdate: "", timezone: "")
        let s = map(.init(data: never, power: [], devices: []))
        XCTAssertTrue(s.paired)
        XCTAssertNil(s.powerNow)
        XCTAssertNil(s.energyToday)
        XCTAssertNil(s.totalEnergy)
        XCTAssertNil(s.lastReading)
        XCTAssertNil(s.invertersOnline, "no inverter listed: not known, not 0")
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .offline)
        XCTAssertEqual(s.alarms.map(\.source), [.lost])
        XCTAssertEqual(s.alarms[0].detail, "ยังไม่มีข้อมูลจาก Growatt · ผลิตจริงไม่ทราบ")
        // it counts for the badge: paired and offline
        XCTAssertEqual(Monitoring.Fleet([s], now: now, settings: .init()).needingAttention, 1)
        XCTAssertTrue(s.curve.allSatisfy { $0 == nil })
    }

    func testAnEmptyReadingKeepsThePreviousStation() throws {
        let last = at(14, 40)
        let first = map(.init(data: data(at: last), power: powers(until: last),
                              devices: [.init(sn: "A", type: 4, status: 1, lost: false), .init(sn: "B", type: 4, status: 0, lost: false)]))
        let again = map(.init(), previous: first)
        XCTAssertEqual(again.powerNow, first.powerNow)
        XCTAssertEqual(again.energyToday, 410)
        XCTAssertEqual(again.totalEnergy, 290_000)
        XCTAssertEqual(again.lastReading, first.lastReading)
        XCTAssertEqual(again.curve, first.curve)
        XCTAssertEqual(again.invertersOnline, 2)
        XCTAssertEqual(again.health(now: now, offlineAfter: 30), .normal, "stale, not offline, within the threshold")
        // the station as read before it was paired stands in for nothing
        let fresh = map(.init(), previous: base)
        XCTAssertNil(fresh.powerNow)
        XCTAssertNil(fresh.totalEnergy)
    }

    func testAPartThatFailedKeepsItsPreviousValueAlone() throws {
        let first = map(.init(data: data(at: at(14, 40)), power: powers(until: at(14, 40)), devices: [.init(sn: "A", type: 4, status: 1, lost: false)]))
        // plant/data came, plant/power and device/list didn't
        let s = map(.init(data: data(at: at(14, 52), power: 160, today: 430)), previous: first)
        XCTAssertEqual(s.powerNow, 160)
        XCTAssertEqual(s.energyToday, 430)
        XCTAssertEqual(s.curve, first.curve)
        XCTAssertEqual(s.invertersOnline, 1)
    }

    // MARK: offline

    func testSilencePastTheThresholdIsOfflineWithALostLine() throws {
        let stopped = at(9, 0)
        let s = map(.init(data: data(at: stopped, power: 95, today: 120), power: powers(until: stopped),
                          devices: [.init(sn: "A", type: 4, status: 1, lost: true)]))
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .offline)
        XCTAssertNil(s.powerNow, "the power at 09:00 isn't the power now")
        XCTAssertEqual(s.energyToday, 120, "what it made before it stopped")
        XCTAssertEqual(s.totalEnergy, 290_000)
        XCTAssertEqual(s.alarms.count, 1)
        let lost = s.alarms[0]
        XCTAssertEqual(lost.source, .lost)
        XCTAssertEqual(lost.part, "ดาต้าล็อกเกอร์")
        XCTAssertEqual(lost.detail, "ไม่มีข้อมูลตั้งแต่ 09:00 · ผลิตจริงไม่ทราบ")
        XCTAssertEqual(lost.since, stopped)
        XCTAssertEqual(lost.loss, .atMost(try XCTUnwrap(s.shortfall)))
        // the curve keeps the morning
        XCTAssertNotNil(s.curve[Monitoring.Forecast.slot(of: at(8, 55), calendar: cal)])
        XCTAssertNil(s.curve[Monitoring.Forecast.slot(of: at(9, 5), calendar: cal)])
        // a reading from yesterday says nothing about today
        let old = map(.init(data: data(at: at(17, 0, dayOffset: -1), power: 0, today: 700)))
        XCTAssertNil(old.energyToday)
        XCTAssertNil(old.powerNow)
        XCTAssertEqual(old.totalEnergy, 290_000)
        XCTAssertTrue(old.alarms[0].detail.hasPrefix("ไม่มีข้อมูลตั้งแต่ "))
        XCTAssertTrue(old.alarms[0].detail.contains("/"), "a day before today names its date")
        // a wider threshold keeps a 20-minute-old reading online
        XCTAssertEqual(map(.init(data: data(at: at(14, 35))), offlineAfter: 30).health(now: now, offlineAfter: 30), .normal)
        XCTAssertEqual(map(.init(data: data(at: at(14, 35))), offlineAfter: 15).alarms.map(\.source), [.lost])
    }

    // MARK: the inverters

    func testAFaultOrALostInverterIsAnAlarmAndNotOnline() throws {
        let last = at(14, 52)
        let devices = [GrowattAPI.Device(sn: "MAX0001", type: 4, model: "MAX 125KTL3-X LV", status: 1, lost: false, lastUpdate: stamp(last)),
                       GrowattAPI.Device(sn: "MAX0002", type: 4, model: "MAX 80KTL3 LV", status: 3, lost: false, lastUpdate: stamp(at(9, 50))),
                       GrowattAPI.Device(sn: "MAX0003", type: 4, model: "MAX 80KTL3 LV", status: 1, lost: true, lastUpdate: stamp(at(11, 0)))]
        let s = map(.init(data: data(at: last), devices: devices))
        XCTAssertEqual(s.inverters, 3, "Growatt lists more than the job knew")
        XCTAssertEqual(s.invertersOnline, 1)
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .alarm)
        XCTAssertEqual(s.alarms.map(\.part), ["INV 2", "INV 3"])
        XCTAssertEqual(s.alarms[0].source, .growatt)
        XCTAssertEqual(s.alarms[0].label, "Error")
        XCTAssertEqual(s.alarms[0].detail, "Fault · MAX 80KTL3 LV MAX0002")
        XCTAssertEqual(s.alarms[0].since, at(9, 50))
        XCTAssertEqual(s.alarms[1].source, .lost)
        XCTAssertEqual(s.alarms[1].detail, "ขาดการติดต่อ · MAX 80KTL3 LV MAX0003")
        // the fleet lists them under ต้องดำเนินการ as one row for the station
        let actions = Monitoring.Fleet([s], now: now, settings: .init()).actions
        XCTAssertEqual(actions.map(\.parts), [["INV 2", "INV 3"]])
        XCTAssertEqual(actions.first?.summary(now: now, calendar: cal), "อินเวอร์เตอร์ · 2 เครื่อง · ตั้งแต่ 09:50")
    }

    func testAnAlarmStillRaisedKeepsItsStartCountAndWorkOrder() throws {
        let fault = GrowattAPI.Device(sn: "MAX0002", type: 4, status: 3, lost: false, lastUpdate: stamp(at(9, 50)))
        var first = map(.init(data: data(at: at(14, 40)), devices: [fault]))
        first.alarms[0].occurrences = 4
        first.alarms[0].workOrder = "TK-0412"
        let later = GrowattAPI.Device(sn: "MAX0002", type: 4, status: 3, lost: false, lastUpdate: stamp(at(14, 52)))
        let s = map(.init(data: data(at: at(14, 52)), devices: [later]), previous: first)
        XCTAssertEqual(s.alarms.count, 1)
        XCTAssertEqual(s.alarms[0].since, at(9, 50))
        XCTAssertEqual(s.alarms[0].occurrences, 4)
        XCTAssertEqual(s.alarms[0].workOrder, "TK-0412")
        // cleared: gone
        let ok = GrowattAPI.Device(sn: "MAX0002", type: 4, status: 1, lost: false, lastUpdate: stamp(at(14, 52)))
        XCTAssertTrue(map(.init(data: data(at: at(14, 52)), devices: [ok]), previous: s).alarms.isEmpty)
    }

    func testAReadWithoutTheDeviceListKeepsTheInvertersAlarms() throws {
        let fault = GrowattAPI.Device(sn: "MAX0002", type: 4, status: 3, lost: false, lastUpdate: stamp(at(9, 50)))
        let first = map(.init(data: data(at: at(14, 40)), devices: [fault]))
        // plant/data only (the history or the strings read alone, or device/list failing): the fault stands
        let s = map(.init(data: data(at: at(14, 52))), previous: first)
        XCTAssertEqual(s.alarms.map(\.id), first.alarms.map(\.id))
        XCTAssertEqual(s.alarms.first?.since, at(9, 50))
        // offline, the logger's line replaces them
        XCTAssertEqual(map(.init(data: data(at: at(9, 0))), previous: first).alarms.map(\.source), [.lost])
    }

    func testAHistoryReadUsesThePlantsZoneWithoutPlantData() throws {
        let first = map(.init(data: data(at: at(14, 40))))
        // a plant on GMT+7, its days read without plant/data
        let zone = TimeZone(secondsFromGMT: 7 * 3600)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let rows = [GrowattAPI.EnergyPoint(date: Map.dayText(yesterday.addingTimeInterval(12 * 3600), zone: zone), energy: 777)]
        let s = map(.init(days: rows, timezone: "GMT+7"), previous: first)
        XCTAssertEqual(s.days[28].energy, 777)
        XCTAssertEqual(s.lastReading, first.lastReading)
        XCTAssertEqual(s.energyToday, 410)
    }

    // MARK: the history

    func testDaysAndMonthsFromPlantEnergy() throws {
        let last = at(14, 52)
        var dayRows: [GrowattAPI.EnergyPoint] = []
        for back in 1...29 {
            let d = cal.date(byAdding: .day, value: -back, to: today)!
            dayRows.append(.init(date: Map.dayText(d.addingTimeInterval(12 * 3600), zone: plantZone), energy: back == 3 ? nil : Double(800 - back)))
        }
        let thisMonth = cal.dateInterval(of: .month, for: now)!.start
        let lastMonth = cal.date(byAdding: .month, value: -1, to: thisMonth)!
        let monthRows = [GrowattAPI.EnergyPoint(date: Map.monthText(lastMonth.addingTimeInterval(12 * 3600), zone: plantZone), energy: 24_000),
                         GrowattAPI.EnergyPoint(date: Map.monthText(thisMonth.addingTimeInterval(12 * 3600), zone: plantZone), energy: 5_000)]
        let s = map(.init(data: data(at: last), days: dayRows, months: monthRows))
        XCTAssertEqual(s.days.count, 30)
        XCTAssertEqual(s.days.last?.start, today)
        XCTAssertEqual(s.days.last?.energy, 410, "today is the live figure")
        XCTAssertEqual(s.days[28].energy, 799)
        XCTAssertNil(s.days[26].energy, "a day Growatt gave no energy for is unknown")
        XCTAssertEqual(s.days[0].energy, 800 - 29)
        XCTAssertEqual(try XCTUnwrap(s.days[0].expected), 880, accuracy: 1e-6)
        XCTAssertEqual(s.months.count, 12)
        XCTAssertEqual(s.months.last?.energy, 5_000)
        XCTAssertEqual(s.months[10].energy, 24_000)
        XCTAssertNil(s.months[0].energy)
        // this month's forecast is its days so far, the one before its whole
        let elapsed = Double((cal.dateComponents([.day], from: thisMonth, to: today).day ?? 0) + 1)
        XCTAssertEqual(try XCTUnwrap(s.months.last?.expected), 880 * elapsed, accuracy: 1e-6)
        let inLastMonth = Double(cal.range(of: .day, in: .month, for: lastMonth)!.count)
        XCTAssertEqual(try XCTUnwrap(s.months[10].expected), 880 * inLastMonth, accuracy: 1e-6)
        // the chart reads them
        let week = Monitoring.Chart([s], range: .week, now: now, calendar: cal)
        XCTAssertEqual(week.total.count, 7)
        XCTAssertEqual(week.total.last?.actual, 410)
        XCTAssertEqual(Monitoring.Chart([s], range: .year, now: now, calendar: cal).total.last?.actual, 5_000)
        // the next poll without the history keeps it, today's figure refreshed
        let next = map(.init(data: data(at: at(14, 57), today: 425)), previous: s)
        XCTAssertEqual(next.days.count, 30)
        XCTAssertEqual(next.days.last?.energy, 425)
        XCTAssertEqual(next.days[28].energy, 799)
        XCTAssertEqual(next.months.count, 12)
    }

    // MARK: settings

    func testPairingNamesItsServer() throws {
        var s = Monitoring.Settings()
        let a = Monitoring.Settings.Server(name: "A", url: "https://openapi.growatt.com/v1/")
        let b = Monitoring.Settings.Server(name: "B", url: "https://test.growatt.com/v1/")
        s.servers = [a, b]
        s.pairings = ["mp25": "1913", "mp44": " 1917 ", "mp7": "plant-x"]
        s.pairingServers = ["mp44": b.id]
        XCTAssertEqual(s.pairing(of: "mp25")?.server.id, a.id, "no server named: the first")
        XCTAssertEqual(s.pairing(of: "mp25")?.plantID, 1913)
        XCTAssertEqual(s.pairing(of: "mp44")?.server.id, b.id)
        XCTAssertEqual(s.pairing(of: "mp44")?.plantID, 1917)
        XCTAssertNil(s.pairing(of: "mp7"), "a plant id that isn't a number")
        XCTAssertNil(s.pairing(of: "mp99"))
        // a named server no longer listed falls back to the first
        s.pairingServers["mp25"] = UUID()
        XCTAssertEqual(s.pairing(of: "mp25")?.server.id, a.id)
        XCTAssertNil(Monitoring.Settings(pairings: ["x": "1"]).pairing(of: "x"), "no server at all")
        // it round-trips, and an older file without it reads
        let json = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(Monitoring.Settings.self, from: json), s)
        let old = try JSONDecoder().decode(Monitoring.Settings.self, from: Data(#"{"pairings":{"a":"1"}}"#.utf8))
        XCTAssertEqual(old.pairings, ["a": "1"])
        XCTAssertTrue(old.pairingServers.isEmpty)
    }
}
