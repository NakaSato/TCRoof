import Foundation

/// แผนก่อสร้าง's sub rows from the plan file's WBS (docs/specs/project-plan-wbs.md, step 4).
public extension InstallPlan {
    /// Puts each stage's WBS sub-tasks in place of the daily reports' places: their baseline dates moved by as much as
    /// the stage has moved from the file's own line for it (a re-plan in the app moves them along), done when ticked or
    /// when the stage is. The other case's rows and rows without dates are left out; a stage the WBS has nothing for
    /// keeps its places.
    mutating func useWBS(_ items: [MasterSchedule.WorkItem], ticked: Set<String>, calendar cal: Calendar = MasterSchedule.calendar) {
        let day = today, nonWorking = nonWorking
        for i in stages.indices {
            let stage = stages[i].row
            guard let task = MasterSchedule.Task(rawValue: stage.id) else { continue }
            let subs = items.items(for: task).filter { !$0.notForThisStation && $0.baselineStart != nil && $0.baselineEnd != nil }
            guard !subs.isEmpty else { continue }
            let line = items.first { $0.code == task.code }?.baselineStart.map { cal.startOfDay(for: $0) }
            let shift = line.flatMap { cal.dateComponents([.day], from: $0, to: stage.start).day } ?? 0
            func move(_ d: Date) -> Date { cal.date(byAdding: .day, value: shift, to: cal.startOfDay(for: d)) ?? d }
            stages[i].subs = subs.map { item in
                let a = move(item.baselineStart!), b = max(move(item.baselineEnd!), a)
                let done = ticked.contains(item.code) || stage.status == .done
                let status: InstallGantt.Status = done ? .done : stage.status == .current && a <= day ? .current : .waiting
                let float = InstallCriticalPath.float(subEnd: b, stageEnd: stage.end, nonWorking: nonWorking, calendar: cal)
                return Row(id: stage.id + "-" + item.code, code: item.code, title: item.title.trimmingCharacters(in: .whitespaces),
                           start: a, end: b, status: status, percent: done ? 100 : 0, float: float,
                           critical: float == 0 && status != .done && stage.critical)
            }
        }
    }
}
