import Foundation
import TCRoofCore

/// What the `แผนก่อสร้าง` tab shows (docs/ui/install-tracking-ipad-v2 §6): the install plan by WBS, its stages (the MP
/// plan's install tasks) and their sub-tasks, with float and the critical path from `InstallCriticalPath`. The MP plan
/// keeps no crew per task, no predecessors, no baseline revision and no make-ready list, so those stay nil and the tab
/// hides them; only `-installDemo YES` fills them with the board's example.
struct InstallPlanData {
    struct Row: Identifiable {
        let id: String
        /// `4` a stage, `4.1` a sub-task.
        let code: String
        let title: String
        let start: Date
        let end: Date
        let status: InstallGantt.Status
        let percent: Double
        /// Working days it can slip; nil for a sub-task with no days of its own (a place from the daily reports).
        let float: Int?
        let critical: Bool
        var crew: Int?
        /// `ต่อจาก`: the WBS code it follows.
        var after: String?

        var days: Int { (MasterSchedule.calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }
    }

    struct Stage: Identifiable {
        var row: Row
        var subs: [Row]
        var id: String { row.id }
    }

    struct Milestone: Identifiable {
        let title: String
        let date: Date
        var id: String { title }
    }

    struct Baseline {
        let revision: String
        let approved: Date
        let by: String
    }

    struct Ready {
        let stage: String
        let items: [(label: String, ok: Bool, note: String)]
    }

    var stages: [Stage]
    let start: Date
    let end: Date
    let today: Date
    /// Days off and days waiting (hatched), as on the overview.
    let nonWorking: Set<Date>
    /// `ตามแผน` / `ช้ากว่าแผน`; nil without a tracking figure.
    var onPlan: Bool?
    var milestones: [Milestone]
    /// Planned crew per day; empty when nothing plans it.
    var crew: [Date: Int]
    /// The team's size, for the crew chart's dashed line; the app keeps none.
    var teamSize: Int?
    var baseline: Baseline?
    var ready: Ready?

    init(gantt g: InstallGantt, nonWorking: Set<Date>, tracking: InstallTracking?, milestones: [Milestone], crew: [Date: Int]) {
        let cal = MasterSchedule.calendar
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
    var days: [Date] {
        var out: [Date] = [], d = start
        while d <= end, let next = MasterSchedule.calendar.date(byAdding: .day, value: 1, to: d) { out.append(d); d = next }
        return out
    }

    static func isSunday(_ d: Date) -> Bool { MasterSchedule.calendar.component(.weekday, from: d) == 1 }

    /// `วันทำงาน`: the span without Sundays and the hatched days.
    var workingDays: Int { days.filter { !Self.isSunday($0) && !nonWorking.contains($0) }.count }

    var subCount: Int { stages.reduce(0) { $0 + $1.subs.count } }

    /// The stage after the running one, for `ความพร้อมขั้นถัดไป`.
    var nextStage: Stage? {
        let i = stages.lastIndex { $0.row.status != .waiting }.map { $0 + 1 } ?? 0
        return stages.indices.contains(i) ? stages[i] : nil
    }

    /// Planned crew per day over the span, and the days over the team.
    var crewDays: [(date: Date, count: Int)] { days.map { ($0, crew[$0] ?? 0) } }
    var overTeam: [Date] { teamSize.map { cap in crewDays.filter { $0.count > cap }.map(\.date) } ?? [] }
}

#if DEBUG
extension InstallPlanData {
    /// The board's crew, links, baseline and make-ready, for screenshots only.
    static func demo(gantt: InstallGantt, nonWorking: Set<Date>, tracking: InstallTracking?, day: Date) -> InstallPlanData {
        func d(_ i: Int) -> Date { day.adding(days: i - 6) }
        let stageCrew = [6, 8, 8, 7, 4, 3, 4]
        let subCrew = [[6, 2, 2, 2], [2, 4, 4, 4, 2], [8, 3, 3, 2, 2], [4, 3, 3, 2, 2], [2, 2, 2, 2, 1], [3, 2, 2, 2, 1], [2, 4, 2, 2, 2]]
        var x = InstallPlanData(gantt: gantt, nonWorking: nonWorking, tracking: tracking,
                                milestones: [.init(title: "เริ่มงานหน้างาน", date: d(0)), .init(title: "ติดตั้งแผงครบ 164 แผง", date: d(4)),
                                             .init(title: "ทดสอบ IEC 62446-1", date: d(9)), .init(title: "ขนานไฟ · ส่งมอบ กปภ.", date: d(12))],
                                crew: [:])
        for i in x.stages.indices {
            x.stages[i].row.crew = stageCrew[i]
            x.stages[i].row.after = i == 0 ? nil : "\(i)"
            for k in x.stages[i].subs.indices {
                x.stages[i].subs[k].crew = subCrew[i][k]
                x.stages[i].subs[k].after = k > 0 ? "\(i + 1).\(k)" : i > 0 ? "\(i)" : nil
            }
        }
        x.crew = Dictionary(uniqueKeysWithValues: x.days.map { day in
            (day, x.stages.enumerated().reduce(0) { $0 + ($1.element.row.start <= day && day <= $1.element.row.end ? stageCrew[$1.offset] : 0) })
        })
        x.teamSize = 8
        x.baseline = Baseline(revision: "Baseline REV 01", approved: d(-2), by: "ผู้ควบคุมงาน กปภ.")
        x.ready = Ready(stage: "ขั้น 5 · อินเวอร์เตอร์ · ระบบ AC",
                        items: [("วัสดุ", false, "ตู้ AC รออนุมัติ MA-05"), ("ใบอนุญาต", true, "WP-02 งานไฟฟ้า"), ("ทีม", true, "TCR02 · 4 คน")])
        return x
    }
}
#endif
