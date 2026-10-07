import Foundation

/// รายงานประจำ of a PWA station (docs/specs/routine-reports-swift.md): the daily report (R2) entered once a day on
/// site, the weekly request (R1) drafted from the MP plan, and the weekly (R3) and monthly (R4) reports assembled
/// from the daily ones. Dates follow `MasterSchedule.calendar` (Bangkok, weeks from Sunday).
public enum RoutineReport {
    public static var calendar: Calendar { MasterSchedule.calendar }

    // MARK: Values

    /// One weather slot: ท้องฟ้าโปร่ง / เมฆครึ้ม / ฝนตก, as the company template's F / C / R.
    public enum Weather: String, Codable, CaseIterable, Sendable {
        case fine = "F", cloudy = "C", rain = "R"

        public var title: String {
            switch self {
            case .fine: "ท้องฟ้าโปร่ง"
            case .cloudy: "เมฆครึ้ม"
            case .rain: "ฝนตก"
            }
        }

        /// Tap order of a slot: F → C → R → blank → F.
        public static func next(_ w: Weather?) -> Weather? {
            switch w {
            case nil: .fine
            case .fine?: .cloudy
            case .cloudy?: .rain
            case .rain?: nil
            }
        }
    }

    /// The 15 weather slots, 06:00 … 20:00.
    public static let weatherHours = Array(6...20)

    /// A crew role or a tool with how many were on site.
    public struct Count: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        public var name: String
        public var count: Int
        public init(name: String, count: Int) { self.name = name; self.count = count }
    }

    public struct Material: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        public var name = ""
        public var location = ""
        public var qty: Double = 0
        public var unit = ""
        public var remark = ""
        public init(name: String = "", location: String = "", qty: Double = 0, unit: String = "", remark: String = "") {
            self.name = name; self.location = location; self.qty = qty; self.unit = unit; self.remark = remark
        }
    }

    /// One work line: what, where, and the cumulative percent done (the sample files' "Today" column).
    public struct ProgressLine: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        /// The MP task it counts towards; nil = งานอื่น.
        public var task: MasterSchedule.Task?
        public var description = ""
        public var location = ""
        /// % สะสม, 0…100.
        public var percent: Double = 0

        public init(task: MasterSchedule.Task?, description: String, location: String, percent: Double = 0) {
            self.task = task; self.description = description; self.location = location; self.percent = percent
        }

        /// Line identity across days: task + description + location.
        public var key: String {
            [task?.rawValue ?? "-", description.trimmingCharacters(in: .whitespaces), location.trimmingCharacters(in: .whitespaces)]
                .joined(separator: "|")
        }

        /// "2.1 ติดตั้งโครงสร้าง… · หลังคา 1", or the description alone.
        public var title: String {
            let what = description.isEmpty ? (task?.title ?? "งานอื่น") : description
            return location.isEmpty ? what : what + " · " + location
        }
    }

    public struct Problem: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        public var description = ""
        public var solution = ""
        public var closed = false
        /// The day it was first reported; open problems carry to the next day with it.
        public var since: Date
        public init(description: String = "", solution: String = "", closed: Bool = false, since: Date) {
            self.description = description; self.solution = solution; self.closed = closed; self.since = since
        }
    }

    // MARK: Daily report (R2)

    public struct Daily: Codable, Equatable, Sendable {
        public var date: Date
        public var workStart = "08.00"
        public var workEnd = "18.00"
        /// One per `weatherHours`; nil = not filled.
        public var weather: [Weather?] = Array(repeating: nil, count: RoutineReport.weatherHours.count)
        public var crew: [Count] = []
        /// The engineer tapped ยืนยันกำลังคนวันนี้; false while the crew is still yesterday's copy.
        public var crewConfirmed = false
        public var tools: [Count] = []
        public var materials: [Material] = []
        public var progress: [ProgressLine] = []
        public var problems: [Problem] = []
        /// Why there is no progress today (หยุดงาน); answers the "no progress" warning.
        public var stopReason = ""

        public init(date: Date) { self.date = RoutineReport.calendar.startOfDay(for: date) }

        enum CodingKeys: String, CodingKey {
            case date, workStart, workEnd, weather, crew, crewConfirmed, tools, materials, progress, problems, stopReason
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try c.decode(Date.self, forKey: .date)
            workStart = try c.decodeIfPresent(String.self, forKey: .workStart) ?? "08.00"
            workEnd = try c.decodeIfPresent(String.self, forKey: .workEnd) ?? "18.00"
            var w = try c.decodeIfPresent([Weather?].self, forKey: .weather) ?? []
            w += Array(repeating: nil, count: max(0, RoutineReport.weatherHours.count - w.count))
            weather = Array(w.prefix(RoutineReport.weatherHours.count))
            crew = try c.decodeIfPresent([Count].self, forKey: .crew) ?? []
            crewConfirmed = try c.decodeIfPresent(Bool.self, forKey: .crewConfirmed) ?? false
            tools = try c.decodeIfPresent([Count].self, forKey: .tools) ?? []
            materials = try c.decodeIfPresent([Material].self, forKey: .materials) ?? []
            progress = try c.decodeIfPresent([ProgressLine].self, forKey: .progress) ?? []
            problems = try c.decodeIfPresent([Problem].self, forKey: .problems) ?? []
            stopReason = try c.decodeIfPresent(String.self, forKey: .stopReason) ?? ""
        }

        public var crewTotal: Int { crew.reduce(0) { $0 + $1.count } }
        public var rainHours: Int { weather.filter { $0 == .rain }.count }
        public var blankWeatherHours: Int { weather.filter { $0 == nil }.count }

        /// The readable text written into `InstallLog.details`, so the log list and search keep working.
        public var summary: String {
            var lines = progress.map { "\($0.title) \(RoutineReport.percent($0.percent))" }
            if progress.isEmpty, !stopReason.isEmpty { lines.append("หยุดงาน: " + stopReason) }
            lines += problems.filter { !$0.closed && !$0.description.isEmpty }.map { "ปัญหา: " + $0.description }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: Station settings (§2.3)

    public struct Settings: Codable, Equatable, Sendable {
        public var contractName = ""
        public var employer = "การไฟฟ้าส่วนภูมิภาค"
        public var contractor = "บริษัท ทีซี รีนิวอะเบิ้ล เอ็นเนอร์ยี่ จำกัด"
        /// หลังคา 1…n, ถังน้ำใส 1…n, ห้องอินเวอร์เตอร์ …
        public var locations: [String] = []
        /// `Calendar` weekdays (1 = Sunday); จ.–ส. by default.
        public var workingWeekdays: Set<Int> = [2, 3, 4, 5, 6, 7]
        /// `yyyy-MM-dd` (Bangkok).
        public var holidays: [String] = []
        public var siteEngineer = ""
        public var inspector = ""
        public var roles = RoutineReport.defaultRoles
        public var tools = RoutineReport.defaultTools
        /// Task raw value → the locations its % is averaged over. A task without an entry averages over the locations
        /// it has been reported at.
        public var taskLocations: [String: [String]] = [:]
        /// Location → its point on the key plan (the A2 site picture), as fractions [x, y] of the picture's width and height.
        public var keyPoints: [String: [Double]] = [:]

        public init() {}

        enum CodingKeys: String, CodingKey {
            case contractName, employer, contractor, locations, workingWeekdays, holidays, siteEngineer, inspector, roles, tools, taskLocations
            case keyPoints
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Settings()
            contractName = try c.decodeIfPresent(String.self, forKey: .contractName) ?? d.contractName
            employer = try c.decodeIfPresent(String.self, forKey: .employer) ?? d.employer
            contractor = try c.decodeIfPresent(String.self, forKey: .contractor) ?? d.contractor
            locations = try c.decodeIfPresent([String].self, forKey: .locations) ?? d.locations
            workingWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .workingWeekdays) ?? d.workingWeekdays
            holidays = try c.decodeIfPresent([String].self, forKey: .holidays) ?? d.holidays
            siteEngineer = try c.decodeIfPresent(String.self, forKey: .siteEngineer) ?? d.siteEngineer
            inspector = try c.decodeIfPresent(String.self, forKey: .inspector) ?? d.inspector
            roles = try c.decodeIfPresent([String].self, forKey: .roles) ?? d.roles
            tools = try c.decodeIfPresent([String].self, forKey: .tools) ?? d.tools
            taskLocations = try c.decodeIfPresent([String: [String]].self, forKey: .taskLocations) ?? d.taskLocations
            keyPoints = try c.decodeIfPresent([String: [Double]].self, forKey: .keyPoints) ?? d.keyPoints
        }

        /// The location's key-plan point as fractions, when placed.
        public func keyPoint(_ location: String) -> (x: Double, y: Double)? {
            guard let p = keyPoints[location], p.count == 2 else { return nil }
            return (p[0], p[1])
        }
    }

    public static let defaultRoles = ["ผู้ควบคุมงาน", "หัวหน้างาน", "ผู้ปฏิบัติงาน", "ช่างไฟฟ้า"]
    public static let defaultTools = ["สว่านไฟฟ้า", "เครื่องเจียร", "ตู้เชื่อม", "บันได"]
    /// The common risks offered on R1 (§4.3).
    public static let commonRisks = ["งานบนที่สูง", "ฝนตก", "งานไฟฟ้ามีแรงดัน", "ยกของหนัก"]

    // MARK: Weekly request (R1)

    public enum RiskLevel: String, Codable, CaseIterable, Sendable {
        case low, medium, high
        public var title: String {
            switch self {
            case .low: "ต่ำ"
            case .medium: "กลาง"
            case .high: "สูง"
            }
        }
    }

    public struct Risk: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        public var description = ""
        public var level = RiskLevel.medium
        public var prevention = ""
        public init(description: String = "", level: RiskLevel = .medium, prevention: String = "") {
            self.description = description; self.level = level; self.prevention = prevention
        }
    }

    public struct PlanLine: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        public var task: MasterSchedule.Task?
        public var description = ""
        public var location = ""
        public var qty: Double = 0
        public var unit = ""
        public init(task: MasterSchedule.Task?, description: String, location: String = "", qty: Double = 0, unit: String = "") {
            self.task = task; self.description = description; self.location = location; self.qty = qty; self.unit = unit
        }
    }

    public struct WeeklyRequest: Codable, Equatable, Identifiable, Sendable {
        /// The Sunday the week starts, as in the MP plan.
        public var weekStart: Date
        public var crew: [Count] = []
        public var tools: [Count] = []
        public var work: [PlanLine] = []
        public var risks: [Risk] = []
        public var engineerSignedAt: Date?
        public var approvedAt: Date?
        public var approvedBy = ""

        public var id: String { MasterSchedule.Actual.key(weekStart) }
        public init(weekStart: Date) { self.weekStart = MasterSchedule.weekStart(weekStart) }

        enum CodingKeys: String, CodingKey { case weekStart, crew, tools, work, risks, engineerSignedAt, approvedAt, approvedBy }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            weekStart = try c.decode(Date.self, forKey: .weekStart)
            crew = try c.decodeIfPresent([Count].self, forKey: .crew) ?? []
            tools = try c.decodeIfPresent([Count].self, forKey: .tools) ?? []
            work = try c.decodeIfPresent([PlanLine].self, forKey: .work) ?? []
            risks = try c.decodeIfPresent([Risk].self, forKey: .risks) ?? []
            engineerSignedAt = try c.decodeIfPresent(Date.self, forKey: .engineerSignedAt)
            approvedAt = try c.decodeIfPresent(Date.self, forKey: .approvedAt)
            approvedBy = try c.decodeIfPresent(String.self, forKey: .approvedBy) ?? ""
        }

        public enum Status: Sendable { case draft, sent, approved }
        public var status: Status { approvedAt != nil ? .approved : engineerSignedAt != nil ? .sent : .draft }
    }

    // MARK: Rules (§3)

    static func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }
    static func add(_ d: Date, _ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: d)! }

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

    public static func isWorkingDay(_ date: Date, settings: Settings) -> Bool {
        settings.workingWeekdays.contains(calendar.component(.weekday, from: date))
            && !settings.holidays.contains(dayKey(date))
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
        return order.map { ($0, total[$0]!) }
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
    public static func feed(_ actual: inout MasterSchedule.Actual, reports: [Daily], settings: Settings, over200kVA: Bool) {
        let tasks = Set(reports.flatMap { $0.progress.compactMap(\.task) })
        guard !tasks.isEmpty else { return }
        let weeks = Array(Set(reports.map { MasterSchedule.weekStart($0.date) })).sorted()
        for task in MasterSchedule.Task.allCases where tasks.contains(task) {
            for w in weeks { actual.set(0, task: task, week: w, over200kVA: over200kVA) }
            for w in weeks {
                let last = reports.filter { MasterSchedule.weekStart($0.date) == w }.map(\.date).max() ?? w
                guard let pct = taskPercent(task, reports: reports, through: last, settings: settings) else { continue }
                actual.setPercent(pct, task: task, week: w, over200kVA: over200kVA)
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
            for p in plan where p.weight > 0 {
                guard let s = p.start, let e = p.end, s <= we, e >= ws else { continue }
                if actual.done(p.task, through: we) >= p.weight - 1e-9 { continue }
                r.work.append(PlanLine(task: p.task, description: p.task.title))
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
        let i = calendar.dateInterval(of: .month, for: date)!
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
