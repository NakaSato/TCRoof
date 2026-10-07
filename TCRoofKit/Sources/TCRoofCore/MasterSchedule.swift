import Foundation

/// Master Project Schedule (MP) of one PWA station: the 18 tasks of the company's MP workbook
/// (`MP 189 สถานีผลิตน้ำทุ่งน้อย …xlsx`), their weights, their planned dates, and plan vs actual progress.
///
/// The plan reproduces the workbook's formulas: given the install window (วันเริ่ม / วันจบ), the
/// construction and commissioning tasks are placed by fractions of its length, and the permit tasks hang off
/// the three permit dates the planner types in. Progress is kept the way the workbook keeps it: weight points
/// per task per week, with the plan spread evenly over the weeks a task spans (weeks start on Sunday).
public enum MasterSchedule {

    // MARK: Tasks

    public enum Part: Int, CaseIterable, Codable, Sendable {
        case permit = 1, construction, commissioning

        public var title: String {
            switch self {
            case .permit: "Part PERMIT"
            case .construction: "Part ติดตั้งอุปกรณ์"
            case .commissioning: "Part การขออนุญาตและการทดสอบ"
            }
        }

        /// The weekly report's short name (`Weekly Update` › ความก้าวหน้างานตามหัวข้อหลัก).
        public var reportTitle: String {
            switch self {
            case .permit: "PERMIT"
            case .construction: "Construction"
            case .commissioning: "Commissioning TEST"
            }
        }
    }

    public enum Task: String, CaseIterable, Codable, Sendable, Identifiable {
        case kickoff, engineering, siteHandover, buildingPermit, pk2, cop, gridConnection
        case structure, dcSide, panels, fireSwitch, inverter, acSide, controlCabinet, zeroExport, monitoring
        case preCommissioning, training

        public var id: String { rawValue }

        public var part: Part {
            switch self {
            case .kickoff, .engineering, .siteHandover, .buildingPermit, .pk2, .cop, .gridConnection: .permit
            case .preCommissioning, .training: .commissioning
            default: .construction
            }
        }

        /// Item number. The workbook numbers grid connection "1.6" a second time; the app uses 1.7.
        public var code: String {
            switch self {
            case .kickoff: "1.1"
            case .engineering: "1.2"
            case .siteHandover: "1.3"
            case .buildingPermit: "1.4"
            case .pk2: "1.5"
            case .cop: "1.6"
            case .gridConnection: "1.7"
            case .structure: "2.1"
            case .dcSide: "2.2"
            case .panels: "2.3"
            case .fireSwitch: "2.4"
            case .inverter: "2.5"
            case .acSide: "2.6"
            case .controlCabinet: "2.7"
            case .zeroExport: "2.8"
            case .monitoring: "2.9"
            case .preCommissioning: "3.1"
            case .training: "3.2"
            }
        }

        public var title: String {
            switch self {
            case .kickoff: "Kick Off"
            case .engineering: "Engineering Approve"
            case .siteHandover: "ส่งมอบพื้นที่และเข้าดำเนินการติดตั้ง"
            case .buildingPermit: "ยื่นขออนุญาตดัดแปลงอาคาร (อ.1)"
            case .pk2: "ยื่นขอใบอนุญาต พค.2"
            case .cop: "COP / ยื่นเอกสารขอใบอนุญาตประกอบกิจการพลังงาน"
            case .gridConnection: "ยื่นขอขนานไฟ"
            case .structure: "ติดตั้งโครงสร้างรองรับแผงเซลล์ และทางเดินบนหลังคา (Walkway)"
            case .dcSide: "ติดตั้งอุปกรณ์ในระบบไฟฟ้า ด้าน DC"
            case .panels: "ติดตั้งแผงเซลล์แสงอาทิตย์"
            case .fireSwitch: "ติดตั้งอุปกรณ์หยุดทำงานฉุกเฉิน (Firefighter Safety Switch)"
            case .inverter: "ติดตั้งอุปกรณ์แปลงผันไฟฟ้าสำหรับต่อกับระบบจำหน่าย Inverter"
            case .acSide: "ติดตั้งอุปกรณ์ในระบบไฟฟ้า ด้าน AC"
            case .controlCabinet: "ติดตั้งตู้ควบคุมระบบไฟฟ้าสำหรับระบบ Solar Rooftop"
            case .zeroExport: "ติดตั้งระบบสื่อสาร และระบบป้องกันไฟฟ้าไหลย้อน (Zero Export Controller)"
            case .monitoring: "ติดตั้งระบบประมวลผลการผลิตไฟฟ้า (Solar Monitoring)"
            case .preCommissioning: "ทดสอบการทำงานของระบบผลิตไฟฟ้า (Pre-Commissioning Test)"
            case .training: "อบรมการใช้งานและการบำรุงรักษา"
            }
        }

        /// Weight in percent points of the whole station (all tasks sum to 100).
        /// A station whose inverters total more than 200 kVA needs พค.2, which takes weight from อ.1 and grid connection;
        /// the permit part stays 5 either way.
        public func weight(over200kVA: Bool) -> Double {
            switch self {
            case .kickoff: 0.5
            case .engineering: 1
            case .siteHandover: 0.5
            case .buildingPermit: over200kVA ? 1 : 1.5
            case .pk2: over200kVA ? 1 : 0
            case .cop: 0
            case .gridConnection: over200kVA ? 1 : 1.5
            case .structure: 20
            case .dcSide: 10
            case .panels: 20
            case .fireSwitch: 2.5
            case .inverter: 15
            case .acSide: 10
            case .controlCabinet: 5
            case .zeroExport: 5
            case .monitoring: 2.5
            case .preCommissioning: 2.5
            case .training: 2.5
            }
        }
    }

    // MARK: Plan

    /// What the planner types in. The workbook reads `installStart` / `installEnd` from its ข้อมูลดิบ sheet by MP number.
    public struct Input: Codable, Equatable, Sendable {
        public var installStart: Date
        public var installEnd: Date
        public var kickoff: Date
        public var engineeringStart: Date
        public var siteHandover: Date
        /// Inverters total more than 200 kVA (the workbook's `เกิน 200 kVA` flag): adds พค.2.
        public var over200kVA: Bool
        public var engineeringDays = 7
        public var buildingPermitDays = 21
        public var pk2Days = 21
        public var gridConnectionDays = 7

        public init(installStart: Date, installEnd: Date, kickoff: Date, engineeringStart: Date, siteHandover: Date,
                    over200kVA: Bool) {
            self.installStart = installStart
            self.installEnd = installEnd
            self.kickoff = kickoff
            self.engineeringStart = engineeringStart
            self.siteHandover = siteHandover
            self.over200kVA = over200kVA
        }

        /// Inverter total over 200 kVA, from the station's inverter rating (kW at PF 1).
        public static func isOver200kVA(inverterKW: Double) -> Bool { inverterKW > 200 }
    }

    public struct PlannedTask: Equatable, Sendable, Identifiable {
        public let task: Task
        public let weight: Double
        /// Nil for a task with no dates (COP, and พค.2 when the station does not need it).
        public let start: Date?
        public let end: Date?
        public var id: String { task.id }

        /// Calendar days from start to end, both included.
        public func days(calendar: Calendar = MasterSchedule.calendar) -> Int? {
            guard let start, let end else { return nil }
            return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        }
    }

    /// Gregorian, Bangkok time, weeks starting on Sunday (Excel `WEEKNUM` type 1).
    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        c.firstWeekday = 1
        return c
    }()

    /// Excel `ROUND`: halves away from zero.
    static func excelRound(_ x: Double) -> Int { Int(x.rounded(.toNearestOrAwayFromZero)) }

    /// The 18 tasks with the workbook's planned dates.
    public static func plan(_ input: Input, calendar cal: Calendar = calendar) -> [PlannedTask] {
        func day(_ d: Date) -> Date { cal.startOfDay(for: d) }
        func add(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: d)! }

        let s = day(input.installStart), e = day(input.installEnd)
        let len = Double((cal.dateComponents([.day], from: s, to: e).day ?? 0) + 1)   // C58
        let r = { (x: Double) in excelRound(x) }
        let big = input.over200kVA

        // part 3 runs backwards from the install end
        let trainingEnd = e, trainingStart = add(e, -r(len * 2.5 / 100))
        let preEnd = trainingStart, preStart = add(preEnd, -r(len * 2.5 / 100))
        let part3Start = preStart                                                     // E46

        // part 2
        let monEnd = preStart, monStart = add(monEnd, -r(len * 2.5 * 2 / 100))
        let zeroEnd = monStart, zeroStart = add(zeroEnd, -r(len * 5 / 100))
        let structStart = s, structEnd = add(part3Start, -r(len / 3))
        let invStart = s, invEnd = structEnd
        let panelsStart = add(structEnd, 1), panelsEnd = add(panelsStart, r(len / 4.5))
        let cabStart = add(invStart, 7), cabEnd = add(s, r(len / 2))
        let fireStart = cabEnd, fireEnd = add(fireStart, r(len * 2.5 * 5 / 100))
        let dcEnd = add(fireStart, -1), dcStart = add(dcEnd, -r(len / 6))
        let acEnd = add(zeroStart, -7), acStart = add(acEnd, -r(len / 5))

        // part 1
        let kick = day(input.kickoff)
        let engStart = day(input.engineeringStart), engEnd = add(engStart, input.engineeringDays)
        let hand = day(input.siteHandover)
        let o1Start = hand, o1End = add(hand, input.buildingPermitDays)
        let gridEnd = e, gridStart = add(e, -input.gridConnectionDays)                 // F46 = install end
        let pk2End: Date? = big ? gridEnd : nil
        let pk2Start = pk2End.map { add($0, -input.pk2Days) }

        let dates: [Task: (Date?, Date?)] = [
            .kickoff: (kick, kick), .engineering: (engStart, engEnd), .siteHandover: (hand, hand),
            .buildingPermit: (o1Start, o1End), .pk2: (pk2Start, pk2End), .cop: (nil, nil),
            .gridConnection: (gridStart, gridEnd),
            .structure: (structStart, structEnd), .dcSide: (dcStart, dcEnd), .panels: (panelsStart, panelsEnd),
            .fireSwitch: (fireStart, fireEnd), .inverter: (invStart, invEnd), .acSide: (acStart, acEnd),
            .controlCabinet: (cabStart, cabEnd), .zeroExport: (zeroStart, zeroEnd), .monitoring: (monStart, monEnd),
            .preCommissioning: (preStart, preEnd), .training: (trainingStart, trainingEnd),
        ]
        return Task.allCases.map { t in
            let d = dates[t] ?? (nil, nil)
            return PlannedTask(task: t, weight: t.weight(over200kVA: big), start: d.0, end: d.1)
        }
    }

    // MARK: Weeks

    /// The Sunday that starts the week holding `date`.
    public static func weekStart(_ date: Date, calendar cal: Calendar = calendar) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    /// Week starts from the week of `from` to the week of `to`, both included.
    public static func weeks(from: Date, to: Date, calendar cal: Calendar = calendar) -> [Date] {
        var w = weekStart(from, calendar: cal)
        let last = weekStart(to, calendar: cal)
        var out: [Date] = []
        while w <= last {
            out.append(w)
            w = cal.date(byAdding: .day, value: 7, to: w)!
        }
        return out
    }

    /// Planned weight points of each task per week: the task's weight spread evenly over the weeks it spans.
    public static func plannedPoints(_ plan: [PlannedTask], calendar cal: Calendar = calendar) -> [Task: [Date: Double]] {
        var out: [Task: [Date: Double]] = [:]
        for p in plan where p.weight > 0 {
            guard let s = p.start, let e = p.end else { continue }
            let ws = weeks(from: s, to: e, calendar: cal)
            out[p.task] = Dictionary(uniqueKeysWithValues: ws.map { ($0, p.weight / Double(ws.count)) })
        }
        return out
    }

    // MARK: Actual

    /// What the site reports: weight points done per task per week, plus the actual start and finish when known.
    public struct Actual: Codable, Equatable, Sendable {
        /// Task raw value → week start (`yyyy-MM-dd`, Sunday) → weight points done that week.
        public var points: [String: [String: Double]] = [:]
        public var started: [String: Date] = [:]
        public var finished: [String: Date] = [:]

        public init() {}

        public static func key(_ week: Date, calendar cal: Calendar = MasterSchedule.calendar) -> String {
            let c = cal.dateComponents([.year, .month, .day], from: weekStart(week, calendar: cal))
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }

        public func points(_ task: Task, week: Date, calendar cal: Calendar = MasterSchedule.calendar) -> Double {
            points[task.rawValue]?[Self.key(week, calendar: cal)] ?? 0
        }

        /// Sets the points for one week, capped so the task's total never passes its weight.
        public mutating func set(_ value: Double, task: Task, week: Date, over200kVA: Bool,
                                 calendar cal: Calendar = MasterSchedule.calendar) {
            let k = Self.key(week, calendar: cal)
            var byWeek = points[task.rawValue] ?? [:]
            let others = byWeek.filter { $0.key != k }.values.reduce(0, +)
            let v = min(max(value, 0), max(task.weight(over200kVA: over200kVA) - others, 0))
            byWeek[k] = v > 0 ? v : nil
            points[task.rawValue] = byWeek.isEmpty ? nil : byWeek
        }

        /// Sets the task's total done as a percent of its weight, booking the change in `week`.
        public mutating func setPercent(_ percent: Double, task: Task, week: Date, over200kVA: Bool,
                                        calendar cal: Calendar = MasterSchedule.calendar) {
            let w = task.weight(over200kVA: over200kVA)
            let target = w * min(max(percent, 0), 100) / 100
            let k = Self.key(week, calendar: cal)
            let others = (points[task.rawValue] ?? [:]).filter { $0.key != k }.values.reduce(0, +)
            set(target - others, task: task, week: week, over200kVA: over200kVA, calendar: cal)
        }

        /// Points done up to and including the week of `date`.
        public func done(_ task: Task, through date: Date, calendar cal: Calendar = MasterSchedule.calendar) -> Double {
            let limit = Self.key(date, calendar: cal)
            return (points[task.rawValue] ?? [:]).filter { $0.key <= limit }.values.reduce(0, +)
        }
    }

    // MARK: Report

    public struct Status: Equatable, Sendable {
        /// Cumulative percent of the whole station, 0…100.
        public let planned: Double
        public let actual: Double
        public let plannedByPart: [Part: Double]
        public let actualByPart: [Part: Double]
        /// Each task's own completion, 0…100 of its weight (only tasks with weight).
        public let plannedByTask: [Task: Double]
        public let actualByTask: [Task: Double]

        /// Actual minus planned; negative is behind (ช้ากว่า).
        public var variance: Double { actual - planned }
        public var isBehind: Bool { variance < 0 }
    }

    /// Plan vs actual up to and including the week of `date` (the workbook's Weekly Update).
    public static func status(plan: [PlannedTask], actual: Actual, through date: Date,
                              calendar cal: Calendar = calendar) -> Status {
        let limit = weekStart(date, calendar: cal)
        let planned = plannedPoints(plan, calendar: cal)
        var pTask: [Task: Double] = [:], aTask: [Task: Double] = [:]
        var pPart: [Part: Double] = [:], aPart: [Part: Double] = [:]
        for p in plan {
            let pp = (planned[p.task] ?? [:]).filter { $0.key <= limit }.values.reduce(0, +)
            let ap = actual.done(p.task, through: date, calendar: cal)
            pPart[p.task.part, default: 0] += pp
            aPart[p.task.part, default: 0] += ap
            if p.weight > 0 {
                pTask[p.task] = pp / p.weight * 100
                aTask[p.task] = ap / p.weight * 100
            }
        }
        return Status(planned: pPart.values.reduce(0, +), actual: aPart.values.reduce(0, +),
                      plannedByPart: pPart, actualByPart: aPart, plannedByTask: pTask, actualByTask: aTask)
    }

    /// Points planned and done inside one calendar month (the workbook's Monthly Update, "% เดือนนี้").
    public static func month(plan: [PlannedTask], actual: Actual, year: Int, month: Int,
                             calendar cal: Calendar = calendar) -> (planned: [Part: Double], actual: [Part: Double]) {
        // the workbook dates each week column by its Monday and files it by MONTH() of that date
        func inMonth(_ w: Date) -> Bool {
            let monday = cal.date(byAdding: .day, value: 1, to: w)!
            let c = cal.dateComponents([.year, .month], from: monday)
            return c.year == year && c.month == month
        }
        let planned = plannedPoints(plan, calendar: cal)
        var p: [Part: Double] = [:], a: [Part: Double] = [:]
        for t in plan {
            p[t.task.part, default: 0] += (planned[t.task] ?? [:]).filter { inMonth($0.key) }.values.reduce(0, +)
            for (k, v) in actual.points[t.task.rawValue] ?? [:] {
                if let w = Self.date(fromKey: k, calendar: cal), inMonth(w) { a[t.task.part, default: 0] += v }
            }
        }
        return (p, a)
    }

    static func date(fromKey key: String, calendar cal: Calendar) -> Date? {
        let n = key.split(separator: "-").compactMap { Int($0) }
        guard n.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: n[0], month: n[1], day: n[2]))
    }
}
