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

    /// Within this many points of the plan counts as `ตามแผน`, as on the board.
    public static let tolerance = 5.0

    public init(actual: Double, planned: Double, actualWeekAgo: Double? = nil, start: Date, due: Date, today: Date) {
        self.actual = actual; self.planned = planned; self.actualWeekAgo = actualWeekAgo
        self.start = start; self.due = due; self.today = today
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

    /// The install period stretched by the SPI (planned duration / SPI), from its start; the due date when nothing is
    /// planned yet or the work is done.
    public func forecastEnd(calendar cal: Calendar = .current) -> Date {
        let first = cal.startOfDay(for: start), last = cal.startOfDay(for: due)
        guard actual < 100, let spi, spi > 0 else { return last }
        let days = (cal.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        let forecast = Int((Double(days) / spi).rounded(.up))
        return cal.date(byAdding: .day, value: max(forecast, 1) - 1, to: first) ?? last
    }

    /// Days between the forecast and the due date: positive is spare time, negative is late.
    public func slackDays(calendar cal: Calendar = .current) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: forecastEnd(calendar: cal)), to: cal.startOfDay(for: due)).day ?? 0
    }
}
