import Foundation

/// How far an app survey draft (`SurveyOptions.missing`) has got, in the job list's four groups.
/// The app builds the items from its form; this type only groups and counts them.
public struct SurveyDraftProgress: Equatable, Sendable {
    public static let groupTitles = ["หลังคา", "ระบบไฟฟ้า", "ค่าไฟ", "รูปบังคับ"]

    /// One required item of the form: its group index in `groupTitles` and whether it is filled.
    public struct Item: Equatable, Sendable {
        public let group: Int
        public let filled: Bool
        public init(group: Int, filled: Bool) { self.group = group; self.filled = filled }
    }

    public let done: Int
    public let total: Int
    /// One flag per group, true when none of its items are missing.
    public let groups: [Bool]

    public init(items: [Item]) {
        total = items.count
        done = items.filter { $0.filled }.count
        groups = Self.groupTitles.indices.map { g in items.allSatisfy { $0.group != g || $0.filled } }
    }

    /// Rounded share of filled items, 0…100.
    public var percent: Int { total == 0 ? 0 : Int((Double(done) / Double(total) * 100).rounded()) }
    /// The first group that is not done; nil when every group is.
    public var current: Int? { groups.firstIndex(of: false) }
}

/// The job card's progress box: key, value, percent and one segment per group.
public struct SurveyCardProgress: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case idle, draft, complete }
    public enum Segment: Equatable, Sendable { case todo, current, done }

    public let key: String
    public let value: String
    public let percent: Int
    public let tone: Tone
    public let segments: [Segment]

    /// `draft` is the job's open draft, if any; `hasSaved` is true when the job has a saved survey.
    public init(draft: SurveyDraftProgress?, hasSaved: Bool) {
        let titles = SurveyDraftProgress.groupTitles
        if let draft {
            percent = draft.percent
            if let cur = draft.current {
                key = "ทำต่อ \(cur + 1)/\(titles.count)"
                value = titles[cur]
                tone = .draft
                segments = titles.indices.map { $0 == cur ? .current : draft.groups[$0] ? .done : .todo }
            } else {
                // every required item filled, the draft just isn't saved yet
                key = "สำรวจครบ"
                value = "รอบันทึก"
                tone = .complete
                segments = titles.map { _ in .done }
            }
        } else if hasSaved {
            key = "สำรวจครบ"; value = "มีแบบสำรวจแล้ว"; percent = 100; tone = .complete
            segments = titles.map { _ in .done }
        } else {
            key = "ยังไม่เริ่ม"; value = "เริ่มที่ \(titles[0])"; percent = 0; tone = .idle
            segments = titles.map { _ in .todo }
        }
    }
}

/// "วันนี้ 09:30 น.", "อีก 3 วัน · 10:00 น.", "5 วันที่แล้ว · 14:00 น." for a survey appointment.
public enum RelativeDay {
    /// Whole calendar days from `now`'s day to `date`'s day (negative in the past).
    public static func days(from now: Date, to date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// `time` is already formatted, e.g. "09:30".
    public static func label(days: Int, time: String) -> String {
        switch days {
        case 0: "วันนี้ \(time) น."
        case 1: "พรุ่งนี้ \(time) น."
        case -1: "เมื่อวาน \(time) น."
        case let d where d > 1: "อีก \(d) วัน · \(time) น."
        default: "\(-days) วันที่แล้ว · \(time) น."
        }
    }
}
