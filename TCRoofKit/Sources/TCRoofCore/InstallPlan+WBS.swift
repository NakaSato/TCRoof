import Foundation

/// แผนก่อสร้าง's sub rows from the plan file's WBS (docs/specs/project-plan-wbs.md, step 4).
public extension InstallPlan {
    /// Puts each stage's WBS sub-tasks in place of the daily reports' places: their baseline dates moved by as much as
    /// the stage has moved from the file's own line for it (a re-plan in the app moves them along), done when ticked or
    /// when the stage is. The other case's rows and rows without dates are left out; a stage the WBS has nothing for
    /// keeps its places.
    mutating func useWBS(_ items: [MasterSchedule.WorkItem], ticked: Set<String>, settings: RoutineReport.Settings? = nil,
                         calendar cal: Calendar = MasterSchedule.calendar) {
        defer { settle() }
        let day = today, nonWorking = nonWorking
        for i in stages.indices {
            let stage = stages[i].row
            guard let task = MasterSchedule.Task(rawValue: stage.id) else { continue }
            let subs = items.items(for: task).filter { !$0.notForThisStation && $0.baselineStart != nil && $0.baselineEnd != nil }
            guard !subs.isEmpty else { continue }
            let line = items.first { $0.code == task.code }?.baselineStart.map { cal.startOfDay(for: $0) }
            let shift = line.flatMap { cal.dateComponents([.day], from: $0, to: stage.start).day } ?? 0
            func move(_ d: Date) -> Date { cal.date(byAdding: .day, value: shift, to: cal.startOfDay(for: d)) ?? d }
            stages[i].fromWBS = true
            stages[i].subs = subs.map { item in
                let a = move(item.baselineStart!), b = max(move(item.baselineEnd!), a)
                let done = ticked.contains(item.code) || stage.status == .done
                let status: InstallGantt.Status = done ? .done : stage.status == .current && a <= day ? .current : .waiting
                let float = InstallCriticalPath.float(subEnd: b, stageEnd: stage.end, nonWorking: nonWorking, calendar: cal)
                var row = Row(id: stage.id + "-" + item.code, code: item.code, title: item.title.trimmingCharacters(in: .whitespaces),
                              start: a, end: b, status: status, percent: done ? 100 : 0, float: float,
                              critical: float == 0 && status != .done && stage.critical)
                // the file's own dates are the sub-task's baseline
                row.baselineStart = cal.startOfDay(for: item.baselineStart!)
                row.baselineEnd = max(cal.startOfDay(for: item.baselineEnd!), row.baselineStart!)
                return row
            }
        }
        // Keep the legacy plan byte-for-byte in behavior until a link is explicitly configured.
        guard items.contains(where: { !($0.dependencies ?? []).isEmpty }) else { dependencyIssues = []; return }
        let starts = Dictionary(stages.map { ($0.id, $0.row.start) }, uniquingKeysWith: { first, _ in first })
        guard let result = InstallCriticalPath.schedule(wbs: items, starts: starts, nonWorking: nonWorking, settings: settings, calendar: cal)
        else { dependencyIssues = []; return }
        dependencyIssues = result.issues
        guard result.isValid else { return }
        // the links decide every stage's float (CHA-77), a stage without WBS rows of its own too
        let taskFloat = InstallCriticalPath.byTask(result, items)
        dependencyWorkingWeekdays = settings?.workingWeekdays
        let byCode = Dictionary(items.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        for i in stages.indices {
            // a task line's own links (the workbook's `2.1 SS+3, 2.1 FF+2`) show on the stage's bar
            if let task = MasterSchedule.Task(rawValue: stages[i].row.id), let links = byCode[task.code]?.dependencies, !links.isEmpty {
                stages[i].row.after = links.map(\.label).joined(separator: ", ")
            }
            for j in stages[i].subs.indices {
                let code = stages[i].subs[j].code
                guard let forecast = result.forecasts[code] else { continue }
                stages[i].subs[j].start = forecast.start
                stages[i].subs[j].end = forecast.end
                stages[i].subs[j].float = forecast.float
                stages[i].subs[j].critical = forecast.critical && stages[i].subs[j].status != .done
                let links = byCode[code]?.dependencies ?? []
                stages[i].subs[j].after = links.isEmpty ? nil : links.map(\.label).joined(separator: ", ")
            }
            // Summary bars expand to contain their forecast children; locked baseline dates stay on each row.
            for j in stages[i].subs.indices {
                let prefix = stages[i].subs[j].code + "."
                let children = stages[i].subs.filter { $0.code.hasPrefix(prefix) }
                if let first = children.map(\.start).min(), let last = children.map(\.end).max() {
                    stages[i].subs[j].start = first; stages[i].subs[j].end = last
                    stages[i].subs[j].float = children.compactMap(\.float).min()
                    stages[i].subs[j].critical = children.contains(where: \.critical)
                }
            }
            if let last = stages[i].subs.map(\.end).max() { stages[i].row.end = max(stages[i].row.end, last) }
            let float = taskFloat[stages[i].row.id] ?? stages[i].subs.compactMap(\.float).min()
            stages[i].row.float = float ?? stages[i].row.float
            stages[i].row.critical = (stages[i].subs.contains(where: \.critical) || float == 0) && stages[i].row.status != .done
        }
        end = stages.map { $0.row.end }.max() ?? end
        if let settings {
            var date = start
            while date <= end {
                if !RoutineReport.isWorkingDay(date, settings: settings) { self.nonWorking.insert(cal.startOfDay(for: date)) }
                guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
                date = next
            }
        }
    }
}
