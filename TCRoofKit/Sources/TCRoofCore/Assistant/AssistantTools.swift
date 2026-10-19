import Foundation

public extension Assistant {

    /// One station as the app hands it to the assistant: no customer details.
    struct Job: Sendable {
        public var id: String
        public var station: String
        public var mpNumber: Int?
        public var kWp: Double?
        /// Nil for a job without an MP plan.
        public var input: MasterSchedule.Input?
        public var actual: MasterSchedule.Actual
        public var dailies: [RoutineReport.Daily]
        /// The person may book progress, dates and late causes on it (`mp.progress`).
        public var canEdit: Bool

        public init(id: String, station: String, mpNumber: Int? = nil, kWp: Double? = nil, input: MasterSchedule.Input?,
                    actual: MasterSchedule.Actual = .init(), dailies: [RoutineReport.Daily] = [], canEdit: Bool) {
            self.id = id; self.station = station; self.mpNumber = mpNumber; self.kWp = kWp
            self.input = input; self.actual = actual; self.dailies = dailies; self.canEdit = canEdit
        }

        public func brief(today: Date) -> ScheduleBrief? {
            input.map { ScheduleBrief(jobID: id, station: station, mpNumber: mpNumber, kWp: kWp, input: $0,
                                      actual: actual, dailies: dailies, today: today) }
        }
    }

    /// A change the model proposed. Nothing is saved until the person confirms it; `apply` then runs on the job's
    /// current progress, so a booking made meanwhile is kept.
    struct PendingAction: Codable, Equatable, Sendable, Identifiable {
        public enum Change: Codable, Equatable, Sendable {
            case progress(task: MasterSchedule.Task, week: String, percent: Double)
            /// The dates the task ends up with (nil: none).
            case dates(task: MasterSchedule.Task, started: String?, finished: String?)
            case lateCause(task: MasterSchedule.Task, cause: MasterSchedule.LateCause?)
        }

        public var id: String
        public var jobID: String
        public var station: String
        public var change: Change
        /// `2.3 ติดตั้งแผงเซลล์…`
        public var title: String
        public var before: String
        public var after: String

        public var task: MasterSchedule.Task {
            switch change {
            case .progress(let t, _, _), .dates(let t, _, _), .lateCause(let t, _): t
            }
        }

        public func apply(to actual: MasterSchedule.Actual, input: MasterSchedule.Input,
                          calendar cal: Calendar = MasterSchedule.calendar) -> MasterSchedule.Actual {
            var a = actual
            switch change {
            case let .progress(task, week, percent):
                guard let w = MasterSchedule.date(fromKey: week, calendar: cal) else { return a }
                a.setPercent(percent, task: task, week: w, weight: input.weight(task), calendar: cal)
            case let .dates(task, started, finished):
                a.setDates(task, started: started.flatMap { MasterSchedule.date(fromKey: $0, calendar: cal) },
                           finished: finished.flatMap { MasterSchedule.date(fromKey: $0, calendar: cal) }, calendar: cal)
            case let .lateCause(task, cause):
                a.lateCauses[task.rawValue] = cause
            }
            return a
        }
    }

    /// The tools the model may call, and their answers. Read tools return JSON; `propose_*` tools return a
    /// `PendingAction` for the person to confirm. Their names are functions/src/allowed-tools.json (the function refuses
    /// any other; `AssistantToolsTests` keeps the two the same).
    struct Toolbox: Sendable {
        public enum Outcome: Equatable, Sendable {
            case result(String)
            case proposal(PendingAction, String)

            public var text: String {
                switch self {
                case .result(let s), .proposal(_, let s): s
                }
            }
        }

        public var jobs: [Job]
        public var today: Date
        public var calendar: Calendar
        private let makeID: @Sendable () -> String

        public init(jobs: [Job], today: Date, calendar: Calendar = MasterSchedule.calendar,
                    makeID: @escaping @Sendable () -> String = { UUID().uuidString }) {
            self.jobs = jobs; self.today = today; self.calendar = calendar; self.makeID = makeID
        }

        public static let names = ["list_stations", "get_schedule", "get_week_tasks",
                                   "propose_progress", "propose_dates", "propose_late_cause"]

        public func run(_ name: String, arguments: String) -> Outcome {
            let args = JSONValue.parse(arguments.isEmpty ? "{}" : arguments) ?? .object([:])
            switch name {
            case "list_stations": return listStations(args)
            case "get_schedule": return withJob(args) { job, _, _ in .result(job.brief(today: today)!.json()) }
            case "get_week_tasks": return withJob(args) { weekTasks($0, $1, $2, args) }
            case "propose_progress": return proposeProgress(args)
            case "propose_dates": return proposeDates(args)
            case "propose_late_cause": return proposeCause(args)
            default: return error("ไม่มีเครื่องมือ \(name)")
            }
        }

        // MARK: Read

        private func listStations(_ args: JSONValue) -> Outcome {
            let onlyBehind = args["filter"]?.string != "all"
            let limit = max(1, min(Int(args["limit"]?.number ?? 20), 100))
            let rows: [[String: JSONValue]] = jobs.compactMap { j in
                guard let b = j.brief(today: today) else { return nil }
                if onlyBehind, b.variance >= 0, (b.projectedSlipDays ?? 0) <= 0 { return nil }
                var r: [String: JSONValue] = [
                    "jobID": .string(j.id), "station": .string(j.station),
                    "plannedPercent": .number(b.plannedPercent), "actualPercent": .number(b.actualPercent),
                    "variance": .number(b.variance), "installEnd": .string(b.installEnd),
                    "thisWeek": .array(b.thisWeek.map(JSONValue.string)),
                ]
                if let mp = j.mpNumber { r["mpNumber"] = .number(Double(mp)) }
                if let s = b.projectedSlipDays { r["projectedSlipDays"] = .number(Double(s)) }
                return r
            }
            .sorted { ($0["variance"]?.number ?? 0) < ($1["variance"]?.number ?? 0) }
            let out: JSONValue = .object(["count": .number(Double(rows.count)),
                                          "stations": .array(rows.prefix(limit).map(JSONValue.object))])
            return .result(Self.encode(out))
        }

        private func weekTasks(_ job: Job, _ input: MasterSchedule.Input, _ plan: [MasterSchedule.PlannedTask],
                               _ args: JSONValue) -> Outcome {
            guard let week = week(args["week"]) else { return error("week ต้องเป็นวันที่ yyyy-MM-dd") }
            let key = MasterSchedule.Actual.key(week, calendar: calendar)
            let planned = MasterSchedule.plannedPoints(plan, calendar: calendar)
            let rows: [JSONValue] = plan.compactMap { p in
                let pp = planned[p.task]?[week] ?? 0
                let ap = job.actual.points[p.task.rawValue]?[key] ?? 0
                guard pp > 0 || ap > 0 else { return nil }
                return .object(["code": .string(p.task.code), "title": .string(p.task.title),
                                "plannedPoints": .number(ScheduleBrief.round(pp)), "actualPoints": .number(ScheduleBrief.round(ap)),
                                "weight": .number(p.weight)])
            }
            return .result(Self.encode(.object(["jobID": .string(job.id), "week": .string(key), "tasks": .array(rows)])))
        }

        // MARK: Propose

        private func proposeProgress(_ args: JSONValue) -> Outcome {
            withEditable(args) { job, input, task in
                guard let percent = args["percent"]?.number, percent >= 0, percent <= 100 else {
                    return error("percent ต้องเป็น 0–100")
                }
                guard let week = week(args["week"]) else { return error("week ต้องเป็นวันที่ yyyy-MM-dd") }
                guard week <= MasterSchedule.weekStart(today, calendar: calendar) else { return error("บันทึกล่วงหน้าไม่ได้") }
                let w = input.weight(task)
                let before = w > 0 ? Self.total(job.actual, task) / w * 100 : 0
                let key = MasterSchedule.Actual.key(week, calendar: calendar)
                return propose(job, task, .progress(task: task, week: key, percent: percent),
                               before: Self.percent(before), after: "\(Self.percent(percent)) (สัปดาห์ \(key))")
            }
        }

        private func proposeDates(_ args: JSONValue) -> Outcome {
            withEditable(args) { job, _, task in
                func pick(_ key: String, _ current: Date?) -> (String?, Bool) {
                    guard let v = args[key] else { return (current.map { ScheduleBrief.day($0, calendar: calendar) }, true) }
                    if v == .null || v.string?.isEmpty == true { return (nil, true) }
                    guard let s = v.string, let d = MasterSchedule.date(fromKey: s, calendar: calendar) else { return (nil, false) }
                    return (ScheduleBrief.day(d, calendar: calendar), true)
                }
                let (s, okS) = pick("started", job.actual.started[task.rawValue])
                let (f, okF) = pick("finished", job.actual.finished[task.rawValue])
                guard okS, okF else { return error("วันที่ต้องเป็น yyyy-MM-dd") }
                let today = ScheduleBrief.day(self.today, calendar: calendar)
                guard (s ?? "") <= today, (f ?? "") <= today else { return error("วันที่จริงต้องไม่เกินวันนี้") }
                let show = { (s: String?, f: String?) in "เริ่ม \(s ?? "–") · เสร็จ \(f ?? "–")" }
                let before = show(job.actual.started[task.rawValue].map { ScheduleBrief.day($0, calendar: calendar) },
                                  job.actual.finished[task.rawValue].map { ScheduleBrief.day($0, calendar: calendar) })
                return propose(job, task, .dates(task: task, started: s, finished: f), before: before, after: show(s, f))
            }
        }

        private func proposeCause(_ args: JSONValue) -> Outcome {
            withEditable(args) { job, _, task in
                let raw = args["cause"]?.string ?? ""
                let cause = MasterSchedule.LateCause(rawValue: raw)
                guard cause != nil || raw == "none" else { return error("cause ต้องเป็น weather, material, owner, contractor หรือ none") }
                return propose(job, task, .lateCause(task: task, cause: cause),
                               before: job.actual.lateCauses[task.rawValue]?.title ?? "ไม่ระบุ", after: cause?.title ?? "ไม่ระบุ")
            }
        }

        private func propose(_ job: Job, _ task: MasterSchedule.Task, _ change: PendingAction.Change,
                             before: String, after: String) -> Outcome {
            let a = PendingAction(id: makeID(), jobID: job.id, station: job.station, change: change,
                                  title: "\(task.code) \(task.title)", before: before, after: after)
            let text = Self.encode(.object([
                "proposalID": .string(a.id), "status": .string("waiting_for_user_confirmation"),
                "station": .string(job.station), "task": .string(a.title), "before": .string(before), "after": .string(after),
                "note": .string("ยังไม่ได้บันทึก ผู้ใช้ต้องกดยืนยันในการ์ดก่อน"),
            ]))
            return .proposal(a, text)
        }

        // MARK: Lookup

        private func withJob(_ args: JSONValue,
                             _ body: (Job, MasterSchedule.Input, [MasterSchedule.PlannedTask]) -> Outcome) -> Outcome {
            let ref = args["job"]?.string ?? ""
            let found = find(ref)
            guard found.count == 1, let job = found.first else {
                if found.isEmpty { return error("ไม่พบสถานี \(ref) ใช้ list_stations เพื่อดูรายชื่อ") }
                return error("พบหลายสถานีที่ตรงกับ \(ref): " + found.prefix(5).map { "\($0.station) (\($0.id))" }.joined(separator: ", "))
            }
            guard let input = job.input else { return error("\(job.station) ยังไม่มีแผน MP") }
            return body(job, input, MasterSchedule.plan(input, calendar: calendar))
        }

        private func withEditable(_ args: JSONValue,
                                  _ body: (Job, MasterSchedule.Input, MasterSchedule.Task) -> Outcome) -> Outcome {
            withJob(args) { job, input, _ in
                guard job.canEdit else { return error("ผู้ใช้นี้ไม่มีสิทธิ์บันทึกความก้าวหน้าของ \(job.station)") }
                guard let task = Self.task(args["task"]?.string ?? "") else { return error("task ต้องเป็นรหัสงาน เช่น 2.3") }
                guard input.weight(task) > 0 else { return error("\(task.code) ไม่มีน้ำหนักในแผนนี้") }
                return body(job, input, task)
            }
        }

        /// A job by its id, its MP number (`189`, `MP 189`) or a part of its station name.
        func find(_ ref: String) -> [Job] {
            let r = ref.trimmingCharacters(in: .whitespaces)
            guard !r.isEmpty else { return [] }
            if let j = jobs.first(where: { $0.id == r }) { return [j] }
            let digits = r.uppercased().replacingOccurrences(of: "MP", with: "").trimmingCharacters(in: .whitespaces)
            if let n = Int(digits) { return jobs.filter { $0.mpNumber == n } }
            return jobs.filter { $0.station.localizedCaseInsensitiveContains(r) }
        }

        static func task(_ s: String) -> MasterSchedule.Task? {
            let t = s.trimmingCharacters(in: .whitespaces)
            return MasterSchedule.Task.allCases.first { $0.code == t || $0.rawValue == t || t.hasPrefix($0.code + " ") }
        }

        /// A week from `yyyy-MM-dd` (any day in it); this week when missing.
        private func week(_ v: JSONValue?) -> Date? {
            guard let s = v?.string, !s.isEmpty else { return MasterSchedule.weekStart(today, calendar: calendar) }
            return MasterSchedule.date(fromKey: s, calendar: calendar).map { MasterSchedule.weekStart($0, calendar: calendar) }
        }

        private func error(_ message: String) -> Outcome { .result(Self.encode(.object(["error": .string(message)]))) }

        static func total(_ a: MasterSchedule.Actual, _ t: MasterSchedule.Task) -> Double {
            (a.points[t.rawValue] ?? [:]).values.reduce(0, +)
        }

        static func percent(_ x: Double) -> String {
            let r = ScheduleBrief.round(x)
            return (r == r.rounded() ? String(Int(r)) : String(r)) + "%"
        }

        static func encode(_ v: JSONValue) -> String {
            let e = JSONEncoder()
            e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? String(data: e.encode(v), encoding: .utf8)) ?? "{}"
        }

        // MARK: Schemas

        /// The OpenAI-style tool definitions sent with each request.
        public static let definitions: [JSONValue] = {
            func fn(_ name: String, _ description: String, _ props: [String: JSONValue], required: [String]) -> JSONValue {
                .object(["type": .string("function"), "function": .object([
                    "name": .string(name), "description": .string(description),
                    "parameters": .object(["type": .string("object"), "properties": .object(props),
                                           "required": .array(required.map(JSONValue.string))]),
                ])])
            }
            func p(_ type: String, _ description: String, enum values: [String]? = nil) -> JSONValue {
                var o: [String: JSONValue] = ["type": .string(type), "description": .string(description)]
                if let values { o["enum"] = .array(values.map(JSONValue.string)) }
                return .object(o)
            }
            let job = p("string", "รหัสงาน (jobID), เลข MP เช่น 189 หรือส่วนหนึ่งของชื่อสถานี")
            let task = p("string", "รหัสงานในแผน MP เช่น 2.3")
            return [
                fn("list_stations", "รายชื่อสถานีที่มีแผน MP เรียงจากช้ากว่าแผนมากที่สุด",
                   ["filter": p("string", "behind = เฉพาะที่ช้ากว่าแผนหรือคาดว่าจะเสร็จช้า, all = ทุกสถานี", enum: ["behind", "all"]),
                    "limit": p("integer", "จำนวนสูงสุด (ค่าเริ่มต้น 20)")], required: []),
                fn("get_schedule", "แผน MP ของสถานีหนึ่ง: % แผนและจริง, แต่ละงาน (ต้องทำกี่คะแนนต่อสัปดาห์, อัตราที่ผ่านมา, วันที่คาดว่าเสร็จ), งานสัปดาห์นี้ และรายงานประจำวันล่าสุด",
                   ["job": job], required: ["job"]),
                fn("get_week_tasks", "คะแนนตามแผนและที่ทำจริงของแต่ละงานในสัปดาห์หนึ่ง",
                   ["job": job, "week": p("string", "วันใดก็ได้ในสัปดาห์ yyyy-MM-dd (ค่าเริ่มต้น สัปดาห์นี้)")], required: ["job"]),
                fn("propose_progress", "เสนอบันทึก % สะสมของงานหนึ่ง ผู้ใช้ต้องกดยืนยันก่อนบันทึก",
                   ["job": job, "task": task, "percent": p("number", "% สะสมของงานนี้ 0–100"),
                    "week": p("string", "สัปดาห์ที่บันทึก yyyy-MM-dd (ค่าเริ่มต้น สัปดาห์นี้)")], required: ["job", "task", "percent"]),
                fn("propose_dates", "เสนอวันเริ่มจริง / วันเสร็จจริงของงานหนึ่ง ผู้ใช้ต้องกดยืนยัน ไม่ใส่ = คงเดิม, ค่าว่าง = ลบ",
                   ["job": job, "task": task, "started": p("string", "yyyy-MM-dd"), "finished": p("string", "yyyy-MM-dd")],
                   required: ["job", "task"]),
                fn("propose_late_cause", "เสนอสาเหตุที่งานล่าช้า ผู้ใช้ต้องกดยืนยัน",
                   ["job": job, "task": task,
                    "cause": p("string", "weather สภาพอากาศ, material วัสดุ, owner เจ้าของงาน, contractor ผู้รับเหมา, none ไม่ระบุ",
                               enum: ["weather", "material", "owner", "contractor", "none"])],
                   required: ["job", "task", "cause"]),
            ]
        }()
    }
}
