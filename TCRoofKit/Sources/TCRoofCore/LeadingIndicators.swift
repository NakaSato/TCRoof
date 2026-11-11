import Foundation

/// A station's leading indicators (CHA-85, PMBOK 7th Guide 2.7.1 and 2.8.5): measures that move a week or two before
/// SPI does, each with a threshold. SPI, % planned against % actual and `คาดส่งมอบ` are lagging: by the time they move the
/// delay has happened. Computed from what the app already keeps, never stored.
public struct LeadingIndicator: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// A step the utility, the ERC or DEDE has (`ERCFlow.waits`) past its time limit: days past, the worst one.
        case authorityOverdue
        /// Site ICL items failed and not checked again for a week or more: items.
        case iclFailed
        /// Weeks running, up to last week, whose average crew on site was under the crew the plan needs: weeks.
        case crewShort
        /// Problems still open in the daily reports within two weeks of the install end: problems.
        case openProblems
        /// This week's weekly request (R1) not sent, signed or approved since the week began: days.
        case requestLate

        /// The Master Plan risk register's KRI the indicator comes before (`qa_sheets.py` `RISKS`).
        public var kri: String {
            switch self {
            case .authorityOverdue: "R01 R02 R04 R10"
            case .iclFailed: "R09"
            case .crewShort: "R03"
            case .openProblems: "R09"
            case .requestLate: "R08"
            }
        }

        public var unit: String {
            switch self {
            case .authorityOverdue, .requestLate: "วัน"
            case .iclFailed, .openProblems: "รายการ"
            case .crewShort: "สัปดาห์"
            }
        }
    }

    public var kind: Kind
    public var value: Int
    public var threshold: Int
    /// One line on what the value is made of (the step, the items, the crew).
    public var detail: String

    public var id: String { kind.rawValue }
    /// At or over its threshold.
    public var tripped: Bool { value >= threshold }

    public init(kind: Kind, value: Int, threshold: Int, detail: String = "") {
        self.kind = kind; self.value = value; self.threshold = threshold; self.detail = detail
    }

    /// `รอ กฟภ. เกินกำหนด 3 วัน`, the page's and the notification's title.
    public var title: String {
        switch kind {
        case .authorityOverdue: "รอหน่วยงานเกินกำหนด \(value) วัน"
        case .iclFailed: "ICL ไม่ผ่าน ยังไม่ตรวจซ้ำ \(value) รายการ"
        case .crewShort: "คนหน้างานต่ำกว่าแผน \(value) สัปดาห์ติด"
        case .openProblems: "ปัญหาค้างใกล้ส่งมอบ \(value) รายการ"
        case .requestLate: "คำขอรายสัปดาห์ (R1) ยังไม่ส่ง \(value) วัน"
        }
    }

    /// One indicator as the assistant's tools give it.
    public struct Brief: Codable, Equatable, Sendable {
        public var indicator: String
        public var value: Int
        public var threshold: Int
        public var unit: String
        public var detail: String
        /// The Master Plan risk register's KRIs it comes before.
        public var kri: String

        public init(_ i: LeadingIndicator) {
            indicator = i.title; value = i.value; threshold = i.threshold; unit = i.kind.unit; detail = i.detail; kri = i.kind.kri
        }
    }

    /// `เกณฑ์เตือน ≥ 2 สัปดาห์`.
    public var thresholdText: String { "เกณฑ์เตือน ≥ \(threshold) \(kind.unit)" }
}

public enum LeadingIndicators {
    /// Each indicator's threshold (เกณฑ์เตือน): at or over it, the indicator trips. Defaults in code; per-program
    /// editing is a later step.
    public struct Thresholds: Codable, Equatable, Sendable {
        public var authorityOverdueDays = 1
        public var iclFailedItems = 1
        /// A failed item counts once it has gone this many days without a pass.
        public var iclFailedAgeDays = 7
        public var crewShortWeeks = 2
        public var openProblems = 1
        /// Open problems count from this many days before the install end.
        public var problemsWindowDays = 14
        public var requestLateDays = 1

        public init() {}

        public static let defaults = Thresholds()

        public func threshold(_ kind: LeadingIndicator.Kind) -> Int {
            switch kind {
            case .authorityOverdue: authorityOverdueDays
            case .iclFailed: iclFailedItems
            case .crewShort: crewShortWeeks
            case .openProblems: openProblems
            case .requestLate: requestLateDays
            }
        }
    }

    /// A failed site ICL item: its sheet and item's names, and when it was last checked.
    public struct FailedItem: Equatable, Sendable {
        public var name: String
        public var checkedAt: Date?
        public init(name: String, checkedAt: Date?) { self.name = name; self.checkedAt = checkedAt }
    }

    public struct Input: Sendable {
        public var waits: [ERCFlow.Wait] = []
        public var failedICL: [FailedItem] = []
        public var dailies: [RoutineReport.Daily] = []
        /// The crew the plan needs to finish on time (`Assistant.Strategy.crewNeed`); nil without one.
        public var crewNeed: Int?
        public var requests: [RoutineReport.WeeklyRequest] = []
        public var installStart: Date
        public var installEnd: Date
        /// The job is handed over: nothing to warn about.
        public var completed = false

        public init(waits: [ERCFlow.Wait] = [], failedICL: [FailedItem] = [], dailies: [RoutineReport.Daily] = [],
                    crewNeed: Int? = nil, requests: [RoutineReport.WeeklyRequest] = [], installStart: Date, installEnd: Date,
                    completed: Bool = false) {
            self.waits = waits; self.failedICL = failedICL; self.dailies = dailies; self.crewNeed = crewNeed
            self.requests = requests; self.installStart = installStart; self.installEnd = installEnd; self.completed = completed
        }
    }

    /// The indicators that apply today, in `Kind` order; one that has nothing to measure (no wait, no crew need, outside
    /// its window) is left out. Each carries its value, so a page can show the ones under threshold too.
    public static func compute(_ input: Input, today: Date, thresholds t: Thresholds = .defaults,
                               calendar cal: Calendar = MasterSchedule.calendar) -> [LeadingIndicator] {
        guard !input.completed else { return [] }
        let day = cal.startOfDay(for: today)
        func days(_ a: Date, _ b: Date) -> Int { cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0 }
        var out: [LeadingIndicator] = []

        if let worst = input.waits.min(by: { $0.left < $1.left }) {
            let over = max(-worst.left, 0)
            out.append(.init(kind: .authorityOverdue, value: over, threshold: t.authorityOverdueDays,
                             detail: worst.title + " | " + worst.text))
        }

        if !input.failedICL.isEmpty {
            let old = input.failedICL.filter { item in item.checkedAt.map { days($0, day) >= t.iclFailedAgeDays } ?? true }
            let names = old.prefix(2).map(\.name).joined(separator: " | ") + (old.count > 2 ? " +\(old.count - 2)" : "")
            out.append(.init(kind: .iclFailed, value: old.count, threshold: t.iclFailedItems,
                             detail: old.isEmpty ? "ไม่ผ่าน \(input.failedICL.count) รายการ ยังไม่ถึง \(t.iclFailedAgeDays) วัน" : names))
        }

        if let need = input.crewNeed, need > 0, day >= cal.startOfDay(for: input.installStart) {
            let weeks = crewWeeks(input.dailies, before: day, calendar: cal)
            let short = weeks.prefix { $0.average < Double(need) }
            let last = weeks.first.map { " | สัปดาห์ก่อนเฉลี่ย " + String(format: "%.1f", $0.average) + " คน" } ?? ""
            out.append(.init(kind: .crewShort, value: short.count, threshold: t.crewShortWeeks,
                             detail: "ต้องการ \(need) คน" + last))
        }

        let end = cal.startOfDay(for: input.installEnd)
        if days(day, end) <= t.problemsWindowDays {
            let open = RoutineReport.problems(input.dailies).open
            let names = open.prefix(2).map(\.description).joined(separator: " | ") + (open.count > 2 ? " +\(open.count - 2)" : "")
            let left = days(day, end)
            out.append(.init(kind: .openProblems, value: open.count, threshold: t.openProblems,
                             detail: (left >= 0 ? "อีก \(left) วันส่งมอบ" : "เลยกำหนดส่งมอบ \(-left) วัน") + (names.isEmpty ? "" : " | " + names)))
        }

        let week = MasterSchedule.weekStart(day, calendar: cal)
        let lastWeekDay = cal.date(byAdding: .day, value: 6, to: week) ?? week
        if week <= end, lastWeekDay >= cal.startOfDay(for: input.installStart) {
            let r = input.requests.first { cal.isDate($0.weekStart, inSameDayAs: week) }
            let sent = r.map { $0.sentAt != nil || $0.approvedAt != nil || $0.engineerSignedAt != nil } ?? false
            out.append(.init(kind: .requestLate, value: sent ? 0 : days(week, day), threshold: t.requestLateDays,
                             detail: sent ? "ส่งแล้ว" : r == nil ? "ยังไม่มีคำขอของสัปดาห์นี้" : "ร่างไว้ ยังไม่ส่งขออนุมัติ"))
        }
        return out
    }

    /// Average crew per reported day, for each full week before `day`'s week, latest first, stopping at the first
    /// week with no report that has a crew.
    static func crewWeeks(_ dailies: [RoutineReport.Daily], before day: Date, calendar cal: Calendar) -> [(week: Date, average: Double)] {
        let byWeek = Dictionary(grouping: dailies.filter { $0.crewTotal > 0 }) { MasterSchedule.weekStart($0.date, calendar: cal) }
        var out: [(Date, Double)] = []
        var w = cal.date(byAdding: .day, value: -7, to: MasterSchedule.weekStart(day, calendar: cal))!
        while let reports = byWeek[w], !reports.isEmpty {
            out.append((w, Double(reports.reduce(0) { $0 + $1.crewTotal }) / Double(reports.count)))
            w = cal.date(byAdding: .day, value: -7, to: w)!
        }
        return out
    }
}

public extension Assistant.Strategy {
    /// The crew it takes for every open task to end on time (`Requirement.crew`): today's average crew scaled by the
    /// pace the slowest task needs. Nil without crew in the last 14 days of daily reports, or once the install end has
    /// passed with work open.
    static func crewNeed(input: MasterSchedule.Input, actual: MasterSchedule.Actual, dailies: [RoutineReport.Daily],
                         workingWeekdays: Set<Int>, today: Date, calendar cal: Calendar = MasterSchedule.calendar) -> Int? {
        let plan = MasterSchedule.plan(input, calendar: cal)
        let recovery = MasterSchedule.recovery(plan: plan, actual: actual, today: today, calendar: cal)
        let crew = crewAverage(dailies, today: today, calendar: cal)
        return requirement(recovery, input: input, crew: crew, workdays: max(workingWeekdays.count, 1), today: today, calendar: cal)?.crew
    }
}

// MARK: - Notifications

public enum LeadingIndicatorNotification {
    /// A tripped indicator at 08:00 on the next Monday, once per indicator per week (the id carries that Monday's
    /// week), as `mp-behind` does. Posted as an MP plan notification, so a tap opens the job.
    public static func plans(jobKey: String, station: String, indicators: [LeadingIndicator], now: Date,
                             calendar cal: Calendar = MasterSchedule.calendar) -> [NotificationPlan] {
        let week = MasterSchedule.weekStart(now, calendar: cal)
        func mondayAt8(_ w: Date) -> Date? {
            cal.date(byAdding: .day, value: 1, to: w).flatMap { cal.date(bySettingHour: 8, minute: 0, second: 0, of: $0) }
        }
        guard let this = mondayAt8(week), let nextWeek = cal.date(byAdding: .day, value: 7, to: week),
              let next = mondayAt8(nextWeek) else { return [] }
        let at = this > now ? this : next
        let weekKey = MasterSchedule.Actual.key(this > now ? week : nextWeek, calendar: cal)
        return indicators.filter(\.tripped).map { i in
            NotificationPlan(id: "lead-\(jobKey)-\(i.kind.rawValue)-\(weekKey)", type: .mp, title: i.title, body: station,
                             sub: [i.detail, i.thresholdText].filter { !$0.isEmpty }.joined(separator: " | "),
                             fire: .at(at), info: [NotificationInfo.job: jobKey])
        }
    }
}
