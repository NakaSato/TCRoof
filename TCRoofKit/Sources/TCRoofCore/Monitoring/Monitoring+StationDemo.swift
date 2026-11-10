import Foundation

extension Monitoring {
    /// The board's example detail for one of `demo()`'s stations (`iPadPwaStationMonitor`), built from the station's
    /// own curve and alarms so the page's cards, charts and tables agree with its row. Example values only, for
    /// `-monitoringDemo YES` and the tests.
    public static func demoDetail(_ s: Station, now: Date, offlineAfter: Int = 30, calendar: Calendar = .current) -> StationDetail {
        let today = calendar.startOfDay(for: now)
        let nowSlot = Forecast.slot(of: now, calendar: calendar)
        let offline = s.health(now: now, offlineAfter: offlineAfter) == .offline
        let mp = s.mpNumber ?? 0
        // the slot after the last reading: nothing past it was received
        let lastSlot: Int = s.lastReading.map { Forecast.slot(of: $0, calendar: calendar) } ?? nowSlot
        let readThrough = offline ? lastSlot : nowSlot
        func wobble(_ i: Int, _ k: Double) -> Double { 1 + 0.015 * sin(Double(i) * 0.9 + k) }

        // inverters: the ratings fill the station's size, the faulty one stops at its alarm
        let ratings = demoRatings(kWp: s.kWp, count: s.inverters)
        let rated = ratings.reduce(0, +)
        let faults = s.alarms.filter { $0.source == .growatt }
        let loggerSN = String(format: "DLG%03d%dZ", mp * 41 % 1000, s.inverters)
        let month = s.months.last?.energy
        var inverters: [Inverter] = []
        for (i, r) in ratings.enumerated() {
            let name = "INV \(i + 1)"
            let fault = faults.filter { $0.part == name }.min { $0.since < $1.since }
            let stopSlot = fault.map { Forecast.slot(of: $0.since, calendar: calendar) }
            let share = rated > 0 ? r / rated : 0
            // the others carry the station after a fault; before it each its share
            let healthyShare: Double = {
                let healthy = ratings.enumerated().filter { j, _ in !faults.contains { $0.part == "INV \(j + 1)" } }.map(\.element)
                let h = healthy.reduce(0, +)
                return h > 0 ? r / h : 0
            }()
            let firstFault = faults.map { Forecast.slot(of: $0.since, calendar: calendar) }.min()
            let curve: [Double?] = s.curve.enumerated().map { j, v in
                guard let v else { return nil }
                if let st = stopSlot, j >= st { return 0 }
                if let ff = firstFault, j >= ff { return v * healthyShare }
                return v * share
            }
            let power: Double? = offline ? nil : (nowSlot < curve.count ? curve[nowSlot] : nil)
            let status: DeviceStatus = offline ? .offline : fault != nil ? .fault : .normal
            let mppts = r >= 100 ? 10 : 7
            let volts = 330.0
            // the station's own currents when it has them (`Monitoring.demo` sets them, a low string included)
            let strings: [[Double?]] = !offline && i < s.inverterStrings.count ? s.inverterStrings[i]
                : (0..<mppts).map { m in
                    (0..<2).map { b -> Double? in
                        if offline { return nil }
                        guard let p = power else { return nil }
                        return p * 1000 / Double(mppts * 2) / volts * wobble(m * 2 + b, Double(mp))
                    }
                }
            let reporting = !offline && power != nil
            let phases: [ACPhase] = ["L1", "L2", "L3"].enumerated().map { k, n in
                guard reporting, let p = power else { return ACPhase(name: n) }
                let v = 230 + 1.4 * sin(Double(k * 2 + mp))
                let kw = p / 3 * wobble(k, 2)
                return ACPhase(name: n, volts: fault == nil ? v : nil, amps: kw * 1000 / v, kW: kw)
            }
            var history: [String: [Double?]] = ["PAC": curve, "MPPT POWER": curve.map { $0.map { $0 * 1.03 } }]
            for (k, p) in ["R", "S", "T"].enumerated() {
                let pw: [Double?] = curve.map { $0.map { $0 / 3 * wobble(k, 5) } }
                let v: [Double?] = curve.enumerated().map { j, c in c == nil ? nil : 230 + 1.5 * sin(Double(j) * 0.2 + Double(k)) }
                history["\(p)-PHASE POWER"] = pw
                history["\(p)-PHASE VOLTAGE"] = v
                history["\(p)-PHASE CURRENT"] = zip(pw, v).map { a, b in a.flatMap { x in b.map { x * 1000 / $0 } } }
            }
            for m in 0..<mppts {
                let pw: [Double?] = curve.map { $0.map { $0 * 1.03 / Double(mppts) * wobble(m, 7) } }
                let v: [Double?] = curve.map { c in c.map { $0 > 0.05 ? 640 + 20 * sin(Double(m)) : 0 } }
                history["MPPT\(m + 1) POWER"] = pw
                history["MPPT\(m + 1) VOLTAGE"] = v
                history["MPPT\(m + 1) CURRENT"] = zip(pw, v).map { a, b in
                    guard let x = a, let y = b, y > 0 else { return a == nil ? nil : 0 }
                    return x * 1000 / y
                }
            }
            inverters.append(Inverter(
                id: name, name: name, model: demoModel(r), sn: String(format: "TCX%02d%02dA%d", mp, Int(r) % 100, i + 1),
                ratedKW: r, status: status, powerNow: power,
                today: offline ? nil : Forecast.energy(curve, through: nowSlot),
                month: month.map { $0 * share }, total: s.totalEnergy.map { $0 * share },
                lastUpdate: s.lastReading, stoppedSince: fault?.since, datalogger: loggerSN, ac: phases,
                frequency: reporting ? 50.01 : nil, temperature: reporting ? 48 : nil, ipmTemperature: reporting ? 55 : nil,
                powerLimit: reporting ? 100 : nil, strings: strings, curve: curve,
                expectedCurve: s.expectedCurve.map { $0 * share }, history: history))
        }

        // the station's use: a pumping station's steady load, read by the meter until the logger stopped
        let base = s.kWp * 0.6
        let load: [Double?] = (0..<Monitoring.slots).map { i in
            i > readThrough ? nil : base * (1 + 0.04 * sin(Double(i) * 0.05 + Double(mp)))
        }
        let pv: [Double?] = (0..<Monitoring.slots).map { i in
            i > readThrough ? nil : (i < s.curve.count ? (s.curve[i] ?? 0) : 0)
        }
        // zero export: the meter never goes below 0
        let meterCurve: [Double?] = zip(load, pv).map { l, p in l.flatMap { x in p.map { max(x - $0, 0) } } }
        let meterNow: Double? = offline ? nil : meterCurve[min(nowSlot, meterCurve.count - 1)]
        let phases: [MeterPhase] = ["L1", "L2", "L3"].enumerated().map { k, n in
            guard let m = meterNow else { return MeterPhase(name: n) }
            let v = 230 + 1.4 * sin(Double(k * 2 + mp))
            let kw = m / 3 * (1 + 0.05 * Double(k - 1))
            return MeterPhase(name: n, volts: v, amps: kw * 1000 / v / 0.97, kW: kw, kvar: kw * 0.25, pf: 0.97)
        }
        var meterHistory: [String: [Double?]] = ["TOTAL POWER": meterCurve]
        for (k, n) in ["L1", "L2", "L3"].enumerated() {
            let pw: [Double?] = meterCurve.map { $0.map { $0 / 3 * (1 + 0.05 * Double(k - 1)) } }
            let v: [Double?] = meterCurve.map { $0 == nil ? nil : 230 + 1.4 * sin(Double(k * 2 + mp)) }
            meterHistory["\(n) POWER"] = pw
            meterHistory["\(n) VOLTAGE"] = v
            meterHistory["\(n) CURRENT"] = zip(pw, v).map { a, b in a.flatMap { x in b.map { x * 1000 / $0 / 0.97 } } }
        }
        let meterSN = Meter(sn: String(format: "MTR%04d", mp * 353 % 10000), model: "CHNT 3 เฟส", lastData: s.lastReading, phases: phases, importNow: meterNow,
                          importToday: Forecast.energy(meterCurve, through: nowSlot),
                          importTotal: base * 24 * 365 * 1.3, exportToday: 0, exportTotal: 0, curve: meterCurve,
                          history: meterHistory)

        // the weather sensor, only where the station has one
        var sensor: Sensor? = nil
        if s.hasIrradianceSensor {
            let irr: [Double?] = s.expectedCurve.enumerated().map { i, e in
                i > readThrough ? nil : (s.kWp > 0 ? e / s.kWp / 0.8 * 1000 * (1 + 0.06 * sin(Double(i) * 0.7 + Double(mp))) : nil)
            }
            let air: [Double?] = (0..<Monitoring.slots).map { i in
                i > readThrough ? nil : 27 + 5 * sin(Double.pi * (Double(i) / Double(Monitoring.slots) - 0.3))
            }
            let module: [Double?] = zip(irr, air).map { g, a in a.map { $0 + (g ?? 0) * 0.025 } }
            let h = irr.compactMap { $0 }.reduce(0, +) * Double(Monitoring.slotMinutes) / 60 / 1000
            sensor = Sensor(sn: String(format: "ENV%04d", mp * 271 % 10000), model: "ENV device", lastData: s.lastReading,
                            irradianceNow: offline ? nil : irr[nowSlot], irradiancePeak: irr.compactMap { $0 }.max(),
                            insolationToday: h, moduleTemp: offline ? nil : module[nowSlot],
                            moduleTempPeak: module.compactMap { $0 }.max(), airTemp: offline ? nil : air[nowSlot],
                            irradianceCurve: irr, moduleTempCurve: module, airTempCurve: air)
        }

        // the logger: 7 days of sends, a short gap three days back on odd MPs, today's silence when offline
        let days: [LoggerDay] = (0..<7).reversed().compactMap { back in
            guard let d = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let due = back == 0 ? nowSlot + 1 : Monitoring.slots
            var gaps: [Range<Int>] = []
            if back == 3, mp % 2 == 1 { gaps.append(26..<33) }
            if back == 0, offline { gaps.append((lastSlot + 1)..<(nowSlot + 1)) }
            return LoggerDay(start: d, dueSlots: due, gaps: gaps)
        }
        var devices: [LoggerDevice] = inverters.map {
            LoggerDevice(id: $0.id, name: $0.name + " · " + numberText($0.ratedKW) + " kW", detail: "Growatt " + ($0.model ?? ""),
                         sn: $0.sn, lastData: $0.lastUpdate, status: $0.status)
        }
        devices.append(LoggerDevice(id: "meter", name: "มิเตอร์ (กันย้อน)", detail: "Smart meter CHNT 3 เฟส", sn: meterSN.sn,
                                    lastData: s.lastReading, status: offline ? .offline : .normal))
        if let sensor {
            devices.append(LoggerDevice(id: "sensor", name: "เซนเซอร์สภาพอากาศ", detail: "ENV device", sn: sensor.sn,
                                        lastData: s.lastReading, status: offline ? .offline : .normal))
        }
        let logger = Logger(sn: loggerSN, model: "ShineLAN-X", online: !offline, lastData: s.lastReading, intervalMinutes: 5,
                            growattHistoryDays: 95, archive: "ทุกคืน 00:30", devices: devices, days: days)

        // the history: today's alarms open, and older lines from the days before
        func at(_ back: Int, _ h: Int, _ m: Int) -> Date {
            let d = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            return calendar.date(bySettingHour: h, minute: m, second: 0, of: d) ?? d
        }
        func inv(_ name: String) -> Inverter? { inverters.first { $0.name == name } }
        var events: [AlarmEvent] = s.alarms.map { a in
            var e = AlarmEvent(alarm: a)
            if let i = inv(a.part) { e.model = i.model; e.sn = i.sn }
            if a.source == .lost { e.model = logger.model; e.sn = logger.sn }
            if a.source == .tcroof { e.device = "INV 1 · " + a.part; e.titleTH = "สตริงต่ำกว่าค่ากลาง"; e.titleEN = a.detail }
            return e
        }
        if let f = faults.first, let i = inv(f.part) {
            let start = at(1, 10, 0)
            events.append(AlarmEvent(id: s.id + "/h/124", source: .growatt, code: f.code, device: f.part, model: i.model, sn: i.sn,
                                     titleTH: AlarmCatalog.entry(f.code)?.th ?? f.detail, titleEN: AlarmCatalog.entry(f.code)?.en ?? f.detail,
                                     firstSeen: start, ended: start.addingTimeInterval(31 * 60),
                                     repeats: (0..<3).map { start.addingTimeInterval(Double($0) * 70) }))
        }
        if s.hasIrradianceSensor {
            events.append(AlarmEvent(id: s.id + "/h/pr", source: .tcroof, device: "ทั้งสถานี", titleTH: "PR ต่ำกว่าเกณฑ์",
                                     titleEN: "PR below 70%", firstSeen: at(1, 18, 0), ended: at(1, 23, 59),
                                     acknowledged: true, allDay: true))
        }
        let lostStart = at(3, 2, 12)
        events.append(AlarmEvent(id: s.id + "/h/lost", source: .lost, device: "ดาต้าล็อกเกอร์", model: logger.model, sn: logger.sn,
                                 titleTH: "ดาต้าล็อกเกอร์ขาดการติดต่อ", titleEN: "Datalogger lost", firstSeen: lostStart,
                                 ended: lostStart.addingTimeInterval(36 * 60), acknowledged: true))
        if let first = inverters.first {
            let start = at(5, 6, 12)
            events.append(AlarmEvent(id: s.id + "/h/203", source: .growatt, code: "203", device: first.name, model: first.model,
                                     sn: first.sn, titleTH: AlarmCatalog.entry("203")?.th ?? "", titleEN: AlarmCatalog.entry("203")?.en ?? "",
                                     firstSeen: start, ended: start.addingTimeInterval(28 * 60), acknowledged: true))
        }
        events.sort { $0.firstSeen > $1.firstSeen }

        return StationDetail(inverters: inverters, logger: logger, meter: meterSN, sensor: sensor, events: events,
                             loadCurve: load, zeroExport: true)
    }

    /// Growatt MAX ratings that fill a station: the first about 60 % of its size, the rest what is left.
    static func demoRatings(kWp: Double, count: Int) -> [Double] {
        let sizes: [Double] = [125, 110, 100, 80, 60, 50, 30]
        func fit(_ kw: Double) -> Double { sizes.first { $0 <= kw } ?? sizes[sizes.count - 1] }
        guard count > 1 else { return count == 1 ? [fit(kWp * 0.95)] : [] }
        var out = [fit(kWp * 0.6)]
        var left = kWp * 0.95 - out[0]
        for k in 1..<count {
            let r = fit(left / Double(count - k))
            out.append(r)
            left -= r
        }
        return out
    }

    static func demoModel(_ kW: Double) -> String {
        let n = Int(kW)
        return kW >= 100 ? "MAX \(n)KTL3-X LV" : "MAX \(n)KTL3 LV"
    }

    static func numberText(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
