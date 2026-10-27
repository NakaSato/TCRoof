import Foundation

/// The iPad install tracking page's KPI strip (docs/ui/install-tracking-ipad §A): where a station stands against its
/// plan, worked out from cumulative percents (the MP plan's `Status`) and the install period.
public struct InstallTracking: Equatable, Sendable {
    public enum Schedule: Equatable, Sendable { case onPlan, behind, ahead }

    /// Cumulative percents, 0…100: done, planned by today, and done a week ago.
    public var actual: Double
    public var planned: Double
    public var actualWeekAgo: Double?
    public var start: Date
    public var due: Date
    public var today: Date
    /// Earned schedule: the day the plan reached today's actual percent (`earnedDate`); nil to stretch by the SPI.
    public var earned: Date?

    /// Within this many points of the plan counts as `ตามแผน`, as on the board.
    public static let tolerance = 5.0

    public init(actual: Double, planned: Double, actualWeekAgo: Double? = nil, start: Date, due: Date, today: Date, earned: Date? = nil) {
        self.actual = actual; self.planned = planned; self.actualWeekAgo = actualWeekAgo
        self.start = start; self.due = due; self.today = today; self.earned = earned
    }

    /// Actual minus planned, rounded; negative is behind.
    public var variance: Int { Int(actual.rounded()) - Int(planned.rounded()) }

    public var schedule: Schedule {
        abs(Double(variance)) <= Self.tolerance ? .onPlan : variance < 0 ? .behind : .ahead
    }

    /// Points done this week; nil without last week's figure.
    public var gainThisWeek: Int? { actualWeekAgo.map { Int(actual.rounded()) - Int($0.rounded()) } }

    /// Schedule performance index, actual over planned; nil before anything is planned.
    public var spi: Double? { planned > 0 ? actual / planned : nil }

    /// When the work ends: with an earned date, the due date moved by the days the work is behind (or ahead of) the
    /// plan today, the rest going at the plan's pace; without one, the install period stretched by the SPI (planned
    /// duration / SPI), from its start. The due date when nothing is planned yet or the work is done.
    public func forecastEnd(calendar cal: Calendar = .current) -> Date {
        let first = cal.startOfDay(for: start), last = cal.startOfDay(for: due)
        guard actual < 100, planned > 0 else { return last }
        if let earned {
            let behind = cal.dateComponents([.day], from: cal.startOfDay(for: earned), to: cal.startOfDay(for: today)).day ?? 0
            return cal.date(byAdding: .day, value: behind, to: last) ?? last
        }
        guard let spi, spi > 0 else { return last }
        let days = (cal.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        let forecast = Int((Double(days) / spi).rounded(.up))
        return cal.date(byAdding: .day, value: max(forecast, 1) - 1, to: first) ?? last
    }

    /// Days between the forecast and the due date: positive is spare time, negative is late.
    public func slackDays(calendar cal: Calendar = .current) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: forecastEnd(calendar: cal)), to: cal.startOfDay(for: due)).day ?? 0
    }
}

public extension InstallTracking {
    /// Earned schedule: the day the MP plan's cumulative planned percent reached `done`. The plan books by week, so
    /// each week's planned total is taken as reached at the week's end and the days between are interpolated. Searched
    /// from the plan's first week to its last; nil when the plan never reaches it.
    static func earnedDate(plan: [MasterSchedule.PlannedTask], actual: MasterSchedule.Actual, done: Double, start: Date,
                           calendar cal: Calendar = MasterSchedule.calendar) -> Date? {
        guard let last = plan.compactMap(\.end).max() else { return nil }
        // from the plan's first task (the permits weigh in its percents too), else the install start
        var week = MasterSchedule.weekStart(plan.compactMap(\.start).min() ?? start, calendar: cal)
        var prev = (date: cal.date(byAdding: .day, value: -1, to: week) ?? week, planned: 0.0)
        var guardWeeks = 0
        while week <= last, guardWeeks < 520 {
            let end = cal.date(byAdding: .day, value: 6, to: week) ?? week
            let p = MasterSchedule.status(plan: plan, actual: actual, through: week, calendar: cal).planned
            if p >= done - 1e-9 {
                guard p > prev.planned + 1e-9 else { return prev.date }
                let f = (done - prev.planned) / (p - prev.planned)
                let span = Double(cal.dateComponents([.day], from: prev.date, to: end).day ?? 7)
                return cal.date(byAdding: .day, value: Int((f * span).rounded()), to: prev.date)
            }
            prev = (end, p)
            week = cal.date(byAdding: .day, value: 7, to: week) ?? last.addingTimeInterval(1)
            guardWeeks += 1
        }
        return nil
    }
}
