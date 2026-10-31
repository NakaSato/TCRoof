import Foundation

/// A value snapshot of the fields needed by the project list; no SwiftData objects cross to the worker.
public struct InstallSummaryInput: Codable, Equatable, Sendable {
    public var base: InstallStationSummary
    public var planJSON: String?
    public var actualJSON: String?

    public init(base: InstallStationSummary, planJSON: String?, actualJSON: String?) {
        self.base = base
        self.planJSON = planJSON
        self.actualJSON = actualJSON
    }

    public func summary(at now: Date) -> InstallStationSummary {
        var summary = base
        guard let data = planJSON?.data(using: .utf8),
              let input = try? JSONDecoder().decode(MasterSchedule.Input.self, from: data) else { return summary }
        let actual = actualJSON?.data(using: .utf8).flatMap { try? JSONDecoder().decode(MasterSchedule.Actual.self, from: $0) } ?? .init()
        let calendar = MasterSchedule.calendar
        let week = MasterSchedule.weekStart(now)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: week) ?? week
        let plan = MasterSchedule.plan(input)
        let status = MasterSchedule.status(plan: plan, actual: actual, through: now)
        let current = plan.first { task in
            guard task.weight > 0, let start = task.start, let end = task.end, start <= weekEnd, end >= week else { return false }
            return (status.actualByTask[task.task] ?? 0) < 99.95
        }
        summary.actual = status.actual
        summary.plan = status.planned
        summary.currentTask = current.map { "\($0.task.code) \($0.task.title)" } ?? ""
        summary.permits = InstallOverview.permits(RoutineReport.permits(plan: plan, actual: actual, at: now))
        return summary
    }
}
