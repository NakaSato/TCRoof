import XCTest
@testable import TCRoofCore

/// `Monitoring.GrowattWebMap`: Growatt's web portal example plants as Monitor rows. The portal names no zone, so it is
/// guessed from a reporting plant's last reading; what the portal didn't say stays nil, never 0.
final class MonitoringWebDemoTests: XCTestCase {
    typealias WebMap = Monitoring.GrowattWebMap
    typealias Plant = GrowattWebDemo.Plant
    typealias Device = GrowattWebDemo.Device

    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }()
    /// 2026-11-09 14:55 in Bangkok.
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 14, minute: 55))! }

    /// `yyyy-MM-dd HH:mm:ss` of `date` on a clock `hours` from GMT.
    func stamp(_ date: Date, hours: Int) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: hours * 3600)!
        let p = c.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", p.year!, p.month!, p.day!, p.hour!, p.minute!, p.second!)
    }

    func device(_ sn: String, status: Int?, pac: Double = 0, eToday: Double = 0, eTotal: Double = 0,
                nominal: Double = 0, last: String, type: String = "tlx") -> Device {
        Device(sn: sn, model: "MIN 5000TL-X", typeName: type, status: status, eToday: eToday, eMonth: eToday * 9,
               eTotal: eTotal, pac: pac, nominalPower: nominal, lastUpdate: last)
    }

    /// A day's 288 samples, W: 1000 × the slot number from 06:00 (slot 72) to 18:00, nil elsewhere.
    var day: [Double?] {
        (0..<Monitoring.slots).map { i in (72..<216).contains(i) ? Double(i) * 1000 : nil }
    }

    func station(_ plant: Plant, day: [Double?]? = nil) -> Monitoring.Station {
        WebMap.station(plant, day: day ?? self.day, previous: nil, now: now, offlineAfter: 30,
                       forecastDailyKWhPerKWp: 4.0, calendar: cal)
    }

    // MARK: the zone

    func testAReportingPlantIsReadInTheZoneOfItsLastReading() {
        let z = WebMap.zone(lastUpdate: stamp(now, hours: 7), reporting: true, now: now)
        XCTAssertEqual(z.secondsFromGMT(), 7 * 3600)
        // a reading 3 minutes ago still rounds to the half hour
        let z2 = WebMap.zone(lastUpdate: stamp(now.addingTimeInterval(-180), hours: 7), reporting: true, now: now)
        XCTAssertEqual(z2.secondsFromGMT(), 7 * 3600)
        // half-hour zones and zones west of GMT
        XCTAssertEqual(WebMap.zone(lastUpdate: stamp(now.addingTimeInterval(5.5 * 3600), hours: 0),
                                   reporting: true, now: now).secondsFromGMT(), 5 * 3600 + 1800)
        XCTAssertEqual(WebMap.zone(lastUpdate: stamp(now, hours: -5), reporting: true, now: now).secondsFromGMT(), -5 * 3600)
        XCTAssertEqual(WebMap.zoneText(TimeZone(secondsFromGMT: 7 * 3600)!), "GMT+07:00")
        XCTAssertEqual(WebMap.zoneText(TimeZone(secondsFromGMT: -(3 * 3600 + 1800))!), "GMT-03:30")
    }

    func testAPlantNotReportingKeepsTheDefaultZone() {
        let z = WebMap.zone(lastUpdate: stamp(now, hours: 7), reporting: false, now: now)
        XCTAssertEqual(z.secondsFromGMT(), Monitoring.GrowattMap.defaultZone.secondsFromGMT())
        XCTAssertEqual(WebMap.zone(lastUpdate: "", reporting: true, now: now).secondsFromGMT(), 8 * 3600)
        XCTAssertEqual(WebMap.zone(lastUpdate: "garbage", reporting: true, now: now).secondsFromGMT(), 8 * 3600)
    }

    func testAReadingDaysOldKeepsTheDefaultZone() {
        let old = now.addingTimeInterval(-3 * 86400)
        let z = WebMap.zone(lastUpdate: stamp(old, hours: 7), reporting: true, now: now)
        XCTAssertEqual(z.secondsFromGMT(), 8 * 3600)
        // just over 14 h off too
        let z2 = WebMap.zone(lastUpdate: stamp(now.addingTimeInterval(-15 * 3600), hours: 0), reporting: true, now: now)
        XCTAssertEqual(z2.secondsFromGMT(), 8 * 3600)
    }

    // MARK: the station

    func testAReportingPlantIsAPairedNormalStation() throws {
        let last = stamp(now.addingTimeInterval(-120), hours: 7)
        let plant = Plant(id: "1234", name: "บ้าน***", nominalPower: 10_000, eTotal: 12_345, devices: [
            device("B", status: 1, pac: 3_200, eToday: 18.5, eTotal: 6_000, last: last),
            device("A", status: 1, pac: 2_800, eToday: 16.0, eTotal: 6_000, last: last),
        ])
        let s = station(plant)
        XCTAssertEqual(s.id, "growatt-web-1234")
        XCTAssertEqual(s.name, "บ้าน***")
        XCTAssertTrue(s.paired)
        XCTAssertEqual(s.kWp, 10, accuracy: 1e-9)
        XCTAssertEqual(s.inverters, 2)
        XCTAssertEqual(s.invertersOnline, 2)
        XCTAssertEqual(try XCTUnwrap(s.energyToday), 34.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.powerNow), 6.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.totalEnergy), 12_345, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.lastReading).timeIntervalSince(now), -120, accuracy: 1)
        XCTAssertTrue(s.alarms.isEmpty)
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .normal)
        XCTAssertEqual(s.expectedToday ?? 0, 40, accuracy: 1e-9)

        // the day's samples in their slots, in kW, up to now (14:55, slot 179)
        XCTAssertEqual(s.curve.count, Monitoring.slots)
        XCTAssertNil(s.curve[71])
        XCTAssertEqual(try XCTUnwrap(s.curve[72]), 72, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.curve[150]), 150, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.curve[179]), 179, accuracy: 1e-9)
        XCTAssertNil(s.curve[180])
        XCTAssertTrue(s.days.isEmpty)
        XCTAssertTrue(s.months.isEmpty)
    }

    func testSizeAndTotalFromTheDevicesWhenThePlantGivesNone() throws {
        let last = stamp(now, hours: 7)
        let plant = Plant(id: "9", name: "x", nominalPower: 0, eTotal: 0, devices: [
            device("A", status: 1, pac: 1_000, eToday: 5, eTotal: 1_000, nominal: 5_000, last: last),
            device("B", status: 1, pac: 1_500, eToday: 6, eTotal: 2_500, nominal: 6_000, last: last),
            device("BAT", status: 1, pac: 0, nominal: 0, last: last, type: "storage"),
        ])
        let s = station(plant)
        XCTAssertEqual(s.kWp, 11, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.totalEnergy), 3_500, accuracy: 1e-9)
        // the battery isn't an inverter
        XCTAssertEqual(s.inverters, 2)
        XCTAssertEqual(s.invertersOnline, 2)
        XCTAssertEqual(try XCTUnwrap(s.powerNow), 2.5, accuracy: 1e-9)
    }

    func testAFaultyInverterIsAnAlarm() throws {
        let last = stamp(now.addingTimeInterval(-60), hours: 7)
        let plant = Plant(id: "77", name: "x", nominalPower: 8_000, eTotal: 100, devices: [
            device("A", status: 1, pac: 2_000, eToday: 10, last: last),
            device("B", status: 3, pac: 900, eToday: 4, last: last),
        ])
        let s = station(plant)
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .alarm)
        XCTAssertEqual(s.invertersOnline, 1)
        let a = try XCTUnwrap(s.alarms.first)
        XCTAssertEqual(s.alarms.count, 1)
        XCTAssertEqual(a.source, .growatt)
        XCTAssertEqual(a.part, "INV 2")
        XCTAssertTrue(a.detail.hasPrefix("Fault"))
        XCTAssertTrue(a.detail.contains("B"))
        // the faulty one's power isn't counted
        XCTAssertEqual(try XCTUnwrap(s.powerNow), 2.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.energyToday), 14, accuracy: 1e-9)
    }

    func testAPlantThatLostContactIsOffline() throws {
        // three days ago on its clock; with nothing reporting the default zone (GMT+8) reads it
        let old = now.addingTimeInterval(-3 * 86400)
        let plant = Plant(id: "5", name: "x", nominalPower: 5_000, eTotal: 4_000, devices: [
            device("A", status: -1, pac: 1_234, eToday: 7, last: stamp(old, hours: 8)),
        ])
        let s = station(plant)
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .offline)
        XCTAssertNil(s.powerNow)
        XCTAssertNil(s.energyToday)
        XCTAssertEqual(try XCTUnwrap(s.lastReading).timeIntervalSince(old), 0, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(s.totalEnergy), 4_000, accuracy: 1e-9)
        XCTAssertEqual(s.alarms.map(\.source), [.lost])
        // the samples are of that old day, not today's
        XCTAssertTrue(s.curve.allSatisfy { $0 == nil })
    }

    func testAPlantWithNoDevicesNeverReported() {
        let plant = Plant(id: "0", name: "ว่าง", nominalPower: 3_000, eTotal: 900, devices: [])
        let s = station(plant)
        XCTAssertTrue(s.paired)
        XCTAssertEqual(s.health(now: now, offlineAfter: 30), .offline)
        XCTAssertNil(s.lastReading)
        XCTAssertNil(s.powerNow)
        XCTAssertNil(s.energyToday)
        XCTAssertNil(s.totalEnergy)
        XCTAssertNil(s.invertersOnline)
        XCTAssertEqual(s.inverters, 1)
        XCTAssertTrue(s.curve.allSatisfy { $0 == nil })
        XCTAssertFalse(s.curve.contains { $0 == 0 })
        XCTAssertEqual(s.alarms.map(\.source), [.lost])

        let r = WebMap.reading(plant, day: day, now: now)
        XCTAssertNil(r.power)
        XCTAssertEqual(r.data?.currentPower, -1)
        XCTAssertEqual(r.data?.lastUpdate, "")
        XCTAssertEqual(r.devices, [])
    }

    func testTheReadingCarriesTheGuessedZoneAndTheDaysTimes() throws {
        let last = stamp(now, hours: 7)
        let plant = Plant(id: "3", name: "x", nominalPower: 1_000, eTotal: 0, devices: [
            device("A", status: 1, last: last), device("BAT", status: 1, last: last, type: "Storage"),
        ])
        let r = WebMap.reading(plant, day: day, now: now)
        XCTAssertEqual(r.data?.timezone, "GMT+07:00")
        let power = try XCTUnwrap(r.power)
        XCTAssertEqual(power.count, Monitoring.slots)
        XCTAssertEqual(power[0].time, "2026-11-09 00:00")
        XCTAssertEqual(power[150].time, "2026-11-09 12:30")
        XCTAssertEqual(power[287].time, "2026-11-09 23:55")
        XCTAssertEqual(r.devices?.map(\.type), [nil, 2])
        XCTAssertEqual(r.devices?.map(\.lost), [false, false])
    }

    // MARK: the portal's own figures

    /// A plant whose `nominalPower` is in kW (`4` beside its inverter's `3600.0`) is read as 4 kW, not 4 W.
    func testAPlantSizeUnder100IsKilowatts() {
        XCTAssertEqual(GrowattWebDemo.plantWatts(4), 4000)
        XCTAssertEqual(GrowattWebDemo.plantWatts(10_000), 10_000)
        XCTAssertEqual(GrowattWebDemo.plantWatts(0), 0)
    }

    /// The plant's own `timezone` wins over the guess, even when its last reading would suggest another zone.
    func testThePlantsOwnZoneWins() throws {
        let info = Data(#"{"result":1,"obj":{"nominalPower":"4","eTotal":"17513.1","timezone":"-4"}}"#.utf8)
        let devices = Data(#"{"result":1,"obj":{"pages":1,"datas":[{"sn":"A","status":"6","nominalPower":"3600.0","eToday":"7.0","pac":"0","lastUpdateTime":"2026-11-08 20:25:07"}]}}"#.utf8)
        let plant = try GrowattWebDemo.parsePlant(info, devices: devices, id: "2371092", name: "Ene")
        XCTAssertEqual(plant.nominalPower, 4000)
        XCTAssertEqual(plant.timezoneHours, -4)
        let now = Date(timeIntervalSince1970: 1_794_169_507) // 2026-11-08 20:25:07 GMT
        let r = Monitoring.GrowattWebMap.reading(plant, day: [], now: now)
        XCTAssertEqual(r.data?.timezone, "GMT-04:00")
    }
}
