import Foundation

extension Monitoring {
    /// One of the app's own lines (`TCRoof`) from one fleet to the next: when its condition began this time, how many
    /// times it was raised today, and whether it holds now. A line shows once its condition has held its time (30
    /// minutes for a low string, at once for the others); each time it shows again the same day counts once more.
    public struct Raised: Hashable, Sendable {
        /// When the condition began this time.
        public var since: Date
        /// Times the line was shown on `day`.
        public var occurrences: Int
        /// The condition holds now.
        public var active: Bool
        /// This time has held long enough to show (and was counted).
        public var shown: Bool
        /// The day `occurrences` counts, its 00:00.
        public var day: Date

        public init(since: Date, occurrences: Int, active: Bool, shown: Bool, day: Date) {
            self.since = since; self.occurrences = occurrences; self.active = active; self.shown = shown; self.day = day
        }

        /// The line at `now` after `previous`, its condition `holding` or not, shown once it has held `hold` seconds.
        static func next(_ previous: Raised?, holding: Bool, now: Date, hold: TimeInterval, calendar: Calendar) -> Raised {
            let today = calendar.startOfDay(for: now)
            var r = previous ?? Raised(since: now, occurrences: 0, active: false, shown: false, day: today)
            // a new day counts from 0, a line still shown across midnight once
            if r.day != today {
                r.day = today
                r.occurrences = r.active && r.shown && holding ? 1 : 0
            }
            guard holding else {
                r.active = false
                r.shown = false
                return r
            }
            if !r.active {
                r.since = now
                r.active = true
                r.shown = false
            }
            if !r.shown, now.timeIntervalSince(r.since) >= hold {
                r.shown = true
                r.occurrences += 1
            }
            return r
        }
    }
}

extension Monitoring.Fleet {
    /// A line whose condition holds now, shown once it has held `hold` seconds.
    struct Check {
        var alarm: Monitoring.Alarm
        var hold: TimeInterval = 0
    }

    /// `สตริงกระแสต่ำ` must hold this long before its line shows (`Settings.stringLowPercent`'s "for 30 minutes").
    public static let stringHold: TimeInterval = 30 * 60

    /// An inverter's strings are judged only when their median carries at least this much, A: at dawn and dusk a few
    /// tenths of an amp apart is a large share and means nothing.
    public static let stringMinimumMedian = 1.0

    static func prID(_ station: String) -> String { station + "/pr" }

    static func stringID(_ station: String, inverter: Int, mppt: Int, string: Int) -> String {
        "\(station)/string/\(inverter + 1)/\(mppt + 1)\(stringLetter(string))"
    }

    /// The lines that make a `ปกติ` station need someone (`needingAttention`): a low string, low PR.
    static func needsAttention(_ id: String, station: String) -> Bool {
        id == prID(station) || id.hasPrefix(station + "/string/")
    }

    /// `สตริงกระแสต่ำ` (`Settings.stringLowPercent`): each string carrying current that is `percent` % or more under
    /// the median of its inverter's strings carrying current (`StringTint.median`). A string with no current isn't
    /// judged (an unused input reads 0 too), nor an inverter whose median is under `stringMinimumMedian`. The loss is
    /// about the day's energy times the string's missing current over all the station's.
    static func stringChecks(_ s: Monitoring.Station, percent: Int, now: Date) -> [Check] {
        guard s.paired, !s.inverterStrings.isEmpty else { return [] }
        let carrying = s.inverterStrings.flatMap { $0.flatMap { $0 } }.compactMap { $0 }
            .filter { $0 > Monitoring.StringTint.noCurrent }
        let total = carrying.reduce(0, +)
        let limit = 1 - Double(percent) / 100
        // the inverter is named only when the station has more than one
        let named = s.inverterStrings.count > 1 || s.inverters > 1
        var out: [Check] = []
        for (i, inverter) in s.inverterStrings.enumerated() {
            guard let median = Monitoring.StringTint.median(inverter.flatMap { $0 }),
                  median >= stringMinimumMedian else { continue }
            for (m, mppt) in inverter.enumerated() {
                for (k, value) in mppt.enumerated() {
                    guard let v = value, v > Monitoring.StringTint.noCurrent, v <= median * limit else { continue }
                    let part = (named ? "INV \(i + 1) · " : "") + "MPPT \(m + 1) \(stringLetter(k))"
                    var loss = Monitoring.Alarm.Loss.unknown
                    if let e = s.energyToday, total > 0 { loss = .about(e * (median - v) / total) }
                    let alarm = Monitoring.Alarm(
                        id: stringID(s.id, inverter: i, mppt: m, string: k), source: .tcroof, part: part,
                        detail: "สตริง \(amps(v)) A จากค่ากลาง \(amps(median)) A · เกณฑ์ \(percent)%", since: now, loss: loss)
                    out.append(Check(alarm: alarm, hold: stringHold))
                }
            }
        }
        return out
    }

    /// `PR ต่ำ` (`Settings.prLowPercent`): today's PR under `percent` %, for a station with an irradiance sensor only
    /// (without one `prToday` is nil and the page shows `—`). Its cost isn't known from PR alone.
    static func prAlarm(_ s: Monitoring.Station, percent: Int, since: Date) -> Monitoring.Alarm? {
        guard s.paired, s.hasIrradianceSensor, let pr = s.prToday, pr < Double(percent) else { return nil }
        // floored, so a station just under the threshold never reads as on it
        let shown = Int(pr.rounded(.down))
        return Monitoring.Alarm(id: prID(s.id), source: .tcroof, part: "PR", detail: "PR \(shown)% · เกณฑ์ \(percent)%",
                                since: since)
    }

    /// `a`, `b`, … for a string's place on its MPPT.
    static func stringLetter(_ k: Int) -> String {
        let letters = Array("abcdefghij")
        return k < letters.count ? String(letters[k]) : String(k + 1)
    }

    /// `3.1`, `10`: amps to a tenth, without a trailing `.0`.
    static func amps(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
}
