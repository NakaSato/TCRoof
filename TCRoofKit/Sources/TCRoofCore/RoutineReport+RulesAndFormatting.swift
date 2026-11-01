import Foundation

extension RoutineReport {
    // MARK: Rules (§3)

    public static func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }
    public static func add(_ d: Date, _ n: Int) -> Date {
        calendar.date(byAdding: .day, value: n, to: d) ?? d.addingTimeInterval(Double(n) * 86_400)
    }

    /// The line's % in the latest report before `date` that has it; 0 when none does.
    public static func previousPercent(_ line: ProgressLine, before date: Date, in reports: [Daily]) -> Double {
        let d = day(date)
        return reports.filter { day($0.date) < d }.sorted { $0.date > $1.date }
            .lazy.compactMap { $0.progress.first { $0.key == line.key }?.percent }.first ?? 0
    }

    /// "วันนี้": today's % minus the previous report's; shown, never stored.
    public static func todayDelta(_ line: ProgressLine, on date: Date, in reports: [Daily]) -> Double {
        line.percent - previousPercent(line, before: date, in: reports)
    }

    /// The next report's draft: crew and tools copied but unconfirmed, open problems and unfinished lines carried over,
    /// weather blank.
    public static func nextDay(from previous: Daily?, date: Date, settings: Settings) -> Daily {
        var d = Daily(date: date)
        if let p = previous {
            d.workStart = p.workStart; d.workEnd = p.workEnd
            d.crew = p.crew; d.tools = p.tools
            d.problems = p.problems.filter { !$0.closed }
            d.progress = p.progress.filter { $0.percent < 100 }
        } else {
            d.crew = settings.roles.map { Count(name: $0, count: 0) }
            d.tools = settings.tools.map { Count(name: $0, count: 0) }
        }
        d.crewConfirmed = false
        return d
    }

    /// A day the station works: one of its weekdays, not one of its own days off, not a public holiday (`PublicHolidays`).
    public static func isWorkingDay(_ date: Date, settings: Settings) -> Bool {
        let key = dayKey(date)
        return settings.workingWeekdays.contains(calendar.component(.weekday, from: date))
            && !settings.holidays.contains(key) && !PublicHolidays.days.contains(key)
    }

    /// Working days from `from` to `to` (both included) with no report.
    public static func missingDays(reported: [Date], settings: Settings, from: Date, to: Date) -> [Date] {
        let have = Set(reported.map(dayKey))
        var out: [Date] = [], d = day(from)
        let end = day(to)
        while d <= end {
            if isWorkingDay(d, settings: settings), !have.contains(dayKey(d)) { out.append(d) }
            d = add(d, 1)
        }
        return out
    }

    /// Working days from `from` to `to`, both included.
    public static func workingDays(settings: Settings, from: Date, to: Date) -> [Date] {
        var out: [Date] = [], d = day(from)
        while d <= day(to) {
            if isWorkingDay(d, settings: settings) { out.append(d) }
            d = add(d, 1)
        }
        return out
    }

    /// Man-days per role over the reports, in first-seen order.
    public static func manDays(_ reports: [Daily]) -> [(name: String, days: Int)] { sum(reports.map(\.crew)) }
    public static func toolDays(_ reports: [Daily]) -> [(name: String, days: Int)] { sum(reports.map(\.tools)) }

    static func sum(_ lists: [[Count]]) -> [(name: String, days: Int)] {
        var order: [String] = [], total: [String: Int] = [:]
        for c in lists.joined() where c.count > 0 {
            if total[c.name] == nil { order.append(c.name) }
            total[c.name, default: 0] += c.count
        }
        return order.compactMap { k in total[k].map { (k, $0) } }
    }

    public static func rainHours(_ reports: [Daily]) -> Int { reports.reduce(0) { $0 + $1.rainHours } }
    public static func rainDays(_ reports: [Daily]) -> Int { reports.filter { $0.rainHours > 0 }.count }

    /// A task's % through `date`: the mean over its locations of each location's latest %; a location not yet reported
    /// counts 0. Nil when the task has never been reported.
    public static func taskPercent(_ task: MasterSchedule.Task, reports: [Daily], through date: Date, settings: Settings) -> Double? {
        let upto = reports.filter { day($0.date) <= day(date) }.sorted { $0.date < $1.date }
        var latest: [String: Double] = [:], order: [String] = []
        for r in upto {
            for l in r.progress where l.task == task {
                if latest[l.location] == nil { order.append(l.location) }
                latest[l.location] = l.percent
            }
        }
        guard !latest.isEmpty else { return nil }
        let places = settings.taskLocations[task.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? order
        guard !places.isEmpty else { return nil }
        return places.reduce(0) { $0 + min(max(latest[$1] ?? 0, 0), 100) } / Double(places.count)
    }

    /// Books every task the reports link into the MP actual: for each week with a report, the task's % at the week's last
    /// report. The weeks with reports are rebuilt from scratch, so an edited old report corrects the plan too.
    ///
    /// Only `counted` reports give the % (the ones the team's engineer has signed; nil counts them all). The others still
    /// clear their weeks, so a report whose signature was taken off no longer books what it said.
    public static func feed(_ actual: inout MasterSchedule.Actual, reports: [Daily], counted: [Daily]? = nil,
                            settings: Settings, over200kVA: Bool) {
        feed(&actual, reports: reports, counted: counted, settings: settings, weight: { $0.weight(over200kVA: over200kVA) })
    }

    /// `feed` against the plan's own weights (`MasterSchedule.Input.weight`).
    public static func feed(_ actual: inout MasterSchedule.Actual, reports: [Daily], counted: [Daily]? = nil,
                            settings: Settings, weight: (MasterSchedule.Task) -> Double) {
        let counted = counted ?? reports
        let tasks = Set(reports.flatMap { $0.progress.compactMap(\.task) })
        guard !tasks.isEmpty else { return }
        let weeks = Array(Set(reports.map { MasterSchedule.weekStart($0.date) })).sorted()
        for task in MasterSchedule.Task.allCases where tasks.contains(task) {
            for w in weeks { actual.set(0, task: task, week: w, weight: weight(task)) }
            for w in weeks {
                let last = reports.filter { MasterSchedule.weekStart($0.date) == w }.map(\.date).max() ?? w
                guard let pct = taskPercent(task, reports: counted, through: last, settings: settings) else { continue }
                actual.setPercent(pct, task: task, week: w, weight: weight(task))
            }
        }
    }

    /// R1's draft for the week of `weekStart`: the MP tasks planned that week and not yet 100 %, plus the latest crew
    /// and tools.
    public static func requestDraft(weekStart: Date, plan: [MasterSchedule.PlannedTask]?, actual: MasterSchedule.Actual,
                                    latest: Daily?, settings: Settings) -> WeeklyRequest {
        var r = WeeklyRequest(weekStart: weekStart)
        let ws = r.weekStart, we = add(ws, 6)
        if let plan {
            let first = WeeklyRequest.workingDays(settings).first ?? 0
            for p in plan where p.weight > 0 {
                guard let s = p.start, let e = p.end else { continue }
                if s <= we, e >= ws {
                    if actual.done(p.task, through: we) >= p.weight - 1e-9 { continue }
                    r.work.append(PlanLine(task: p.task, description: p.task.title, days: r.days(from: s, to: e, settings: settings)))
                } else if e < ws, e >= add(ws, -7), p.task.part != .permit, actual.done(p.task, through: ws) < p.weight - 1e-9 {
                    // behind the plan: it should have ended this week, so it carries over from the first working day
                    r.work.append(PlanLine(task: p.task, description: p.task.title, days: [first]))
                }
            }
        }
        r.crew = latest?.crew ?? settings.roles.map { Count(name: $0, count: 0) }
        r.tools = latest?.tools ?? settings.tools.map { Count(name: $0, count: 0) }
        return r
    }

    public enum Warning: Hashable, Sendable {
        case weatherBlank(Int), noCrew, crewUnconfirmed, wentDown(String), noProgress

        public var text: String {
            switch self {
            case let .weatherBlank(n): "ยังไม่กรอกสภาพอากาศ \(n) ชั่วโมง"
            case .noCrew: "ยังไม่มีกำลังคน"
            case .crewUnconfirmed: "ยังไม่ยืนยันกำลังคนวันนี้ (ใช้ค่าเมื่อวาน)"
            case let .wentDown(t): "ความก้าวหน้าลดลง: " + t
            case .noProgress: "ไม่มีความก้าวหน้าและไม่ได้ระบุเหตุหยุดงาน"
            }
        }
    }

    /// What to check before signing R2.
    public static func warnings(_ d: Daily, previous: [Daily]) -> [Warning] {
        var w: [Warning] = []
        if d.blankWeatherHours > 0 { w.append(.weatherBlank(d.blankWeatherHours)) }
        if d.crewTotal == 0 { w.append(.noCrew) } else if !d.crewConfirmed { w.append(.crewUnconfirmed) }
        for l in d.progress where todayDelta(l, on: d.date, in: previous) < -1e-9 { w.append(.wentDown(l.title)) }
        if d.progress.isEmpty, d.stopReason.trimmingCharacters(in: .whitespaces).isEmpty { w.append(.noProgress) }
        return w
    }

    // MARK: Permits (R4 §4.5)

    public enum PermitState: Equatable, Sendable {
        case done, inProgress, late, notStarted, notDue, unplanned

        public var title: String {
            switch self {
            case .done: "เสร็จแล้ว"
            case .inProgress: "กำลังดำเนินการ"
            case .late: "เลยกำหนด"
            case .notStarted: "ยังไม่เริ่ม"
            case .notDue: "ยังไม่ถึงกำหนด"
            case .unplanned: "ไม่มีกำหนด"
            }
        }
    }

    public struct PermitRow: Equatable, Sendable {
        public let task: MasterSchedule.Task
        public let start: Date?
        public let end: Date?
        /// Done, 0…100 of the task's weight.
        public let percent: Double
        public let state: PermitState
    }

    /// The permit part of the MP plan (อ.1, พค.2, COP, ขนานไฟ …) as of `date`; พค.2 is left out when the station
    /// doesn't need it. A task with no weight (COP) can only show its dates.
    public static func permits(plan: [MasterSchedule.PlannedTask], actual: MasterSchedule.Actual, at date: Date) -> [PermitRow] {
        let d = day(date)
        return plan.filter { $0.task.part == .permit && ($0.weight > 0 || $0.task == .cop) }.map { p in
            let pct = p.weight > 0 ? min(100, actual.done(p.task, through: d) / p.weight * 100) : 0
            let state: PermitState
            if pct >= 99.95 { state = .done }
            else if let s = p.start, let e = p.end {
                state = pct > 0 ? (day(e) < d ? .late : .inProgress) : day(e) < d ? .late : day(s) > d ? .notDue : .notStarted
            } else { state = pct > 0 ? .inProgress : .unplanned }
            return PermitRow(task: p.task, start: p.start, end: p.end, percent: pct, state: state)
        }
    }

    // MARK: Periods

    /// The week of `date`, Sunday to Saturday.
    public static func week(of date: Date) -> ClosedRange<Date> {
        let s = MasterSchedule.weekStart(date)
        return s...add(s, 6)
    }

    public static func month(of date: Date) -> ClosedRange<Date> {
        guard let i = calendar.dateInterval(of: .month, for: date) else {
            let d = day(date)
            return d...d
        }
        return day(i.start)...add(day(i.end), -1)
    }

    public static func reports(_ all: [Daily], in range: ClosedRange<Date>) -> [Daily] {
        all.filter { range.contains(day($0.date)) }.sorted { $0.date < $1.date }
    }

    /// Lines that moved forward on their day ("วันนี้" > 0), with the delta.
    public static func workDone(_ d: Daily, in all: [Daily]) -> [(line: ProgressLine, delta: Double)] {
        d.progress.compactMap { l in
            let delta = todayDelta(l, on: d.date, in: all)
            return delta > 1e-9 ? (l, delta) : nil
        }
    }

    /// Problems raised or still open in the range, and the ones closed in it.
    public static func problems(_ reports: [Daily]) -> (open: [Problem], closed: [Problem]) {
        var latest: [UUID: Problem] = [:], order: [UUID] = []
        for r in reports.sorted(by: { $0.date < $1.date }) {
            for p in r.problems where !p.description.isEmpty {
                if latest[p.id] == nil { order.append(p.id) }
                latest[p.id] = p
            }
        }
        let all = order.compactMap { latest[$0] }
        return (all.filter { !$0.closed }, all.filter(\.closed))
    }

    // MARK: Formatting

    public static func dayKey(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static let thaiMonths = ["มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
                                    "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"]
    public static let thaiMonthsShort = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."]

    /// "1 ก.ค. 2568".
    public static func thaiDate(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.day ?? 0) \(thaiMonthsShort[(c.month ?? 1) - 1]) \((c.year ?? 0) + 543)"
    }

    /// "กรกฎาคม 2568".
    public static func thaiMonth(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: d)
        return "\(thaiMonths[(c.month ?? 1) - 1]) \((c.year ?? 0) + 543)"
    }

    /// "40%", "12.5%".
    public static func percent(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        return (r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) + "%"
    }

    public enum Kind: Int, CaseIterable, Sendable {
        case request = 1, daily, weekly, monthly

        public var title: String {
            switch self {
            case .request: "คำขอปฏิบัติงานรายสัปดาห์"
            case .daily: "รายงานประจำวัน"
            case .weekly: "รายงานประจำสัปดาห์"
            case .monthly: "รายงานผลความก้าวหน้าประจำเดือน"
            }
        }
    }

    /// `2568-07-01 รายงานประจำวัน <สถานี>.pdf`: the Buddhist-era date of the report (week start for R1 / R3, month for R4).
    public static func fileName(_ kind: Kind, date: Date, station: String) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = (c.year ?? 0) + 543
        let stamp = kind == .monthly ? String(format: "%04d-%02d", y, c.month ?? 0)
                                     : String(format: "%04d-%02d-%02d", y, c.month ?? 0, c.day ?? 0)
        let name = station.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return "\(stamp) \(kind.title)" + (safe.isEmpty ? "" : " " + safe) + ".pdf"
    }

    /// The Drive folder of a report kind, as in the cleaned station folder (§4.6): `2. รายงานประจำวัน/2568-07 กรกฎาคม`.
    public static func folder(_ kind: Kind, date: Date) -> [String] {
        let top = "\(kind.rawValue). \(kind.title)"
        guard kind == .daily else { return [top] }
        let c = calendar.dateComponents([.year, .month], from: date)
        return [top, String(format: "%04d-%02d ", (c.year ?? 0) + 543, c.month ?? 0) + thaiMonths[(c.month ?? 1) - 1]]
    }

    /// The daily photos' Drive folder: `5. ภาพถ่ายประจำวัน/2568-07 กรกฎาคม/2568-07-01`.
    public static func photoFolder(date: Date) -> [String] {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = (c.year ?? 0) + 543
        return ["5. ภาพถ่ายประจำวัน", String(format: "%04d-%02d ", y, c.month ?? 0) + thaiMonths[(c.month ?? 1) - 1],
                String(format: "%04d-%02d-%02d", y, c.month ?? 0, c.day ?? 0)]
    }

    /// `2568-07-01 03 หลังคา 1.jpg`: date, 1-based number, and the progress line's location or task when tagged.
    public static func photoName(date: Date, index: Int, line: ProgressLine?) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d-%02d-%02d %02d", (c.year ?? 0) + 543, c.month ?? 0, c.day ?? 0, index)
        let what = line.map { $0.location.isEmpty ? ($0.task?.code ?? $0.description) : $0.location } ?? ""
        let safe = what.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        return stamp + (safe.isEmpty ? "" : " " + safe) + ".jpg"
    }
}
