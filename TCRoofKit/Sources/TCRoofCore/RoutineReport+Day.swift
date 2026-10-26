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

    public static let thaiWeekdaysFull = ["อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัสบดี", "ศุกร์", "เสาร์"]

    /// "2 ก.ค. 2568 (วันพุธ)", the iPad daily report's title after `รายงานประจำวันที่ `.
    public static func thaiDateFullWeekday(_ d: Date) -> String {
        thaiDate(d) + " (วัน" + thaiWeekdaysFull[(calendar.component(.weekday, from: d) - 1) % 7] + ")"
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

    // MARK: Date picker (docs/ui/daily-report-ipad-v3 §1)

    /// A day's dot in the one-page report's month calendar.
    public enum DayStatus: Hashable, Sendable {
        /// The reporter signed it (`engineerSignedAt`).
        case sent
        case draft
        /// A working day before today, on or after the install start, with no report.
        case missing
        /// No dot: a day off, today or later without a report, or before the install start.
        case none
    }

    /// The day's dot. `signed` is nil when the day has no report, else whether it is signed. A report on a day off still
    /// shows its state; today without a report has no dot yet, since the day isn't over.
    public static func dayStatus(_ date: Date, signed: Bool?, settings: Settings, today: Date, from start: Date? = nil) -> DayStatus {
        if let signed { return signed ? .sent : .draft }
        let d = day(date)
        guard d < day(today), isWorkingDay(d, settings: settings) else { return .none }
        if let start, d < day(start) { return .none }
        return .missing
    }

    /// The month of `date` for a calendar grid that starts on Sunday: the blank cells before the 1st and every day.
    public static func monthGrid(_ date: Date) -> (leading: Int, days: [Date]) {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return (0, []) }
        let first = day(month.start)
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        return (calendar.component(.weekday, from: first) - 1, (0..<count).map { add(first, $0) })
    }

    // MARK: Working time (docs/ui/daily-report-ipad-v3 §2)

    /// The working-time picker's limits: start 06–10, end 15–20, at least 4 hours, 1-hour steps.
    public enum WorkHours {
        public static let starts = 6...10
        public static let ends = 15...20
        public static let minimum = 4
        /// The picker's presets (the station settings keep one pair of hours, not a list).
        public static let presets: [(start: String, end: String)] = [("08.00", "17.00"), ("08.00", "18.00"), ("07.00", "16.00")]

        /// `8` → `"08.00"`, the stored format.
        public static func text(_ hour: Int) -> String { String(format: "%02d.00", hour) }

        /// The start or end moved by `step` hours, or nil when that leaves its range or the 4-hour minimum.
        public static func step(start: Int, end: Int, moveEnd: Bool, by step: Int) -> (start: Int, end: Int)? {
            let s = moveEnd ? start : start + step, e = moveEnd ? end + step : end
            guard starts.contains(s), ends.contains(e), e - s >= minimum else { return nil }
            return (s, e)
        }
    }

    // MARK: Task list (docs/ui/daily-report-ipad-v2 §4)

    /// Today's % for a tap on the 10-segment bar's segment `segment` (1…10, each 10 % of the whole task): up to
    /// `segment × 10`, capped at what is left; nil for a segment already done before today.
    public static func todayFromSegment(_ segment: Int, before: Double) -> Double? {
        let target = Double(min(max(segment, 1), 10) * 10)
        guard target > before + 1e-9 else { return nil }
        return min(target - before, 100 - before)
    }

    /// Today's % moved by `step` (the ± buttons, 5 %), kept within 0 … what is left.
    public static func stepToday(_ today: Double, before: Double, by step: Double) -> Double {
        min(max(today + step, 0), max(100 - before, 0))
    }

    /// Today's lines by location, in Thai numeric order (`หลังคา 2` before `หลังคา 10`), lines without a location last;
    /// each group keeps the report's order.
    public static func locationGroups(_ lines: [ProgressLine]) -> [(location: String, lines: [ProgressLine])] {
        var order: [String] = [], groups: [String: [ProgressLine]] = [:]
        for l in lines {
            let k = l.location.trimmingCharacters(in: .whitespaces)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(l)
        }
        let thai = Locale(identifier: "th_TH")
        order.sort { a, b in
            if a.isEmpty != b.isEmpty { return b.isEmpty }
            return a.compare(b, options: [.numeric, .caseInsensitive], locale: thai) == .orderedAscending
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}
