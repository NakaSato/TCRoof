import Foundation

extension Monitoring {
    /// What one poll read from Growatt's OpenAPI for a paired station: `plant/data`, today's and yesterday's
    /// `plant/power`, `device/list`, each inverter's latest readings (`invs_data`) and `plant/energy` by day and by month. A part is nil when its call failed or
    /// wasn't made this time (only what a screen shows is read, the history once a day: CHA-107), and
    /// `GrowattMap.station` then keeps the station's previous value for it, so a failed read never turns a figure into 0.
    public struct GrowattReading: Equatable, Sendable {
        public var data: GrowattAPI.PlantData?
        public var power: [GrowattAPI.PowerPoint]?
        public var yesterdayPower: [GrowattAPI.PowerPoint]?
        public var devices: [GrowattAPI.Device]?
        public var days: [GrowattAPI.EnergyPoint]?
        public var months: [GrowattAPI.EnergyPoint]?
        /// Each inverter's latest readings by serial number (`device/inverter/invs_data`), for the string currents.
        public var inverters: [String: GrowattAPI.Latest]?
        /// The plant's zone as `plant/data` last gave it, for a read that didn't call `plant/data` this time.
        public var timezone: String?

        public init(data: GrowattAPI.PlantData? = nil, power: [GrowattAPI.PowerPoint]? = nil,
                    yesterdayPower: [GrowattAPI.PowerPoint]? = nil, devices: [GrowattAPI.Device]? = nil,
                    days: [GrowattAPI.EnergyPoint]? = nil, months: [GrowattAPI.EnergyPoint]? = nil,
                    inverters: [String: GrowattAPI.Latest]? = nil, timezone: String? = nil) {
            self.data = data; self.power = power; self.yesterdayPower = yesterdayPower; self.devices = devices
            self.days = days; self.months = months; self.inverters = inverters; self.timezone = timezone
        }

        /// Nothing came back at all.
        public var isEmpty: Bool {
            data == nil && power == nil && yesterdayPower == nil && devices == nil && days == nil && months == nil
                && inverters == nil
        }
    }

    /// Growatt's answers as a `Station` (issue #259): a pure mapping, so it is tested on fixture JSON. What Growatt
    /// didn't say stays nil (`—` on the page), never 0: a plant that never reported (`current_power` -1, no
    /// `last_update_time`) has no power, no energy and no last reading; a station whose last reading is older than
    /// the logger threshold is offline, with its power unknown and a `Lost` line in `ต้องดำเนินการ`.
    public enum GrowattMap {
        /// The guide's examples write times in GMT+8; a plant that names no zone is read as that.
        public static let defaultZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current

        /// `GMT+8`, `GMT+07:00`, `UTC`, or a zone name (`Asia/Bangkok`); `defaultZone` when it says nothing readable.
        public static func timeZone(_ text: String) -> TimeZone {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return defaultZone }
            let upper = t.uppercased()
            if upper == "UTC" || upper == "GMT" || upper == "Z" { return TimeZone(secondsFromGMT: 0) ?? defaultZone }
            for prefix in ["GMT", "UTC"] where upper.hasPrefix(prefix) {
                var rest = Substring(upper.dropFirst(prefix.count))
                var sign = 1
                if rest.hasPrefix("+") { rest = rest.dropFirst() } else if rest.hasPrefix("-") { sign = -1; rest = rest.dropFirst() }
                let parts = rest.split(separator: ":").map { Int($0) }
                guard let hours = parts.first ?? nil, parts.count <= 2 else { return defaultZone }
                let minutes = parts.count == 2 ? (parts[1] ?? 0) : 0
                return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60)) ?? defaultZone
            }
            return TimeZone(identifier: t) ?? defaultZone
        }

        /// `yyyy-MM-dd HH:mm:ss`, `yyyy-MM-dd HH:mm` or `yyyy-MM-dd` on the plant's clock; nil for anything else.
        public static func date(_ text: String, zone: TimeZone) -> Date? {
            let fields = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" || $0 == "T" })
                .map { Int($0) }
            guard fields.count >= 3, fields.count <= 6, !fields.contains(where: { $0 == nil }) else { return nil }
            let v: [Int] = fields.compactMap { $0 }
            var c = DateComponents()
            c.year = v[0]; c.month = v[1]; c.day = v[2]
            c.hour = v.count > 3 ? v[3] : 0
            c.minute = v.count > 4 ? v[4] : 0
            c.second = v.count > 5 ? v[5] : 0
            guard (1...12).contains(v[1]), (1...31).contains(v[2]), (0...23).contains(c.hour ?? 0),
                  (0...59).contains(c.minute ?? 0), (0...60).contains(c.second ?? 0) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            return cal.date(from: c)
        }

        /// `yyyy-MM-dd` of `date` on the plant's clock (the `date` of `plant/power` and `plant/energy`).
        public static func dayText(_ date: Date, zone: TimeZone) -> String {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            let c = cal.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }

        /// `yyyy-MM` of `date` on the plant's clock.
        public static func monthText(_ date: Date, zone: TimeZone) -> String { String(dayText(date, zone: zone).prefix(7)) }

        /// `plant/power`'s unit: the guide gives W, so readings are divided by 1000, unless the reading nearest the
        /// plant's power now (`plant/data`, kW) is closer to it unscaled.
        public static func powerScale(_ points: [GrowattAPI.PowerPoint], currentKW: Double?) -> Double {
            guard let kw = currentKW, kw > 0.5, let last = points.last(where: { ($0.power ?? 0) > 0 })?.power else { return 0.001 }
            return abs(last / 1000 - kw) <= abs(last - kw) ? 0.001 : 1
        }

        /// The day's readings as one value per 5-minute slot (the mean of a slot's readings), nil where none; only
        /// readings of `day` (the local day `day` falls in), and none after `through` when given.
        public static func curve(_ points: [GrowattAPI.PowerPoint], day: Date, zone: TimeZone, scale: Double,
                                 through: Int? = nil, calendar: Calendar) -> [Double?] {
            var sums = [Double](repeating: 0, count: Monitoring.slots)
            var counts = [Int](repeating: 0, count: Monitoring.slots)
            for p in points {
                guard let w = p.power, w >= 0, let t = date(p.time, zone: zone), calendar.isDate(t, inSameDayAs: day) else { continue }
                let i = Forecast.slot(of: t, calendar: calendar)
                sums[i] += w * scale
                counts[i] += 1
            }
            let last = through ?? (Monitoring.slots - 1)
            return (0..<Monitoring.slots).map { i in
                i > last || counts[i] == 0 ? nil : sums[i] / Double(counts[i])
            }
        }

        /// `base` (the job's station: id, MP, name, kWp, inverters) filled from `reading`, with `previous` (the
        /// station as last mapped) standing in for every part the reading lacks. `forecastDailyKWhPerKWp` is the
        /// site's figure (`Forecast.dailyKWhPerKWp`), `offlineAfter` the settings' logger threshold, minutes. `ผลิตต่ำกว่าที่คาด` needs
        /// the other stations, so the fleet raises it (`Fleet.belowAlarm`).
        public static func station(_ base: Station, reading: GrowattReading, previous: Station?, now: Date,
                                   offlineAfter: Int, forecastDailyKWhPerKWp: Double,
                                   calendar: Calendar = .current) -> Station {
            let prev = previous.flatMap { $0.paired ? $0 : nil }
            var s = Station(id: base.id, mpNumber: base.mpNumber, name: base.name, kWp: base.kWp,
                            inverters: max(base.inverters, prev?.inverters ?? 0), paired: true)
            let today = calendar.startOfDay(for: now)
            let nowSlot = Forecast.slot(of: now, calendar: calendar)
            let zone = timeZone(reading.data?.timezone ?? reading.timezone ?? "")

            // the forecast: the site's clear day, its part to now
            let dayKWh = base.kWp * forecastDailyKWhPerKWp
            s.expectedCurve = Forecast.curve(dailyKWh: dayKWh)
            s.expectedToday = dayKWh
            s.expectedSoFar = Forecast.energy(s.expectedCurve, through: nowSlot)

            // plant/data: the last reading, the energy and the power now
            if let d = reading.data {
                let last = date(d.lastUpdate, zone: zone)
                // never reported: `current_power` -1 or no time; nothing of it is known
                let reported = last != nil && d.currentPower >= 0
                s.lastReading = last ?? prev?.lastReading
                if reported, let last {
                    s.totalEnergy = d.totalEnergy
                    let isToday = calendar.isDate(last, inSameDayAs: now)
                    s.energyToday = isToday ? d.todayEnergy : nil
                    s.powerNow = isToday ? d.currentPower : nil
                } else {
                    s.totalEnergy = prev?.totalEnergy
                    s.energyToday = nil
                    s.powerNow = nil
                }
            } else {
                s.lastReading = prev?.lastReading
                s.totalEnergy = prev?.totalEnergy
                s.energyToday = prev?.energyToday
                s.powerNow = prev?.powerNow
            }
            let offline = s.lastReading.map { now.timeIntervalSince($0) > Double(offlineAfter * 60) } ?? true
            // the power at a reading that old isn't the power now
            if offline { s.powerNow = nil }

            // plant/power: today's curve and yesterday's by the same time
            let scale = powerScale(reading.power ?? [], currentKW: s.powerNow)
            if let pts = reading.power {
                s.curve = curve(pts, day: today, zone: zone, scale: scale, through: nowSlot, calendar: calendar)
            } else {
                s.curve = prev?.curve ?? []
            }
            if let pts = reading.yesterdayPower, let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
                let y = curve(pts, day: yesterday, zone: zone, scale: scale, calendar: calendar)
                s.yesterdaySoFar = Forecast.energy(y, through: nowSlot)
            } else {
                s.yesterdaySoFar = prev?.yesterdaySoFar
            }

            // device/list: the inverters and how many report without a fault
            let inverters: [GrowattAPI.Device]? = reading.devices.map(GrowattAPI.Device.inverters)
            if let inv = inverters {
                if inv.isEmpty {
                    s.invertersOnline = nil
                } else {
                    s.inverters = max(s.inverters, inv.count)
                    s.invertersOnline = inv.filter(\.isOnline).count
                }
            } else {
                s.invertersOnline = prev?.invertersOnline
            }

            // invs_data: each inverter's string currents, in the same INV order
            s.inverterStrings = strings(reading.inverters, order: inverters, previous: prev?.inverterStrings ?? [])

            // the alarms: the logger's silence, and each inverter's fault or lost contact
            var alarms: [Alarm] = []
            if offline {
                let since = s.lastReading ?? today
                let detail = s.lastReading == nil ? "ยังไม่มีข้อมูลจาก Growatt · ผลิตจริงไม่ทราบ"
                    : "ไม่มีข้อมูลตั้งแต่ " + clock(since, today: today, calendar: calendar) + " · ผลิตจริงไม่ทราบ"
                alarms.append(Alarm(id: base.id + "/lost", source: .lost, part: "ดาต้าล็อกเกอร์", detail: detail, since: since,
                                    loss: s.shortfall.map { Alarm.Loss.atMost($0) } ?? Alarm.Loss.unknown))
            } else if let inv = inverters {
                for (i, d) in inv.enumerated() {
                    let part = "INV \(i + 1)"
                    let since = date(d.lastUpdate, zone: zone) ?? now
                    let label = [d.model, d.sn].filter { !$0.isEmpty }.joined(separator: " ")
                    if d.isFault {
                        alarms.append(Alarm(id: base.id + "/fault/" + d.sn, source: .growatt, part: part,
                                            detail: "Fault" + (label.isEmpty ? "" : " · " + label), since: since))
                    } else if d.isLost {
                        alarms.append(Alarm(id: base.id + "/lost/" + d.sn, source: .lost, part: part,
                                            detail: "ขาดการติดต่อ" + (label.isEmpty ? "" : " · " + label), since: since))
                    }
                }
            } else {
                // device/list not read this time: its inverters' faults stand as last read
                alarms += (prev?.alarms ?? []).filter { $0.id.hasPrefix(base.id + "/fault/") || $0.id.hasPrefix(base.id + "/lost/") }
            }
            // one still raised keeps when it began, its count and its work order
            let before = Dictionary((prev?.alarms ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            s.alarms = alarms.map { a in
                guard let p = before[a.id] else { return a }
                var kept = a
                kept.since = min(p.since, a.since)
                kept.occurrences = p.occurrences
                kept.workOrder = p.workOrder
                return kept
            }

            // plant/energy: the last 30 days and 12 months, today's and this month's from the live figures
            let days = Chart.periodStarts(n: 30, byMonth: false, now: now, calendar: calendar)
            if let pts = reading.days {
                s.days = days.map { d in
                    let key = dayText(d.addingTimeInterval(12 * 3600), zone: zone)
                    let e = calendar.isDate(d, inSameDayAs: now) ? s.energyToday : pts.first { $0.date.hasPrefix(key) }?.energy
                    return Period(start: d, energy: e, expected: dayKWh)
                }
            } else if let old = prev?.days, !old.isEmpty {
                s.days = old.map { p in
                    calendar.isDate(p.start, inSameDayAs: now) ? Period(start: p.start, energy: s.energyToday, expected: dayKWh) : p
                }
            }
            let months = Chart.periodStarts(n: 12, byMonth: true, now: now, calendar: calendar)
            if let pts = reading.months {
                s.months = months.map { m in
                    let key = monthText(m.addingTimeInterval(12 * 3600), zone: zone)
                    let inMonth = calendar.range(of: .day, in: .month, for: m)?.count ?? 30
                    let current = calendar.isDate(m, equalTo: now, toGranularity: .month)
                    let elapsed = current ? (calendar.dateComponents([.day], from: m, to: today).day ?? 0) + 1 : inMonth
                    return Period(start: m, energy: pts.first { $0.date.hasPrefix(key) }?.energy, expected: dayKWh * Double(elapsed))
                }
            } else {
                s.months = prev?.months ?? []
            }

            // nothing here reads the zero-export meter or an irradiance sensor
            s.backfeedToday = nil
            s.hasIrradianceSensor = false
            s.prToday = nil
            return s
        }

        /// A MAX wires two strings to each MPPT: `currentString1` and `2` are MPPT 1's `a` and `b`, and so on.
        public static let stringsPerMPPT = 2

        /// One inverter's currents as MPPT rows of strings (`Station.inverterStrings`' inner part), A. From
        /// `currentStringN` two to an MPPT, else, when Growatt gives no string carrying current, from `ipvN` with one
        /// "string" per MPPT. The unused inputs after the last one carrying current are left out; nothing carrying
        /// current anywhere (night, or neither field given) is empty.
        public static func mppts(_ latest: GrowattAPI.Latest) -> [[Double?]] {
            func used(_ values: [Double?]) -> [Double?] {
                guard let last = values.lastIndex(where: { ($0 ?? 0) > StringTint.noCurrent }) else { return [] }
                return Array(values[...last])
            }
            let strings = used(latest.stringCurrents)
            if !strings.isEmpty {
                return stride(from: 0, to: strings.count, by: stringsPerMPPT).map {
                    Array(strings[$0..<min($0 + stringsPerMPPT, strings.count)])
                }
            }
            return used(latest.mpptCurrents).map { [$0] }
        }

        /// Every inverter's string currents in `INV` order (`device/list`'s inverters by serial number, else the
        /// batch's serials sorted). An inverter the batch left out, or the whole batch failing (`batch` nil), keeps
        /// its previous currents, so a missed read never shows 0; one out of contact has none (its last readings are
        /// old). One reading no current at all keeps its previous grid with 0 A, else none.
        static func strings(_ batch: [String: GrowattAPI.Latest]?, order devices: [GrowattAPI.Device]?,
                            previous: [[[Double?]]]) -> [[[Double?]]] {
            guard let batch else { return previous }
            let sns = devices.map { $0.map(\.sn) } ?? batch.keys.sorted()
            let lost = Set(devices?.filter(\.isLost).map(\.sn) ?? [])
            let out: [[[Double?]]] = sns.enumerated().map { i, sn in
                let kept = i < previous.count ? previous[i] : []
                guard !lost.contains(sn) else { return [] }
                guard let latest = batch[sn] else { return kept }
                let rows = mppts(latest)
                return rows.isEmpty ? kept.map { $0.map { $0 == nil ? nil : 0 } } : rows
            }
            return out.allSatisfy(\.isEmpty) ? [] : out
        }

        /// `09:00` today, else `7/11 17:00`.
        static func clock(_ date: Date, today: Date, calendar: Calendar) -> String {
            let c = calendar.dateComponents([.day, .month, .hour, .minute], from: date)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            return calendar.isDate(date, inSameDayAs: today) ? time : "\(c.day ?? 0)/\(c.month ?? 0) " + time
        }
    }
}
