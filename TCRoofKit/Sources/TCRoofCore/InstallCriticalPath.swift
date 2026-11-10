import Foundation

/// The critical path of an install plan (docs/ui/install-tracking-ipad-v2 §6), for the `แผนก่อสร้าง` tab's red
/// outlines and float tails, and the assistant's `floatDays`. A plan whose WBS has links (FS, SS, FF; `WBSDependencies`)
/// takes its critical path and float from them (`float(wbs:…)`, CHA-77). Without links the MP plan keeps no
/// predecessors, so they are read from the dates: a task follows every task that ends on or before the day it starts
/// (finish → start). Float is counted in working days, so days off and days waiting on the utility between two tasks
/// are not spare time.
public enum InstallCriticalPath {
    public struct Task: Equatable, Sendable {
        public var id: String
        public var start: Date
        public var end: Date
        public init(id: String, start: Date, end: Date) { self.id = id; self.start = start; self.end = end }
    }

    /// Each task's float: the working days it can slip before it moves the plan's last end.
    public static func float(_ tasks: [Task], nonWorking: Set<Date> = [], calendar cal: Calendar = MasterSchedule.calendar) -> [String: Int] {
        guard let first = tasks.map(\.start).min(), let last = tasks.map(\.end).max() else { return [:] }
        let off = Set(nonWorking.map { cal.startOfDay(for: $0) })
        // the working day count from the first start: a day off takes the number of the working day before it
        var ordinal: [Date: Int] = [:]
        var n = 0, d = cal.startOfDay(for: first)
        let end = cal.startOfDay(for: last)
        while d <= end {
            if !off.contains(d) { n += 1 }
            ordinal[d] = n
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        func endIndex(_ date: Date) -> Int { ordinal[cal.startOfDay(for: date)] ?? 0 }
        // a task that starts on a day off starts on the next working day
        func startIndex(_ date: Date) -> Int {
            let day = cal.startOfDay(for: date)
            return (ordinal[day] ?? 0) + (off.contains(day) ? 1 : 0)
        }
        let finish = endIndex(last)
        var out: [String: Int] = [:]
        // a task's successors start no earlier than it ends, so the latest ends are settled first
        for t in tasks.sorted(by: { ($0.end, $0.start) > ($1.end, $1.start) }) {
            let e = endIndex(t.end)
            let next = tasks.filter { $0.id != t.id && cal.startOfDay(for: $0.start) >= cal.startOfDay(for: t.end) && out[$0.id] != nil }
            let viaNext = next.map { max(startIndex($0.start) - e - 1, 0) + (out[$0.id] ?? 0) }
            out[t.id] = viaNext.min() ?? max(finish - e, 0)
        }
        return out
    }

    /// The tasks with no float.
    public static func critical(_ tasks: [Task], nonWorking: Set<Date> = [], calendar cal: Calendar = MasterSchedule.calendar) -> Set<String> {
        Set(float(tasks, nonWorking: nonWorking, calendar: cal).filter { $0.value == 0 }.map(\.key))
    }

    /// A sub-task's float inside its stage: the working days from its end to the stage's end.
    public static func float(subEnd: Date, stageEnd: Date, nonWorking: Set<Date> = [], calendar cal: Calendar = MasterSchedule.calendar) -> Int {
        let off = Set(nonWorking.map { cal.startOfDay(for: $0) })
        var n = 0, d = cal.startOfDay(for: subEnd)
        let last = cal.startOfDay(for: stageEnd)
        while d < last {
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
            if !off.contains(d) { n += 1 }
        }
        return n
    }

    /// Each MP task's float (keyed by `Task.rawValue`) from the plan's WBS links, PMBOK's critical path method: the
    /// least float of its task line and its sub-tasks in `WBSDependencies`' forward and backward passes. The rows are
    /// first moved with their task's start in the plan (`starts`, as `แผนก่อสร้าง` moves them). Nil when the WBS has
    /// no links or they don't hold together, so the caller keeps the date-based float.
    public static func float(wbs items: [MasterSchedule.WorkItem], starts: [String: Date], nonWorking: Set<Date> = [],
                             settings: RoutineReport.Settings? = nil, calendar cal: Calendar = MasterSchedule.calendar) -> [String: Int]? {
        let result = schedule(wbs: items, starts: starts, nonWorking: nonWorking, settings: settings, calendar: cal)
        guard let result, result.isValid, !result.forecasts.isEmpty else { return nil }
        return byTask(result, items)
    }

    /// `WBSDependencies.schedule` on the rows moved with their task's start; nil without links.
    static func schedule(wbs items: [MasterSchedule.WorkItem], starts: [String: Date], nonWorking: Set<Date>,
                         settings: RoutineReport.Settings?, calendar cal: Calendar) -> WBSDependencies.Result? {
        guard items.contains(where: { !($0.dependencies ?? []).isEmpty }) else { return nil }
        let projected = items.map { item -> MasterSchedule.WorkItem in
            guard let task = item.task, let start = starts[task.rawValue],
                  let base = items.first(where: { $0.code == task.code })?.baselineStart else { return item }
            let shift = cal.dateComponents([.day], from: cal.startOfDay(for: base), to: cal.startOfDay(for: start)).day ?? 0
            return item.shifted(days: shift, calendar: cal)
        }
        return WBSDependencies.schedule(projected, nonWorking: nonWorking, settings: settings, calendar: cal)
    }

    /// The least float of each task's rows in the forecast.
    static func byTask(_ result: WBSDependencies.Result, _ items: [MasterSchedule.WorkItem]) -> [String: Int] {
        var out: [String: Int] = [:]
        for item in items {
            guard let task = item.task, let f = result.forecasts[item.code]?.float else { continue }
            out[task.rawValue] = min(out[task.rawValue] ?? .max, f)
        }
        return out
    }
}
