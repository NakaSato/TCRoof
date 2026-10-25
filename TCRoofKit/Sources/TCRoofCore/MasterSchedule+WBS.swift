import Foundation

/// A station plan's work breakdown (docs/specs/project-plan-wbs.md): the rows of the `แผนโครงการ` sheet of the team's
/// plan files (`Project_Plan_TCRoof`), each MP task's sub-tasks with their evidence, owner, weight and dates. The MP
/// tasks themselves stay the 18 of `Task`; a row belongs to the task its code starts with (`2.5.3` → 2.5 Inverter).
public extension MasterSchedule {
    struct WorkItem: Codable, Equatable, Sendable, Identifiable {
        /// `2.5.3`, `1.7.1`, `0.2`: the sheet's WBS code.
        public var code: String
        public var title: String
        /// What proves it done (หลักฐาน / เลขที่เอกสาร).
        public var evidence: String?
        public var responsible: String?
        /// Percent points of the whole station; a task's sub-tasks add up to its weight.
        public var weight: Double
        /// The sheet's own words (`ย้อนจาก 2.10 (60 วัน)`, `Master Plan`), kept as written.
        public var predecessor: String?
        public var lagDays: Int?
        public var days: Int?
        public var baselineStart: Date?
        public var baselineEnd: Date?
        public var forecastStart: Date?
        public var forecastEnd: Date?
        /// `ยังไม่เริ่ม`, `กำลังดำเนินการ` … as the sheet last worked it out.
        public var status: String?
        /// มาตรฐาน / หมายเหตุ; `หลักฐาน: site_map` names a station paper (`StationDocs`).
        public var note: String?
        /// Who approves or accepts it (`PM`, `วศ.`).
        public var approver: String?
        /// 0 a part, 1 a task line, 2 a sub-task, as the sheet indents it.
        public var level: Int

        public init(code: String, title: String, weight: Double = 0, level: Int = 2) {
            self.code = code; self.title = title; self.weight = weight; self.level = level
        }

        public var id: String { code }

        /// The MP task the row belongs to: its code's first two parts. Part 0 (preparation) and 2.10 Tie-in have none.
        public var task: Task? {
            let parts = code.split(separator: ".")
            guard parts.count >= 2 else { return nil }
            let head = parts[0] + "." + parts[1]
            return Task.allCases.first { $0.code == head }
        }

        /// ◆: a date the team waits for (an approval, a result), not work it does.
        public var isMilestone: Bool { title.hasPrefix("◆") }

        /// The template marks the rows of the other cases (HV on an LV station, พค.2 under 200 kVA) and keeps them at 0.
        public var notForThisStation: Bool {
            title.contains("(ไม่เกี่ยวกับสถานีนี้)") || title.contains("(ไม่ต้องยื่น)") || title.contains("(ไม่ต้อง")
        }

        /// The station papers its note names (`หลักฐาน: site_map, sld`).
        public var evidenceKinds: [String] {
            guard let note, let r = note.range(of: "หลักฐาน:") else { return [] }
            return note[r.upperBound...].split { ",·;".contains($0) || $0.isWhitespace }
                .map(String.init).filter { $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } && $0.contains { $0.isASCII } }
        }
    }
}

public extension MasterSchedule.WorkItem {
    /// The same row `days` later (earlier when negative), as `Input.shifted` moves a template's plan.
    func shifted(days: Int, calendar cal: Calendar = MasterSchedule.calendar) -> Self {
        func move(_ d: Date?) -> Date? { d.map { cal.date(byAdding: .day, value: days, to: $0) ?? $0 } }
        var i = self
        i.baselineStart = move(baselineStart); i.baselineEnd = move(baselineEnd)
        i.forecastStart = move(forecastStart); i.forecastEnd = move(forecastEnd)
        return i
    }
}

public extension Array where Element == MasterSchedule.WorkItem {
    /// The sub-tasks of one MP task, without the task's own line.
    func items(for task: MasterSchedule.Task) -> [MasterSchedule.WorkItem] {
        filter { $0.task == task && $0.code != task.code }
    }
}

// MARK: - Ticks

public extension MasterSchedule {
    /// A WBS row ticked done (docs/specs/project-plan-wbs.md, step 2): who, the day, and the evidence when any. Ticks
    /// are kept by row code, apart from the plan's progress, so a contractor can send them; team devices book them
    /// (`bookWBS`).
    struct WBSTick: Codable, Equatable, Sendable {
        /// The email of who ticked it.
        public var by: String
        /// The day it was done; its week takes the booking.
        public var at: Date
        /// A document number, when one was given.
        public var document: String?

        public init(by: String, at: Date, document: String? = nil) {
            self.by = by; self.at = at; self.document = document
        }

        /// A contractor's ticks taken in by a team device: a contractor adds ticks in their own name and changes or
        /// takes back only ticks a contractor made; the team's stay as they are. `contractors` are the job's external
        /// people.
        public static func trusting(_ incoming: [String: WBSTick], local: [String: WBSTick], contractors: Set<String>) -> [String: WBSTick] {
            func isContractor(_ t: WBSTick?) -> Bool { t.map { contractors.contains(Permissions.normalized($0.by)) } ?? false }
            var out = local
            for code in Set(incoming.keys).union(local.keys) {
                let old = local[code], new = incoming[code]
                switch (old, new) {
                case (nil, let n?) where isContractor(n): out[code] = n
                case (let o?, nil) where isContractor(o): out[code] = nil
                case (let o?, let n?) where o != n && isContractor(o) && isContractor(n): out[code] = n
                default: break
                }
            }
            return out
        }
    }

    /// What `bookWBS` booked for one ticked row, so taking the tick back takes exactly that away.
    struct WBSBooking: Codable, Equatable, Sendable {
        /// Task raw value and week key (`Actual.key`).
        public var task: String
        public var week: String
        public var points: Double
    }

    /// Books the ticked rows into the plan's progress: each row's weight in the week of its tick, once per row (kept in
    /// `Actual.fromWBS`), never past its task's weight; a tick taken back, or a row the plan no longer has, takes its
    /// booking away again. The task's start moves back to the earliest tick, and it finishes on the last one once it
    /// reaches its weight. A task's own line, rows of the other case and rows without a task or weight book nothing. Running it again
    /// changes nothing, so every team device can run it after a change arrives. Returns whether anything changed.
    @discardableResult
    static func bookWBS(_ actual: inout Actual, items: [WorkItem], ticks: [String: WBSTick], input: Input,
                        calendar cal: Calendar = MasterSchedule.calendar) -> Bool {
        let before = actual
        let byCode = Dictionary(items.map { ($0.code, $0) }) { a, _ in a }
        for (code, b) in actual.fromWBS where ticks[code] == nil || byCode[code] == nil {
            var week = actual.points[b.task] ?? [:]
            let left = (week[b.week] ?? 0) - b.points
            week[b.week] = left > 1e-9 ? left : nil
            actual.points[b.task] = week.isEmpty ? nil : week
            actual.fromWBS[code] = nil
        }
        for item in items {
            // the task's own line is its sub-tasks' sum: only they book
            guard actual.fromWBS[item.code] == nil, let tick = ticks[item.code], let task = item.task, item.code != task.code,
                  item.weight > 0, !item.notForThisStation else { continue }
            let key = task.rawValue, weight = input.weight(task)
            let done = (actual.points[key] ?? [:]).values.reduce(0, +)
            let points = max(0, min(item.weight, weight - done))
            let day = cal.startOfDay(for: tick.at), week = Actual.key(day, calendar: cal)
            if points > 0 { actual.points[key, default: [:]][week, default: 0] += points }
            actual.fromWBS[item.code] = WBSBooking(task: key, week: week, points: points)
            actual.started[key] = actual.started[key].map { min($0, day) } ?? day
            if done + points >= weight - 1e-9 { actual.finished[key] = max(actual.finished[key] ?? day, day) }
        }
        return actual != before
    }
}
