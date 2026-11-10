import Foundation

extension Monitoring {
    /// One station's page (`Monitoring สถานี`, CHA-73, board `iPadPwaStationMonitor`): what its devices say beyond the
    /// fleet's row. Each part is nil (or empty) when the source doesn't give it, so the page shows `—` /
    /// `ไม่มีข้อมูล` and never 0 for it. Growatt's OpenAPI as read today (`plant/*`, `device/list`) gives none of the
    /// device detail; `StationDetail(station:)` keeps only what the row knows, and the demo fills the rest.
    public struct StationDetail: Hashable, Sendable {
        public var inverters: [Inverter]
        public var logger: Logger?
        public var meter: Meter?
        public var sensor: Sensor?
        /// The alarm history, newest first.
        public var events: [AlarmEvent]
        /// The station's own use, kW per 5-minute slot (PV + bought − sent back); empty without a meter.
        public var loadCurve: [Double?]
        /// The zero-export relay is on (`กันย้อนเปิด`); nil when not known.
        public var zeroExport: Bool?

        public init(inverters: [Inverter] = [], logger: Logger? = nil, meter: Meter? = nil, sensor: Sensor? = nil,
                    events: [AlarmEvent] = [], loadCurve: [Double?] = [], zeroExport: Bool? = nil) {
            self.inverters = inverters; self.logger = logger; self.meter = meter; self.sensor = sensor
            self.events = events; self.loadCurve = loadCurve; self.zeroExport = zeroExport
        }

        /// What the fleet's row knows: one inverter line per inverter (status from the row's alarms, string currents
        /// from `inverterStrings`), the logger's last reading, and the current alarms as the history. Nothing else is made up.
        public init(station s: Station, health: Health) {
            let offline = health == .offline
            let faulty = Set(s.alarms.filter { $0.source == .growatt }.map(\.part))
            let lost = Set(s.alarms.filter { $0.source == .lost }.map(\.part))
            let inverters: [Inverter] = (0..<max(s.inverters, 0)).map { i in
                let name = "INV \(i + 1)"
                let status: DeviceStatus = !s.paired ? .unknown
                    : offline || lost.contains(name) ? .offline : faulty.contains(name) ? .fault : .unknown
                // the currents Growatt last gave, none while the station is out of contact
                let strings = !offline && i < s.inverterStrings.count ? s.inverterStrings[i] : []
                return Inverter(id: name, name: name, status: status, strings: strings)
            }
            self.init(inverters: inverters,
                      logger: s.paired ? Logger(online: offline ? false : true, lastData: s.lastReading) : nil,
                      events: s.alarms.map { AlarmEvent(alarm: $0) }.sorted { $0.firstSeen > $1.firstSeen })
        }

        /// The station's use today so far, kWh.
        public func loadToday(through slot: Int) -> Double? { Forecast.energy(loadCurve, through: slot) }

        /// Inverters with a fault or out of contact.
        public var problemInverters: Int { inverters.filter { $0.status == .fault || $0.status == .offline }.count }
    }

    /// A device's state as the board's chips: `Normal`, `Fault`, `Offline`; unknown reads `—`.
    public enum DeviceStatus: String, Hashable, Sendable {
        case normal, fault, offline, unknown

        public var title: String {
            switch self {
            case .normal: "Normal"
            case .fault: "Fault"
            case .offline: "Offline"
            case .unknown: "—"
            }
        }
    }

    // MARK: inverters

    public struct ACPhase: Hashable, Sendable {
        public var name: String
        public var volts: Double?
        public var amps: Double?
        public var kW: Double?

        public init(name: String, volts: Double? = nil, amps: Double? = nil, kW: Double? = nil) {
            self.name = name; self.volts = volts; self.amps = amps; self.kW = kW
        }
    }

    public struct Inverter: Identifiable, Hashable, Sendable {
        public var id: String
        /// `INV 1`.
        public var name: String
        public var model: String?
        public var sn: String?
        public var ratedKW: Double?
        public var status: DeviceStatus
        public var powerNow: Double?
        public var today: Double?
        public var month: Double?
        public var total: Double?
        public var lastUpdate: Date?
        /// When it stopped producing (a fault), for `หยุดผลิตตั้งแต่ 09:50`.
        public var stoppedSince: Date?
        public var datalogger: String?
        public var ac: [ACPhase]
        public var frequency: Double?
        public var temperature: Double?
        public var ipmTemperature: Double?
        /// The power limit set on it, %.
        public var powerLimit: Double?
        /// String currents, A: one row per MPPT, its strings `a`, `b`.
        public var strings: [[Double?]]
        /// Today's power and its forecast, kW per 5-minute slot.
        public var curve: [Double?]
        public var expectedCurve: [Double]
        /// Values over the day for `เปรียบเทียบค่า`, by `CompareMetric.id`; empty when the source gives none.
        public var history: [String: [Double?]]

        public init(id: String, name: String, model: String? = nil, sn: String? = nil, ratedKW: Double? = nil,
                    status: DeviceStatus = .unknown, powerNow: Double? = nil, today: Double? = nil, month: Double? = nil,
                    total: Double? = nil, lastUpdate: Date? = nil, stoppedSince: Date? = nil, datalogger: String? = nil,
                    ac: [ACPhase] = [], frequency: Double? = nil, temperature: Double? = nil, ipmTemperature: Double? = nil,
                    powerLimit: Double? = nil, strings: [[Double?]] = [], curve: [Double?] = [], expectedCurve: [Double] = [],
                    history: [String: [Double?]] = [:]) {
            self.id = id; self.name = name; self.model = model; self.sn = sn; self.ratedKW = ratedKW; self.status = status
            self.powerNow = powerNow; self.today = today; self.month = month; self.total = total
            self.lastUpdate = lastUpdate; self.stoppedSince = stoppedSince; self.datalogger = datalogger; self.ac = ac
            self.frequency = frequency; self.temperature = temperature; self.ipmTemperature = ipmTemperature
            self.powerLimit = powerLimit; self.strings = strings; self.curve = curve; self.expectedCurve = expectedCurve
            self.history = history
        }

        /// Every string's tint, in the grid's order (row by row).
        public var stringTints: [[StringTint]] {
            let tints = StringTint.of(strings.flatMap { $0 })
            var out: [[StringTint]] = [], i = 0
            for row in strings {
                out.append(Array(tints[i..<(i + row.count)]))
                i += row.count
            }
            return out
        }

        /// The median of the strings carrying current, A.
        public var stringMedian: Double? { StringTint.median(strings.flatMap { $0 }) }
    }

    /// A string current's tint on the MPPT grid: none (nothing read, or no current), low (20 % or more under the
    /// median of the strings carrying current), else normal.
    public enum StringTint: Hashable, Sendable {
        case normal, low, none

        /// Under this much is no current, A.
        public static let noCurrent = 0.05
        /// A string this far under the median is tinted.
        public static let lowShare = 0.8

        public static func median(_ values: [Double?]) -> Double? {
            let on = values.compactMap { $0 }.filter { $0 > noCurrent }.sorted()
            guard !on.isEmpty else { return nil }
            let m = on.count / 2
            return on.count.isMultiple(of: 2) ? (on[m - 1] + on[m]) / 2 : on[m]
        }

        public static func of(_ values: [Double?]) -> [StringTint] {
            let med = median(values)
            return values.map { v in
                guard let v, v > noCurrent else { return .none }
                guard let med else { return .normal }
                return v <= med * lowShare ? .low : .normal
            }
        }
    }

    // MARK: the data logger

    public struct Logger: Hashable, Sendable {
        public var sn: String?
        public var model: String?
        /// Reporting (`ออนไลน์`); nil when not known.
        public var online: Bool?
        public var lastData: Date?
        public var intervalMinutes: Int?
        /// How far back Growatt keeps 5-minute values, days.
        public var growattHistoryDays: Int?
        /// TCRoof's own archive, `ทุกคืน 00:30`; nil while there is none.
        public var archive: String?
        public var devices: [LoggerDevice]
        /// The last 7 days, oldest first, today last; empty when not known.
        public var days: [LoggerDay]

        public init(sn: String? = nil, model: String? = nil, online: Bool? = nil, lastData: Date? = nil,
                    intervalMinutes: Int? = nil, growattHistoryDays: Int? = nil, archive: String? = nil,
                    devices: [LoggerDevice] = [], days: [LoggerDay] = []) {
            self.sn = sn; self.model = model; self.online = online; self.lastData = lastData
            self.intervalMinutes = intervalMinutes; self.growattHistoryDays = growattHistoryDays; self.archive = archive
            self.devices = devices; self.days = days
        }

        /// The 7 days' share received, and the hours missing.
        public var receivedShare: Double? {
            let due = days.reduce(0) { $0 + $1.dueSlots }
            guard due > 0 else { return nil }
            let missing = days.reduce(0) { $0 + $1.missingSlots }
            return Double(due - missing) / Double(due)
        }
        public var missingHours: Double {
            Double(days.reduce(0) { $0 + $1.missingSlots } * Monitoring.slotMinutes) / 60
        }
    }

    public struct LoggerDevice: Identifiable, Hashable, Sendable {
        public var id: String
        /// `INV 1 · 125 kW`.
        public var name: String
        /// `Growatt MAX 125KTL3-X LV`.
        public var detail: String
        public var sn: String?
        public var lastData: Date?
        public var status: DeviceStatus

        public init(id: String, name: String, detail: String, sn: String? = nil, lastData: Date? = nil,
                    status: DeviceStatus = .unknown) {
            self.id = id; self.name = name; self.detail = detail; self.sn = sn; self.lastData = lastData; self.status = status
        }
    }

    /// One day of the logger's 5-minute sends: the slots due so far (288 a whole day, today up to now) and the ones
    /// that never came, as slot ranges from 00:00.
    public struct LoggerDay: Identifiable, Hashable, Sendable {
        public var start: Date
        public var dueSlots: Int
        public var gaps: [Range<Int>]
        public var id: Date { start }

        public init(start: Date, dueSlots: Int, gaps: [Range<Int>] = []) {
            self.start = start; self.dueSlots = min(max(dueSlots, 0), Monitoring.slots); self.gaps = gaps
        }

        /// Missing slots among the ones due, overlapping gaps counted once.
        public var missingSlots: Int {
            var missing = Set<Int>()
            for g in gaps { for i in g where i >= 0 && i < dueSlots { missing.insert(i) } }
            return missing.count
        }

        /// Received over due, 0…1; nil before any slot is due.
        public var receivedShare: Double? {
            guard dueSlots > 0 else { return nil }
            return Double(dueSlots - missingSlots) / Double(dueSlots)
        }
    }

    // MARK: the meter

    public struct MeterPhase: Hashable, Sendable {
        public var name: String
        public var volts: Double?
        public var amps: Double?
        public var kW: Double?
        public var kvar: Double?
        public var pf: Double?

        public init(name: String, volts: Double? = nil, amps: Double? = nil, kW: Double? = nil, kvar: Double? = nil,
                    pf: Double? = nil) {
            self.name = name; self.volts = volts; self.amps = amps; self.kW = kW; self.kvar = kvar; self.pf = pf
        }
    }

    /// The zero-export meter at the utility's point: + bought, − sent back.
    public struct Meter: Hashable, Sendable {
        public var sn: String?
        public var model: String?
        public var lastData: Date?
        public var phases: [MeterPhase]
        public var importNow: Double?
        public var importToday: Double?
        public var importTotal: Double?
        public var exportToday: Double?
        public var exportTotal: Double?
        /// kW per 5-minute slot, + bought, − sent back.
        public var curve: [Double?]
        public var history: [String: [Double?]]

        public init(sn: String? = nil, model: String? = nil, lastData: Date? = nil, phases: [MeterPhase] = [],
                    importNow: Double? = nil, importToday: Double? = nil, importTotal: Double? = nil,
                    exportToday: Double? = nil, exportTotal: Double? = nil, curve: [Double?] = [],
                    history: [String: [Double?]] = [:]) {
            self.sn = sn; self.model = model; self.lastData = lastData; self.phases = phases; self.importNow = importNow
            self.importToday = importToday; self.importTotal = importTotal; self.exportToday = exportToday
            self.exportTotal = exportTotal; self.curve = curve; self.history = history
        }

        /// The phases added up: kW and kvar summed, PF from them; nil when a phase doesn't say.
        public var total: MeterPhase {
            let kw = Fleet.sumAll(phases.map(\.kW)), kvar = Fleet.sumAll(phases.map(\.kvar))
            var pf: Double? = nil
            if let p = kw, let q = kvar {
                let s = (p * p + q * q).squareRoot()
                pf = s > 0 ? abs(p) / s : nil
            }
            return MeterPhase(name: "รวม", kW: kw, kvar: kvar, pf: pf)
        }
    }

    // MARK: the weather sensor

    public struct Sensor: Hashable, Sendable {
        public var sn: String?
        public var model: String?
        public var lastData: Date?
        /// W/m².
        public var irradianceNow: Double?
        public var irradiancePeak: Double?
        /// kWh/m² today.
        public var insolationToday: Double?
        public var moduleTemp: Double?
        public var moduleTempPeak: Double?
        public var airTemp: Double?
        public var irradianceCurve: [Double?]
        public var moduleTempCurve: [Double?]
        public var airTempCurve: [Double?]

        public init(sn: String? = nil, model: String? = nil, lastData: Date? = nil, irradianceNow: Double? = nil,
                    irradiancePeak: Double? = nil, insolationToday: Double? = nil, moduleTemp: Double? = nil,
                    moduleTempPeak: Double? = nil, airTemp: Double? = nil, irradianceCurve: [Double?] = [],
                    moduleTempCurve: [Double?] = [], airTempCurve: [Double?] = []) {
            self.sn = sn; self.model = model; self.lastData = lastData; self.irradianceNow = irradianceNow
            self.irradiancePeak = irradiancePeak; self.insolationToday = insolationToday; self.moduleTemp = moduleTemp
            self.moduleTempPeak = moduleTempPeak; self.airTemp = airTemp; self.irradianceCurve = irradianceCurve
            self.moduleTempCurve = moduleTempCurve; self.airTempCurve = airTempCurve
        }

        /// PR today: the energy over what the station's size makes of the measured insolation; nil without it.
        public func pr(energy: Double?, kWp: Double) -> Double? {
            guard let e = energy, let h = insolationToday, h > 0, kWp > 0 else { return nil }
            return e / (kWp * h)
        }
    }

    // MARK: energy flow

    /// `การไหลของพลังงาน`: the kW now on each line (grid → load ← PV, and what goes back to the grid), and PV's share of
    /// today's use. A line flows (moves) only with power on it.
    public struct EnergyFlow: Hashable, Sendable {
        public var pv: Double?
        public var bought: Double?
        public var sentBack: Double?
        public var load: Double?
        /// PV used on site today over the station's use today.
        public var pvShareOfUse: Double?

        public static let flowingKW = 0.05

        public init(pv: Double?, bought: Double?, sentBack: Double?, load: Double?, pvShareOfUse: Double?) {
            self.pv = pv; self.bought = bought; self.sentBack = sentBack; self.load = load; self.pvShareOfUse = pvShareOfUse
        }

        /// From the station's row and its meter, at `slot` (now). Offline: nothing is known now.
        public init(station s: Station, detail d: StationDetail, slot: Int, offline: Bool) {
            let meterNow: Double? = offline ? nil : d.meter.flatMap { m in slot < m.curve.count ? m.curve[slot] : nil }
            let pv: Double? = offline ? nil : s.powerNow
            let load: Double? = offline ? nil : d.loadCurve.indices.contains(slot) ? d.loadCurve[slot] : nil
            let loadToday = d.loadToday(through: slot)
            var share: Double? = nil
            if let pvToday = s.energyToday, let use = loadToday, use > 0 {
                let sent = d.meter?.exportToday ?? 0
                share = min(max((pvToday - sent) / use, 0), 1)
            }
            self.init(pv: pv, bought: meterNow.map { max($0, 0) }, sentBack: meterNow.map { max(-$0, 0) },
                      load: load, pvShareOfUse: share)
        }

        public static func flows(_ kW: Double?) -> Bool { (kW ?? 0) > flowingKW }
    }

    // MARK: tabs

    public enum StationTab: String, CaseIterable, Hashable, Sendable {
        case overview = "ov", inverters = "inv", logger = "log", meter = "mt", weather = "wx", compare = "cmp", alarms = "ev"

        public var title: String {
            switch self {
            case .overview: "ภาพรวม"
            case .inverters: "อินเวอร์เตอร์"
            case .logger: "ดาต้าล็อกเกอร์"
            case .meter: "มิเตอร์"
            case .weather: "สภาพอากาศ"
            case .compare: "เปรียบเทียบค่า"
            case .alarms: "ประวัติแจ้งเตือน"
            }
        }

        /// `-monitoringStationTab overview|inverters|…` or the board's keys `ov|inv|…`.
        public init?(flag: String) {
            let f = flag.lowercased()
            if let t = StationTab(rawValue: f) { self = t; return }
            let names: [String: StationTab] = ["overview": .overview, "inverters": .inverters, "logger": .logger,
                                                "meter": .meter, "weather": .weather, "compare": .compare, "alarms": .alarms]
            guard let t = names[f] else { return nil }
            self = t
        }
    }

    public struct TabBadge: Hashable, Sendable {
        public enum Tone: Hashable, Sendable { case bad, muted }
        public var text: String
        public var tone: Tone
    }

    /// The tab bar's badges: problem inverters (else their count), a lost logger, no sensor, new alarms.
    public static func badge(_ tab: StationTab, station s: Station, detail d: StationDetail, health: Health,
                             acknowledged: Set<String>) -> TabBadge? {
        switch tab {
        case .inverters:
            let n = d.problemInverters
            if n > 0 { return TabBadge(text: "\(n) มีปัญหา", tone: .bad) }
            return d.inverters.isEmpty ? nil : TabBadge(text: "\(d.inverters.count)", tone: .muted)
        case .logger:
            return health == .offline && s.paired ? TabBadge(text: "ขาดการติดต่อ", tone: .bad) : nil
        case .weather:
            return d.sensor == nil ? TabBadge(text: "ไม่มี", tone: .muted) : nil
        case .alarms:
            let n = AlarmEvent.unacknowledged(d.events, acknowledged: acknowledged)
            return n > 0 ? TabBadge(text: "\(n) ใหม่", tone: .bad) : nil
        case .overview, .meter, .compare:
            return nil
        }
    }
}

extension Monitoring.Fleet {
    /// The sum when every value is known, else nil.
    static func sumAll(_ values: [Double?]) -> Double? {
        guard !values.isEmpty, !values.contains(where: { $0 == nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }
}
