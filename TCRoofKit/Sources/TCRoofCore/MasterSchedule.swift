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
        /// Inverters total 200 kVA or more (the workbook's `เกิน 200 kVA` flag, `isOver200kVA`): adds พค.2.
        public var over200kVA: Bool
        public var engineeringDays = 7
        public var buildingPermitDays = 21
        public var pk2Days = 21
        public var gridConnectionDays = 7
        /// Task raw value → the dates and weight the station's own plan workbook gives it (`MPWorkbook` import). `plan`
        /// uses them in place of the formulas; nil for a plan made in the app. A task the workbook lacks has no dates
        /// and no weight.
        public var fixed: [String: FixedTask]?
        /// The plan as it was before its first confirmed re-plan (task raw value → dates and weight), kept so reports can
        /// show the original plan beside the new one. Nil until a re-plan; an imported workbook is a new plan without one.
        public var baseline: [String: FixedTask]?

        public init(installStart: Date, installEnd: Date, kickoff: Date, engineeringStart: Date, siteHandover: Date,
                    over200kVA: Bool) {
            self.installStart = installStart
            self.installEnd = installEnd
            self.kickoff = kickoff
            self.engineeringStart = engineeringStart
            self.siteHandover = siteHandover
            self.over200kVA = over200kVA
        }

        /// Inverter total of 200 kVA or more (`ERCFlow.needsPK2`), from the station's inverter rating (kW at PF 1).
        public static func isOver200kVA(inverterKW: Double) -> Bool { ERCFlow.needsPK2(kVA: inverterKW) }

        /// An imported plan's install window: from its site tasks' (parts 2 and 3) first start to their last end, so the
        /// Plan calendar shows what the workbook plans.
        public mutating func fitInstallWindow() {
            guard let fixed else { return }
            let site = Task.allCases.filter { $0.part != .permit }.compactMap { fixed[$0.rawValue] }
            if let s = site.compactMap(\.start).min() { installStart = s }
            if let e = site.compactMap(\.end).max() { installEnd = max(e, installStart) }
        }

        /// The plan before its first re-plan, with dates; nil when it was never re-planned.
        public var original: Input? {
            guard let baseline else { return nil }
            var i = self
            i.fixed = baseline
            i.baseline = nil
            return i
        }

        /// This plan's tasks as fixed dates and weights, the form a re-plan keeps (an imported plan's `fixed` as it is).
        public func fixedTasks(calendar cal: Calendar = MasterSchedule.calendar) -> [String: FixedTask] {
            fixed ?? Dictionary(uniqueKeysWithValues: MasterSchedule.plan(self, calendar: cal).map {
                ($0.task.rawValue, FixedTask(start: $0.start, end: $0.end, weight: $0.weight))
            })
        }

        /// The task's weight in this plan: the workbook's when imported, else the standard one.
        public func weight(_ task: Task) -> Double {
            guard let fixed else { return task.weight(over200kVA: over200kVA) }
            return fixed[task.rawValue]?.weight ?? 0
        }
    }

    /// One task as an imported workbook plans it.
    public struct FixedTask: Codable, Equatable, Sendable {
        public var start: Date?
        public var end: Date?
        public var weight: Double

        public init(start: Date?, end: Date?, weight: Double) {
            self.start = start; self.end = end; self.weight = weight
        }
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
            if let fixed = input.fixed {
                let f = fixed[t.rawValue]
                return PlannedTask(task: t, weight: f?.weight ?? 0, start: f?.start.map(day), end: f?.end.map(day))
            }
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
    /// Why a task runs past its plan, picked on the iPad install tracking page's task sheet.
    public enum LateCause: String, Codable, CaseIterable, Sendable {
        case weather, material, owner, contractor

        public var title: String {
            switch self {
            case .weather: "สภาพอากาศ"
            case .material: "วัสดุ"
            case .owner: "เจ้าของงาน"
            case .contractor: "ผู้รับเหมา"
            }
        }
    }

    public struct Actual: Codable, Equatable, Sendable {
        /// Task raw value → week start (`yyyy-MM-dd`, Sunday) → weight points done that week.
        public var points: [String: [String: Double]] = [:]
        public var started: [String: Date] = [:]
        public var finished: [String: Date] = [:]
        /// Task raw value → why it runs late; optional in older plans.
        public var lateCauses: [String: LateCause] = [:]
        /// Changes confirmed on the project assistant's cards, oldest first: who confirmed what and when. Changes typed
        /// in by hand are not listed. Optional in older plans.
        public var confirmations: [Confirmation] = []
        /// Task raw value → the approval day the station's papers booked it at 100 % on (`PermitLink`). The link books a
        /// task once: progress the team changes afterwards, or an approval taken back, is left to the team. Optional in
        /// older plans.
        public var fromDocuments: [String: Date] = [:]

        public init() {}

        /// One assistant card someone confirmed (ผ่านผู้ช่วย).
        public struct Confirmation: Codable, Equatable, Sendable {
            /// Task raw value; a re-plan names its first task.
            public var task: String
            /// The email of the person who tapped ยืนยัน.
            public var by: String
            public var at: Date
            /// The card's before and after, as it read.
            public var before: String
            public var after: String
            public var replan: Bool

            public init(task: String, by: String, at: Date, before: String, after: String, replan: Bool = false) {
                self.task = task; self.by = by; self.at = at; self.before = before; self.after = after; self.replan = replan
            }
        }

        /// The latest assistant confirmation for a task.
        public func lastConfirmation(_ task: Task) -> Confirmation? {
            confirmations.last { $0.task == task.rawValue }
        }

        enum CodingKeys: String, CodingKey { case points, started, finished, lateCauses, confirmations, fromDocuments }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            points = try c.decodeIfPresent([String: [String: Double]].self, forKey: .points) ?? [:]
            started = try c.decodeIfPresent([String: Date].self, forKey: .started) ?? [:]
            finished = try c.decodeIfPresent([String: Date].self, forKey: .finished) ?? [:]
            // a cause this build doesn't know is dropped, not a failed plan
            let raw = (try? c.decodeIfPresent([String: String].self, forKey: .lateCauses)) ?? nil
            lateCauses = (raw ?? [:]).compactMapValues(LateCause.init(rawValue:))
            confirmations = (try? c.decodeIfPresent([Confirmation].self, forKey: .confirmations)) ?? []
            fromDocuments = (try? c.decodeIfPresent([String: Date].self, forKey: .fromDocuments)) ?? [:]
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(points, forKey: .points)
            try c.encode(started, forKey: .started)
            try c.encode(finished, forKey: .finished)
            try c.encode(lateCauses, forKey: .lateCauses)
            // left out when empty, so a plan without any reads as before
            if !confirmations.isEmpty { try c.encode(confirmations, forKey: .confirmations) }
            if !fromDocuments.isEmpty { try c.encode(fromDocuments, forKey: .fromDocuments) }
        }

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
            set(value, task: task, week: week, weight: task.weight(over200kVA: over200kVA), calendar: cal)
        }

        /// `set` against the task's weight in the plan (`Input.weight`).
        public mutating func set(_ value: Double, task: Task, week: Date, weight: Double,
                                 calendar cal: Calendar = MasterSchedule.calendar) {
            let k = Self.key(week, calendar: cal)
            var byWeek = points[task.rawValue] ?? [:]
            let others = byWeek.filter { $0.key != k }.values.reduce(0, +)
            let v = min(max(value, 0), max(weight - others, 0))
            byWeek[k] = v > 0 ? v : nil
            points[task.rawValue] = byWeek.isEmpty ? nil : byWeek
        }

        /// Sets the task's total done as a percent of its weight, booking the change in `week`.
        public mutating func setPercent(_ percent: Double, task: Task, week: Date, over200kVA: Bool,
                                        calendar cal: Calendar = MasterSchedule.calendar) {
            setPercent(percent, task: task, week: week, weight: task.weight(over200kVA: over200kVA), calendar: cal)
        }

        /// `setPercent` against the task's weight in the plan (`Input.weight`).
        public mutating func setPercent(_ percent: Double, task: Task, week: Date, weight w: Double,
                                        calendar cal: Calendar = MasterSchedule.calendar) {
            let target = w * min(max(percent, 0), 100) / 100
            let k = Self.key(week, calendar: cal)
            let others = (points[task.rawValue] ?? [:]).filter { $0.key != k }.values.reduce(0, +)
            set(target - others, task: task, week: week, weight: w, calendar: cal)
        }

        /// The tasks (raw values) and weeks (`key`) a plan file has Actual cells for: what a merge may take from it, a
        /// cleared cell included.
        public struct Coverage: Sendable, Equatable {
            public var tasks: Set<String>
            public var weeks: Set<String>
            public init(tasks: Set<String>, weeks: Set<String>) { self.tasks = tasks; self.weeks = weeks }
        }

        /// Another copy's progress (a workbook updated in Excel) taken into this one.
        ///
        /// With `base`, the progress the file held when the app last wrote or read it, and `covering`, only what was
        /// changed in the file since is taken, a cleared cell included: a booking moved or removed in Excel moves or goes
        /// here too, and what the app booked since stays. Without them (a file the app never saw), the file's points win
        /// for the task-weeks it has and its dates where it has them, and what only this copy has is kept.
        ///
        /// Either way no task the file changed ends above its weight in `weights` (task raw value → its weight points): its
        /// latest weeks give way. `changed` counts the task-weeks and dates the file changed.
        public func merging(_ other: Actual, base: Actual? = nil, covering: Coverage? = nil, weights: [String: Double] = [:])
            -> (actual: Actual, changed: Int) {
            var out = self, changed = 0, touched = Set<String>()
            func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 * max(1, abs(a)) }
            let dates: [WritableKeyPath<Actual, [String: Date]>] = [\.started, \.finished]
            if let base, let covering {
                for task in covering.tasks {
                    for week in covering.weeks {
                        let f = other.points[task]?[week] ?? 0
                        // unchanged in the file since the app saw it, or already the same here
                        guard !near(f, base.points[task]?[week] ?? 0), !near(f, out.points[task]?[week] ?? 0) else { continue }
                        out.put(f, task: task, week: week)
                        changed += 1; touched.insert(task)
                    }
                    for kp in dates {
                        let f = other[keyPath: kp][task]
                        guard !Self.sameDay(f, base[keyPath: kp][task]), !Self.sameDay(f, out[keyPath: kp][task]) else { continue }
                        out[keyPath: kp][task] = f
                        changed += 1
                    }
                }
            } else {
                for (task, weeks) in other.points {
                    for (week, v) in weeks where v > 0 && !near(v, out.points[task]?[week] ?? 0) {
                        out.put(v, task: task, week: week)
                        changed += 1; touched.insert(task)
                    }
                }
                for kp in dates {
                    for (task, d) in other[keyPath: kp] where !Self.sameDay(d, out[keyPath: kp][task]) {
                        out[keyPath: kp][task] = d
                        changed += 1
                    }
                }
            }
            out.cap(weights.filter { touched.contains($0.key) })
            return (out, changed)
        }

        static func sameDay(_ a: Date?, _ b: Date?, calendar cal: Calendar = MasterSchedule.calendar) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (x?, y?): cal.isDate(x, inSameDayAs: y)
            default: false
            }
        }

        /// One task-week's points as given, 0 clearing it.
        private mutating func put(_ v: Double, task: String, week: String) {
            var byWeek = points[task] ?? [:]
            byWeek[week] = v > 0 ? v : nil
            points[task] = byWeek.isEmpty ? nil : byWeek
        }

        /// Each task in `weights` trimmed to its weight, its latest weeks first.
        private mutating func cap(_ weights: [String: Double]) {
            for (task, w) in weights {
                guard var byWeek = points[task] else { continue }
                var over = byWeek.values.reduce(0, +) - max(w, 0)
                guard over > 1e-9 else { continue }
                for week in byWeek.keys.sorted(by: >) where over > 1e-9 {
                    let v = byWeek[week] ?? 0, cut = min(v, over)
                    byWeek[week] = v - cut > 1e-9 ? v - cut : nil
                    over -= cut
                }
                points[task] = byWeek.isEmpty ? nil : byWeek
            }
        }

        /// Points done up to and including the week of `date`.
        public func done(_ task: Task, through date: Date, calendar cal: Calendar = MasterSchedule.calendar) -> Double {
            let limit = Self.key(date, calendar: cal)
            return (points[task.rawValue] ?? [:]).filter { $0.key <= limit }.values.reduce(0, +)
        }

        /// Sets the task's วันเริ่มจริง / วันเสร็จจริง as days (nil clears one). A finish before the start moves to it.
        public mutating func setDates(_ task: Task, started s: Date?, finished f: Date?,
                                      calendar cal: Calendar = MasterSchedule.calendar) {
            let s = s.map { cal.startOfDay(for: $0) }
            var f = f.map { cal.startOfDay(for: $0) }
            if let s, let e = f, e < s { f = s }
            started[task.rawValue] = s
            finished[task.rawValue] = f
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
