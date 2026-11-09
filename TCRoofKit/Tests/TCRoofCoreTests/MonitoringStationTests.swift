import XCTest
@testable import TCRoofCore

/// `Monitoring สถานี` (CHA-73): the string tint, the logger's uptime, the compare limits, the alarm filters and
/// acknowledgements, the tab badges, and the demo's agreement with its row.
final class MonitoringStationTests: XCTestCase {
    typealias M = Monitoring

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        return c
    }

    private var now: Date { M.demoNow(calendar: calendar) }

    private func demo(_ mp: Int) -> M.Station {
        M.demo(now: now, calendar: calendar).first { $0.mpNumber == mp }!
    }

    // MARK: strings

    func testStringTintTwentyPercentUnderTheMedian() {
        // median of the strings with current is 10
        let t = M.StringTint.of([10, 10, 10, 8.1, 8.0, 0, nil, 12])
        XCTAssertEqual(t, [.normal, .normal, .normal, .normal, .low, .none, .none, .normal])
    }

    func testStringTintWithNoCurrentAnywhere() {
        XCTAssertEqual(M.StringTint.of([0, nil, 0.01]), [.none, .none, .none])
        XCTAssertNil(M.StringTint.median([0, nil]))
    }

    func testStringMedianOfEvenCount() {
        XCTAssertEqual(M.StringTint.median([4, 2, 6, 8]), 5)
    }

    // MARK: logger

    func testLoggerDayShareCountsOverlappingGapsOnce() {
        let d = M.LoggerDay(start: now, dueSlots: 100, gaps: [10..<20, 15..<25, 95..<120])
        XCTAssertEqual(d.missingSlots, 20) // 10…24 and 95…99
        XCTAssertEqual(d.receivedShare ?? 0, 0.8, accuracy: 1e-9)
    }

    func testLoggerWeekShareAndHours() {
        let full = M.LoggerDay(start: now, dueSlots: 288)
        let gap = M.LoggerDay(start: now, dueSlots: 288, gaps: [0..<6])
        let none = M.LoggerDay(start: now, dueSlots: 0)
        let l = M.Logger(days: [full, gap, none])
        XCTAssertEqual(l.receivedShare ?? 0, Double(576 - 6) / 576, accuracy: 1e-9)
        XCTAssertEqual(l.missingHours, 0.5, accuracy: 1e-9)
        XCTAssertNil(none.receivedShare)
        XCTAssertNil(M.Logger().receivedShare, "no days: not known, never 100 %")
    }

    // MARK: compare

    private func line(_ dev: String, _ id: String, _ unit: String) -> M.CompareLine {
        M.CompareLine(deviceID: dev, deviceName: dev, metric: M.CompareMetric(id, unit: unit, group: .power))
    }

    func testCompareRefusesAFifthLine() {
        var s = M.CompareSelection()
        for i in 1...4 { XCTAssertNil(s.add(line("INV \(i)", "PAC", "kW"))) }
        XCTAssertEqual(s.add(line("INV 5", "PAC", "kW")), .tooManyLines)
        XCTAssertEqual(s.lines.count, 4)
        // taking one off makes room
        s.toggle(line("INV 1", "PAC", "kW"))
        XCTAssertNil(s.add(line("INV 5", "PAC", "kW")))
    }

    func testCompareRefusesAThirdUnit() {
        var s = M.CompareSelection()
        XCTAssertNil(s.add(line("INV 1", "PAC", "kW")))
        XCTAssertNil(s.add(line("INV 1", "MPPT1 VOLTAGE", "V")))
        XCTAssertEqual(s.add(line("INV 1", "MPPT1 CURRENT", "A")), .tooManyUnits)
        XCTAssertNil(s.add(line("INV 2", "MPPT1 VOLTAGE", "V")), "a unit already on an axis is fine")
        XCTAssertEqual(s.units, ["kW", "V"])
        XCTAssertEqual(s.count(device: "INV 1"), 2)
    }

    func testCompareToggleTwiceIsANoOp() {
        var s = M.CompareSelection([line("INV 1", "PAC", "kW")])
        s.toggle(line("INV 1", "PAC", "kW"))
        XCTAssertTrue(s.lines.isEmpty)
    }

    // MARK: alarms

    func testAlarmFilterByStateDeviceAndPeriod() {
        let s = demo(25)
        let d = M.demoDetail(s, now: now, calendar: calendar)
        let all = M.AlarmFilter(period: .month, end: now).apply(d.events, acknowledged: [], calendar: calendar)
        XCTAssertEqual(all.count, d.events.count)
        XCTAssertEqual(all.first?.firstSeen, all.map(\.firstSeen).max(), "newest first")

        let open = M.AlarmFilter(period: .month, end: now, state: .open).apply(d.events, acknowledged: [], calendar: calendar)
        XCTAssertTrue(open.allSatisfy(\.isOpen))
        XCTAssertFalse(open.isEmpty)

        let inv2 = M.AlarmFilter(period: .month, end: now, device: .inverter("INV 2")).apply(d.events, acknowledged: [], calendar: calendar)
        XCTAssertTrue(inv2.allSatisfy { $0.device == "INV 2" })

        let day = M.AlarmFilter(period: .day, end: now).apply(d.events, acknowledged: [], calendar: calendar)
        XCTAssertTrue(day.allSatisfy { calendar.isDate($0.firstSeen, inSameDayAs: now) || $0.isOpen })
    }

    func testAcknowledgingLowersTheBadge() {
        let s = demo(25)
        let d = M.demoDetail(s, now: now, calendar: calendar)
        let health = s.health(now: now, offlineAfter: 30)
        let before = M.AlarmEvent.unacknowledged(d.events, acknowledged: [])
        XCTAssertGreaterThan(before, 0)
        XCTAssertEqual(M.badge(.alarms, station: s, detail: d, health: health, acknowledged: [])?.text, "\(before) ใหม่")
        let first = d.events.first { !$0.acknowledged }!
        XCTAssertEqual(M.AlarmEvent.unacknowledged(d.events, acknowledged: [first.id]), before - 1)
        let all = Set(d.events.map(\.id))
        XCTAssertNil(M.badge(.alarms, station: s, detail: d, health: health, acknowledged: all))
        let unack = M.AlarmFilter(end: now, state: .unacknowledged).apply(d.events, acknowledged: all, calendar: calendar)
        XCTAssertTrue(unack.isEmpty)
    }

    func testCatalogGivesFixStepsForKnownCodesOnly() {
        let e = M.AlarmEvent(id: "x", source: .growatt, code: "124", device: "INV 2", titleTH: "", firstSeen: now)
        XCTAssertEqual(e.fix?.en, "No AC Connection")
        let unknown = M.AlarmEvent(id: "y", source: .growatt, code: "999", device: "INV 2", titleTH: "", firstSeen: now)
        XCTAssertNil(unknown.fix)
    }

    // MARK: badges and the demo

    func testBadgesFollowTheData() {
        let mp25 = demo(25), mp44 = demo(44), mp12 = demo(12)
        func badge(_ t: M.StationTab, _ s: M.Station) -> String? {
            let h = s.health(now: now, offlineAfter: 30)
            return M.badge(t, station: s, detail: M.demoDetail(s, now: now, calendar: calendar), health: h, acknowledged: [])?.text
        }
        XCTAssertEqual(badge(.inverters, mp25), "1 มีปัญหา")
        XCTAssertEqual(badge(.inverters, mp12), "2", "no problem: the count")
        XCTAssertNil(badge(.logger, mp25))
        XCTAssertEqual(badge(.logger, mp44), "ขาดการติดต่อ")
        XCTAssertEqual(badge(.weather, mp25), "ไม่มี")
        XCTAssertNil(badge(.weather, mp12))
    }

    func testDemoInvertersAddUpToTheStation() {
        let s = demo(25)
        let d = M.demoDetail(s, now: now, calendar: calendar)
        XCTAssertEqual(d.inverters.count, s.inverters)
        let power = d.inverters.compactMap(\.powerNow).reduce(0, +)
        XCTAssertEqual(power, s.powerNow ?? -1, accuracy: 0.01)
        let today = d.inverters.compactMap(\.today).reduce(0, +)
        XCTAssertEqual(today, s.energyToday ?? -1, accuracy: 0.5)
        XCTAssertEqual(d.inverters.filter { $0.status == .fault }.map(\.name), ["INV 2"])
        XCTAssertTrue(d.inverters[1].stringTints.joined().allSatisfy { $0 == .none }, "a stopped inverter carries no current")
    }

    func testDemoStringAlarmIsTinted() {
        let d = M.demoDetail(demo(12), now: now, calendar: calendar)
        // MP 12's `MPPT 4 b`
        XCTAssertEqual(d.inverters[0].stringTints[3][1], .low)
    }

    func testOfflineStationKnowsNothingLive() {
        let s = demo(44)
        let d = M.demoDetail(s, now: now, calendar: calendar)
        XCTAssertTrue(d.inverters.allSatisfy { $0.powerNow == nil && $0.status == .offline })
        XCTAssertNil(d.meter?.importNow)
        let flow = M.EnergyFlow(station: s, detail: d, slot: M.Forecast.slot(of: now, calendar: calendar), offline: true)
        XCTAssertNil(flow.pv); XCTAssertNil(flow.load); XCTAssertNil(flow.bought)
        XCTAssertFalse(M.EnergyFlow.flows(flow.pv))
        XCTAssertLessThan(d.logger?.days.last?.receivedShare ?? 1, 1)
    }

    func testEnergyFlowBalancesAtNow() {
        let s = demo(25)
        let d = M.demoDetail(s, now: now, calendar: calendar)
        let f = M.EnergyFlow(station: s, detail: d, slot: M.Forecast.slot(of: now, calendar: calendar), offline: false)
        // use = PV + bought (zero export: nothing sent back)
        XCTAssertEqual((f.pv ?? 0) + (f.bought ?? 0), f.load ?? -1, accuracy: 0.01)
        XCTAssertEqual(f.sentBack, 0)
        XCTAssertTrue(M.EnergyFlow.flows(f.pv))
        XCTAssertNotNil(f.pvShareOfUse)
    }

    func testRealStationKeepsOnlyWhatItsRowKnows() {
        let s = M.Station.unpaired(id: "j1", mpNumber: 9, name: "x", kWp: 100, inverters: 2)
        let d = M.StationDetail(station: s, health: .offline)
        XCTAssertEqual(d.inverters.map(\.name), ["INV 1", "INV 2"])
        XCTAssertTrue(d.inverters.allSatisfy { $0.powerNow == nil && $0.status == .unknown })
        XCTAssertNil(d.logger); XCTAssertNil(d.meter); XCTAssertNil(d.sensor)
        XCTAssertNil(M.badge(.logger, station: s, detail: d, health: .offline, acknowledged: []), "unpaired is not a lost logger")
    }

    func testMeterTotal() {
        let m = M.Meter(phases: [M.MeterPhase(name: "L1", kW: 3, kvar: 4), M.MeterPhase(name: "L2", kW: 3, kvar: 4)])
        XCTAssertEqual(m.total.kW, 6)
        XCTAssertEqual(m.total.pf ?? 0, 0.6, accuracy: 1e-9)
        let partial = M.Meter(phases: [M.MeterPhase(name: "L1", kW: 3), M.MeterPhase(name: "L2")])
        XCTAssertNil(partial.total.kW, "a phase not known: the total isn't either")
    }

    func testTabFlags() {
        XCTAssertEqual(M.StationTab(flag: "inv"), .inverters)
        XCTAssertEqual(M.StationTab(flag: "alarms"), .alarms)
        XCTAssertNil(M.StationTab(flag: "nope"))
    }
}
