import Foundation

/// The iPhone PWA `แผนงาน` page (docs/ui/pwa-plan-iphone): the day agenda of PWA work, the project S-curve with a
/// Gantt row per station, and the deadlines of the next two weeks. Everything is worked out from the stations' MP
/// plans (`MasterSchedule`), their survey appointments and their papers (`StationDocs`); the app turns its jobs
/// into `Station`s.
public enum PWAPlan {

    /// Gregorian, Bangkok time, weeks Monday to Sunday numbered as ISO 8601 (the week strip's `สัปดาห์ที่ 42`).
    /// The MP plan itself keeps its Sunday weeks (`MasterSchedule.calendar`).
    public static let calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        return c
    }()

    // MARK: Station

    /// One PWA job as the page needs it.
    public struct Station: Identifiable, Sendable {
        public var id: String
        public var mpNumber: Int?
        /// The job code, shown where a station has no MP number.
        public var code: String
        public var name: String
        public var kWp: Double
        /// The contractor's short name (`A`); empty when no record keeps one.
        public var contractor: String
        /// Our own team (`TCR01`); empty when none.
        public var team: String
        public var input: MasterSchedule.Input?
        public var actual: MasterSchedule.Actual
        public var handedOver: Bool
        public var reportSentToday: Bool
        public var surveyAt: Date?
        /// The PWA representative's inspection appointments.
        public var inspections: [RoutineReport.Inspection]
        /// `Calendar` weekdays the site works (1 = Sunday).
        public var workingWeekdays: Set<Int>
        /// The site's working hours as minutes after midnight, the time of an install row; nil shows `ทั้งวัน`.
        public var workStart: Int?
        public var workEnd: Int?
        public var docs: StationDocs.Station
        public var docsContext: StationDocs.Context
        /// `yyyy-MM-dd` days the site doesn't work, left out of the ERC flow's working-day limits.
        public var holidays: Set<String>

        public init(id: String, mpNumber: Int? = nil, code: String = "", name: String, kWp: Double = 0, contractor: String = "",
                    team: String = "", input: MasterSchedule.Input? = nil, actual: MasterSchedule.Actual = .init(),
                    handedOver: Bool = false, reportSentToday: Bool = true, surveyAt: Date? = nil,
                    inspections: [RoutineReport.Inspection] = [],
                    workingWeekdays: Set<Int> = [2, 3, 4, 5, 6, 7], workStart: Int? = nil, workEnd: Int? = nil,
                    docs: StationDocs.Station = .init(),
                    docsContext: StationDocs.Context? = nil, holidays: Set<String> = []) {
            self.id = id; self.mpNumber = mpNumber; self.code = code; self.name = name; self.kWp = kWp
            self.contractor = contractor; self.team = team; self.input = input; self.actual = actual
            self.handedOver = handedOver; self.reportSentToday = reportSentToday; self.surveyAt = surveyAt
            self.inspections = inspections; self.workingWeekdays = workingWeekdays; self.docs = docs
            self.workStart = workStart; self.workEnd = workEnd; self.holidays = holidays
            self.docsContext = docsContext ?? StationDocs.Context(docs, inverterKW: input?.over200kVA == true ? 200 : nil)
        }

        /// `MP 189`, or the job code.
        public var ref: String { mpNumber.map { "MP \($0)" } ?? code }
        public var shortName: String { PWAPlan.shortName(name) }
    }

    /// `สถานีผลิตน้ำทุ่งน้อย | สาขาเมืองพล` → `ทุ่งน้อย`, for the narrow columns.
    public static func shortName(_ name: String) -> String {
        var s = name.components(separatedBy: " | ").first ?? name
        for prefix in ["สถานีผลิตน้ำ", "สถานีจ่ายน้ำ", "สถานีสูบน้ำ", "การประปา", "สถานี"] where s.hasPrefix(prefix) && s.count > prefix.count {
            s.removeFirst(prefix.count)
            break
        }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? name : s
    }

    /// `ทุ่งน้อย | ผู้รับเหมา A | TCR01`, leaving out what the station has none of.
    static func who(_ s: Station) -> String {
        [s.shortName, s.contractor.isEmpty ? "" : contractorTitle(s.contractor), s.team].filter { !$0.isEmpty }.joined(separator: " | ")
    }

    public static func contractorTitle(_ contractor: String) -> String { "ผู้รับเหมา " + contractor }

    // MARK: Agenda

    public enum JobType: String, CaseIterable, Sendable {
        case install, survey, inspection, document, test, notice

        public var title: String {
            switch self {
            case .install: "ติดตั้ง"
            case .survey: "สำรวจ"
            case .inspection: "ตรวจรับ"
            case .document: "เอกสาร"
            case .test: "ทดสอบ"
            case .notice: "เตือน"
            }
        }
    }

    public enum AgendaStatus: String, Sendable {
        case doing, booked, onPlan, waiting, mustSubmit, alert

        public var title: String {
            switch self {
            case .doing: "กำลังทำ"
            case .booked: "นัดแล้ว"
            case .onPlan: "ตามแผน"
            case .waiting: "รอ"
            case .mustSubmit: "ต้องยื่น"
            case .alert: "เตือน"
            }
        }
    }

    /// The screen a row opens.
    public enum Target: String, Sendable { case station, schedule, docs, survey, dailies }

    public struct AgendaItem: Identifiable, Equatable, Sendable {
        public var id: String
        public var day: Date
        /// Minutes from midnight; nil for work with no set time.
        public var start: Int?
        public var end: Int?
        public var type: JobType
        public var ref: String
        public var title: String
        public var subtitle: String
        public var status: AgendaStatus
        public var contractor: String
        public var team: String
        /// `Station.id`.
        public var station: String
        public var opens: Target

        public init(id: String, day: Date, start: Int? = nil, end: Int? = nil, type: JobType, ref: String, title: String,
                    subtitle: String, status: AgendaStatus, contractor: String = "", team: String = "", station: String = "",
                    opens: Target = .station) {
            self.id = id; self.day = day; self.start = start; self.end = end; self.type = type; self.ref = ref
            self.title = title; self.subtitle = subtitle; self.status = status; self.contractor = contractor
            self.team = team; self.station = station; self.opens = opens
        }

        public func matches(search: String) -> Bool { PWAPlan.matches([ref, title, subtitle], search) }
    }

    /// The team filter's key for our own teams.
    public static let ownTeams = "TC"

    /// The team filter's choices: each contractor in the list, then `TC` when any row has one of our teams.
    public static func teamKeys(_ items: [AgendaItem]) -> [String] {
        Set(items.map(\.contractor).filter { !$0.isEmpty }).sorted() + (items.contains { !$0.team.isEmpty } ? [ownTeams] : [])
    }

    /// A row passes a team key by its contractor, and `TC` by having one of our teams. Nil passes every row.
    public static func matches(_ item: AgendaItem, team key: String?) -> Bool {
        guard let key else { return true }
        return item.contractor == key || (key == ownTeams && !item.team.isEmpty)
    }

    static func matches(_ fields: [String], _ search: String) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// `08:00` from minutes after midnight.
    public static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    /// When the reminder to send the daily report sits in today's agenda.
    public static let reportReminder = 16 * 60

    /// The agenda of `days`: per station one install row on each working day a construction task (2.x) is planned, a
    /// test row on the days of 3.1, the survey appointment, the PWA representative's inspection appointments, the
    /// document deadlines falling on the day, and today one
    /// reminder naming the stations whose daily report isn't sent. Rows with a time come after the day's untimed ones.
    public static func agenda(_ stations: [Station], deadlines: [Deadline], days: [Date], today: Date,
                              threshold: Double = InstallOverview.defaultThreshold, calendar cal: Calendar = calendar) -> [AgendaItem] {
        let mp = MasterSchedule.calendar
        let today = cal.startOfDay(for: today)
        var out: [AgendaItem] = []
        // a month of days asks for each station's plan 31 times
        let planned = stations.map { s -> (plan: [MasterSchedule.PlannedTask], status: MasterSchedule.Status)? in
            guard let input = s.input, !s.handedOver else { return nil }
            let plan = MasterSchedule.plan(input, calendar: mp)
            return (plan, MasterSchedule.status(plan: plan, actual: s.actual, through: today, calendar: mp))
        }
        for d in days.map({ cal.startOfDay(for: $0) }) {
            let key = dayKey(d, cal), isToday = d == today
            let works = { (s: Station) in s.workingWeekdays.contains(cal.component(.weekday, from: d)) }
            for (s, planned) in zip(stations, planned) {
                if let at = s.surveyAt, cal.isDate(at, inSameDayAs: d) {
                    let c = cal.dateComponents([.hour, .minute], from: at)
                    out.append(AgendaItem(id: "srv-\(s.id)-\(key)", day: d, start: (c.hour ?? 0) * 60 + (c.minute ?? 0), type: .survey,
                                          ref: s.ref, title: "นัดสำรวจ " + s.name, subtitle: [s.shortName, s.team].filter { !$0.isEmpty }.joined(separator: " | "),
                                          status: .booked, contractor: s.contractor, team: s.team, station: s.id, opens: .survey))
                }
                for i in s.inspections where cal.isDate(i.at, inSameDayAs: d) {
                    let c = cal.dateComponents([.hour, .minute], from: i.at)
                    let subject = i.subject.trimmingCharacters(in: .whitespaces)
                    out.append(AgendaItem(id: "chk-\(s.id)-\(i.id)", day: d, start: (c.hour ?? 0) * 60 + (c.minute ?? 0), type: .inspection,
                                          ref: s.ref, title: subject.isEmpty ? "ผู้แทน กปภ. ตรวจรับ" : "ผู้แทน กปภ. ตรวจ " + subject, subtitle: who(s),
                                          status: .waiting, contractor: s.contractor, team: s.team, station: s.id, opens: .station))
                }
                guard let (plan, status) = planned, works(s) else { continue }
                let on = plan.filter { p in
                    guard p.weight > 0, let a = p.start, let b = p.end else { return false }
                    return mp.startOfDay(for: a) <= d && d <= mp.startOfDay(for: b)
                }
                let building = on.filter { $0.task.part == .construction }
                if let task = building.first(where: { (status.actualByTask[$0.task] ?? 0) < 99.95 }) ?? building.first {
                    let late = -status.variance >= threshold ? "ช้ากว่าแผน \(Int((-status.variance).rounded()))%" : ""
                    out.append(AgendaItem(id: "ins-\(s.id)-\(key)", day: d, start: s.workStart, end: s.workEnd, type: .install, ref: s.ref,
                                          title: "\(task.task.code) \(task.task.title)", subtitle: [who(s), late].filter { !$0.isEmpty }.joined(separator: " | "),
                                          status: isToday ? .doing : .onPlan, contractor: s.contractor, team: s.team, station: s.id, opens: .station))
                }
                if on.contains(where: { $0.task == .preCommissioning }) {
                    out.append(AgendaItem(id: "tst-\(s.id)-\(key)", day: d, type: .test, ref: s.ref, title: "3.1 Pre-Commissioning (IEC 62446)",
                                          subtitle: who(s), status: isToday ? .doing : .onPlan, contractor: s.contractor, team: s.team,
                                          station: s.id, opens: .station))
                }
            }
            for due in deadlines where due.kind == .document && cal.isDate(due.date, inSameDayAs: d) {
                let s = stations.first { $0.id == due.station }
                out.append(AgendaItem(id: "doc-\(due.id)", day: d, type: .document, ref: s?.ref ?? "", title: due.title,
                                      subtitle: [s?.shortName ?? "", isToday ? "ครบกำหนดวันนี้" : due.chip].filter { !$0.isEmpty }.joined(separator: " | "),
                                      status: .mustSubmit, contractor: s?.contractor ?? "", team: s?.team ?? "", station: due.station, opens: .docs))
            }
            if isToday {
                let missing = stations.filter { s in
                    guard let input = s.input, !s.handedOver, !s.reportSentToday, works(s) else { return false }
                    return mp.startOfDay(for: input.installStart) <= d && d <= mp.startOfDay(for: input.installEnd)
                }
                if let first = missing.first {
                    out.append(AgendaItem(id: "ntf-\(key)", day: d, start: reportReminder, type: .notice, ref: "รายงาน",
                                          title: "ส่งรายงานประจำวันก่อน 18:00",
                                          subtitle: "ยังไม่ส่ง \(missing.count) สถานี | " + missing.map(\.shortName).joined(separator: " "),
                                          status: .alert, station: first.id, opens: .dailies))
                }
            }
        }
        return sorted(out)
    }

    // MARK: Next items (the main home's `แผนงานถัดไป`)

    /// The job types the iPhone home's `แผนงานถัดไป` card shows.
    public static let nextTypes: Set<JobType> = [.install, .test, .document]

    /// The nearest rows of `types` still ahead of `now`, one per station and type, nearest first, at most `limit`.
    /// A row's moment is its day at its start time; one with no time counts from the next day on.
    public static func next(_ items: [AgendaItem], after now: Date, types: Set<JobType> = nextTypes, limit: Int = 3,
                            calendar cal: Calendar = calendar) -> [AgendaItem] {
        var seen: Set<String> = []
        let ahead = items.filter { types.contains($0.type) && moment($0, calendar: cal) > now }
        return Array(sorted(ahead).filter { seen.insert($0.station + "/" + $0.type.rawValue).inserted }.prefix(limit))
    }

    static func moment(_ item: AgendaItem, calendar cal: Calendar = calendar) -> Date {
        cal.date(byAdding: .minute, value: item.start ?? 0, to: item.day) ?? item.day
    }

    /// `วันนี้`, `พรุ่งนี้` or `อีก 2 วัน`: how far `day` is from `today`.
    public static func ahead(_ day: Date, from today: Date, calendar cal: Calendar = calendar) -> String {
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: day)).day ?? 0
        return n <= 0 ? "วันนี้" : n == 1 ? "พรุ่งนี้" : "อีก \(n) วัน"
    }

    /// By day, then the untimed rows in type order, then by start time.
    public static func sorted(_ items: [AgendaItem]) -> [AgendaItem] {
        let order = Dictionary(uniqueKeysWithValues: JobType.allCases.enumerated().map { ($1, $0) })
        return items.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            if x.day != y.day { return x.day < y.day }
            if (x.start ?? -1) != (y.start ?? -1) { return (x.start ?? -1) < (y.start ?? -1) }
            if x.type != y.type { return (order[x.type] ?? 0) < (order[y.type] ?? 0) }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func dayKey(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Calendar

    /// The seven days of the week that starts on `monday`.
    public static func week(from monday: Date, calendar cal: Calendar = calendar) -> [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: monday)) }
    }

    /// The month of `date` as Monday-first rows of seven; nil is a blank cell before the 1st or after the last day.
    public static func monthRows(containing date: Date, calendar cal: Calendar = calendar) -> [[Date?]] {
        guard let month = cal.dateInterval(of: .month, for: date), let count = cal.range(of: .day, in: .month, for: date)?.count else { return [] }
        let blanks = (cal.component(.weekday, from: month.start) + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: blanks) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: month.start) }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0 ..< $0 + 7]) }
    }

    /// The job types of each day that has rows.
    public static func types(_ items: [AgendaItem]) -> [Date: Set<JobType>] {
        items.reduce(into: [:]) { $0[$1.day, default: []].insert($1.type) }
    }

    /// One colour bar of a calendar row: a job type over the cells `from...to`.
    public struct BarRun: Equatable, Sendable {
        public var type: JobType
        /// 0 is `ติดตั้ง`; 1 and 2 hold the other types.
        public var lane: Int
        public var from: Int
        public var to: Int
    }

    /// Lanes under `ติดตั้ง` in a calendar cell.
    public static let otherLanes = 2

    /// The bars of one week row of the calendar. A type on consecutive days is one run, which the selected day
    /// breaks on both sides. `ติดตั้ง` has lane 0; the other runs take the first of lanes 1–2 that is free from
    /// their first day, earliest run first (then in the types' order), and a run with no free lane is left out.
    public static func barRuns(_ cells: [Date?], types: [Date: Set<JobType>], selected: Date? = nil) -> [BarRun] {
        var runs: [BarRun] = []
        for type in JobType.allCases {
            var open = false
            for (i, cell) in cells.enumerated() {
                guard let d = cell, types[d]?.contains(type) == true else { open = false; continue }
                if open, d != selected, cells[i - 1] != selected {
                    runs[runs.count - 1].to = i
                } else {
                    runs.append(BarRun(type: type, lane: 0, from: i, to: i))
                    open = true
                }
            }
        }
        var out = runs.filter { $0.type == .install }
        var laneEnd = Array(repeating: -1, count: otherLanes)
        let others = runs.enumerated().filter { $0.element.type != .install }
            .sorted { $0.element.from != $1.element.from ? $0.element.from < $1.element.from : $0.offset < $1.offset }
        for (_, run) in others {
            guard let lane = laneEnd.firstIndex(where: { $0 < run.from }) else { continue }
            laneEnd[lane] = run.to
            out.append(BarRun(type: run.type, lane: lane + 1, from: run.from, to: run.to))
        }
        return out
    }

    // MARK: S-curve

    /// Plan and actual of the whole project per MP week, each station weighted by its kWp.
    public struct Curve: Equatable, Sendable {
        /// The Sundays that start each week, first plan week to last.
        public var weeks: [Date]
        /// Cumulative percent planned by the end of each week.
        public var plan: [Double]
        /// Cumulative percent done, up to this week only.
        public var actual: [Double]
        /// This week's place in `weeks`; nil before the first week or after the last.
        public var todayIndex: Int?
        /// The header's figures: plan and actual to this week, as `MasterSchedule.status` gives them.
        public var planned: Double
        public var done: Double

        public init(weeks: [Date], plan: [Double], actual: [Double], todayIndex: Int?, planned: Double, done: Double) {
            self.weeks = weeks; self.plan = plan; self.actual = actual; self.todayIndex = todayIndex
            self.planned = planned; self.done = done
        }

        public static let empty = Curve(weeks: [], plan: [], actual: [], todayIndex: nil, planned: 0, done: 0)

        /// Weeks from the first to the last, for `สัปดาห์ 11/20`.
        public var totalWeeks: Int { max(weeks.count - 1, 0) }
        /// Rounded like the header: behind only when the whole percents differ.
        public var behindBy: Int { max(Int(planned.rounded()) - Int(done.rounded()), 0) }
    }

    /// The S-curve over the stations that have a plan: for each week from the earliest planned start to the latest
    /// planned end, Σ kWp × cumulative % ÷ Σ kWp (equal weights when no station has a kWp, as `MPOverviewView.totals`).
    public static func curve(_ stations: [Station], today: Date) -> Curve {
        let cal = MasterSchedule.calendar
        let planned = stations.compactMap { s in s.input.map { (s, MasterSchedule.plan($0, calendar: cal)) } }
        let dates = planned.flatMap { $0.1.filter { $0.weight > 0 }.flatMap { [$0.start, $0.end].compactMap { $0 } } }
        guard let first = dates.min(), let last = dates.max() else { return .empty }
        let weeks = MasterSchedule.weeks(from: first, to: last, calendar: cal)
        let kWp = planned.map { max($0.0.kWp, 0) }, sum = kWp.reduce(0, +)
        let weights = sum > 0 ? kWp.map { $0 / sum } : kWp.map { _ in 1 / Double(planned.count) }
        let points = planned.map { MasterSchedule.plannedPoints($0.1, calendar: cal) }
        let thisWeek = MasterSchedule.weekStart(today, calendar: cal)

        func plan(through week: Date) -> Double {
            zip(points, weights).reduce(0) { total, p in
                total + p.1 * p.0.values.reduce(0) { $0 + $1.filter { $0.key <= week }.values.reduce(0, +) }
            }
        }
        func actual(through week: Date) -> Double {
            zip(planned, weights).reduce(0) { total, p in
                total + p.1 * p.0.1.reduce(0) { $0 + p.0.0.actual.done($1.task, through: week, calendar: cal) }
            }
        }
        let todayIndex = weeks.firstIndex(of: thisWeek)
        let shown = thisWeek < weeks[0] ? [] : weeks.filter { $0 <= thisWeek }
        return Curve(weeks: weeks, plan: weeks.map(plan), actual: shown.map(actual), todayIndex: todayIndex,
                     planned: plan(through: thisWeek), done: actual(through: thisWeek))
    }

    // MARK: Gantt

    /// One station's row of `รายสถานี`: its install window, how far it is and where the plan stands.
    public struct Bar: Identifiable, Equatable, Sendable {
        public var id: String
        public var ref: String
        public var name: String
        public var fullName: String
        public var contractor: String
        public var team: String
        public var start: Date
        public var due: Date
        /// 0…100.
        public var actual: Double
        public var planned: Double
        public var behind: Bool

        public init(id: String, ref: String, name: String, fullName: String, contractor: String = "", team: String = "",
                    start: Date, due: Date, actual: Double, planned: Double, behind: Bool) {
            self.id = id; self.ref = ref; self.name = name; self.fullName = fullName; self.contractor = contractor
            self.team = team; self.start = start; self.due = due; self.actual = actual; self.planned = planned; self.behind = behind
        }

        public func matches(search: String) -> Bool { PWAPlan.matches([ref, fullName], search) }
    }

    /// The stations with a plan, by due date.
    public static func bars(_ stations: [Station], today: Date, threshold: Double = InstallOverview.defaultThreshold) -> [Bar] {
        let cal = MasterSchedule.calendar
        return stations.compactMap { s -> Bar? in
            guard let input = s.input else { return nil }
            let st = MasterSchedule.status(plan: MasterSchedule.plan(input, calendar: cal), actual: s.actual, through: today, calendar: cal)
            return Bar(id: s.id, ref: s.ref, name: s.shortName, fullName: s.name, contractor: s.contractor, team: s.team,
                       start: cal.startOfDay(for: input.installStart), due: cal.startOfDay(for: input.installEnd),
                       actual: st.actual, planned: st.planned, behind: -st.variance >= threshold)
        }
        .sorted { $0.due < $1.due }
    }

    // MARK: Deadlines

    public enum DeadlineKind: String, Sendable { case handover, document, other }
    public enum Tone: String, Sendable { case late, risk, ok }

    public struct Deadline: Identifiable, Equatable, Sendable {
        public var id: String
        public var date: Date
        public var kind: DeadlineKind
        public var title: String
        public var subtitle: String
        public var chip: String
        public var tone: Tone
        public var station: String
        public var opens: Target

        public init(id: String, date: Date, kind: DeadlineKind, title: String, subtitle: String, chip: String, tone: Tone,
                    station: String = "", opens: Target = .station) {
            self.id = id; self.date = date; self.kind = kind; self.title = title; self.subtitle = subtitle
            self.chip = chip; self.tone = tone; self.station = station; self.opens = opens
        }

        public func matches(search: String) -> Bool { PWAPlan.matches([title, subtitle], search) }
    }

    /// The three submissions the MP plan dates: the task whose planned start is the day to hand the papers in.
    static let submissions: [(task: MasterSchedule.Task, package: StationDocs.Package)] =
        [(.buildingPermit, .building), (.pk2, .pk2), (.gridConnection, .gridConnection)]

    /// The MP task that dates a package's submission; nil for a package the plan page has no deadline for.
    public static func submissionTask(_ package: StationDocs.Package) -> MasterSchedule.Task? {
        submissions.first { $0.package == package }?.task
    }

    static func submissionTitle(_ package: StationDocs.Package, _ ctx: StationDocs.Context) -> String {
        switch package {
        case .pk2: "ยื่น พค.2 (กกพ.)"
        case .gridConnection: "ยื่นขอขนานไฟ"
        default:
            switch ctx.buildingRoute {
            case .notify: "แจ้งเทศบาล (ยกเว้น ข.1)"
            case .permit: "ยื่นขออนุญาตดัดแปลงอาคาร (อ.1)"
            case .unknown: "ยื่นอาคาร (อ.1 / แจ้งเทศบาล)"
            }
        }
    }

    /// Every open deadline of the stations that have a plan and aren't handed over, by date:
    /// - handover on the plan's install end: late once past or when behind the plan by `threshold`, at risk when
    ///   under the plan at all;
    /// - the building, พค.2 and grid-connection submissions on the day the team set for the package, else on the
    ///   planned start of MP 1.4, 1.5 and 1.7, until the task is booked as done or every paper of the package is
    ///   submitted;
    /// - the O&M training on the planned start of MP 3.2, until it is booked as done;
    /// - each step of the station's ERC flow (under 200 kVA or 200 and over) that the utility or DEDE has, on the last day
    ///   of its time limit (`ERCFlow.waits`).
    public static func deadlines(_ stations: [Station], library: StationDocs.Library = .init(), today: Date,
                                 threshold: Double = InstallOverview.defaultThreshold) -> [Deadline] {
        let cal = MasterSchedule.calendar
        let today = cal.startOfDay(for: today)
        func daysLate(_ d: Date) -> Int { cal.dateComponents([.day], from: d, to: today).day ?? 0 }
        var out: [Deadline] = []
        for s in stations {
            guard let input = s.input, !s.handedOver else { continue }
            let plan = MasterSchedule.plan(input, calendar: cal)
            let st = MasterSchedule.status(plan: plan, actual: s.actual, through: today, calendar: cal)
            let label = s.ref + " " + s.shortName
            let figures = "จริง \(Int(st.actual.rounded()))% / แผน \(Int(st.planned.rounded()))%"

            let due = cal.startOfDay(for: input.installEnd)
            let (chip, tone): (String, Tone) =
                due < today ? ("เลยกำหนด \(daysLate(due)) วัน", .late)
                : -st.variance >= threshold ? ("ช้ากว่าแผน", .late)
                : st.variance < 0 ? ("เสี่ยงช้า", .risk) : ("ตามแผน", .ok)
            let party = [s.contractor.isEmpty ? "" : contractorTitle(s.contractor), s.team].first { !$0.isEmpty } ?? ""
            out.append(Deadline(id: "hand-\(s.id)", date: due, kind: .handover, title: "ส่งมอบงาน",
                                subtitle: [label, tone == .ok ? party : figures].filter { !$0.isEmpty }.joined(separator: " | "),
                                chip: chip, tone: tone, station: s.id, opens: .station))

            for sub in submissions where sub.package != .pk2 || s.docsContext.over200kVA {
                guard let start = s.docs.due(sub.package) ?? plan.first(where: { $0.task == sub.task })?.start,
                      (st.actualByTask[sub.task] ?? 0) < 99.95 else { continue }
                let states = StationDocs.papers(in: sub.package, s.docsContext)
                    .map { StationDocs.state($0, station: s.docs, library: library).status }.filter { $0 != .notNeeded }
                if !states.isEmpty && states.allSatisfy({ $0 == .submitted || $0 == .approved }) { continue }
                let ready = states.filter(\.isReady).count, date = cal.startOfDay(for: start)
                let (chip, tone): (String, Tone) =
                    date < today ? ("เลยกำหนด \(daysLate(date)) วัน", .late)
                    : !states.isEmpty && ready == states.count ? ("พร้อมยื่น", .ok)
                    : date == today ? ("วันนี้", .risk) : ("เอกสาร \(ready)/\(states.count)", .risk)
                out.append(Deadline(id: "doc-\(sub.package.rawValue)-\(s.id)", date: date, kind: .document,
                                    title: submissionTitle(sub.package, s.docsContext),
                                    subtitle: "\(label) | ชุด\(sub.package.title) \(ready)/\(states.count)",
                                    chip: chip, tone: tone, station: s.id, opens: .docs))
            }

            if let record = s.docs.erc {
                let ctx = ERCFlow.Context(holidays: s.holidays, variant: .init(over200kVA: s.docsContext.over200kVA))
                for wait in ERCFlow.waits(record, ctx, today: today) {
                    guard let date = ERCFlow.date(wait.due) else { continue }
                    out.append(Deadline(id: "erc-\(wait.step.rawValue)-\(s.id)", date: date, kind: .document, title: wait.title,
                                        subtitle: "\(label) | \(wait.step.party.title) | ลำดับ กกพ. ข้อ \(wait.number ?? 0)",
                                        chip: wait.text, tone: wait.left < 0 ? .late : wait.left <= 3 ? .risk : .ok,
                                        station: s.id, opens: .docs))
                }
            }

            if let start = plan.first(where: { $0.task == .training })?.start, (st.actualByTask[.training] ?? 0) < 99.95 {
                let date = cal.startOfDay(for: start)
                out.append(Deadline(id: "train-\(s.id)", date: date, kind: .other, title: "อบรม O&M (3.2)", subtitle: label,
                                    chip: date < today ? "เลยกำหนด \(daysLate(date)) วัน" : "ตามแผน", tone: date < today ? .late : .ok,
                                    station: s.id, opens: .station))
            }
        }
        return out.enumerated().sorted { $0.element.date != $1.element.date ? $0.element.date < $1.element.date : $0.offset < $1.offset }
            .map(\.element)
    }

    /// The page's two groups. `สัปดาห์นี้` is Monday to Sunday of this week plus everything overdue; `สัปดาห์หน้า` the
    /// seven days after. Later deadlines aren't shown.
    public struct DeadlineGroups: Equatable, Sendable {
        public var thisWeek: [Deadline]
        public var nextWeek: [Deadline]
        /// Monday of this week and of the next.
        public var thisStart: Date
        public var nextStart: Date

        public var all: [Deadline] { thisWeek + nextWeek }
        public var hasLate: Bool { all.contains { $0.tone == .late } }
    }

    public static func groups(_ deadlines: [Deadline], today: Date, calendar cal: Calendar = calendar) -> DeadlineGroups {
        let start = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? cal.startOfDay(for: today)
        let next = cal.date(byAdding: .day, value: 7, to: start) ?? start
        let after = cal.date(byAdding: .day, value: 14, to: start) ?? start
        return DeadlineGroups(thisWeek: deadlines.filter { $0.date < next }, nextWeek: deadlines.filter { $0.date >= next && $0.date < after },
                              thisStart: start, nextStart: next)
    }
}
