import Foundation

/// The assistant's planning figures (docs/specs/project-assistant-qwen.md §6): recovery scenarios, the all-station
/// priorities and crew loads, the three-week look-ahead and a re-plan draft. Swift works out every number; the model
/// explains them and recommends. Every figure assumes a task's pace scales with its crew and working days, which the
/// results say.
public extension Assistant {

    enum Strategy {

        // MARK: Shared

        /// What each task waits for: the plan's order of work. A task's start is planned against these, so a re-plan
        /// moves a task by as much as its predecessors' ends moved.
        public static let predecessors: [MasterSchedule.Task: [MasterSchedule.Task]] = [
            .engineering: [.kickoff], .buildingPermit: [.siteHandover], .pk2: [.buildingPermit],
            .gridConnection: [.buildingPermit, .pk2],
            .structure: [.siteHandover, .engineering], .dcSide: [.structure], .panels: [.structure],
            .inverter: [.siteHandover], .controlCabinet: [.siteHandover], .fireSwitch: [.controlCabinet],
            .acSide: [.inverter, .controlCabinet], .zeroExport: [.acSide], .monitoring: [.zeroExport],
            .preCommissioning: [.structure, .dcSide, .panels, .fireSwitch, .inverter, .acSide, .controlCabinet, .zeroExport, .monitoring],
            .training: [.preCommissioning],
        ]

        /// The tasks so that each comes after its predecessors.
        static let order: [MasterSchedule.Task] = {
            var out: [MasterSchedule.Task] = []
            func visit(_ t: MasterSchedule.Task) {
                guard !out.contains(t) else { return }
                for p in predecessors[t] ?? [] { visit(p) }
                out.append(t)
            }
            MasterSchedule.Task.allCases.forEach(visit)
            return out
        }()

        static let assumption = "สมมติว่าอัตราการทำงานแปรตามจำนวนคนและวันทำงาน งานที่ยังไม่มีความก้าวหน้าใช้อัตราตามแผน"

        /// The average crew of the days with a crew in the last 14 days; nil without any.
        static func crewAverage(_ dailies: [RoutineReport.Daily], today: Date, calendar cal: Calendar) -> Double? {
            let from = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: today))!
            let crews = dailies.filter { $0.date > from && $0.date <= today && $0.crewTotal > 0 }.map(\.crewTotal)
            return crews.isEmpty ? nil : Double(crews.reduce(0, +)) / Double(crews.count)
        }

        /// One open task's rate in points per week: its pace so far, else the plan's (weight over its weeks).
        static func rate(_ r: MasterSchedule.Recovery, calendar cal: Calendar) -> (Double, assumed: Bool) {
            if let p = r.pacePerWeek, p > 1e-9 { return (p, false) }
            let weeks = max(MasterSchedule.weeks(from: r.plannedStart, to: r.plannedEnd, calendar: cal).count, 1)
            return (r.weight / Double(weeks), true)
        }

        static func day(_ d: Date, _ cal: Calendar) -> String { ScheduleBrief.day(d, calendar: cal) }
        static func days(_ a: Date, _ b: Date, _ cal: Calendar) -> Int {
            cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
        }
        static func text<T: Encodable>(_ v: T) -> String {
            let e = JSONEncoder()
            e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? String(data: e.encode(v), encoding: .utf8)) ?? "{}"
        }

        // MARK: What if

        public struct TaskFinish: Codable, Equatable, Sendable {
            public var code: String
            public var title: String
            public var plannedEnd: String
            public var finish: String
            public var slipDays: Int
            /// The rate is the plan's, not one measured on site.
            public var assumedRate: Bool
        }

        public struct Scenario: Codable, Equatable, Sendable {
            public var name: String
            /// The pace multiplier the scenario gives every open task.
            public var paceFactor: Double
            public var stationFinish: String?
            /// Days `stationFinish` falls after the install end.
            public var slipDays: Int?
            public var tasks: [TaskFinish]
        }

        public struct Requirement: Codable, Equatable, Sendable {
            /// The pace multiplier needed for every open task to end by its planned end (by the install end once that
            /// has passed), set by the slowest task.
            public var paceFactor: Double
            public var bottleneck: String
            /// The crew that gives that pace at today's working days; nil without crew in the daily reports.
            public var crew: Int?
            /// Working days per week needed at today's crew; nil when more than 7.
            public var workingDaysPerWeek: Int?
        }

        public struct WhatIf: Codable, Equatable, Sendable {
            public var jobID: String
            public var station: String
            public var today: String
            public var installEnd: String
            /// The install tracking page's `คาดส่งมอบ` (SPI), quoted for the station; the scenarios compare task by task.
            public var handoverForecast: String
            public var handoverSlipDays: Int
            public var crewAverage: Double?
            public var workingDaysPerWeek: Int
            public var base: Scenario
            public var scenario: Scenario?
            /// Nil when nothing is left or the install end has passed.
            public var toFinishOnTime: Requirement?
            public var note: String
            public var json: String { Strategy.text(self) }
        }

        /// One task's dates in a forecast.
        struct Dated { var start: Date; var end: Date; var why: String; var assumed: Bool }

        /// Every task's dates from today at `factor` times its rate, in the plan's order of work: a task under way ends
        /// when its rate finishes it, a task not started keeps its length (shortened by `factor`) and moves by as much as
        /// its predecessors' ends moved later, unless it is in `startNow` (it starts this week). Finished tasks stay.
        /// `keepPlannedEnds` never ends a task before its plan (a re-plan); a what-if may.
        static func forecast(plan: [MasterSchedule.PlannedTask], actual: MasterSchedule.Actual, factor: Double,
                             startNow: Set<MasterSchedule.Task> = [], keepPlannedEnds: Bool, today: Date,
                             calendar cal: Calendar) -> [MasterSchedule.Task: Dated] {
            let byTask = Dictionary(uniqueKeysWithValues: plan.map { ($0.task, $0) })
            let recovery = Dictionary(uniqueKeysWithValues: MasterSchedule.recovery(plan: plan, actual: actual, today: today, calendar: cal).map { ($0.task, $0) })
            let thisWeek = MasterSchedule.weekStart(today, calendar: cal)
            let f = max(factor, 0.1)
            var out: [MasterSchedule.Task: Dated] = [:]
            for t in order {
                guard let p = byTask[t], p.weight > 0, let s = p.start, let e = p.end, let r = recovery[t] else { continue }
                let push = (predecessors[t] ?? []).compactMap { q -> (Int, MasterSchedule.Task)? in
                    guard let moved = out[q], let old = byTask[q]?.end else { return nil }
                    return (days(old, moved.end, cal), q)
                }.max { $0.0 < $1.0 }
                let late = max(push?.0 ?? 0, 0)
                func add(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: d)! }
                switch r.state {
                case .done:
                    out[t] = Dated(start: s, end: e, why: "", assumed: false)
                case .upcoming:
                    let length = Int((Double(days(s, e, cal) + 1) / f - 1e-6).rounded(.up))
                    let begin = startNow.contains(t) ? max(thisWeek, cal.startOfDay(for: today)) : add(s, late)
                    let why = startNow.contains(t) ? "เริ่มสัปดาห์นี้" : late > 0 ? "เลื่อนตาม \(push!.1.code)" : ""
                    out[t] = Dated(start: begin, end: add(begin, max(length, 1) - 1), why: why, assumed: true)
                default:
                    let (rate, assumed) = Self.rate(r, calendar: cal)
                    let n = Int((7 * r.remaining / (rate * f) - 1e-6).rounded(.up))
                    let paced = add(thisWeek, max(n, 1) - 1)
                    let pushed = add(e, late)
                    var end = late > 0 ? max(paced, pushed) : paced
                    if keepPlannedEnds { end = max(end, e) }
                    let why = end == e ? "" : late > 0 && pushed >= paced ? "เลื่อนตาม \(push!.1.code)"
                        : assumed ? "ยังไม่มีความก้าวหน้า ใช้อัตราตามแผนนับจากสัปดาห์นี้" : "ตามอัตราที่ทำได้จริง"
                    out[t] = Dated(start: s, end: end, why: why, assumed: assumed)
                }
            }
            return out
        }

        /// The finishes if every open task runs at `factor` times its rate, the tasks of `startNow` starting this week.
        static func scenario(_ name: String, plan: [MasterSchedule.PlannedTask], actual: MasterSchedule.Actual,
                             input: MasterSchedule.Input, factor: Double, startNow: Set<MasterSchedule.Task> = [],
                             today: Date, calendar cal: Calendar) -> Scenario {
            let done = Set(MasterSchedule.recovery(plan: plan, actual: actual, today: today, calendar: cal).filter { $0.state == .done }.map(\.task))
            let dated = forecast(plan: plan, actual: actual, factor: factor, startNow: startNow, keepPlannedEnds: false, today: today, calendar: cal)
            let tasks = plan.compactMap { p -> TaskFinish? in
                guard let d = dated[p.task], let e = p.end, !done.contains(p.task) else { return nil }
                return TaskFinish(code: p.task.code, title: p.task.title, plannedEnd: day(e, cal), finish: day(d.end, cal),
                                  slipDays: days(e, d.end, cal), assumedRate: d.assumed)
            }
            let last = dated.values.map(\.end).max()
            return Scenario(name: name, paceFactor: ScheduleBrief.round(factor), stationFinish: last.map { day($0, cal) },
                            slipDays: last.map { days(input.installEnd, $0, cal) },
                            tasks: tasks.sorted { $0.slipDays > $1.slipDays })
        }

        /// What it takes for every open task to end on time.
        static func requirement(_ recovery: [MasterSchedule.Recovery], input: MasterSchedule.Input, crew: Double?,
                                workdays: Int, today: Date, calendar cal: Calendar) -> Requirement? {
            let thisWeek = MasterSchedule.weekStart(today, calendar: cal)
            var worst: (Double, MasterSchedule.Recovery)?
            for r in recovery where r.state != .done {
                let due = r.plannedEnd >= thisWeek ? r.plannedEnd : input.installEnd
                guard due >= thisWeek else { return nil }
                let weeks = Double(MasterSchedule.weeks(from: thisWeek, to: due, calendar: cal).count)
                let f = r.remaining / weeks / Self.rate(r, calendar: cal).0
                if worst == nil || f > worst!.0 { worst = (f, r) }
            }
            guard let (f, r) = worst else { return nil }
            let d = Int((Double(workdays) * f).rounded(.up))
            return Requirement(paceFactor: ScheduleBrief.round(f), bottleneck: "\(r.task.code) \(r.task.title)",
                               crew: crew.map { Int(($0 * f).rounded(.up)) }, workingDaysPerWeek: d <= 7 ? d : nil)
        }

        public static func whatIf(_ job: Job, input: MasterSchedule.Input, crewChange: Int = 0, extraDays: Int = 0,
                                  startNow: Set<MasterSchedule.Task> = [], today: Date,
                                  calendar cal: Calendar = MasterSchedule.calendar) -> WhatIf {
            let plan = MasterSchedule.plan(input, calendar: cal)
            let recovery = MasterSchedule.recovery(plan: plan, actual: job.actual, today: today, calendar: cal)
            let crew = crewAverage(job.dailies, today: today, calendar: cal)
            let workdays = max(job.workingWeekdays.count, 1)
            var notes = [assumption]
            var s: Scenario?
            if crewChange != 0 || extraDays != 0 || !startNow.isEmpty {
                var f = 1.0, parts: [String] = []
                if crewChange != 0 {
                    if let crew, crew > 0 {
                        f *= max(crew + Double(crewChange), 0) / crew
                        parts.append("คน \(crewChange > 0 ? "+" : "")\(crewChange)")
                    } else { notes.append("ไม่มีจำนวนคนในรายงานประจำวัน 14 วัน จึงไม่คิดผลของการเพิ่มคน") }
                }
                if extraDays != 0 {
                    let d = min(max(workdays + extraDays, 1), 7)
                    f *= Double(d) / Double(workdays)
                    parts.append("ทำงาน \(d) วัน/สัปดาห์")
                }
                if !startNow.isEmpty { parts.append("เริ่ม " + startNow.map(\.code).sorted().joined(separator: ", ") + " สัปดาห์นี้") }
                s = scenario(parts.joined(separator: " · "), plan: plan, actual: job.actual, input: input, factor: max(f, 0.1),
                             startNow: startNow, today: today, calendar: cal)
            }
            let brief = ScheduleBrief(jobID: job.id, station: job.station, input: input, actual: job.actual, today: today, calendar: cal)
            return WhatIf(jobID: job.id, station: job.station, today: day(today, cal), installEnd: day(input.installEnd, cal),
                          handoverForecast: brief.handoverForecast, handoverSlipDays: brief.handoverSlipDays,
                          crewAverage: crew.map(ScheduleBrief.round), workingDaysPerWeek: workdays,
                          base: scenario("อัตราเดิม", plan: plan, actual: job.actual, input: input, factor: 1, today: today, calendar: cal),
                          scenario: s,
                          toFinishOnTime: requirement(recovery, input: input, crew: crew, workdays: workdays, today: today, calendar: cal),
                          note: notes.joined(separator: " · "))
        }

        // MARK: Priorities

        public struct StationRisk: Codable, Equatable, Sendable {
            public var jobID: String
            public var station: String
            public var mpNumber: Int?
            public var kWp: Double?
            public var crewGroup: String
            public var variance: Double
            public var projectedSlipDays: Int?
            /// Days late weighted by size (kWp / 100) plus the points behind; higher first.
            public var riskScore: Double
            public var crewAverage: Double?
            /// Crew needed to end on time (`WhatIf.toFinishOnTime`).
            public var crewNeeded: Int?
            /// Crew it could lend and still end on time; only for a station that needs less than it has.
            public var spareCrew: Int?
        }

        public struct GroupWeek: Codable, Equatable, Sendable {
            public var crewGroup: String
            public var week: String
            public var stations: [String]
            public var crewNow: Double
            public var crewNeeded: Int
            public var overloaded: Bool
        }

        public struct Move: Codable, Equatable, Sendable {
            public var crewGroup: String
            public var from: String
            public var to: String
            public var crew: Int
        }

        public struct Priorities: Codable, Equatable, Sendable {
            public var today: String
            public var stations: [StationRisk]
            /// Each crew group's stations with site work in the next four weeks, and the crew they need.
            public var loads: [GroupWeek]
            /// Spare crew of stations ahead, offered to the riskiest of the same group.
            public var moves: [Move]
            public var note: String
            public var json: String { Strategy.text(self) }
        }

        public static func priorities(_ jobs: [Job], today: Date, calendar cal: Calendar = MasterSchedule.calendar) -> Priorities {
            struct Row { var risk: StationRisk; var sitePlan: [MasterSchedule.Recovery]; var factor: Double? }
            let thisWeek = MasterSchedule.weekStart(today, calendar: cal)
            var rows: [Row] = []
            for j in jobs {
                guard let input = j.input, let b = j.brief(today: today) else { continue }
                let plan = MasterSchedule.plan(input, calendar: cal)
                let recovery = MasterSchedule.recovery(plan: plan, actual: j.actual, today: today, calendar: cal)
                let crew = crewAverage(j.dailies, today: today, calendar: cal)
                let req = requirement(recovery, input: input, crew: crew, workdays: max(j.workingWeekdays.count, 1), today: today, calendar: cal)
                let slip = b.projectedSlipDays ?? 0
                let score = Double(max(slip, 0)) * (j.kWp ?? 100) / 100 + max(-b.variance, 0)
                let spare = crew.flatMap { c in req.flatMap { $0.paceFactor < 1 && slip <= 0 ? Int((c * (1 - $0.paceFactor)).rounded(.down)) : nil } }
                rows.append(Row(risk: StationRisk(jobID: j.id, station: j.station, mpNumber: j.mpNumber, kWp: j.kWp,
                                                  crewGroup: j.crewGroup, variance: b.variance, projectedSlipDays: b.projectedSlipDays,
                                                  riskScore: ScheduleBrief.round(score), crewAverage: crew.map(ScheduleBrief.round),
                                                  crewNeeded: req?.crew, spareCrew: spare.flatMap { $0 > 0 ? $0 : nil }),
                                sitePlan: recovery.filter { $0.task.part != .permit && $0.state != .done }, factor: req?.paceFactor))
            }
            rows.sort { $0.risk.riskScore > $1.risk.riskScore }

            var loads: [GroupWeek] = []
            for w in 0..<4 {
                let start = cal.date(byAdding: .day, value: 7 * w, to: thisWeek)!, end = cal.date(byAdding: .day, value: 6, to: start)!
                let busy = rows.filter { r in
                    r.sitePlan.contains { $0.plannedStart <= end && ($0.plannedEnd >= start || $0.state == .overdue) }
                }
                for (group, rs) in Dictionary(grouping: busy, by: \.risk.crewGroup) {
                    let now = rs.compactMap(\.risk.crewAverage).reduce(0, +)
                    let needed = rs.reduce(0) { $0 + ($1.risk.crewNeeded ?? Int(($1.risk.crewAverage ?? 0).rounded(.up))) }
                    loads.append(GroupWeek(crewGroup: group, week: day(start, cal), stations: rs.map(\.risk.station),
                                           crewNow: ScheduleBrief.round(now), crewNeeded: needed, overloaded: Double(needed) > now + 0.5))
                }
            }
            loads.sort { ($0.week, $0.crewGroup) < ($1.week, $1.crewGroup) }

            var moves: [Move] = []
            for (group, rs) in Dictionary(grouping: rows.map(\.risk), by: \.crewGroup) {
                var donors = rs.filter { ($0.spareCrew ?? 0) > 0 }.sorted { ($0.spareCrew ?? 0) > ($1.spareCrew ?? 0) }
                for r in rs where (r.projectedSlipDays ?? 0) > 0 {
                    let short = (r.crewNeeded ?? 0) - Int((r.crewAverage ?? 0).rounded(.down))
                    guard short > 0, !donors.isEmpty else { continue }
                    let d = donors.removeFirst()
                    moves.append(Move(crewGroup: group, from: d.station, to: r.station, crew: min(short, d.spareCrew ?? 0)))
                }
            }
            return Priorities(today: day(today, cal), stations: rows.map(\.risk), loads: loads,
                              moves: moves.sorted { ($0.crewGroup, $0.to) < ($1.crewGroup, $1.to) }, note: assumption)
        }

        // MARK: Look-ahead

        public struct Waiting: Codable, Equatable, Sendable {
            public var code: String
            public var actualPercent: Double
        }

        public struct AheadTask: Codable, Equatable, Sendable {
            public var code: String
            public var title: String
            public var plannedPoints: Double
            public var actualPercent: Double
            public var state: MasterSchedule.Recovery.State?
            /// Predecessors not yet done.
            public var waitingFor: [Waiting]
        }

        public struct AheadWeek: Codable, Equatable, Sendable {
            public var week: String
            public var tasks: [AheadTask]
            public var inspections: [String]
            public var deadlines: [String]
        }

        public struct Weather: Codable, Equatable, Sendable {
            public var reportedDays: Int
            public var rainDays: Int
            public var rainHours: Int
            public var stoppedDays: Int
        }

        public struct LookAhead: Codable, Equatable, Sendable {
            public var jobID: String
            public var station: String
            public var today: String
            public var weeks: [AheadWeek]
            /// Overdue tasks, which every week carries until done.
            public var overdue: [String]
            /// The last 14 days of daily reports.
            public var weather: Weather
            public var openProblems: [String]
            public var json: String { Strategy.text(self) }
        }

        public static func lookAhead(_ job: Job, input: MasterSchedule.Input, weeks count: Int = 3, today: Date,
                                     calendar cal: Calendar = MasterSchedule.calendar) -> LookAhead {
            let plan = MasterSchedule.plan(input, calendar: cal)
            let planned = MasterSchedule.plannedPoints(plan, calendar: cal)
            let status = MasterSchedule.status(plan: plan, actual: job.actual, through: today, calendar: cal)
            let recovery = Dictionary(uniqueKeysWithValues: MasterSchedule.recovery(plan: plan, actual: job.actual, today: today, calendar: cal).map { ($0.task, $0) })
            let pct = { (t: MasterSchedule.Task) in ScheduleBrief.round(status.actualByTask[t] ?? 0) }
            let thisWeek = MasterSchedule.weekStart(today, calendar: cal)
            let weeks = (0..<max(1, min(count, 6))).map { w -> AheadWeek in
                let start = cal.date(byAdding: .day, value: 7 * w, to: thisWeek)!, end = cal.date(byAdding: .day, value: 6, to: start)!
                let tasks = plan.compactMap { p -> AheadTask? in
                    let pts = planned[p.task]?[start] ?? 0
                    guard pts > 0, recovery[p.task]?.state != .done else { return nil }
                    let waiting = (predecessors[p.task] ?? []).filter { input.weight($0) > 0 && pct($0) < 100 }
                        .map { Waiting(code: $0.code, actualPercent: pct($0)) }
                    return AheadTask(code: p.task.code, title: p.task.title, plannedPoints: ScheduleBrief.round(pts),
                                     actualPercent: pct(p.task), state: recovery[p.task]?.state, waitingFor: waiting)
                }
                let inspections = job.inspections.filter { $0.at >= start && $0.at <= cal.date(byAdding: .day, value: 1, to: end)! }
                    .sorted { $0.at < $1.at }.map { day($0.at, cal) + ($0.subject.isEmpty ? "" : " " + $0.subject) }
                let deadlines = job.deadlines.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
                    .map { day($0.date, cal) + " " + $0.title }
                return AheadWeek(week: day(start, cal), tasks: tasks, inspections: inspections, deadlines: deadlines)
            }
            let from = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: today))!
            let recent = job.dailies.filter { $0.date > from && $0.date <= today }
            let weather = Weather(reportedDays: recent.count, rainDays: recent.filter { $0.rainHours > 0 }.count,
                                  rainHours: recent.reduce(0) { $0 + $1.rainHours },
                                  stoppedDays: recent.filter { !$0.stopReason.isEmpty }.count)
            let problems = recent.sorted { $0.date < $1.date }.flatMap { $0.problems.filter { !$0.closed && !$0.description.isEmpty }.map(\.description) }
            return LookAhead(jobID: job.id, station: job.station, today: day(today, cal), weeks: weeks,
                             overdue: plan.filter { recovery[$0.task]?.state == .overdue }.map { "\($0.task.code) \($0.task.title)" },
                             weather: weather, openProblems: problems.reduce(into: []) { if !$0.contains($1) { $0.append($1) } })
        }

        // MARK: Re-plan

        public struct Shift: Codable, Equatable, Sendable {
            public var code: String
            public var title: String
            public var plannedStart: String
            public var plannedEnd: String
            public var newStart: String
            public var newEnd: String
            public var shiftDays: Int
            public var why: String
        }

        public struct Replan: Codable, Equatable, Sendable {
            public var jobID: String
            public var station: String
            public var installEnd: String
            public var newInstallEnd: String
            public var slipDays: Int
            /// Only the tasks whose dates change.
            public var tasks: [Shift]
            public var note: String
            public var json: String { Strategy.text(self) }
        }

        /// A realistic plan from today: a task under way ends when its pace finishes it (never earlier than planned),
        /// and a task not started moves by as much as its predecessors' ends moved, keeping its length and the plan's
        /// overlaps. Finished tasks stay.
        public static func replan(_ job: Job, input: MasterSchedule.Input, today: Date,
                                  calendar cal: Calendar = MasterSchedule.calendar) -> Replan {
            let plan = MasterSchedule.plan(input, calendar: cal)
            let dated = forecast(plan: plan, actual: job.actual, factor: 1, keepPlannedEnds: true, today: today, calendar: cal)
            let shifts = order.compactMap { t -> Shift? in
                guard let p = plan.first(where: { $0.task == t }), let s = p.start, let e = p.end, let d = dated[t],
                      d.start != s || d.end != e else { return nil }
                return Shift(code: t.code, title: t.title, plannedStart: day(s, cal), plannedEnd: day(e, cal),
                             newStart: day(d.start, cal), newEnd: day(d.end, cal), shiftDays: days(e, d.end, cal), why: d.why)
            }
            let siteEnd = dated.filter { $0.key.part != .permit }.map(\.value.end).max() ?? input.installEnd
            let newEnd = max(siteEnd, input.installEnd)
            return Replan(jobID: job.id, station: job.station, installEnd: day(input.installEnd, cal), newInstallEnd: day(newEnd, cal),
                          slipDays: days(input.installEnd, newEnd, cal), tasks: shifts,
                          note: assumption + " · ยืนยันแล้วแผนเดิมจะถูกแทนที่ (ต้องมีสิทธิ์ตั้งค่าแผน)")
        }
    }
}

// MARK: - Tools

extension Assistant.Toolbox {
    func whatIf(_ job: Assistant.Job, _ args: JSONValue) -> Outcome {
        guard let input = job.input else { return error("\(job.station) ยังไม่มีแผน MP") }
        var startNow: Set<MasterSchedule.Task> = []
        if case .array(let codes) = args["start_now"] ?? .array([]) {
            for c in codes {
                guard let t = Self.task(c.string ?? "") else { return error("start_now ต้องเป็นรหัสงาน เช่น 2.3") }
                startNow.insert(t)
            }
        }
        let crew = Int(args["crew_change"]?.number ?? 0), extra = Int(args["extra_days"]?.number ?? 0)
        guard abs(crew) <= 100, abs(extra) <= 6 else { return error("crew_change ±100 และ extra_days ±6 เท่านั้น") }
        return .result(Assistant.Strategy.whatIf(job, input: input, crewChange: crew, extraDays: extra, startNow: startNow,
                                                 today: today, calendar: calendar).json)
    }

    func lookAhead(_ job: Assistant.Job, _ args: JSONValue) -> Outcome {
        guard let input = job.input else { return error("\(job.station) ยังไม่มีแผน MP") }
        return .result(Assistant.Strategy.lookAhead(job, input: input, weeks: Int(args["weeks"]?.number ?? 3), today: today,
                                                    calendar: calendar).json)
    }

    func proposeReplan(_ args: JSONValue) -> Outcome {
        withJob(args) { job, input, plan in
            guard job.canReplan else { return error("ผู้ใช้นี้ไม่มีสิทธิ์แก้แผนของ \(job.station) (ตั้งค่าแผน)") }
            guard case .array(let rows) = args["tasks"] ?? .null, !rows.isEmpty else { return error("tasks ต้องมีอย่างน้อยหนึ่งงาน") }
            var changes: [Assistant.PendingAction.TaskDates] = []
            for row in rows {
                guard let t = Self.task(row["task"]?.string ?? "") else { return error("task ต้องเป็นรหัสงาน เช่น 2.3") }
                guard input.weight(t) > 0 else { return error("\(t.code) ไม่มีน้ำหนักในแผนนี้") }
                guard let s = row["start"]?.string.flatMap({ MasterSchedule.date(fromKey: $0, calendar: calendar) }),
                      let e = row["end"]?.string.flatMap({ MasterSchedule.date(fromKey: $0, calendar: calendar) }) else {
                    return error("\(t.code): start และ end ต้องเป็น yyyy-MM-dd")
                }
                guard e >= s else { return error("\(t.code): end ต้องไม่ก่อน start") }
                guard !changes.contains(where: { $0.task == t }) else { return error("\(t.code) ซ้ำ") }
                changes.append(.init(task: t, start: ScheduleBrief.day(s, calendar: calendar), end: ScheduleBrief.day(e, calendar: calendar)))
            }
            let reason = String((args["reason"]?.string ?? "").prefix(300))
            let draft = Assistant.PendingAction(id: "", jobID: job.id, station: job.station, change: .replan(tasks: changes, reason: reason),
                                                title: "", before: "", after: "")
            let newInput = draft.replanned(input, calendar: calendar) ?? input
            let old = ScheduleBrief.day(input.installEnd, calendar: calendar), new = ScheduleBrief.day(newInput.installEnd, calendar: calendar)
            let byTask = Dictionary(uniqueKeysWithValues: plan.map { ($0.task, $0) })
            let lines = changes.map { c -> String in
                let p = byTask[c.task]
                return "\(c.task.code) \(p?.end.map { ScheduleBrief.day($0, calendar: calendar) } ?? "–") → \(c.end)"
            }
            return propose(job, changes[0].task, .replan(tasks: changes, reason: reason),
                           before: "วันจบติดตั้ง \(old)", after: (["วันจบติดตั้ง \(new)"] + lines).joined(separator: "\n"),
                           title: "แผนใหม่ \(changes.count) งาน" + (reason.isEmpty ? "" : " · \(reason)"))
        }
    }

    static let strategyDefinitions: [JSONValue] = {
        func fn(_ name: String, _ description: String, _ props: [String: JSONValue], required: [String]) -> JSONValue {
            .object(["type": .string("function"), "function": .object([
                "name": .string(name), "description": .string(description),
                "parameters": .object(["type": .string("object"), "properties": .object(props),
                                       "required": .array(required.map(JSONValue.string))]),
            ])])
        }
        func p(_ type: String, _ description: String) -> JSONValue { .object(["type": .string(type), "description": .string(description)]) }
        let job = p("string", "รหัสงาน (jobID), เลข MP เช่น 189 หรือส่วนหนึ่งของชื่อสถานี")
        return [
            fn("what_if", "จำลองแผนเร่งงานของสถานีหนึ่ง: วันจบของแต่ละงานด้วยอัตราเดิม และเมื่อเพิ่มคน เพิ่มวันทำงาน หรือเริ่มงานที่ยังไม่เริ่มสัปดาห์นี้ พร้อมสิ่งที่ต้องทำเพื่อให้ทันแผน (คน วันทำงาน งานคอขวด)",
               ["job": job, "crew_change": p("integer", "จำนวนคนที่เพิ่ม (ลบ = ลด) เทียบกับค่าเฉลี่ย 14 วัน"),
                "extra_days": p("integer", "วันทำงานต่อสัปดาห์ที่เพิ่ม เช่น 1 = ทำเสาร์หรืออาทิตย์เพิ่ม"),
                "start_now": .object(["type": .string("array"), "items": .object(["type": .string("string")]),
                                      "description": .string("รหัสงานที่ยังไม่เริ่มที่จะเริ่มคู่ขนานสัปดาห์นี้ เช่น [\"2.3\"]")])],
               required: ["job"]),
            fn("station_priorities", "จัดลำดับความเสี่ยงทุกสถานี (วันที่ช้า × ขนาด kWp) ภาระคนของแต่ละผู้รับเหมา/ทีม 4 สัปดาห์ข้างหน้า และสถานีที่มีคนเหลือพอย้ายไปช่วย",
               [:], required: []),
            fn("look_ahead", "แผนล่วงหน้ารายสัปดาห์ของสถานีหนึ่ง: งานแต่ละสัปดาห์ งานก่อนหน้าที่ยังไม่เสร็จ นัดตรวจ กำหนดส่งเอกสาร ฝนและวันหยุดงาน 14 วัน ปัญหาค้าง",
               ["job": job, "weeks": p("integer", "จำนวนสัปดาห์ 1–6 (ค่าเริ่มต้น 3)")], required: ["job"]),
            fn("suggest_replan", "ร่างแผนใหม่ที่ทำได้จริงจากวันนี้: วันเริ่ม/จบใหม่ของงานที่ต้องเลื่อน และวันจบติดตั้งใหม่ ใช้ก่อน propose_replan",
               ["job": job], required: ["job"]),
            fn("propose_replan", "เสนอแผนใหม่ (แทนวันตามแผนของงาน) ผู้มีสิทธิ์ตั้งค่าแผนต้องกดยืนยันก่อนบันทึก ใช้วันที่จาก suggest_replan",
               ["job": job, "reason": p("string", "เหตุผลสั้น ๆ"),
                "tasks": .object(["type": .string("array"), "description": .string("งานที่เปลี่ยนวัน"),
                                  "items": .object(["type": .string("object"), "properties": .object([
                                      "task": p("string", "รหัสงาน เช่น 2.3"), "start": p("string", "yyyy-MM-dd"), "end": p("string", "yyyy-MM-dd")]),
                                      "required": .array(["task", "start", "end"].map(JSONValue.string))])])],
               required: ["job", "tasks"]),
        ]
    }()
}
