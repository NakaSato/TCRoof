import Foundation

extension Monitoring {
    /// The forecast a station is measured against (the loss is what falls short of it): its size × the site's kWh/kWp
    /// a day, spread over the day as a clear day's curve.
    public enum Forecast {
        /// kWh/kWp a day without the site's GPS.
        public static let typicalDaily = 4.0
        /// The day the curve covers: 06:00 to 18:30.
        static let sunrise = 6.0, sunset = 18.5

        /// kWh/kWp a day at the site, from the app's yield (`PlaneYield`, a plane tilted 10° to the south); the typical
        /// figure without a latitude.
        public static func dailyKWhPerKWp(latitude: Double?, longitude: Double?) -> Double {
            guard let lat = latitude else { return typicalDaily }
            let year: Double = PlaneYield.kWhPerKWp(latitude: lat, longitude: longitude, tilt: 10, azimuthFromSouth: 0)
            return year > 0 ? year / 365 : typicalDaily
        }

        /// kW per 5-minute slot from 00:00 whose day adds up to `dailyKWh`.
        public static func curve(dailyKWh: Double) -> [Double] {
            let shape: [Double] = (0..<Monitoring.slots).map { i in
                let h = (Double(i) + 0.5) * Double(Monitoring.slotMinutes) / 60
                guard h > sunrise, h < sunset else { return 0 }
                return pow(sin(Double.pi * (h - sunrise) / (sunset - sunrise)), 1.3)
            }
            let area = energy(shape, through: Monitoring.slots - 1)
            return area > 0 ? shape.map { $0 * dailyKWh / area } : shape
        }

        /// kWh of a power curve up to and including `slot`.
        public static func energy(_ curve: [Double], through slot: Int) -> Double {
            let hours = Double(Monitoring.slotMinutes) / 60
            return curve.prefix(max(slot + 1, 0)).reduce(0) { $0 + $1 * hours }
        }

        /// kWh of a read curve up to `slot`, nil when nothing was read.
        public static func energy(_ curve: [Double?], through slot: Int) -> Double? {
            let read = curve.prefix(max(slot + 1, 0)).compactMap { $0 }
            guard !read.isEmpty else { return nil }
            return read.reduce(0, +) * Double(Monitoring.slotMinutes) / 60
        }

        /// The slot `date` falls in, in its day.
        public static func slot(of date: Date, calendar: Calendar = .current) -> Int {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return min(((c.hour ?? 0) * 60 + (c.minute ?? 0)) / Monitoring.slotMinutes, Monitoring.slots - 1)
        }
    }

    public enum ChartRange: String, CaseIterable, Sendable {
        /// `วันนี้` (every 5 minutes), `7 วัน`, `30 วัน`, `12 เดือน`.
        case today, week, month, year

        /// Days (or months for `year`) the range covers.
        public var length: Int {
            switch self {
            case .today: 1
            case .week: 7
            case .month: 30
            case .year: 12
            }
        }
    }

    public struct ChartPoint: Identifiable, Hashable, Sendable {
        public var x: Date
        /// kW for today, kWh a day or month otherwise; nil where nothing was read (or not yet).
        public var actual: Double?
        public var expected: Double?
        public var id: Date { x }

        /// The shaded gap: how far it fell under the forecast.
        public var loss: Double? {
            guard let a = actual, let e = expected, e > a else { return nil }
            return e - a
        }
    }

    public struct ChartSeries: Identifiable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var points: [ChartPoint]
    }

    /// A time marked on the day's line: when an alarm began.
    public struct ChartEvent: Identifiable, Hashable, Sendable {
        public var id: String
        public var x: Date
        /// `MP 25 INV 2 หยุด`.
        public var label: String
        public var source: Alarm.Source
    }

    /// Chart events close in time, as one pill in the lane under the plot (CHA-110): those less than
    /// `Chart.clusterGap` after the cluster's first, or all of those before the axis (`ก่อน 06:00 · n`).
    public struct EventCluster: Identifiable, Hashable, Sendable {
        public var events: [ChartEvent]
        /// Before the axis begins: no rule is drawn for it, and its pill sits at the axis' start.
        public var early: Bool
        public var id: String { (early ? "early/" : "") + (events.first?.id ?? "") }
        /// The first event's time.
        public var x: Date { events.first?.x ?? .distantPast }
    }

    /// The column beside the chart, for its range.
    public struct ChartSummary: Hashable, Sendable {
        /// Made so far and its share of the forecast so far, kWh.
        public var produced: Double?
        public var expected: Double?
        public var share: Double? {
            guard let p = produced, let e = expected, e > 0 else { return nil }
            return p / e
        }
        /// Today: the whole day at the rate so far (the forecast's day × the share so far).
        public var projected: Double?
        /// The gap under the forecast, kWh.
        public var loss: Double?
        /// Today: yesterday by the same time; a week: the week before; nil when not known.
        public var previous: Double?
        public var vsPrevious: Double? {
            guard let p = produced, let q = previous, q > 0 else { return nil }
            return p / q - 1
        }
        /// The last reading (today only).
        public var asOf: Date?
    }

    /// `กำลังผลิตรวม`: the fleet's line against the forecast for a range, or one line per station.
    public struct Chart: Sendable {
        public let range: ChartRange
        /// The fleet's total, and each station's (`hidden` left out). Past `splitLimit` stations, the five largest
        /// have their own line and the rest one together (`othersID`).
        public let total: [ChartPoint]
        public let series: [ChartSeries]
        /// The stations with their own line, in the chips' order, and those drawn together as `อื่น ๆ`.
        public let leadIDs: [String]
        public let otherIDs: [String]
        public let events: [ChartEvent]
        public let summary: ChartSummary
        /// The axis: 06:00 to 19:00 today, else the range's first to last day.
        public let domain: ClosedRange<Date>

        /// Today's line is drawn from 06:00 to 19:00.
        public static let dayWindow = (6 * 60 / Monitoring.slotMinutes)..<(19 * 60 / Monitoring.slotMinutes)

        /// At most this many chips under `แยกสถานี` (CHA-110).
        public static let splitLimit = 6
        /// The series of the stations past the five largest.
        public static let othersID = "others"
        /// Events closer than this share a pill.
        public static let clusterGap: TimeInterval = 3600

        public init(_ stations: [Station], range: ChartRange, now: Date, calendar: Calendar = .current, hidden: Set<String> = []) {
            self.range = range
            let (lead, rest) = Chart.split(stations)
            leadIDs = lead.map(\.id)
            otherIDs = rest.map(\.id)
            let shownLead = lead.filter { !hidden.contains($0.id) }
            let shownRest = rest.filter { !hidden.contains($0.id) }
            switch range {
            case .today:
                let start = calendar.startOfDay(for: now)
                let nowSlot = Forecast.slot(of: now, calendar: calendar)
                func x(_ i: Int) -> Date { start.addingTimeInterval(TimeInterval(i * Monitoring.slotMinutes * 60)) }
                func points(_ s: [Station]) -> [ChartPoint] {
                    Chart.dayWindow.map { i in
                        let read: [Double] = i > nowSlot ? [] : s.compactMap { st in i < st.curve.count ? st.curve[i] : nil }
                        let exp: [Double] = s.compactMap { st in i < st.expectedCurve.count ? st.expectedCurve[i] : nil }
                        return ChartPoint(x: x(i), actual: read.isEmpty ? nil : read.reduce(0, +),
                                          expected: exp.isEmpty ? nil : exp.reduce(0, +))
                    }
                }
                total = points(stations)
                series = shownLead.map { ChartSeries(id: $0.id, name: Chart.name($0), points: points([$0])) }
                    + (shownRest.isEmpty ? [] : [ChartSeries(id: Chart.othersID, name: "อื่น ๆ", points: points(shownRest))])
                // once per station and part, at its first alarm today
                events = stations.flatMap { s -> [ChartEvent] in
                    let today = s.alarms.filter { $0.source != .tcroof && $0.since >= start && $0.since <= now }
                    let first = Dictionary(grouping: today, by: \.part).compactMap { $0.value.min { $0.since < $1.since } }
                    return first.map { a in
                        ChartEvent(id: s.id + "/" + a.part, x: a.since,
                                   label: [Chart.name(s), a.part, a.source == .lost ? "ขาดการติดต่อ" : "หยุด"].joined(separator: " "),
                                   source: a.source)
                    }
                }
                .sorted { $0.x < $1.x }
                let produced = Fleet.sum(stations.map(\.energyToday)), expected = Fleet.sum(stations.map(\.expectedSoFar))
                let day = Fleet.sum(stations.map(\.expectedToday))
                let projected: Double? = {
                    guard let p = produced, let e = expected, e > 0, let d = day else { return nil }
                    return d * p / e
                }()
                summary = ChartSummary(produced: produced, expected: expected, projected: projected,
                                       loss: expected.map { max($0 - (produced ?? 0), 0) },
                                       previous: Fleet.sum(stations.map(\.yesterdaySoFar)),
                                       asOf: stations.compactMap(\.lastReading).max())
                domain = x(Chart.dayWindow.lowerBound)...x(Chart.dayWindow.upperBound)
            case .week, .month, .year:
                let n = range.length, byMonth = range == .year
                let ends = Chart.periodStarts(n: n, byMonth: byMonth, now: now, calendar: calendar)
                func periods(_ s: Station) -> [Period] { byMonth ? s.months : s.days }
                func key(_ d: Date) -> Date {
                    byMonth ? (calendar.dateInterval(of: .month, for: d)?.start ?? d) : calendar.startOfDay(for: d)
                }
                func points(_ s: [Station], _ starts: [Date]) -> [ChartPoint] {
                    starts.map { d in
                        let ps = s.compactMap { st in periods(st).first { key($0.start) == d } }
                        return ChartPoint(x: d, actual: Fleet.sum(ps.map(\.energy)), expected: Fleet.sum(ps.map(\.expected)))
                    }
                }
                total = points(stations, ends)
                series = shownLead.map { ChartSeries(id: $0.id, name: Chart.name($0), points: points([$0], ends)) }
                    + (shownRest.isEmpty ? [] : [ChartSeries(id: Chart.othersID, name: "อื่น ๆ", points: points(shownRest, ends))])
                events = []
                let produced = Fleet.sum(total.map(\.actual)), expected = Fleet.sum(total.map(\.expected))
                let loss = Fleet.sum(total.map { p -> Double? in p.expected == nil ? nil : (p.loss ?? 0) })
                // a week against the one before, when the 30 days hold it
                let previous: Double? = range == .week
                    ? Fleet.sum(points(stations, Chart.periodStarts(n: 7, byMonth: false,
                                                                    now: calendar.date(byAdding: .day, value: -7, to: now) ?? now,
                                                                    calendar: calendar)).map(\.actual))
                    : nil
                summary = ChartSummary(produced: produced, expected: expected, projected: nil, loss: loss, previous: previous, asOf: nil)
                domain = (ends.first ?? now)...(ends.last ?? now)
            }
        }

        /// The first day (or month) of each of the last `n`, oldest first, `now`'s last.
        static func periodStarts(n: Int, byMonth: Bool, now: Date, calendar: Calendar) -> [Date] {
            let unit: Calendar.Component = byMonth ? .month : .day
            let last = byMonth ? (calendar.dateInterval(of: .month, for: now)?.start ?? now) : calendar.startOfDay(for: now)
            return (0..<n).reversed().compactMap { calendar.date(byAdding: unit, value: -$0, to: last) }
        }

        /// The stations with their own line and the rest: all of them up to `splitLimit`, else the five largest
        /// (by kWp, then MP) and the others.
        static func split(_ stations: [Station]) -> (lead: [Station], rest: [Station]) {
            guard stations.count > splitLimit else { return (stations, []) }
            let ranked = stations.sorted { a, b in
                a.kWp != b.kWp ? a.kWp > b.kWp : (a.mpNumber ?? .max) < (b.mpNumber ?? .max)
            }
            let lead = Array(ranked.prefix(splitLimit - 1))
            let ids = Set(lead.map(\.id))
            return (lead, stations.filter { !ids.contains($0.id) })
        }

        /// The station's code: `MP 25`, else the plant name's first word when it reads as a code (`P1_3` of
        /// `P1_3 สถานีผลิตน้ำบ้านโป่ง`: Latin letters or digits, at most 12 characters), else the whole name.
        public static func name(_ s: Station) -> String {
            if let mp = s.mpNumber { return "MP \(mp)" }
            return code(of: s.name) ?? s.name
        }

        /// The name less its code: `สถานีผลิตน้ำบ้านโป่ง` of `P1_3 สถานีผลิตน้ำบ้านโป่ง`; the name when it has none.
        public static func rest(_ s: Station) -> String {
            guard s.mpNumber == nil, let c = code(of: s.name) else { return s.name }
            return String(s.name.dropFirst(c.count)).trimmingCharacters(in: .whitespaces)
        }

        static func code(of name: String) -> String? {
            let words = name.split(whereSeparator: \.isWhitespace)
            guard words.count > 1, let first = words.first, first.count <= 12,
                  first.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) && $0.isASCII }),
                  first.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
            return String(first)
        }

        /// The day's events as pills: those before the axis in one, then each run less than `clusterGap` after its
        /// first. Empty for the other ranges.
        public var clusters: [EventCluster] {
            let early = events.filter { $0.x < domain.lowerBound }
            var out: [EventCluster] = early.isEmpty ? [] : [EventCluster(events: early, early: true)]
            for e in events where e.x >= domain.lowerBound {
                if let last = out.last, !last.early, e.x.timeIntervalSince(last.x) < Chart.clusterGap {
                    out[out.count - 1].events.append(e)
                } else {
                    out.append(EventCluster(events: [e], early: false))
                }
            }
            return out
        }

        /// The day's highest reading so far, and the last one (today only).
        public var peak: ChartPoint? {
            guard range == .today else { return nil }
            return total.filter { $0.actual != nil }.max { ($0.actual ?? 0) < ($1.actual ?? 0) }
        }
        public var current: ChartPoint? {
            guard range == .today else { return nil }
            return total.last { $0.actual != nil }
        }
    }
}
