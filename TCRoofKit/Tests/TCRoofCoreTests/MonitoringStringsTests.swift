import XCTest
@testable import TCRoofCore

/// CHA-106: each inverter's string currents from Growatt's `device/inverter/invs_data`, into `Station.inverterStrings`
/// (so `สตริงกระแสต่ำ` judges real stations) and the station page's MPPT grid. The replies are made up in the guide's
/// shape with the field names the live portal answered for a MAX (`currentString1…`, `ipv1…`); a recorded reply is still
/// to come, as `invs_data` hasn't been seen on the live server.
final class MonitoringStringsTests: XCTestCase {
    typealias Map = Monitoring.GrowattMap
    let cal = Calendar.current
    var now: Date { Monitoring.demoNow(calendar: cal) }
    let base = Monitoring.Station.unpaired(id: "mp12", mpNumber: 12, name: "สถานี 12", kWp: 200, inverters: 2)

    /// `invs_data` as the guide nests it: each inverter's readings under its serial number, twice.
    func reply(_ inverters: [String: [String: Any]]) throws -> Data {
        var data: [String: Any] = [:]
        for (sn, fields) in inverters { data[sn] = ["dataloggerSn": "DL01", sn: fields] }
        return try JSONSerialization.data(withJSONObject: ["error_code": 0, "error_msg": "", "data": data])
    }

    func batch(_ inverters: [String: [String: Any]]) throws -> [String: GrowattAPI.Latest] {
        try GrowattAPI.parseLatestBatch(try reply(inverters))
    }

    /// Two MAX inverters at their serials' order, reporting now.
    var devices: [GrowattAPI.Device] {
        [GrowattAPI.Device(sn: "MAXB", type: 4, status: 1), GrowattAPI.Device(sn: "MAXA", type: 4, status: 1)]
    }

    func plantData() -> GrowattAPI.PlantData {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let p = c.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now.addingTimeInterval(-180))
        let stamp = String(format: "%04d-%02d-%02d %02d:%02d:%02d", p.year!, p.month!, p.day!, p.hour!, p.minute!, p.second!)
        return GrowattAPI.PlantData(todayEnergy: 600, monthlyEnergy: 0, yearlyEnergy: 0, totalEnergy: 1, currentPower: 120,
                                    lastUpdate: stamp, timezone: "GMT+8")
    }

    func map(_ inverters: [String: GrowattAPI.Latest]?, devices: [GrowattAPI.Device]? = nil,
             previous: Monitoring.Station? = nil) -> Monitoring.Station {
        Map.station(base, reading: .init(data: plantData(), devices: devices ?? self.devices, inverters: inverters),
                    previous: previous, now: now, offlineAfter: 30, forecastDailyKWhPerKWp: 4, calendar: cal)
    }

    // MARK: one inverter's reply

    func testStringsTwoToAnMPPTUpToTheLastCarryingCurrent() throws {
        let b = try batch(["MAXA": ["currentString1": 9.8, "currentString2": "9.6", "currentString3": 9.9,
                                     "currentString4": 3.1, "currentString5": 0, "currentString6": 0, "currentString32": 0,
                                     "ipv1": 19.4, "ipv2": 13]])
        let latest = try XCTUnwrap(b["MAXA"])
        XCTAssertEqual(latest.datalogger, "DL01")
        XCTAssertEqual(latest.stringCurrents.count, 32, "up to the last one Growatt sent")
        XCTAssertNil(latest.stringCurrents[6], "one Growatt left out")
        XCTAssertEqual(latest.mpptCurrents, [19.4, 13])
        // the unused inputs after string 4 are left out; a number written as text still reads
        XCTAssertEqual(Map.mppts(latest), [[9.8, 9.6], [9.9, 3.1]])
    }

    func testOnlyMPPTCurrentsGiveOneStringAnMPPT() throws {
        let latest = try XCTUnwrap(try batch(["MAXA": ["ipv1": 19.4, "ipv2": 18.9, "ipv3": 0, "pac": 1000]])["MAXA"])
        XCTAssertEqual(latest.stringCurrents, [])
        XCTAssertEqual(Map.mppts(latest), [[19.4], [18.9]])
        // all strings at 0 (given, but nothing on them): the MPPTs are read instead
        let zeros = try XCTUnwrap(try batch(["MAXA": ["currentString1": 0, "currentString2": 0, "ipv1": 7.5]])["MAXA"])
        XCTAssertEqual(Map.mppts(zeros), [[7.5]])
    }

    func testNoCurrentAnywhereIsNoGrid() throws {
        let night = try XCTUnwrap(try batch(["MAXA": ["currentString1": 0, "currentString2": 0.02, "ipv1": 0]])["MAXA"])
        XCTAssertEqual(Map.mppts(night), [])
        let none = try XCTUnwrap(try batch(["MAXA": ["pac": 0]])["MAXA"])
        XCTAssertEqual(Map.mppts(none), [])
    }

    // MARK: the station

    func testEachInverterInINVOrder() throws {
        let s = map(try batch(["MAXA": ["currentString1": 10, "currentString2": 10],
                               "MAXB": ["currentString1": 8, "currentString2": 8, "currentString3": 8]]))
        // device/list's inverters sorted by serial: MAXA is INV 1
        XCTAssertEqual(s.inverterStrings, [[[10, 10]], [[8, 8], [8]]])
        // without device/list, the batch's serials sorted
        let alone = map(try batch(["MAXB": ["currentString1": 8], "MAXA": ["currentString1": 10]]), devices: [])
        XCTAssertEqual(alone.inverterStrings, [], "device/list said there are no inverters")
    }

    func testAMissedReadKeepsTheLastCurrentsNeverZero() throws {
        let before = map(try batch(["MAXA": ["currentString1": 10, "currentString2": 9],
                                    "MAXB": ["currentString1": 8, "currentString2": 7]]))
        // invs_data failed: every inverter keeps its currents
        XCTAssertEqual(map(nil, previous: before).inverterStrings, before.inverterStrings)
        // one inverter left out of the reply keeps its own
        let partial = map(try batch(["MAXB": ["currentString1": 6, "currentString2": 6]]), previous: before)
        XCTAssertEqual(partial.inverterStrings, [[[10, 9]], [[6, 6]]])
        // read, but no current (dusk): the last grid at 0 A, as read
        let dusk = map(try batch(["MAXA": ["currentString1": 0], "MAXB": ["currentString1": 0]]), previous: before)
        XCTAssertEqual(dusk.inverterStrings, [[[0, 0]], [[0, 0]]])
        // and nothing judged at 0 A
        XCTAssertTrue(Monitoring.Fleet.stringChecks(dusk, percent: 20, now: now).isEmpty)
    }

    func testAnInverterOutOfContactHasNoCurrents() throws {
        let lost = [GrowattAPI.Device(sn: "MAXA", type: 4, status: 1), GrowattAPI.Device(sn: "MAXB", type: 4, status: 1, lost: true)]
        let s = map(try batch(["MAXA": ["currentString1": 10, "currentString2": 10],
                               "MAXB": ["currentString1": 10, "currentString2": 2]]), devices: lost)
        XCTAssertEqual(s.inverterStrings, [[[10, 10]], []], "its last readings are old: not judged")
    }

    func testAWeakStringRaisesItsLineAfterThirtyMinutes() throws {
        let reading = try batch(["MAXA": ["currentString1": 10, "currentString2": 10, "currentString3": 10, "currentString4": 10],
                                 "MAXB": ["currentString1": 9.6, "currentString2": 9.8, "currentString3": 10, "currentString4": 3.1]])
        let s = map(reading)
        // the same reading 30 minutes on: a logger threshold past that, as if the polls in between read the same
        let settings = Monitoring.Settings(loggerOfflineMinutes: 60)
        let first = Monitoring.Fleet([s], now: now, settings: settings, calendar: cal)
        XCTAssertFalse(first.stations[0].alarms.contains { $0.part.contains("MPPT") }, "not before it has held")
        let later = Monitoring.Fleet([s], now: now.addingTimeInterval(Monitoring.Fleet.stringHold), settings: settings,
                                     raised: first.raised, calendar: cal)
        let line = try XCTUnwrap(later.stations[0].alarms.first { $0.part.contains("MPPT") })
        XCTAssertEqual(line.part, "INV 2 · MPPT 2 b")
        XCTAssertEqual(line.detail, "สตริง 3.1 A จากค่ากลาง 9.7 A · เกณฑ์ 20%")
    }

    func testThePageGridShowsTheSameCurrents() throws {
        let s = map(try batch(["MAXA": ["currentString1": 10, "currentString2": 4]]))
        let d = Monitoring.StationDetail(station: s, health: .normal)
        XCTAssertEqual(d.inverters.map(\.strings), [[[10, 4]], []])
        XCTAssertEqual(d.inverters[0].stringMedian, 7)
        // none while the station is out of contact
        XCTAssertEqual(Monitoring.StationDetail(station: s, health: .offline).inverters.map(\.strings), [[], []])
    }

    // MARK: from the server's poll

    func testTheServersInvsDataReadsAsTheAppsOwn() throws {
        let text = String(decoding: try reply(["MAXA": ["currentString1": 10, "currentString2": 3]]), as: UTF8.self)
        let r = try XCTUnwrap(Monitoring.ServerReading(fields: ["stationID": "mp12", "plantID": 7, "inverters": text], readAt: now))
        XCTAssertEqual(r.reading.inverters?["MAXA"].map(Map.mppts), [[10, 3]])
        let without = try XCTUnwrap(Monitoring.ServerReading(fields: ["stationID": "mp12", "plantID": 7], readAt: now))
        XCTAssertNil(without.reading.inverters, "an older document: the station keeps its currents")
    }
}
