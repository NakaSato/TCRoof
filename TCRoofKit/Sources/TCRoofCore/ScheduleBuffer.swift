import Foundation

/// A station's schedule reserve and how much of it is used (CHA-87, PMBOK 7th Guide 2.8.5 contingency and management
/// reserve, 2.4.2). As the Master Plan's risk sheet keeps `COD + สำรองทั้งหมด` (known-risk reserve + MGMT_RES), the
/// buffer sits after the plan's end (`installEnd`) and protects `installEnd + buffer`:
/// - contingency: the open authority tasks' spread at baseline (`HandoverRange` late − likely with nothing done, CHA-80);
/// - management: 10 % of the plan's span (the Master Plan's `MGMT_PCT` of the time left to COD).
/// The forecast's days past `installEnd` (`InstallTracking.forecastEnd`, the page's `คาดส่งมอบ`) use it up. The
/// buffer-consumption ("fever") chart plots % of the buffer used against % of the work done, week by week.
public enum ScheduleBuffer {
    /// The Master Plan's management reserve share (`MGMT_PCT`).
    public static let managementShare = 0.10
    /// Red once the buffer used runs this many points ahead of the work done, or once it is all used.
    public static let redMargin = 33.0

    public enum Zone: String, Codable, Sendable {
        /// The buffer is used no faster than the work progresses.
        case green
        /// Used faster than the work progresses.
        case amber
        /// A third of the buffer ahead of the work, or all of it used.
        case red
    }

    public struct Size: Equatable, Sendable {
        public var contingency: Int
        public var management: Int
        /// At least one day.
        public var total: Int { max(contingency + management, 1) }

        public init(contingency: Int, management: Int) { self.contingency = contingency; self.management = management }
    }

    /// One week of the fever chart.
    public struct Point: Equatable, Sendable {
        public var date: Date
        /// % of the work done, 0…100.
        public var done: Double
        /// % of the buffer used, 0 and up (over 100 is past the protected date).
        public var used: Double
        public var zone: Zone { ScheduleBuffer.zone(used: used, done: done) }

        public init(date: Date, done: Double, used: Double) { self.date = date; self.done = done; self.used = used }
    }

    public struct Status: Equatable, Sendable {
        public var size: Size
        /// `installEnd` + the buffer.
        public var protectedDate: Date
        /// The forecast's days past `installEnd`, 0 when on time or early.
        public var usedDays: Int
        /// Buffer days left; negative past the protected date.
        public var remainingDays: Int { size.total - usedDays }
        public var now: Point
        /// Weekly points from the install start to today, oldest first; the last is `now`.
        public var history: [Point]
        public var zone: Zone { now.zone }

        public init(size: Size, protectedDate: Date, usedDays: Int, now: Point, history: [Point]) {
            self.size = size; self.protectedDate = protectedDate; self.usedDays = usedDays; self.now = now; self.history = history
        }
    }

    /// Green while the buffer used is at most the work done, red a third ahead or all used, amber between.
    public static func zone(used: Double, done: Double) -> Zone {
        if used >= 100 - 1e-9 || used > done + redMargin + 1e-9 { return .red }
        return used > done + 1e-9 ? .amber : .green
    }

    /// The buffer of a plan as it was set, with nothing done.
    public static func size(plan: [MasterSchedule.PlannedTask], input: MasterSchedule.Input,
                            calendar cal: Calendar = MasterSchedule.calendar) -> Size {
        let end = cal.startOfDay(for: input.installEnd)
        let first = cal.startOfDay(for: plan.compactMap(\.start).min() ?? input.installStart)
        func days(_ a: Date, _ b: Date) -> Int { cal.dateComponents([.day], from: a, to: b).day ?? 0 }
        let spread = HandoverRange.forecast(plan: plan, actual: .init(), base: end, installEnd: end, today: first, calendar: cal)
            .map { max(days(cal.startOfDay(for: $0.likely), cal.startOfDay(for: $0.late)), 0) } ?? 0
        let span = max(days(cal.startOfDay(for: input.installStart), end) + 1, 0)
        return Size(contingency: spread, management: Int((Double(span) * managementShare).rounded()))
    }

    /// Today's use of the buffer and, with `history`, the weekly points before it; nil before the install starts.
    public static func status(input: MasterSchedule.Input, actual: MasterSchedule.Actual, today: Date, history withHistory: Bool = true,
                              calendar cal: Calendar = MasterSchedule.calendar) -> Status? {
        let plan = MasterSchedule.plan(input, calendar: cal)
        let day = cal.startOfDay(for: today), start = cal.startOfDay(for: input.installStart)
        guard day >= start else { return nil }
        let size = size(plan: plan, input: input, calendar: cal)
        let end = cal.startOfDay(for: input.installEnd)
        func point(_ d: Date) -> (Point, Int) {
            let s = MasterSchedule.status(plan: plan, actual: actual, through: d, calendar: cal)
            let t = InstallTracking(actual: s.actual, planned: s.planned, start: input.installStart, due: input.installEnd, today: d,
                                    earned: InstallTracking.earnedDate(plan: plan, actual: actual, done: s.actual,
                                                                       start: input.installStart, calendar: cal))
            let late = max(cal.dateComponents([.day], from: end, to: cal.startOfDay(for: t.forecastEnd(calendar: cal))).day ?? 0, 0)
            return (Point(date: d, done: min(max(s.actual, 0), 100), used: Double(late) / Double(size.total) * 100), late)
        }
        var history: [Point] = []
        var d = cal.date(byAdding: .day, value: 6, to: MasterSchedule.weekStart(start, calendar: cal)) ?? start
        while withHistory, d < day, history.count < 260 {
            history.append(point(d).0)
            d = cal.date(byAdding: .day, value: 7, to: d) ?? day
        }
        let (now, late) = point(day)
        history.append(now)
        return Status(size: size, protectedDate: cal.date(byAdding: .day, value: size.total, to: end) ?? end,
                      usedDays: late, now: now, history: history)
    }
}
