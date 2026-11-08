import Foundation

extension Monitoring {
    /// One line of `ประวัติแจ้งเตือน`: an alarm from Growatt, the logger's silence or the app's own check, with when it
    /// began and ended, its repeats and its work order. Acknowledging it (`รับทราบ`) is the viewer's, kept apart.
    public struct AlarmEvent: Identifiable, Hashable, Sendable {
        public var id: String
        public var source: Alarm.Source
        /// Growatt's code (`124`); empty for the other sources.
        public var code: String
        /// `INV 2`, `ดาต้าล็อกเกอร์`, `ทั้งสถานี`.
        public var device: String
        public var model: String?
        public var sn: String?
        public var titleTH: String
        public var titleEN: String
        public var firstSeen: Date
        /// Nil while it is still raised.
        public var ended: Date?
        /// Every time it was raised, the first included.
        public var repeats: [Date]
        public var workOrder: String?
        /// Acknowledged where it came from (the demo's older lines); the viewer's own are a separate set.
        public var acknowledged: Bool
        /// A whole-day check (`ทั้งวัน`).
        public var allDay: Bool

        public init(id: String, source: Alarm.Source, code: String = "", device: String, model: String? = nil,
                    sn: String? = nil, titleTH: String, titleEN: String = "", firstSeen: Date, ended: Date? = nil,
                    repeats: [Date] = [], workOrder: String? = nil, acknowledged: Bool = false, allDay: Bool = false) {
            self.id = id; self.source = source; self.code = code; self.device = device; self.model = model; self.sn = sn
            self.titleTH = titleTH; self.titleEN = titleEN; self.firstSeen = firstSeen; self.ended = ended
            self.repeats = repeats.isEmpty ? [firstSeen] : repeats; self.workOrder = workOrder
            self.acknowledged = acknowledged; self.allDay = allDay
        }

        /// A current alarm of the fleet's row as a history line.
        public init(alarm a: Alarm) {
            let known = AlarmCatalog.entry(a.source == .growatt ? a.code : "")
            let step: TimeInterval = 80
            self.init(id: a.id, source: a.source, code: a.code, device: a.part,
                      titleTH: known?.th ?? (a.source == .lost ? "ขาดการติดต่อ" : a.detail),
                      titleEN: known?.en ?? (a.source == .lost ? "Datalogger lost" : ""),
                      firstSeen: a.since, repeats: (0..<max(a.occurrences, 1)).map { a.since.addingTimeInterval(Double($0) * step) },
                      workOrder: a.workOrder)
        }

        /// `Error 124`, `Lost`, `TCRoof`.
        public var label: String {
            switch source {
            case .growatt: code.isEmpty ? "Error" : "Error " + code
            case .lost: "Lost"
            case .tcroof: "TCRoof"
            }
        }

        public var isOpen: Bool { ended == nil }

        public func duration(now: Date) -> TimeInterval { max((ended ?? now).timeIntervalSince(firstSeen), 0) }

        public func isAcknowledged(_ set: Set<String>) -> Bool { acknowledged || set.contains(id) }

        /// Growatt's fix steps for its code, empty when the catalog doesn't know it.
        public var fix: AlarmCatalog.Entry? { source == .growatt ? AlarmCatalog.entry(code) : nil }

        public static func unacknowledged(_ events: [AlarmEvent], acknowledged: Set<String>) -> Int {
            events.filter { !$0.isAcknowledged(acknowledged) }.count
        }
    }

    /// `ประวัติแจ้งเตือน`'s filters.
    public struct AlarmFilter: Hashable, Sendable {
        public enum Period: String, CaseIterable, Hashable, Sendable {
            case day, month, year
            /// The days it covers back from its end.
            public var days: Int { self == .day ? 1 : self == .month ? 30 : 365 }
        }
        public enum Device: Hashable, Sendable {
            case all
            case inverter(String)
            case logger
            case tcroof
        }
        public enum State: String, CaseIterable, Hashable, Sendable {
            case all, open, unacknowledged
        }

        public var period: Period
        /// The last day the period covers.
        public var end: Date
        public var device: Device
        public var state: State

        public init(period: Period = .month, end: Date, device: Device = .all, state: State = .all) {
            self.period = period; self.end = end; self.device = device; self.state = state
        }

        /// The first and the last day covered.
        public func interval(calendar: Calendar = .current) -> (start: Date, end: Date) {
            let last = calendar.startOfDay(for: end)
            let first = calendar.date(byAdding: .day, value: -(period.days - 1), to: last) ?? last
            return (first, calendar.date(byAdding: .day, value: 1, to: last) ?? last)
        }

        /// The events in the period (begun in it, or still open across it), of the device and state picked, newest first.
        public func apply(_ events: [AlarmEvent], acknowledged: Set<String>, calendar: Calendar = .current) -> [AlarmEvent] {
            let (start, stop) = interval(calendar: calendar)
            return events.filter { e in
                let inPeriod = e.firstSeen < stop && (e.ended ?? stop) >= start
                let device: Bool = switch self.device {
                case .all: true
                case .inverter(let name): e.device == name
                case .logger: e.source == .lost
                case .tcroof: e.source == .tcroof
                }
                let state: Bool = switch self.state {
                case .all: true
                case .open: e.isOpen
                case .unacknowledged: !e.isAcknowledged(acknowledged)
                }
                return inPeriod && device && state
            }
            .sorted { $0.firstSeen > $1.firstSeen }
        }
    }

    /// Growatt's alarm texts and fix steps for the codes the stations have shown, from the inverter manuals (MAX
    /// series, `Error` codes). A code missing here shows without steps.
    public enum AlarmCatalog {
        public struct Entry: Hashable, Sendable {
            public var th: String
            public var en: String
            public var stepsTH: [String]
            public var stepsEN: String
        }

        public static let entries: [String: Entry] = [
            "124": Entry(th: "ไม่มีไฟฝั่ง AC", en: "No AC Connection",
                         stepsTH: ["ปิดเครื่องแล้วตรวจสอบสายฝั่ง AC", "ถ้ายังขึ้นอยู่ ติดต่อผู้ผลิต"],
                         stepsEN: "1. After shutdown, check AC wiring. 2. If the error message still exists, contact manufacturer."),
            "117": Entry(th: "รีเลย์ผิดปกติ", en: "Relay fault",
                         stepsTH: ["รีสตาร์ทอินเวอร์เตอร์", "ถ้ายังขึ้นอยู่ ติดต่อผู้ผลิต"],
                         stepsEN: "1. Restart inverter. 2. If the error message still exists, contact manufacturer."),
            "203": Entry(th: "ฉนวนฝั่ง PV ต่ำ", en: "PV Isolation Low",
                         stepsTH: ["ตรวจสอบความเป็นฉนวนระหว่างแผงกับกราวด์", "ถ้ายังขึ้นอยู่ ติดต่อผู้ผลิต"],
                         stepsEN: "1. Check the insulation of the PV panels to ground. 2. If the error message still exists, contact manufacturer."),
        ]

        public static func entry(_ code: String) -> Entry? { entries[code] }
    }

    // MARK: compare

    public enum CompareGroup: String, CaseIterable, Hashable, Sendable {
        case power, voltage, current

        public var title: String {
            switch self {
            case .power: "กำลัง"
            case .voltage: "แรงดัน"
            case .current: "กระแส"
            }
        }
    }

    /// A value a device gives over the day: `PAC` (kW), `MPPT1 VOLTAGE` (V).
    public struct CompareMetric: Identifiable, Hashable, Sendable {
        public var id: String
        public var unit: String
        public var group: CompareGroup

        public init(_ id: String, unit: String, group: CompareGroup) {
            self.id = id; self.unit = unit; self.group = group
        }

        /// An inverter's values: PAC, the DC side, the phases, then each MPPT.
        public static func inverter(mppts: Int) -> [CompareMetric] {
            var out: [CompareMetric] = [CompareMetric("PAC", unit: "kW", group: .power),
                                        CompareMetric("MPPT POWER", unit: "kW", group: .power)]
            for p in ["R", "S", "T"] {
                out.append(CompareMetric("\(p)-PHASE POWER", unit: "kW", group: .power))
                out.append(CompareMetric("\(p)-PHASE VOLTAGE", unit: "V", group: .voltage))
                out.append(CompareMetric("\(p)-PHASE CURRENT", unit: "A", group: .current))
            }
            for i in 0..<max(mppts, 0) {
                out.append(CompareMetric("MPPT\(i + 1) POWER", unit: "kW", group: .power))
                out.append(CompareMetric("MPPT\(i + 1) VOLTAGE", unit: "V", group: .voltage))
                out.append(CompareMetric("MPPT\(i + 1) CURRENT", unit: "A", group: .current))
            }
            return out
        }

        public static let meter: [CompareMetric] = {
            var out = [CompareMetric("TOTAL POWER", unit: "kW", group: .power)]
            for p in ["L1", "L2", "L3"] {
                out.append(CompareMetric("\(p) POWER", unit: "kW", group: .power))
                out.append(CompareMetric("\(p) VOLTAGE", unit: "V", group: .voltage))
                out.append(CompareMetric("\(p) CURRENT", unit: "A", group: .current))
            }
            return out
        }()

        /// The sensor's values sit under `กำลัง` (it has no voltage or current).
        public static let sensor: [CompareMetric] = [
            CompareMetric("IRRADIANCE", unit: "W/m²", group: .power),
            CompareMetric("MODULE TEMP", unit: "°C", group: .power),
            CompareMetric("AIR TEMP", unit: "°C", group: .power),
        ]
    }

    public struct CompareDevice: Identifiable, Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable { case inverter, meter, sensor }
        public var id: String
        public var kind: Kind
        public var name: String
        public var detail: String
        public var status: DeviceStatus
        public var metrics: [CompareMetric]
        /// The values by metric, kW / V / A … per 5-minute slot today; empty when the source gives none.
        public var history: [String: [Double?]]
    }

    /// One line on the compare chart.
    public struct CompareLine: Identifiable, Hashable, Sendable {
        public var deviceID: String
        public var deviceName: String
        public var metric: CompareMetric
        public var id: String { deviceID + "/" + metric.id }

        public init(deviceID: String, deviceName: String, metric: CompareMetric) {
            self.deviceID = deviceID; self.deviceName = deviceName; self.metric = metric
        }
    }

    /// The lines picked: at most 4, in at most 2 units (the left and right axes).
    public struct CompareSelection: Hashable, Sendable {
        public static let maxLines = 4
        public static let maxUnits = 2

        public enum Refusal: Hashable, Sendable {
            case tooManyLines, tooManyUnits

            public var note: String {
                switch self {
                case .tooManyLines: "เลือกได้ไม่เกิน \(CompareSelection.maxLines) เส้น เอาเส้นเดิมออกก่อน"
                case .tooManyUnits: "หน่วยต่างกันได้ \(CompareSelection.maxUnits) หน่วย (แกนซ้ายและขวา)"
                }
            }
        }

        public private(set) var lines: [CompareLine]

        public init(_ lines: [CompareLine] = []) { self.lines = [] ; for l in lines { _ = add(l) } }

        /// The units in the order first picked: the first is the left axis.
        public var units: [String] {
            var out: [String] = []
            for l in lines where !out.contains(l.metric.unit) { out.append(l.metric.unit) }
            return out
        }

        public func contains(_ line: CompareLine) -> Bool { lines.contains { $0.id == line.id } }

        public func count(device: String) -> Int { lines.filter { $0.deviceID == device }.count }

        /// Adds the line, or says why it can't.
        @discardableResult
        public mutating func add(_ line: CompareLine) -> Refusal? {
            guard !contains(line) else { return nil }
            if lines.count >= Self.maxLines { return .tooManyLines }
            if !units.contains(line.metric.unit), units.count >= Self.maxUnits { return .tooManyUnits }
            lines.append(line)
            return nil
        }

        public mutating func remove(_ line: CompareLine) { lines.removeAll { $0.id == line.id } }

        /// A tap on a value: off when on, else added (or refused).
        @discardableResult
        public mutating func toggle(_ line: CompareLine) -> Refusal? {
            if contains(line) { remove(line); return nil }
            return add(line)
        }
    }
}

extension Monitoring.StationDetail {
    /// The devices `เปรียบเทียบค่า` lists: the inverters, the meter, the sensor.
    public var compareDevices: [Monitoring.CompareDevice] {
        var out: [Monitoring.CompareDevice] = inverters.map { inv in
            Monitoring.CompareDevice(id: inv.id, kind: .inverter, name: inv.name,
                          detail: [inv.model.map { "Growatt " + $0 }, inv.sn].compactMap { $0 }.joined(separator: " · "),
                          status: inv.status, metrics: Monitoring.CompareMetric.inverter(mppts: inv.strings.count), history: inv.history)
        }
        if let m = meter {
            out.append(Monitoring.CompareDevice(id: "meter", kind: .meter, name: "มิเตอร์",
                                     detail: [m.model, m.sn].compactMap { $0 }.joined(separator: " · "),
                                     status: m.lastData == nil ? .unknown : .normal, metrics: Monitoring.CompareMetric.meter,
                                     history: m.history))
        }
        if let s = sensor {
            var h: [String: [Double?]] = [:]
            if !s.irradianceCurve.isEmpty { h["IRRADIANCE"] = s.irradianceCurve }
            if !s.moduleTempCurve.isEmpty { h["MODULE TEMP"] = s.moduleTempCurve }
            if !s.airTempCurve.isEmpty { h["AIR TEMP"] = s.airTempCurve }
            out.append(Monitoring.CompareDevice(id: "sensor", kind: .sensor, name: "เซนเซอร์สภาพอากาศ",
                                     detail: [s.model, s.sn].compactMap { $0 }.joined(separator: " · "),
                                     status: s.lastData == nil ? .unknown : .normal, metrics: Monitoring.CompareMetric.sensor, history: h))
        }
        return out
    }
}
