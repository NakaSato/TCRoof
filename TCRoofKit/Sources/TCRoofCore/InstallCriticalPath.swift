import Foundation

/// The critical path of an install plan (docs/ui/install-tracking-ipad-v2 §6), for the `แผนก่อสร้าง` tab's red
/// outlines and float tails. The MP plan keeps no predecessors, so the links are read from the dates: a task follows
/// every task that ends on or before the day it starts (finish → start). Float is counted in working days, so days
/// off and days waiting on the utility between two tasks are not spare time.
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
}
