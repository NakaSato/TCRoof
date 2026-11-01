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

        /// "2.1 ติดตั้งโครงสร้าง… | หลังคา 1", or the description alone.
        public var title: String {
            let what = description.isEmpty ? (task?.title ?? "งานอื่น") : description
            return location.isEmpty ? what : what + " | " + location
        }
    }

    public struct Problem: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        public var description = ""
        public var solution = ""
        public var closed = false
        /// The day it was first reported; open problems carry to the next day with it.
        public var since: Date
        /// The progress line it was raised under (`ProgressLine.key`), on the iPad one-page report; nil for one raised
        /// elsewhere or before this field. The PDF's problem table doesn't use it.
        public var lineKey: String?
        public init(description: String = "", solution: String = "", closed: Bool = false, since: Date, lineKey: String? = nil) {
            self.description = description; self.solution = solution; self.closed = closed; self.since = since
            self.lineKey = lineKey
        }

        enum CodingKeys: String, CodingKey { case id, description, solution, closed, since, lineKey }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            solution = try c.decodeIfPresent(String.self, forKey: .solution) ?? ""
            closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
            since = try c.decode(Date.self, forKey: .since)
            lineKey = try c.decodeIfPresent(String.self, forKey: .lineKey)
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
        /// The module installation checklist of ZNSHINE's manual (`ModuleRules.InstallDailyCheck`, JSON), on days with
        /// module work; nil otherwise, so a report without one encodes as before (docs/specs/module-install-rules.md §7.3).
        public var moduleCheck: String?

        public init(date: Date) { self.date = RoutineReport.calendar.startOfDay(for: date) }

        enum CodingKeys: String, CodingKey {
            case date, workStart, workEnd, weather, crew, crewConfirmed, tools, materials, progress, problems, stopReason, moduleCheck
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
            moduleCheck = try c.decodeIfPresent(String.self, forKey: .moduleCheck)
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

    /// An appointment for the PWA's representative to inspect work at the station.
    public struct Inspection: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var at: Date
        /// What is inspected (`2.5 Inverter`); may be empty.
        public var subject: String

        public init(id: String = UUID().uuidString, at: Date, subject: String = "") {
            self.id = id; self.at = at; self.subject = subject
        }
    }

    public struct Settings: Codable, Equatable, Sendable {
        public var contractName = ""
        public var employer = "การไฟฟ้าส่วนภูมิภาค"
        public var contractor = "บริษัท ทีซี รีนิวอะเบิ้ล เอ็นเนอร์ยี่ จำกัด"
        /// The short name of the subcontractor that installs this station (`A`); empty when our own team does.
        /// The PWA plan page's team filter groups stations by it.
        public var subcontractor = ""
        /// The PWA representative's inspection appointments, shown as `ตรวจรับ` rows in the PWA plan page's agenda.
        public var inspections: [Inspection] = []
        /// หลังคา 1…n, ถังน้ำใส 1…n, ห้องอินเวอร์เตอร์ …
        public var locations: [String] = []
        /// `Calendar` weekdays (1 = Sunday); จ.–ส. by default.
        public var workingWeekdays: Set<Int> = [2, 3, 4, 5, 6, 7]
        /// `yyyy-MM-dd` (Bangkok).
        public var holidays: [String] = []
        /// The site's working hours, as minutes after midnight: 08:00–17:00 by default.
        public var workStart = 8 * 60
        public var workEnd = 17 * 60
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
            case keyPoints, subcontractor, inspections, workStart, workEnd
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
            subcontractor = try c.decodeIfPresent(String.self, forKey: .subcontractor) ?? d.subcontractor
            inspections = try c.decodeIfPresent([Inspection].self, forKey: .inspections) ?? d.inspections
            workStart = try c.decodeIfPresent(Int.self, forKey: .workStart) ?? d.workStart
            workEnd = try c.decodeIfPresent(Int.self, forKey: .workEnd) ?? d.workEnd
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
        /// The 5 × 5 assessment (1–5 each), when it was scored on the iPad page (`assess`); `level` follows the score so
        /// the PDF and older devices keep working. Nil for older risks.
        public var likelihood: Int?
        public var severity: Int?
        public init(description: String = "", level: RiskLevel = .medium, prevention: String = "") {
            self.description = description; self.level = level; self.prevention = prevention
        }

        enum CodingKeys: String, CodingKey { case id, description, level, prevention, likelihood, severity }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            level = try c.decodeIfPresent(RiskLevel.self, forKey: .level) ?? .medium
            prevention = try c.decodeIfPresent(String.self, forKey: .prevention) ?? ""
            likelihood = try c.decodeIfPresent(Int.self, forKey: .likelihood)
            severity = try c.decodeIfPresent(Int.self, forKey: .severity)
        }

        /// As before for an unscored risk: the scores are left out while unset.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(description, forKey: .description)
            try c.encode(level, forKey: .level); try c.encode(prevention, forKey: .prevention)
            try c.encodeIfPresent(likelihood, forKey: .likelihood); try c.encodeIfPresent(severity, forKey: .severity)
        }
    }

    public struct PlanLine: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        public var task: MasterSchedule.Task?
        public var description = ""
        public var location = ""
        public var qty: Double = 0
        public var unit = ""
        /// The days of the week it is asked for, 0 = Monday … 5 = Saturday (`WeeklyRequest.date(ofDay:)`); empty = no day
        /// yet. Older requests have none.
        public var days: [Int] = []
        public init(task: MasterSchedule.Task?, description: String, location: String = "", qty: Double = 0, unit: String = "",
                    days: [Int] = []) {
            self.task = task; self.description = description; self.location = location; self.qty = qty; self.unit = unit
            self.days = days
        }

        enum CodingKeys: String, CodingKey { case id, task, description, location, qty, unit, days }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            task = try c.decodeIfPresent(MasterSchedule.Task.self, forKey: .task)
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
            qty = try c.decodeIfPresent(Double.self, forKey: .qty) ?? 0
            unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
            days = try c.decodeIfPresent([Int].self, forKey: .days) ?? []
        }

        /// As before for a line with no day: `days` is left out while empty.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encodeIfPresent(task, forKey: .task)
            try c.encode(description, forKey: .description); try c.encode(location, forKey: .location)
            try c.encode(qty, forKey: .qty); try c.encode(unit, forKey: .unit)
            if !days.isEmpty { try c.encode(days, forKey: .days) }
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
        /// When it was sent for approval (`ส่งขออนุมัติ`) and by whom (an email): a contractor's request waits here for
        /// the team. Nil: a draft, or sent back.
        public var sentAt: Date?
        public var sentBy = ""
        /// Roles off on a day: `"<crew index>-<day>"` (`offKey`). Empty for older requests.
        public var crewOff: [String] = []
        /// The week's working hours, as minutes after midnight, when the request sets its own; nil: the station's
        /// (`Settings.workStart` / `workEnd`). Older requests have none.
        public var workStart: Int?
        public var workEnd: Int?

        public var id: String { MasterSchedule.Actual.key(weekStart) }
        public init(weekStart: Date) { self.weekStart = MasterSchedule.weekStart(weekStart) }

        enum CodingKeys: String, CodingKey {
            case weekStart, crew, tools, work, risks, engineerSignedAt, approvedAt, approvedBy, sentAt, sentBy, crewOff, workStart, workEnd
        }

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
            sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt)
            sentBy = try c.decodeIfPresent(String.self, forKey: .sentBy) ?? ""
            crewOff = try c.decodeIfPresent([String].self, forKey: .crewOff) ?? []
            workStart = try c.decodeIfPresent(Int.self, forKey: .workStart)
            workEnd = try c.decodeIfPresent(Int.self, forKey: .workEnd)
        }

        /// As before for a request with no role off: `crewOff` is left out while empty.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(weekStart, forKey: .weekStart); try c.encode(crew, forKey: .crew); try c.encode(tools, forKey: .tools)
            try c.encode(work, forKey: .work); try c.encode(risks, forKey: .risks)
            try c.encodeIfPresent(engineerSignedAt, forKey: .engineerSignedAt); try c.encodeIfPresent(approvedAt, forKey: .approvedAt)
            try c.encode(approvedBy, forKey: .approvedBy); try c.encodeIfPresent(sentAt, forKey: .sentAt); try c.encode(sentBy, forKey: .sentBy)
            if !crewOff.isEmpty { try c.encode(crewOff, forKey: .crewOff) }
            try c.encodeIfPresent(workStart, forKey: .workStart); try c.encodeIfPresent(workEnd, forKey: .workEnd)
        }

        public enum Status: Sendable { case draft, sent, approved }
        /// Approved, sent (by the contractor, or signed by our engineer as before `sentAt`), or a draft.
        public var status: Status { approvedAt != nil ? .approved : (sentAt != nil || engineerSignedAt != nil) ? .sent : .draft }

        /// `ส่งขออนุมัติ`. Our engineer's sending also signs it, as before; a contractor's waits for the team.
        public mutating func send(by email: String, signs: Bool, at date: Date = .now) {
            sentAt = date
            sentBy = email
            if signs { engineerSignedAt = date }
        }

        /// `ส่งกลับให้แก้`: back to a draft the contractor can change.
        public mutating func sendBack() {
            sentAt = nil
            sentBy = ""
            engineerSignedAt = nil
        }

        /// `บันทึกอนุมัติแล้ว`.
        public mutating func approve(by name: String, at date: Date) {
            approvedBy = name
            approvedAt = date
            if sentAt == nil { sentAt = date }
        }

        /// `เปิดแก้อีกครั้ง` on an approved request: back to sent, for the team to change and approve again.
        public mutating func reopen() {
            approvedAt = nil
            approvedBy = ""
        }

        /// Whether this member may change it: the team until it is approved (then they reopen it first), a contractor
        /// only while it is a draft.
        public func isEditable(external: Bool) -> Bool {
            switch status {
            case .approved: false
            case .sent: !external
            case .draft: true
            }
        }

        /// The requests as they arrive from Firestore. A contractor's write (`weeklyRequestsBy` is one of the job's
        /// externals) may only change drafts: a week this device holds as sent or approved stays as it is, and a
        /// contractor can't approve, sign or keep a week deleted that was sent. The rules can't see inside the JSON, so
        /// team devices check it here, as `IECReport.trusting` drops a close the team didn't make.
        public static func trusting(_ incoming: [WeeklyRequest], local: [WeeklyRequest], byContractor: Bool) -> [WeeklyRequest] {
            guard byContractor else { return incoming }
            let held = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var out: [WeeklyRequest] = incoming.map { r in
                guard let mine = held[r.id] else {
                    var r = r
                    r.approvedAt = nil; r.approvedBy = ""; r.engineerSignedAt = nil
                    return r
                }
                if mine.status != .draft { return mine }
                var r = r
                r.approvedAt = mine.approvedAt; r.approvedBy = mine.approvedBy; r.engineerSignedAt = mine.engineerSignedAt
                return r
            }
            let came = Set(incoming.map(\.id))
            out += local.filter { !came.contains($0.id) && $0.status != .draft }
            return out.sorted { $0.weekStart < $1.weekStart }
        }
    }
}
