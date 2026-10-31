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
        public let status: InstallGantt.Status
        public let percent: Double
        /// Working days it can slip; nil for a sub-task with no days of its own (a place from the daily reports).
        public var float: Int?
        public var critical: Bool
        public var crew: Int?
        /// `ต่อจาก`: the WBS code it follows.
        public var after: String?
        /// Its dates in the baseline (`useBaseline`), drawn under its bar; nil without one.
        public var baselineStart: Date?
        public var baselineEnd: Date?

        public var days: Int { (MasterSchedule.calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }
    }

    public struct Stage: Equatable, Sendable, Identifiable {
        public var row: Row
        public var subs: [Row]
        public var id: String { row.id }
    }

    public struct Milestone: Equatable, Sendable, Identifiable {
        public let title: String
        public let date: Date
        public var id: String { title }
        public init(title: String, date: Date) { self.title = title; self.date = date }
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
    }

    /// Every day from the first start to the last end.
    public var days: [Date] {
        var out: [Date] = [], d = start
        while d <= end, let next = MasterSchedule.calendar.date(byAdding: .day, value: 1, to: d) { out.append(d); d = next }
        return out
    }

    public static func isSunday(_ d: Date) -> Bool { MasterSchedule.calendar.component(.weekday, from: d) == 1 }

    /// `วันทำงาน`: the span without Sundays and the hatched days.
    public var workingDays: Int {
        days.filter { day in
            let works = dependencyWorkingWeekdays.map { $0.contains(MasterSchedule.calendar.component(.weekday, from: day)) } ?? !Self.isSunday(day)
            return works && !nonWorking.contains(day)
        }.count
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
