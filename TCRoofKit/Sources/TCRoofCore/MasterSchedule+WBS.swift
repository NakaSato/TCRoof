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
        /// Explicit finish-to-start links. Nil in older plans; worksheet prose is never interpreted as a link.
        public var dependencies: [WBSDependency]?
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
    /// The sub-tasks of one MP task, without the task's own line; a sub-task's own steps (2.5.1.1 under 2.5.1) follow it.
    func items(for task: MasterSchedule.Task) -> [MasterSchedule.WorkItem] {
        filter { $0.task == task && $0.code != task.code }
    }

    /// The codes of the rows other rows sit under (`2.5`, `2.5.1` when the Inverter station's steps are there): such a
    /// row is its sub-rows' sum, so only they are ticked and booked.
    var parentCodes: Set<String> {
        let codes = Set(map(\.code))
        return Set(compactMap { item -> String? in
            guard let dot = item.code.lastIndex(of: ".") else { return nil }
            let parent = String(item.code[..<dot])
            return codes.contains(parent) ? parent : nil
        })
    }
}

// MARK: - Ticks

public extension MasterSchedule {
    /// A WBS row ticked done (docs/specs/project-plan-wbs.md, step 2): who, the day, the evidence when any, and where
    /// the tick came from (`Source`). Ticks are kept by row code, apart from the plan's progress; team devices book them
    /// (`bookWBS`). Only the team ticks: a contractor's way in is the daily report, whose picks count once the team
    /// confirms them (`RoutineReport.wbsPending`, CHA-71).
    struct WBSTick: Codable, Equatable, Sendable {
        /// Where a tick came from. Nil in ticks made before sources: read through `origin(contractors:)`.
        public enum Source: String, Codable, Sendable, CaseIterable {
            /// `ทีมติ๊ก`: a team member tapped the box.
            case team
            /// `รายงานประจำวัน`: a contractor picked it in a daily report line and the team confirmed it.
            case daily
            /// `Google Sheet`: `Y` on the Master Plan sheet's WBS tab, written by its Apps Script.
            case sheet
            /// The plan file's `เสร็จ (Y)` column, taken in by an import.
            case file
        }

        /// The email of who ticked it; for a daily report's pick, the team member who confirmed it; for the sheet's,
        /// who typed the `Y`.
        public var by: String
        /// The day it was done; its week takes the booking.
        public var at: Date
        /// A document number, when one was given.
        public var document: String?
        /// Taken from a plan file whose row was marked `Y` without a `เสร็จ` date: `at` is only the import's day, so
        /// export leaves the file's date cell as it is. Nil for a tick made in the app.
        public var undated: Bool?
        /// Nil in older ticks (`origin`).
        public var source: Source?
        /// A daily report's pick: who reported it (the report's recorder, a name).
        public var reportedBy: String?
        /// A daily report's pick: when the team confirmed it (`at` is the report's day).
        public var confirmedAt: Date?

        public init(by: String, at: Date, document: String? = nil, undated: Bool? = nil, source: Source? = nil,
                    reportedBy: String? = nil, confirmedAt: Date? = nil) {
            self.by = by; self.at = at; self.document = document; self.undated = undated
            self.source = source; self.reportedBy = reportedBy; self.confirmedAt = confirmedAt
        }

        enum CodingKeys: String, CodingKey { case by, at, document, undated, source, reportedBy, confirmedAt }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            by = try c.decode(String.self, forKey: .by)
            at = try c.decode(Date.self, forKey: .at)
            document = try c.decodeIfPresent(String.self, forKey: .document)
            undated = try c.decodeIfPresent(Bool.self, forKey: .undated)
            // a source a later build adds reads as none, rather than losing every tick of the job
            source = ((try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil).flatMap(Source.init(rawValue:))
            reportedBy = try c.decodeIfPresent(String.self, forKey: .reportedBy)
            confirmedAt = try c.decodeIfPresent(Date.self, forKey: .confirmedAt)
        }

        /// Where the tick came from as its row shows it.
        public enum Origin: Equatable, Sendable {
            case team, daily, sheet, file
            /// A contractor's own tick, made before CHA-71 took that away.
            case contractor

            /// The row's chip.
            public var label: String {
                switch self {
                case .team: "ทีมติ๊ก"
                case .daily: "รายงานประจำวัน"
                case .sheet: "Google Sheet"
                case .file: "ไฟล์แผน"
                case .contractor: "ผู้รับเหมาติ๊ก"
                }
            }
        }

        /// `source`, else (an older tick) a contractor's when `by` is one of the job's external people, else the team's.
        public func origin(contractors: Set<String> = []) -> Origin {
            switch source {
            case .team?: return .team
            case .daily?: return .daily
            case .sheet?: return .sheet
            case .file?: return .file
            case nil: return contractors.contains(Permissions.normalized(by)) ? .contractor : .team
            }
        }

        /// The ticks a team device takes from a record. A contractor no longer ticks (CHA-71: the rules refuse their
        /// write, and builds before it may still try), so ticks signed by one of the job's external people change
        /// nothing; anything else (the team, the Master Plan sheet) is taken as it comes.
        public static func trusting(_ incoming: [String: WBSTick], local: [String: WBSTick], signedBy: String?,
                                    contractors: Set<String>) -> [String: WBSTick] {
            if let signedBy, contractors.contains(Permissions.normalized(signedBy)) { return local }
            return incoming
        }
    }

    /// The ticks a plan file brings (its `แผนโครงการ` sheet's `เสร็จ (Y)` column, docs/specs/project-plan-wbs.md step
    /// 3): only rows ticked or unticked in the file since `base` (the rows it was exported with, else the file the job
    /// keeps) change, so a tick made in the app after the export stays. A row ticked in the file takes its `เสร็จ` date,
    /// else `today` (marked `undated`, so export writes no date for it), in the name of who imports it. Returns the
    /// ticks and how many rows changed.
    static func mergingTicks(_ local: [String: WBSTick], fileDone: Set<String>, dates: [String: Date], base: Set<String>?,
                        by: String, today: Date) -> (ticks: [String: WBSTick], changed: Int) {
        let base = base ?? []
        var out = local, changed = 0
        for code in fileDone.subtracting(base).sorted() where out[code] == nil {
            out[code] = WBSTick(by: by, at: dates[code] ?? today, undated: dates[code] == nil ? true : nil, source: .file)
            changed += 1
        }
        for code in base.subtracting(fileDone).sorted() where out[code] != nil {
            out[code] = nil
            changed += 1
        }
        return (out, changed)
    }

    /// The rows' `ผู้รับผิดชอบ` and `หลักฐาน / เลขที่เอกสาร` with a file's taken in, for a file that gives only its
    /// progress (`รับเฉพาะความก้าวหน้า`): a cell changed in Excel since `base` (the file the job keeps) takes the file's
    /// text, a cell emptied there included; the rest stay the job's. Without a base, every cell where the file says
    /// something else is taken. Rows the job doesn't have are left out. Returns the rows and how many cells changed.
    static func mergingText(_ local: [WorkItem], file: [WorkItem], base: [WorkItem]?) -> (items: [WorkItem], changed: Int) {
        let inFile = Dictionary(file.map { ($0.code, $0) }) { a, _ in a }
        let inBase = base.map { b in Dictionary(b.map { ($0.code, $0) }) { a, _ in a } }
        var out = local, changed = 0
        for i in out.indices {
            guard let f = inFile[out[i].code] else { continue }
            let b = inBase?[out[i].code]
            for field in [\WorkItem.responsible, \WorkItem.evidence] {
                let was = inBase == nil ? out[i][keyPath: field] : b?[keyPath: field]
                guard f[keyPath: field] != was, f[keyPath: field] != out[i][keyPath: field] else { continue }
                out[i][keyPath: field] = f[keyPath: field]
                changed += 1
            }
        }
        return (out, changed)
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
    /// reaches its weight. A task's own line, a row with steps under it, rows of the other case and rows without a task or weight book
    /// nothing. Running it again
    /// changes nothing, so every team device can run it after a change arrives. Returns whether anything changed.
    @discardableResult
    static func bookWBS(_ actual: inout Actual, items: [WorkItem], ticks: [String: WBSTick], input: Input,
                        calendar cal: Calendar = MasterSchedule.calendar) -> Bool {
        let before = actual
        let byCode = Dictionary(items.map { ($0.code, $0) }) { a, _ in a }
        let parents = items.parentCodes
        for (code, b) in actual.fromWBS {
            let item = byCode[code]
            let valid = ticks[code] != nil && item != nil && item?.task != nil && item?.code != item?.task?.code
                && !parents.contains(code) && (item?.weight ?? 0) > 0 && item?.notForThisStation == false
            if !valid || abs((item?.weight ?? 0) - b.points) > 1e-9 {
                var week = actual.points[b.task] ?? [:]
                let left = (week[b.week] ?? 0) - b.points
                week[b.week] = left > 1e-9 ? left : nil
                actual.points[b.task] = week.isEmpty ? nil : week
                actual.fromWBS[code] = nil
            }
        }
        for item in items {
            // the task's own line, and any row with steps under it, is its sub-rows' sum: only they book
            guard actual.fromWBS[item.code] == nil, let tick = ticks[item.code], let task = item.task, item.code != task.code,
                  !parents.contains(item.code), item.weight > 0, !item.notForThisStation else { continue }
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

public extension Permissions {
    /// May tick a WBS row of this job done (`mp.wbs_tick`): the team only. A contractor reports finished sub-tasks in
    /// the daily report instead (CHA-71), and firestore.rules refuse their ticks.
    func mayTickWBS(on job: JobAccess?) -> Bool { role != .external && can(.mpWBSTick, on: job) }

    /// May take this tick back: whoever made it (for a daily report's pick, who confirmed it), a manager, or the job's
    /// supervising engineer. Never a contractor.
    func mayTakeBack(_ tick: MasterSchedule.WBSTick, on job: JobAccess?) -> Bool {
        guard mayTickWBS(on: job) else { return false }
        if Self.normalized(tick.by) == email || role == .manager || role == .maintainer { return true }
        return isSupervisor(job)
    }

    /// May confirm a contractor's daily-report pick or send it back (`ยืนยัน` / `ส่งกลับ`): whoever may tick.
    func mayConfirmWBS(on job: JobAccess?) -> Bool { mayTickWBS(on: job) }
}
