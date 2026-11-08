import Foundation

/// The iPad install tracking page's `แผนก่อสร้าง` tab (docs/ui/install-tracking-ipad-v2 §6): the install plan by WBS,
/// its stages (the MP plan's install tasks, as `InstallGantt` rows) and their sub-tasks, with float and the critical
/// path from `InstallCriticalPath`, or the explicit WBS graph when configured. Baselines and predecessor labels
/// come from the WBS; crew and make-ready details remain optional.
public struct InstallPlan: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let id: String
        /// `4` a stage, `4.1` a sub-task.
        public let code: String
        public let title: String
        public var start: Date
        public var end: Date
        /// A stage's is rolled up from its sub-tasks (`settle`).
        public var status: InstallGantt.Status
        public var percent: Double
        /// Working days it can slip; nil for a sub-task with no days of its own (a place from the daily reports).
        public var float: Int?
        public var critical: Bool
        public var crew: Int?
        /// `ต่อจาก`: the WBS code it follows.
        public var after: String?
        /// Its dates in the baseline (`useBaseline`), drawn under its bar; nil without one.
        public var baselineStart: Date?
        public var baselineEnd: Date?

        /// Calendar days, Sundays included; `InstallPlan.workingDays(of:)` counts the working ones.
        public var days: Int { (MasterSchedule.calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }

        /// Not done and past its end: late work drives the finish, so it is on the critical path whatever its dates say.
        public func overdue(today: Date) -> Bool { status != .done && end < today }
    }

    public struct Stage: Equatable, Sendable, Identifiable {
        public var row: Row
        public var subs: [Row]
        /// Its sub-tasks are the plan file's WBS rows (`useWBS`), its whole checklist; otherwise they are the places the
        /// daily reports named so far, which can't say the stage is done.
        public var fromWBS = false
        public var id: String { row.id }
        public init(row: Row, subs: [Row], fromWBS: Bool = false) { self.row = row; self.subs = subs; self.fromWBS = fromWBS }
    }

    public struct Milestone: Equatable, Sendable, Identifiable {
        public let title: String
        public let date: Date
        /// The work it marks is complete; nil when nothing links it to work (then a past date counts as passed).
        public var done: Bool?
        public var id: String { title }
        public init(title: String, date: Date, done: Bool? = nil) { self.title = title; self.date = date; self.done = done }

        public enum State: Equatable, Sendable {
            /// `ผ่านแล้ว`
            case done
            /// `เลยกำหนด`: its day has passed and its work isn't complete.
            case overdue
            /// `วันนี้`
            case today
            /// `อีก n วัน`
            case ahead(Int)
        }

        /// By the work's completion first, then by the date.
        public func state(today: Date, calendar cal: Calendar = MasterSchedule.calendar) -> State {
            if done == true { return .done }
            let left = cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: date)).day ?? 0
            if left < 0 { return done == nil ? .done : .overdue }
            return left == 0 ? .today : .ahead(left)
        }
    }

    public struct Baseline: Equatable, Sendable {
        public let revision: String
        public let approved: Date
        public let by: String
        public init(revision: String, approved: Date, by: String) { self.revision = revision; self.approved = approved; self.by = by }
    }

    /// `ความพร้อมขั้นถัดไป`: the next stage and what it still needs.
    public struct Ready: Equatable, Sendable {
        public struct Item: Equatable, Sendable {
            public let label: String
            public let ok: Bool
            public let note: String
            public init(_ label: String, ok: Bool, note: String) { self.label = label; self.ok = ok; self.note = note }
        }
        public let stage: String
        public let items: [Item]
        public init(stage: String, items: [Item]) { self.stage = stage; self.items = items }
    }

    public var stages: [Stage]
    public var start: Date
    public var end: Date
    public var dependencyIssues: [WBSDependencies.Issue] = []
    var dependencyWorkingWeekdays: Set<Int>?
    public let today: Date
    /// Days off and days waiting (hatched), as on the overview.
    public var nonWorking: Set<Date>
    /// `ตามแผน` / `ช้ากว่าแผน`; nil without a tracking figure.
    public var onPlan: Bool?
    /// The one schedule status the header shows (CHA-64), from the progress against the plan to date.
    public var schedule: InstallTracking.Schedule?
    /// Calendar days the work is behind the plan (negative: ahead), by earned schedule (today against the day the plan
    /// reached today's percent), else from the forecast end; nil without a tracking figure.
    public var lateDays: Int?
    public var milestones: [Milestone]
    /// Planned crew per day; empty when nothing plans it.
    public var crew: [Date: Int]
    /// The team's size, for the crew chart's dashed line; the app keeps none.
    public var teamSize: Int?
    public var baseline: Baseline?
    public var ready: Ready?

    public init(gantt g: InstallGantt, nonWorking: Set<Date>, tracking: InstallTracking?, milestones: [Milestone] = [], crew: [Date: Int] = [:],
                calendar cal: Calendar = MasterSchedule.calendar) {
        let span = g.span(calendar: cal) ?? g.today...g.today
        start = span.lowerBound
        end = span.upperBound
        today = cal.startOfDay(for: g.today)
        self.nonWorking = nonWorking
        onPlan = tracking.map { $0.schedule != .behind }
        schedule = tracking?.schedule
        lateDays = tracking.map { t in
            if let earned = t.earned { return cal.dateComponents([.day], from: cal.startOfDay(for: earned), to: cal.startOfDay(for: t.today)).day ?? 0 }
            return -t.slackDays(calendar: cal)
        }
        self.milestones = milestones
        self.crew = crew
        let float = InstallCriticalPath.float(g.rows.map { .init(id: $0.id, start: $0.start, end: $0.end) }, nonWorking: nonWorking, calendar: cal)
        let day = today
        stages = g.rows.map { r in
            let f = float[r.id]
            let stage = Row(id: r.id, code: r.code, title: r.title, start: cal.startOfDay(for: r.start), end: cal.startOfDay(for: r.end),
                            status: r.status, percent: r.percent, float: f, critical: f == 0 && r.status != .done)
            let subs = r.subs.enumerated().map { k, s -> Row in
                let done = s.percent >= 99.95
                let own = s.start != nil && s.end != nil
                let a = cal.startOfDay(for: s.start ?? r.start), b = cal.startOfDay(for: s.end ?? r.end)
                let status: InstallGantt.Status = done || r.status == .done ? .done
                    : s.percent > 0 || (r.status == .current && a <= day) ? .current : .waiting
                let sf = own ? InstallCriticalPath.float(subEnd: b, stageEnd: stage.end, nonWorking: nonWorking, calendar: cal) : nil
                return Row(id: r.id + "-\(k)", code: "\(r.code).\(k + 1)", title: s.title, start: a, end: b, status: status,
                           percent: done ? 100 : s.percent, float: sf, critical: sf == 0 && status != .done && stage.critical)
            }
            return Stage(row: stage, subs: subs)
        }
        settle()
    }

    /// After the rows are set (here and after `useWBS`): each stage rolls up its sub-tasks' status and progress, and
    /// late work joins the critical path (CHA-64).
    mutating func settle() {
        for i in stages.indices {
            let subs = stages[i].subs
            if !subs.isEmpty {
                var row = stages[i].row
                if stages[i].fromWBS, subs.allSatisfy({ $0.status == .done }) {
                    row.status = .done
                } else if row.status == .waiting, subs.contains(where: { $0.status != .waiting }) {
                    row.status = .current
                }
                // progress by days: a sub-task's percent of its share of the stage's sub-task days
                let total = subs.reduce(0) { $0 + $1.days }
                if total > 0 {
                    let rolled = subs.reduce(0.0) { $0 + $1.percent * Double($1.days) } / Double(total)
                    row.percent = row.status == .done ? 100 : max(row.percent, rolled)
                }
                stages[i].row = row
            }
            for j in stages[i].subs.indices {
                var sub = stages[i].subs[j]
                if stages[i].row.status == .done { sub.status = .done; sub.percent = 100 }
                if sub.overdue(today: today) { sub.critical = true; sub.float = 0 }
                if sub.status == .done { sub.critical = false }
                stages[i].subs[j] = sub
            }
            var row = stages[i].row
            if row.overdue(today: today) || stages[i].subs.contains(where: \.critical) { row.critical = true }
            if row.overdue(today: today) { row.float = 0 }
            if row.status == .done { row.critical = false }
            stages[i].row = row
        }
    }

    /// The header's status: `ช้ากว่าแผน 3 วัน`, `ตามแผน`, `เร็วกว่าแผน 2 วัน`; nil without a tracking figure.
    public var scheduleText: String? {
        guard let schedule else { return nil }
        let n = abs(lateDays ?? 0)
        switch schedule {
        case .onPlan: return "ตามแผน"
        case .behind: return n > 0 ? "ช้ากว่าแผน \(n) วัน" : "ช้ากว่าแผน"
        case .ahead: return n > 0 ? "เร็วกว่าแผน \(n) วัน" : "เร็วกว่าแผน"
        }
    }

    /// Every day from the first start to the last end.
    public var days: [Date] {
        var out: [Date] = [], d = start
        while d <= end, let next = MasterSchedule.calendar.date(byAdding: .day, value: 1, to: d) { out.append(d); d = next }
        return out
    }

    public static func isSunday(_ d: Date) -> Bool { MasterSchedule.calendar.component(.weekday, from: d) == 1 }

    /// `วันทำงาน`: the span without Sundays and the hatched days.
    public var workingDays: Int { days.filter(isWorking).count }

    /// A row's working days, as the `วันทำงาน` column counts them (CHA-64): its calendar days without the days off.
    public func workingDays(of row: Row) -> Int {
        var n = 0, d = row.start
        while d <= row.end, let next = MasterSchedule.calendar.date(byAdding: .day, value: 1, to: d) {
            if isWorking(d) { n += 1 }
            d = next
        }
        return n
    }

    public func isWorking(_ day: Date) -> Bool {
        let works = dependencyWorkingWeekdays.map { $0.contains(MasterSchedule.calendar.component(.weekday, from: day)) } ?? !Self.isSunday(day)
        return works && !nonWorking.contains(MasterSchedule.calendar.startOfDay(for: day))
    }

    public var subCount: Int { stages.reduce(0) { $0 + $1.subs.count } }

    /// The stage after the running one, for `ความพร้อมขั้นถัดไป`.
    public var nextStage: Stage? {
        let i = stages.lastIndex { $0.row.status != .waiting }.map { $0 + 1 } ?? 0
        return stages.indices.contains(i) ? stages[i] : nil
    }

    /// Planned crew per day over the span, and the days over the team.
    public var crewDays: [(date: Date, count: Int)] { days.map { ($0, crew[$0] ?? 0) } }
    public var overTeam: [Date] { teamSize.map { cap in crewDays.filter { $0.count > cap }.map(\.date) } ?? [] }
}
