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
        /// The fleet's reference, kWh/kWp so far (`Fleet.reference`); nil when the forecast stands in.
        public var reference: Double? = nil
        public var id: String { station.id }

        /// What the station should have made by now, kWh: its size at the fleet's median kWh/kWp (issue #259
        /// decision 2: the weather is the same for all, so a cloudy day isn't a loss), else the forecast so far.
        public var expected: Double? { reference.map { $0 * station.kWp } ?? station.expectedSoFar }

        /// `expected` less what was made, kWh, never below 0; all of it when no energy is known.
        public var shortfall: Double? { expected.map { max($0 - (station.energyToday ?? 0), 0) } }

        /// `สูญเสีย`: only for a station that isn't normal (a normal one's gap is the weather, not a fault). Offline, all
        /// of it is at most a figure: nothing has been read since.
        public var loss: Alarm.Loss? {
            guard health != .normal, let s = shortfall else { return nil }
            return health == .offline ? .atMost(s) : .measured(s)
        }

        /// Listed under `มีปัญหา`.
        public var hasProblem: Bool { health != .normal || !station.alarms.isEmpty }
    }

    /// One line of `ต้องดำเนินการ`: a station with everything raised on it, the worst first (CHA-110: one row per
    /// station, not one per inverter behind the same logger).
    public struct Action: Identifiable, Hashable, Sendable {
        public var station: Station
        /// The station's alarms, the costliest first (then the earliest); `alarm` is that one.
        public var alarms: [Alarm]
        public var id: String { station.id }
        public var alarm: Alarm { alarms[0] }
        /// Times raised today, over the station's alarms.
        public var occurrences: Int { alarms.reduce(0) { $0 + $1.occurrences } }
        public var lossKWh: Double { alarm.loss.kWh }

        /// The chip: `ขาดการติดต่อ`, `Error 124`, `TCRoof ตรวจพบ`.
        public var status: String { alarm.source == .tcroof ? "TCRoof ตรวจพบ" : alarm.label }

        /// The parts raised, each once, in `alarms`' order.
        public var parts: [String] {
            var seen = Set<String>()
            return alarms.map(\.part).filter { seen.insert($0).inserted }
        }

        /// The line under the title, device · count · since: `ดาต้าล็อกเกอร์ · 6 อินเวอร์เตอร์ · ตั้งแต่ 00:10`,
        /// `อินเวอร์เตอร์ · 3 เครื่อง · ตั้งแต่ 09:48`, `INV 2 · No AC Connection · ตั้งแต่ 09:48`.
        public func summary(now: Date, calendar: Calendar = .current) -> String {
            let today = calendar.startOfDay(for: now)
            let since = alarms.map(\.since).min() ?? alarm.since
            let when = "ตั้งแต่ " + GrowattMap.clock(since, today: today, calendar: calendar)
            let parts = self.parts
            var line: [String]
            if alarm.part == Action.logger {
                line = [Action.logger, "\(station.inverters) อินเวอร์เตอร์"]
            } else if parts.count > 1, parts.allSatisfy({ $0.hasPrefix("INV ") }) {
                line = ["อินเวอร์เตอร์", "\(parts.count) เครื่อง"]
            } else {
                line = [alarm.part, alarm.detail]
                if parts.count > 1 { line.append("อีก \(parts.count - 1) รายการ") }
            }
            line.append(when)
            // one part's repeats; over several parts the count would mix them
            if parts.count == 1, occurrences > 1 { line.append("เกิด \(occurrences) ครั้ง") }
            return line.filter { !$0.isEmpty }.joined(separator: " · ")
        }

        static let logger = "ดาต้าล็อกเกอร์"
    }

    /// The fleet at `now`: every figure of the page above the table, and the table's rows.
    public struct Fleet: Sendable {
        public let rows: [Row]
        public let now: Date
        public let settings: Settings
        let calendar: Calendar

        /// The median kWh/kWp so far of the stations running normally, the loss's reference; nil with fewer than
        /// `minimumForMedian` of them, when each station's forecast stands in.
        public let reference: Double?

        /// Normal stations needed before their median is the reference.
        public static let minimumForMedian = 3

        /// The share of the day's forecast that must have passed before `ผลิตต่ำกว่าที่คาด` is checked: about 09:00
        /// on the clear-day curve, so the early morning (a few kWh against a few kWh) raises nothing.
        public static let belowMinimumShare = 0.15

        /// The app's own lines (`TCRoof`) as raised at `now`, to pass as `raised` to the next fleet, so each line keeps
        /// its age and today's count from one reading to the next (`Raised`).
        public let raised: [String: Raised]

        /// `raised`: the previous fleet's, so a line still raised keeps when it began and how many times it came today.
        public init(_ stations: [Station], now: Date, settings: Settings, raised previous: [String: Raised] = [:],
                    calendar: Calendar = .current) {
            self.now = now
            self.settings = settings
            self.calendar = calendar
            let health = stations.map { $0.health(now: now, offlineAfter: settings.loggerOfflineMinutes) }
            let normal: [Double] = zip(stations, health).compactMap { s, h in h == .normal ? s.specificYield : nil }
            let median = Fleet.median(normal)
            let reference = normal.count >= Fleet.minimumForMedian ? median : nil
            self.reference = reference
            var next: [String: Raised] = [:]
            rows = zip(stations, health).map { s, h in
                let delta: Double? = {
                    // offline: today's energy isn't known, so neither is its yield against the others
                    guard h != .offline, let m = median, m > 0, let y = s.specificYield else { return nil }
                    return y / m - 1
                }()
                var s = s
                s.alarms.removeAll { Fleet.isOwnLine($0.id, station: s.id) }
                var row = Row(station: s, health: h, yieldVsMedian: delta, reference: reference)
                // a lost logger's line is priced as the row's loss is (against the median when there is one), so the
                // action list and `สูญเสียวันนี้` give the same figure for it
                if reference != nil, let short = row.shortfall {
                    for i in row.station.alarms.indices where row.station.alarms[i].source == .lost {
                        if case .atMost = row.station.alarms[i].loss { row.station.alarms[i].loss = .atMost(short) }
                    }
                }
                // what holds now; a line shows once it has held its time, keeping its age and today's count
                var checks: [Check] = []
                if h == .normal, let a = Fleet.belowAlarm(row, percent: settings.belowExpectedPercent, since: now) {
                    checks.append(Check(alarm: a))
                }
                if h != .offline {
                    checks += Fleet.stringChecks(row.station, percent: settings.stringLowPercent, now: now)
                }
                if h == .normal, let a = Fleet.prAlarm(row.station, percent: settings.prLowPercent, since: now) {
                    checks.append(Check(alarm: a))
                }
                for c in checks {
                    let r = Raised.next(previous[c.alarm.id], holding: true, now: now, hold: c.hold, calendar: calendar)
                    next[c.alarm.id] = r
                    guard r.shown else { continue }
                    var a = c.alarm
                    a.since = r.since
                    a.occurrences = r.occurrences
                    row.station.alarms.append(a)
                }
                // a line not raised now is kept for today's count until the day ends
                for (id, p) in previous where Fleet.isOwnLine(id, station: s.id) && next[id] == nil {
                    let r = Raised.next(p, holding: false, now: now, hold: 0, calendar: calendar)
                    if r.occurrences > 0 || r.active { next[id] = r }
                }
                return row
            }
            raised = next
        }

        static func belowID(_ station: String) -> String { station + "/below" }

        /// The lines this fleet raises itself (`ผลิตต่ำกว่าที่คาด`, a low string, low PR), replaced at every fleet.
        static func isOwnLine(_ id: String, station: String) -> Bool {
            id == belowID(station) || id == prID(station) || id.hasPrefix(station + "/string/")
        }

        /// `ผลิตต่ำกว่าที่คาด` (`Settings.belowExpectedPercent`) for a station running normally: a `TCRoof` line, so
        /// it stays `ปกติ` and nothing is notified, once `belowMinimumShare` of its day's forecast has passed and its
        /// energy is under `percent` % of what it should have made (`Row.expected`). A station in alarm or offline is
        /// listed by its cause already.
        static func belowAlarm(_ r: Row, percent: Int, since: Date) -> Alarm? {
            let s = r.station
            guard s.paired, let made = s.energyToday, let expected = r.expected, expected > 0,
                  let soFar = s.expectedSoFar, let day = s.expectedToday, day > 0,
                  soFar >= day * belowMinimumShare else { return nil }
            let share = made / expected
            guard share < Double(percent) / 100 else { return nil }
            // floored, so a station just under the threshold never reads as on it
            let shown = Int((share * 100).rounded(.down))
            let basis = r.reference == nil ? "ที่คาด" : "ค่ากลาง"
            return Alarm(id: belowID(s.id), source: .tcroof, part: "สถานี",
                         detail: "ผลิต \(shown)% ของ\(basis) · เกณฑ์ \(percent)%", since: since,
                         loss: .measured(expected - made))
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

        /// `สูญเสียวันนี้`: what the stations not running normally fell short of what they should have made
        /// (`Row.expected`), kWh, its share of the fleet's forecast so far and how many stations.
        public var lossToday: Double? {
            let l = rows.compactMap { $0.loss?.kWh }
            return l.isEmpty ? (expectedSoFar == nil ? nil : 0) : l.reduce(0, +)
        }
        public var lossShare: Double? {
            guard let l = lossToday, let x = expectedSoFar, x > 0 else { return nil }
            return l / x
        }
        public var lossStations: Int { rows.filter { $0.loss != nil }.count }

        /// `พร้อมใช้งาน`: inverters reporting without a fault over all of them (an offline station's count none). An
        /// inverter asleep at night isn't counted against it (CHA-110).
        public var invertersOnline: Int {
            rows.reduce(0) { n, r in
                guard r.health != .offline else { return n }
                let s = r.station
                return n + min((s.invertersOnline ?? s.inverters) + (s.invertersAsleep ?? 0), s.inverters)
            }
        }
        /// Inverters asleep at night behind a logger still reporting (`Station.invertersAsleep`).
        public var invertersAsleep: Int {
            rows.reduce(0) { $0 + ($1.health == .offline ? 0 : ($1.station.invertersAsleep ?? 0)) }
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
        /// source and in alarm or offline, or `ปกติ` with a low string or low PR line (CHA-92; nothing is notified for
        /// those). A station not paired yet has no feed to fall silent, so it doesn't count: until stations are paired
        /// the badge is 0.
        public var needingAttention: Int {
            rows.filter { r in
                guard r.station.paired else { return false }
                return r.health != .normal || r.station.alarms.contains { Fleet.needsAttention($0.id, station: r.station.id) }
            }.count
        }

        // MARK: night

        /// Night on the device's clock (`Daylight`): the page reads as night, not as zeros (CHA-110).
        public var isNight: Bool { Daylight.isNight(now, calendar: calendar) }
        /// Before sunrise: today has made nothing yet, so the cards show yesterday's figures.
        public var isBeforeSunrise: Bool { Daylight.isBeforeSunrise(now, calendar: calendar) }

        /// When the fleet's forecast passes 2 % of its peak today, to the 5 minutes: `คาดเริ่มผลิตราว 06:10`.
        public var productionStart: Date? {
            let curve: [Double] = (0..<Monitoring.slots).map { i in
                stations.reduce(0) { $0 + (i < $1.expectedCurve.count ? $1.expectedCurve[i] : 0) }
            }
            guard let peak = curve.max(), peak > 0, let i = curve.firstIndex(where: { $0 >= peak * 0.02 }) else { return nil }
            return calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(i * Monitoring.slotMinutes * 60))
        }

        /// Yesterday's whole day from the stations' days, kWh; nil when none has it.
        public var yesterdayEnergy: Double? { Fleet.sum(stations.map { Fleet.yesterday($0, calendar: calendar, now: now)?.energy }) }
        /// kWh/kWp yesterday over the stations with yesterday's energy.
        public var yesterdaySpecificYield: Double? {
            let known = stations.compactMap { s in Fleet.yesterday(s, calendar: calendar, now: now)?.energy.map { (s.kWp, $0) } }
            let size = known.reduce(0) { $0 + $1.0 }
            return size > 0 ? known.reduce(0) { $0 + $1.1 } / size : nil
        }
        /// Yesterday under its forecast, kWh, over the stations with both.
        public var yesterdayLoss: Double? {
            Fleet.sum(stations.map { s -> Double? in
                guard let p = Fleet.yesterday(s, calendar: calendar, now: now), let e = p.energy, let x = p.expected else { return nil }
                return max(x - e, 0)
            })
        }

        static func yesterday(_ s: Station, calendar: Calendar, now: Date) -> Period? {
            guard let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return nil }
            return s.days.first { calendar.isDate($0.start, inSameDayAs: day) }
        }

        // MARK: ต้องดำเนินการ

        /// One line per station, the costliest first; within a station its alarms the costliest, then the earliest.
        public var actions: [Action] {
            let list: [Action] = stations.compactMap { s in
                guard !s.alarms.isEmpty else { return nil }
                let sorted = s.alarms.sorted { a, b in
                    a.loss.kWh != b.loss.kWh ? a.loss.kWh > b.loss.kWh : a.since < b.since
                }
                return Action(station: s, alarms: sorted)
            }
            return list.sorted { a, b in
                if a.lossKWh != b.lossKWh { return a.lossKWh > b.lossKWh }
                let x = a.station.mpNumber ?? .max, y = b.station.mpNumber ?? .max
                return x != y ? x < y : a.station.name < b.station.name
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
                    let x = a.shortfall ?? -1, y = b.shortfall ?? -1
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
