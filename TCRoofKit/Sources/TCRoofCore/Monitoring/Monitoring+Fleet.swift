import Foundation

extension Monitoring {
    public enum Filter: String, CaseIterable, Sendable {
        /// `ทั้งหมด`, `มีปัญหา` (not normal, or anything listed), `ออฟไลน์`.
        case all, problem, offline
    }

    public enum Sort: String, CaseIterable, Sendable {
        /// `สูญเสียมากสุด`, `kWh/kWp ต่ำสุด`, `MP`.
        case loss, specificYield, mp
    }

    /// A station as a row of the table, with what depends on the others (the median) and on now (its health).
    public struct Row: Identifiable, Hashable, Sendable {
        public var station: Station
        public var health: Health
        /// kWh/kWp against the median of the stations running normally: -0.46 is 46 % under it.
        public var yieldVsMedian: Double?
        public var id: String { station.id }

        /// `สูญเสีย`: only for a station that isn't normal (a normal one's gap is the weather, not a fault). Offline, all
        /// of it is at most a figure: nothing has been read since.
        public var loss: Alarm.Loss? {
            guard health != .normal, let s = station.shortfall else { return nil }
            return health == .offline ? .atMost(s) : .measured(s)
        }

        /// Listed under `มีปัญหา`.
        public var hasProblem: Bool { health != .normal || !station.alarms.isEmpty }
    }

    /// One line of `ต้องดำเนินการ`: a station's part with what was raised on it, the worst first.
    public struct Action: Identifiable, Hashable, Sendable {
        public var station: Station
        /// The part's alarms, the costliest first; `alarm` is that one.
        public var alarms: [Alarm]
        public var id: String { station.id + "/" + alarm.part }
        public var alarm: Alarm { alarms[0] }
        /// Times raised today, over the part's alarms.
        public var occurrences: Int { alarms.reduce(0) { $0 + $1.occurrences } }
        public var lossKWh: Double { alarm.loss.kWh }
    }

    /// The fleet at `now`: every figure of the page above the table, and the table's rows.
    public struct Fleet: Sendable {
        public let rows: [Row]
        public let now: Date
        public let settings: Settings

        public init(_ stations: [Station], now: Date, settings: Settings) {
            self.now = now
            self.settings = settings
            let health = stations.map { $0.health(now: now, offlineAfter: settings.loggerOfflineMinutes) }
            let normal: [Double] = zip(stations, health).compactMap { s, h in h == .normal ? s.specificYield : nil }
            let median = Fleet.median(normal)
            rows = zip(stations, health).map { s, h in
                let delta: Double? = {
                    // offline: today's energy isn't known, so neither is its yield against the others
                    guard h != .offline, let m = median, m > 0, let y = s.specificYield else { return nil }
                    return y / m - 1
                }()
                return Row(station: s, health: h, yieldVsMedian: delta)
            }
        }

        public var stations: [Station] { rows.map(\.station) }

        static func median(_ v: [Double]) -> Double? {
            guard !v.isEmpty else { return nil }
            let s = v.sorted(), n = s.count
            return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
        }

        /// Sums the known values; nil when none is known, so the page shows `—` and not 0.
        static func sum(_ v: [Double?]) -> Double? {
            let known = v.compactMap { $0 }
            return known.isEmpty ? nil : known.reduce(0, +)
        }

        // MARK: since installed

        public var kWp: Double { stations.reduce(0) { $0 + $1.kWp } }
        public var inverters: Int { stations.reduce(0) { $0 + $1.inverters } }
        /// kWh since the stations started.
        public var totalEnergy: Double? { Fleet.sum(stations.map(\.totalEnergy)) }
        /// Baht: the energy at the settings' rate; nil until a rate is picked.
        public var value: Double? {
            guard let e = totalEnergy, let r = settings.rate else { return nil }
            return e * r
        }
        /// Tonnes of CO₂.
        public var co2Tonnes: Double? { totalEnergy.map { $0 * Monitoring.co2PerKWh / 1000 } }

        // MARK: the six cards

        /// kW now, and over the fleet's size.
        public var powerNow: Double? { Fleet.sum(stations.map(\.powerNow)) }
        public var powerShare: Double? {
            guard let p = powerNow, kWp > 0 else { return nil }
            return p / kWp
        }

        /// Today so far against the forecast so far, kWh.
        public var energyToday: Double? { Fleet.sum(stations.map(\.energyToday)) }
        public var expectedSoFar: Double? { Fleet.sum(stations.map(\.expectedSoFar)) }
        public var yieldShare: Double? {
            guard let e = energyToday, let x = expectedSoFar, x > 0 else { return nil }
            return e / x
        }

        /// kWh/kWp today over the stations reporting energy, against the median of the normal ones.
        public var specificYield: Double? {
            let reporting = stations.filter { $0.energyToday != nil && $0.kWp > 0 }
            let size = reporting.reduce(0) { $0 + $1.kWp }
            guard size > 0 else { return nil }
            return reporting.reduce(0) { $0 + ($1.energyToday ?? 0) } / size
        }
        public var medianYield: Double? {
            Fleet.median(rows.compactMap { $0.health == .normal ? $0.station.specificYield : nil })
        }
        public var specificVsMedian: Double? {
            guard let y = specificYield, let m = medianYield, m > 0 else { return nil }
            return y / m - 1
        }

        /// `สูญเสียวันนี้`: what the stations not running normally fell short of the forecast, kWh, its share of the
        /// fleet's forecast so far and how many stations.
        public var lossToday: Double? {
            let l = rows.compactMap { $0.loss?.kWh }
            return l.isEmpty ? (expectedSoFar == nil ? nil : 0) : l.reduce(0, +)
        }
        public var lossShare: Double? {
            guard let l = lossToday, let x = expectedSoFar, x > 0 else { return nil }
            return l / x
        }
        public var lossStations: Int { rows.filter { $0.loss != nil }.count }

        /// `พร้อมใช้งาน`: inverters reporting without a fault over all of them (an offline station's count none).
        public var invertersOnline: Int {
            rows.reduce(0) { n, r in n + (r.health == .offline ? 0 : (r.station.invertersOnline ?? r.station.inverters)) }
        }
        public var availability: Double? { inverters > 0 ? Double(invertersOnline) / Double(inverters) : nil }

        /// `ไหลย้อน`: energy sent to the grid today over the stations with the meter's readings, and how many of them
        /// sent none.
        public var backfeed: Double? { Fleet.sum(stations.map(\.backfeedToday)) }
        public var backfeedReporting: Int { stations.filter { $0.backfeedToday != nil }.count }
        public var backfeedClean: Int { stations.filter { ($0.backfeedToday ?? 1) < 0.05 }.count }

        /// Stations reporting (not offline).
        public var online: Int { rows.filter { $0.health != .offline }.count }
        public var alarmCount: Int { stations.reduce(0) { $0 + $1.alarms.count } }

        /// Stations that need someone (the iPad dock's `Monitor` badge, issue #270, decision 1 of #267): paired with a
        /// source and in alarm or offline. A station not paired yet has no feed to fall silent, so it doesn't count:
        /// until stations are paired the badge is 0.
        public var needingAttention: Int { rows.filter { $0.station.paired && $0.health != .normal }.count }

        // MARK: ต้องดำเนินการ

        /// One line per station and part, the costliest first.
        public var actions: [Action] {
            var groups: [String: Action] = [:]
            var order: [String] = []
            for s in stations {
                for a in s.alarms {
                    let key = s.id + "/" + a.part
                    if groups[key] == nil { groups[key] = Action(station: s, alarms: []); order.append(key) }
                    groups[key]?.alarms.append(a)
                }
            }
            let list: [Action] = order.compactMap { key in
                guard var g = groups[key] else { return nil }
                g.alarms.sort { $0.loss.kWh > $1.loss.kWh }
                return g
            }
            return list.sorted { a, b in
                if a.lossKWh != b.lossKWh { return a.lossKWh > b.lossKWh }
                return (a.station.mpNumber ?? .max) < (b.station.mpNumber ?? .max)
            }
        }

        // MARK: the table

        public func count(_ f: Filter) -> Int { rows(f).count }

        public func rows(_ f: Filter) -> [Row] {
            switch f {
            case .all: rows
            case .problem: rows.filter(\.hasProblem)
            case .offline: rows.filter { $0.health == .offline }
            }
        }

        public func rows(_ f: Filter, sort: Sort) -> [Row] {
            let mp = { (r: Row) in r.station.mpNumber ?? .max }
            return rows(f).sorted { a, b in
                switch sort {
                case .loss:
                    let x = a.station.shortfall ?? -1, y = b.station.shortfall ?? -1
                    return x != y ? x > y : mp(a) < mp(b)
                case .specificYield:
                    // a station with no energy read last
                    let x = a.station.specificYield ?? .infinity, y = b.station.specificYield ?? .infinity
                    return x != y ? x < y : mp(a) < mp(b)
                case .mp:
                    return mp(a) != mp(b) ? mp(a) < mp(b) : a.station.name < b.station.name
                }
            }
        }
    }
}
