import Foundation

/// The iPad one-page daily report's figures (docs/ui/daily-report-ipad): what today's lines add to the station, the
/// day's labour hours, the `วันนี้` quick picks, the MP tasks planned this week that today's report hasn't got yet,
/// and a task's progress against its plan.
extension RoutineReport {

    // MARK: Station % today

    /// The locations a task's % is averaged over: the settings' list for it, else every location it has been reported
    /// at (today's report included); at least 1.
    public static func locationCount(_ task: MasterSchedule.Task, reports: [Daily], settings: Settings) -> Int {
        if let set = settings.taskLocations[task.rawValue], !set.isEmpty { return set.count }
        let places = Set(reports.flatMap { $0.progress.filter { $0.task == task }.map(\.location) })
        return max(places.count, 1)
    }

    /// What one line adds to the whole station today, in station % points: its % today × its task's weight ÷ the
    /// task's location count. A line with no MP task adds nothing.
    public static func stationGain(_ line: ProgressLine, on d: Daily, previous: [Daily], settings: Settings,
                                   over200kVA: Bool) -> Double {
        stationGain(line, on: d, previous: previous, settings: settings, weight: { $0.weight(over200kVA: over200kVA) })
    }

    /// `stationGain` against the plan's own weights (`MasterSchedule.Input.weight`).
    public static func stationGain(_ line: ProgressLine, on d: Daily, previous: [Daily], settings: Settings,
                                   weight: (MasterSchedule.Task) -> Double) -> Double {
        guard let task = line.task else { return 0 }
        let today = todayDelta(line, on: d.date, in: previous)
        let n = locationCount(task, reports: previous + [d], settings: settings)
        return today * weight(task) / Double(n) / 100
    }

    /// Σ of `stationGain` over the day's lines.
    public static func stationGain(_ d: Daily, previous: [Daily], settings: Settings, over200kVA: Bool) -> Double {
        d.progress.reduce(0) { $0 + stationGain($1, on: d, previous: previous, settings: settings, over200kVA: over200kVA) }
    }

    /// A task's % done through the day (the day's report counted) against its plan to that week; `behind` is plan
    /// minus actual, positive when late.
    public struct TaskStanding: Equatable, Sendable {
        public let actual: Double
        public let planned: Double
        public var behind: Double { planned - actual }
    }

    public static func standing(_ task: MasterSchedule.Task, on d: Daily, previous: [Daily], settings: Settings,
                                plan: [MasterSchedule.PlannedTask]) -> TaskStanding {
        let reports = previous.filter { day($0.date) != day(d.date) } + [d]
        let actual = taskPercent(task, reports: reports, through: d.date, settings: settings) ?? 0
        let planned = MasterSchedule.status(plan: plan, actual: .init(), through: d.date).plannedByTask[task] ?? 0
        return TaskStanding(actual: actual, planned: planned)
    }

    // MARK: Quick picks

    /// `+10% | +20% | +30% | +50% | เสร็จ` for a line at `before` %: the steps that still fit, then what is left (เสร็จ).
    /// Nothing once the line is done.
    public static func quickPicks(before: Double) -> [Double] {
        let left = 100 - min(max(before, 0), 100)
        guard left > 1e-9 else { return [] }
        return [10, 20, 30, 50].filter { $0 < left - 1e-9 } + [left]
    }

    // MARK: Labour

    public struct Labour: Equatable, Sendable {
        public let people: Int
        /// Hours from the start to the end of the working time.
        public let hours: Int
        /// Rain slots inside the working time.
        public let rainHours: Int
        /// คน-ชม.
        public var total: Int { people * hours }
        /// คน-ชม. less the rain inside the working time.
        public var working: Int { people * max(hours - rainHours, 0) }
    }

    /// Hours of `08.00` / `8:00`, or nil.
    public static func hour(_ s: String) -> Int? {
        Int(s.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == "." || $0 == ":" }).first ?? "")
    }

    /// The day's crew × its working hours, and the same less the rain hours that fall inside the working time.
    public static func labour(_ d: Daily) -> Labour {
        let start = hour(d.workStart) ?? 8, end = hour(d.workEnd) ?? 17
        let rain = zip(weatherHours, d.weather).filter { h, w in w == .rain && h >= start && h < end }.count
        return Labour(people: d.crewTotal, hours: max(end - start, 0), rainHours: rain)
    }

    // MARK: Planned work not in today's report

    /// MP tasks planned in the week of the day and not done, at each of their locations, that today's report has no
    /// line for: the key plan's `+` pins. A task's locations are the settings' list for it, else where it has been
    /// reported and isn't at 100 %. Each line starts where the last report left it.
    public static func plannedNotReported(on d: Daily, previous: [Daily], settings: Settings,
                                          plan: [MasterSchedule.PlannedTask]) -> [ProgressLine] {
        let week = RoutineReport.week(of: d.date)
        let today = Set(d.progress.map { "\($0.task?.rawValue ?? "-")|\($0.location)" })
        var out: [ProgressLine] = []
        for p in plan where p.weight > 0 {
            guard let s = p.start, let e = p.end, day(s) <= week.upperBound, day(e) >= week.lowerBound else { continue }
            let set = settings.taskLocations[p.task.rawValue] ?? []
            let places: [String]
            if !set.isEmpty {
                places = set
            } else {
                var seen: [String] = []
                for r in previous.sorted(by: { $0.date < $1.date }) {
                    for l in r.progress where l.task == p.task && !seen.contains(l.location) { seen.append(l.location) }
                }
                places = seen
            }
            for place in places where !today.contains("\(p.task.rawValue)|\(place)") {
                var line = ProgressLine(task: p.task, description: "", location: place)
                line.percent = previousPercent(line, before: d.date, in: previous)
                if line.percent < 100 - 1e-9 { out.append(line) }
            }
        }
        return out
    }

    /// The line a `+` pin adds: the planned line moved on 10 % (capped at 100).
    public static func startToday(_ planned: ProgressLine) -> ProgressLine {
        var l = planned
        l.id = UUID()
        l.percent = min(planned.percent + 10, 100)
        return l
    }

    // MARK: Tools

    /// Tools a task usually needs, by MP task (the default tool list's names), for `ใช้ …` on the task panel.
    public static func suggestedTools(_ task: MasterSchedule.Task?) -> [String] {
        switch task {
        case .structure?: ["สว่านไฟฟ้า", "ตู้เชื่อม"]
        case .panels?, .dcSide?: ["สว่านไฟฟ้า", "บันได"]
        case .inverter?, .acSide?, .fireSwitch?: ["สว่านไฟฟ้า"]
        case .controlCabinet?: ["สว่านไฟฟ้า", "เครื่องเจียร"]
        default: []
        }
    }

    // MARK: Formatting

    public static let thaiWeekdaysShort = ["อา.", "จ.", "อ.", "พ.", "พฤ.", "ศ.", "ส."]

    /// "พ. 2 ก.ค. 2568".
    public static func thaiWeekdayDate(_ d: Date) -> String {
        thaiWeekdaysShort[(calendar.component(.weekday, from: d) - 1) % 7] + " " + thaiDate(d)
    }

    /// The working day before or after `date` (the day switcher), skipping days off; nil past `limit` going forward.
    public static func reportDay(from date: Date, by step: Int, settings: Settings, limit: Date? = nil) -> Date? {
        var d = day(date)
        for _ in 0..<31 {
            d = add(d, step)
            if let limit, step > 0, d > day(limit) { return nil }
            if isWorkingDay(d, settings: settings) { return d }
        }
        return nil
    }
}
