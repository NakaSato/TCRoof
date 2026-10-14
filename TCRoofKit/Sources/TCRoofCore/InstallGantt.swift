import Foundation

/// The iPad install tracking page's `ความคืบหน้าเทียบแผน` card (docs/ui/install-tracking-ipad §B), from a station's MP
/// plan: one row per construction and commissioning task (2.1 – 3.2), with the places the daily reports book it at as
/// its sub-rows. The permit tasks (1.x) run months before the install and stay out.
public struct InstallGantt: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case done, current, waiting }

    /// One place a task is booked at, with its latest % สะสม.
    public struct Sub: Equatable, Sendable, Identifiable {
        public var title: String
        public var percent: Double
        /// Its own planned days; nil for a place from the daily reports, which has none (its bar spans the task's).
        public var start: Date?
        public var end: Date?
        public var id: String { title }
        public init(_ title: String, percent: Double, start: Date? = nil, end: Date? = nil) {
            self.title = title; self.percent = percent; self.start = start; self.end = end
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String
        public var code: String
        public var title: String
        public var status: Status
        public var start: Date
        public var end: Date
        /// The actual bar: from when work began to when it finished, or to today while it runs.
        public var actualStart: Date?
        public var actualEnd: Date?
        public var percent: Double
        /// Where the running task ends at its pace so far; nil when it isn't running or has no progress yet.
        public var forecastEnd: Date?
        /// Days past the plan's end: finished late, forecast late, or not done and past its end.
        public var overrunDays: Int
        public var subs: [Sub]

        public init(id: String, code: String, title: String, status: Status, start: Date, end: Date, actualStart: Date? = nil,
                    actualEnd: Date? = nil, percent: Double, forecastEnd: Date? = nil, overrunDays: Int = 0, subs: [Sub] = []) {
            self.id = id; self.code = code; self.title = title; self.status = status; self.start = start; self.end = end
            self.actualStart = actualStart; self.actualEnd = actualEnd; self.percent = percent; self.forecastEnd = forecastEnd
            self.overrunDays = overrunDays; self.subs = subs
        }
    }

    public var rows: [Row]
    public var today: Date

    public init(rows: [Row], today: Date) { self.rows = rows; self.today = today }

    /// The rows of a plan. `places` gives each task's places with their latest percent (`RoutineReport.places`).
    public init(plan: [MasterSchedule.PlannedTask], actual: MasterSchedule.Actual, places: [MasterSchedule.Task: [Sub]],
                today: Date, calendar cal: Calendar = MasterSchedule.calendar) {
        let day = cal.startOfDay(for: today)
        func days(_ a: Date, _ b: Date) -> Int { cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0 }
        self.today = day
        rows = plan.compactMap { p in
            guard p.task.part != .permit, p.weight > 0, let start = p.start, let end = p.end else { return nil }
            let percent = min(max(actual.done(p.task, through: day, calendar: cal) / p.weight * 100, 0), 100)
            let done = percent >= 99.95
            let began = actual.started[p.task.rawValue] ?? (percent > 0 ? start : nil)
            let finished = actual.finished[p.task.rawValue]
            let status: Status = done ? .done : (percent > 0 || began != nil || start <= day) ? .current : .waiting
            var row = Row(id: p.task.rawValue, code: p.task.code, title: p.task.title, status: status, start: start, end: end,
                          actualStart: began, percent: percent, subs: places[p.task] ?? [])
            switch status {
            case .done:
                row.actualEnd = finished ?? min(day, end)
                if let f = row.actualEnd { row.overrunDays = max(days(end, f), 0) }
            case .current:
                if let began { row.actualEnd = max(day, began) }
                if let began, percent > 0 {
                    // the pace so far: the days taken over the share done
                    let taken = Double(max(days(began, day) + 1, 1))
                    let total = Int((taken / (percent / 100)).rounded(.up))
                    row.forecastEnd = cal.date(byAdding: .day, value: max(total, 1) - 1, to: cal.startOfDay(for: began))
                }
                row.overrunDays = max(days(end, row.forecastEnd ?? day), 0)
            case .waiting: break
            }
            return row
        }
    }

    /// From the first planned start to the last date anything reaches, today included.
    public func span(calendar cal: Calendar = MasterSchedule.calendar) -> ClosedRange<Date>? {
        guard let first = rows.map(\.start).min() else { return nil }
        let ends = rows.flatMap { [$0.end, $0.actualEnd, $0.forecastEnd].compactMap { $0 } } + [today]
        let last = ends.max() ?? today
        return cal.startOfDay(for: min(first, today))...cal.startOfDay(for: last)
    }

    /// Sub-rows at 100 % over all sub-rows: `27 งานย่อย`.
    public var subCount: Int { rows.reduce(0) { $0 + $1.subs.count } }
}

public extension RoutineReport {
    /// Each MP task's places with their latest % สะสม, through `date`: the station's own list for the task when it
    /// has one, else the places the reports used, in the order they first appear.
    static func places(reports: [Daily], through date: Date, settings: Settings) -> [MasterSchedule.Task: [InstallGantt.Sub]] {
        let upto = reports.filter { day($0.date) <= day(date) }.sorted { $0.date < $1.date }
        var latest: [MasterSchedule.Task: [String: Double]] = [:], order: [MasterSchedule.Task: [String]] = [:]
        for r in upto {
            for l in r.progress {
                guard let t = l.task else { continue }
                if latest[t]?[l.location] == nil { order[t, default: []].append(l.location) }
                latest[t, default: [:]][l.location] = l.percent
            }
        }
        var out: [MasterSchedule.Task: [InstallGantt.Sub]] = [:]
        for t in MasterSchedule.Task.allCases {
            let own = settings.taskLocations[t.rawValue] ?? []
            let names = own.isEmpty ? order[t] ?? [] : own
            guard !names.isEmpty else { continue }
            out[t] = names.map { .init($0.isEmpty ? "ไม่ระบุตำแหน่ง" : $0, percent: min(max(latest[t]?[$0] ?? 0, 0), 100)) }
        }
        return out
    }
}
