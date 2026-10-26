import Foundation

/// แผนก่อสร้าง against its baseline (docs/specs/project-plan-wbs.md, step 4): each stage's baseline dates under its bar
/// and how many days its end has moved.
public extension InstallPlan.Row {
    /// Days its end moved from the baseline's end: positive when later, negative when earlier; nil without a baseline.
    var slip: Int? {
        baselineEnd.map { MasterSchedule.calendar.dateComponents([.day], from: $0, to: end).day ?? 0 }
    }
}

public extension InstallPlan {
    /// The baseline's dates by task raw value: the plan before its first re-plan (`Input.baseline`), else the plan
    /// file's locked Baseline columns on each task's WBS line. Empty when there is neither.
    static func baselineDates(input: MasterSchedule.Input, wbs: [MasterSchedule.WorkItem],
                              calendar cal: Calendar = MasterSchedule.calendar) -> [String: ClosedRange<Date>] {
        var out: [String: ClosedRange<Date>] = [:]
        func put(_ key: String, _ a: Date?, _ b: Date?) {
            guard let a, let b else { return }
            let s = cal.startOfDay(for: a)
            out[key] = s...max(cal.startOfDay(for: b), s)
        }
        if let base = input.baseline {
            for (key, t) in base { put(key, t.start, t.end) }
        } else {
            for task in MasterSchedule.Task.allCases {
                guard let line = wbs.first(where: { $0.code == task.code }) else { continue }
                put(task.rawValue, line.baselineStart, line.baselineEnd)
            }
        }
        return out
    }

    /// Gives each stage its baseline dates (by stage id, the task's raw value).
    mutating func useBaseline(_ dates: [String: ClosedRange<Date>]) {
        for i in stages.indices {
            guard let r = dates[stages[i].row.id] else { continue }
            stages[i].row.baselineStart = r.lowerBound
            stages[i].row.baselineEnd = r.upperBound
        }
    }

    /// `เทียบ Baseline`: the last stage end against the last baseline end of the stages that have one; nil without.
    var slip: Int? {
        let based = stages.map(\.row).filter { $0.baselineEnd != nil }
        guard let end = based.map(\.end).max(), let base = based.compactMap(\.baselineEnd).max() else { return nil }
        return MasterSchedule.calendar.dateComponents([.day], from: base, to: end).day ?? 0
    }

    /// `ตรงแผน`, `ช้า 3 วัน`, `เร็ว 2 วัน`.
    static func slipText(_ days: Int) -> String {
        days == 0 ? "ตรงแผน" : days > 0 ? "ช้า \(days) วัน" : "เร็ว \(-days) วัน"
    }
}
