import Foundation

/// `Monitoring ทุกสถานี` (issue #259, board `iPadPwaMonitoring`): the handed-over PWA stations as one fleet, from a
/// read-only monitoring source (Growatt). The figures here are what the source gives plus the app's forecast; nothing
/// is written back to an inverter.
///
/// A station with no source, or one that stopped reporting, keeps nil for what it doesn't know, so the page shows
/// `—` / `ไม่มีข้อมูล` and never 0 for it.
public enum Monitoring {
    /// Thailand's grid, kg CO₂ per kWh, as the station page counts it.
    public static let co2PerKWh = 0.5
    /// Today's curves are 5-minute slots from 00:00.
    public static let slotMinutes = 5
    public static let slots = 24 * 60 / slotMinutes
    /// Growatt answers 10012 to calls closer together than this.
    public static let minimumPollMinutes = 5

    public enum Health: String, CaseIterable, Sendable {
        case normal, alarm, offline
    }

    /// Something to look at: an inverter's error from Growatt, a logger that lost contact, or the app's own check of the
    /// readings (a string well under its inverter's median). Sorted by the energy it costs.
    public struct Alarm: Identifiable, Hashable, Sendable {
        public enum Source: String, Sendable {
            /// The inverter's own error code (`Error 124`).
            case growatt
            /// The data logger stopped reporting (`Lost`).
            case lost
            /// The app's check of the readings (`TCRoof`).
            case tcroof
        }

        /// What it costs today: read from the readings, at most a figure (nothing is known since contact was lost), or
        /// about a figure (estimated from a string's current).
        public enum Loss: Hashable, Sendable {
            case measured(Double)
            case atMost(Double)
            case about(Double)
            case unknown

            public var kWh: Double {
                switch self {
                case .measured(let v), .atMost(let v), .about(let v): v
                case .unknown: 0
                }
            }
        }

        public var id: String
        public var source: Source
        /// Growatt's code (`124`); empty for the other sources.
        public var code: String
        /// Where: `INV 2`, `ดาต้าล็อกเกอร์`, `MPPT 4 b`.
        public var part: String
        /// What: `No AC Connection`, `ไม่มีข้อมูล`, `สตริง 3.1 A จากค่ากลาง 10 A`.
        public var detail: String
        public var since: Date
        /// Times it happened today.
        public var occurrences: Int
        /// The work order opened for it, `TK-0412`; nil when none is yet.
        public var workOrder: String?
        public var loss: Loss

        public init(id: String, source: Source, code: String = "", part: String, detail: String, since: Date,
                    occurrences: Int = 1, workOrder: String? = nil, loss: Loss = .unknown) {
            self.id = id; self.source = source; self.code = code; self.part = part; self.detail = detail
            self.since = since; self.occurrences = occurrences; self.workOrder = workOrder; self.loss = loss
        }

        /// `Error 124`, `Lost`, `TCRoof`.
        public var label: String {
            switch source {
            case .growatt: code.isEmpty ? "Error" : "Error " + code
            case .lost: "Lost"
            case .tcroof: "TCRoof"
            }
        }
    }

    /// One day's (or month's) energy and its forecast, kWh; nil when not known.
    public struct Period: Hashable, Sendable {
        public var start: Date
        public var energy: Double?
        public var expected: Double?

        public init(start: Date, energy: Double?, expected: Double?) {
            self.start = start; self.energy = energy; self.expected = expected
        }
    }

    public struct Station: Identifiable, Hashable, Sendable {
        public var id: String
        public var mpNumber: Int?
        public var name: String
        public var kWp: Double
        /// Inverters the station has, and those reporting without a fault; nil when not known.
        public var inverters: Int
        public var invertersOnline: Int?
        /// Paired with a source (a Growatt plant). False: everything below is nil, the row reads `ไม่มีข้อมูล`.
        public var paired: Bool
        /// kW at the last reading.
        public var powerNow: Double?
        /// Today's energy so far, kWh.
        public var energyToday: Double?
        /// The forecast from 00:00 to the last reading, and for the whole day, kWh.
        public var expectedSoFar: Double?
        public var expectedToday: Double?
        /// Since the station started (Growatt's `total_energy`), kWh.
        public var totalEnergy: Double?
        public var lastReading: Date?
        /// Energy sent back to the grid today, kWh (the zero-export meter); nil without its readings.
        public var backfeedToday: Double?
        /// PR is worked out only with an irradiance sensor.
        public var hasIrradianceSensor: Bool
        public var prToday: Double?
        /// String currents, A, per inverter (`INV 1` first), then per MPPT its strings `a`, `b` (from Growatt's
        /// `invs_data`, `GrowattMap.strings`); empty when the source gives none, so no string is judged.
        public var inverterStrings: [[[Double?]]]
        public var alarms: [Alarm]
        /// Today's power, kW, one value per 5-minute slot from 00:00 (`Monitoring.slots`); nil where nothing was read.
        public var curve: [Double?]
        /// The forecast's power for the same slots, kW.
        public var expectedCurve: [Double]
        /// Yesterday's energy by the same time of day, kWh.
        public var yesterdaySoFar: Double?
        /// The last 30 days (oldest first, today last) and the last 12 months (oldest first, this month last).
        public var days: [Period]
        public var months: [Period]

        public init(id: String, mpNumber: Int? = nil, name: String, kWp: Double, inverters: Int, invertersOnline: Int? = nil,
                    paired: Bool = true, powerNow: Double? = nil, energyToday: Double? = nil, expectedSoFar: Double? = nil,
                    expectedToday: Double? = nil, totalEnergy: Double? = nil, lastReading: Date? = nil,
                    backfeedToday: Double? = nil, hasIrradianceSensor: Bool = false, prToday: Double? = nil,
                    inverterStrings: [[[Double?]]] = [], alarms: [Alarm] = [], curve: [Double?] = [], expectedCurve: [Double] = [], yesterdaySoFar: Double? = nil,
                    days: [Period] = [], months: [Period] = []) {
            self.id = id; self.mpNumber = mpNumber; self.name = name; self.kWp = kWp; self.inverters = inverters
            self.invertersOnline = invertersOnline; self.paired = paired; self.powerNow = powerNow
            self.energyToday = energyToday; self.expectedSoFar = expectedSoFar; self.expectedToday = expectedToday
            self.totalEnergy = totalEnergy; self.lastReading = lastReading; self.backfeedToday = backfeedToday
            self.hasIrradianceSensor = hasIrradianceSensor
            // PR needs measured irradiance (issue #259): without a sensor there is none to show
            self.prToday = hasIrradianceSensor ? prToday : nil
            self.inverterStrings = inverterStrings
            self.alarms = alarms; self.curve = curve; self.expectedCurve = expectedCurve
            self.yesterdaySoFar = yesterdaySoFar; self.days = days; self.months = months
        }

        /// A PWA station handed over but not paired with a monitoring source yet.
        public static func unpaired(id: String, mpNumber: Int?, name: String, kWp: Double, inverters: Int) -> Station {
            Station(id: id, mpNumber: mpNumber, name: name, kWp: kWp, inverters: inverters, paired: false)
        }

        /// Offline when it isn't paired, never reported, or its last reading is older than `offlineAfter` minutes; in
        /// alarm with an inverter's error or an inverter not reporting. The app's own checks (`TCRoof`) are listed
        /// but leave the station `ปกติ`.
        public func health(now: Date, offlineAfter minutes: Int) -> Health {
            guard paired, let last = lastReading, now.timeIntervalSince(last) <= Double(minutes * 60) else { return .offline }
            if alarms.contains(where: { $0.source != .tcroof }) { return .alarm }
            if let online = invertersOnline, online < inverters { return .alarm }
            return .normal
        }

        /// Power over the station's size, 0…1.
        public var powerShare: Double? {
            guard let p = powerNow, kWp > 0 else { return nil }
            return p / kWp
        }

        /// Today's energy over the forecast so far.
        public var yieldShare: Double? {
            guard let e = energyToday, let x = expectedSoFar, x > 0 else { return nil }
            return e / x
        }

        /// kWh/kWp today.
        public var specificYield: Double? {
            guard let e = energyToday, kWp > 0 else { return nil }
            return e / kWp
        }

        /// The forecast so far less what was made, kWh, never below 0. With no energy known, all of the forecast.
        public var shortfall: Double? {
            guard let x = expectedSoFar else { return nil }
            return max(x - (energyToday ?? 0), 0)
        }
    }
}
