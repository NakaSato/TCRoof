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

public extension Array where Element == MasterSchedule.WorkItem {
    /// The sub-tasks of one MP task, without the task's own line.
    func items(for task: MasterSchedule.Task) -> [MasterSchedule.WorkItem] {
        filter { $0.task == task && $0.code != task.code }
    }
}
