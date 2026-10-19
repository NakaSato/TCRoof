import Foundation

/// One station's MP plan as the project assistant reads it: plan vs actual, each task's recovery numbers, this and the
/// next two weeks' tasks, and the last days of daily reports. Customer names, phones and addresses are never in it.
/// Numbers are rounded so the model quotes them as the app shows them.
public struct ScheduleBrief: Codable, Equatable, Sendable {
    public struct PartLine: Codable, Equatable, Sendable {
        public var part: String
        public var plannedPercent: Double
        public var actualPercent: Double
    }

    public struct TaskLine: Codable, Equatable, Sendable {
        public var code: String
        public var title: String
        public var weight: Double
        public var plannedStart: String?
        public var plannedEnd: String?
        public var plannedPercent: Double
        public var actualPercent: Double
        public var actualStart: String?
        public var actualFinish: String?
        public var lateCause: String?
        public var state: MasterSchedule.Recovery.State?
        public var remainingPoints: Double?
        public var neededPointsPerWeek: Double?
        public var pacePointsPerWeek: Double?
        public var projectedFinish: String?
        public var slipDays: Int?
    }

    public struct DayLine: Codable, Equatable, Sendable {
        public struct Line: Codable, Equatable, Sendable {
            public var code: String?
            public var title: String
            public var percent: Double
        }
        public var date: String
        public var crew: Int
        public var rainHours: Int
        public var stopReason: String?
        public var progress: [Line]
        public var openProblems: [String]
    }

    public var jobID: String
    public var station: String
    public var mpNumber: Int?
    public var kWp: Double?
    public var today: String
    public var installStart: String
    public var installEnd: String
    public var plannedPercent: Double
    public var actualPercent: Double
    /// Actual minus planned; negative is behind.
    public var variance: Double
    /// The latest projected finish of the unfinished tasks, and its days past the install end.
    public var projectedFinish: String?
    public var projectedSlipDays: Int?
    public var parts: [PartLine]
    public var tasks: [TaskLine]
    /// Codes of the tasks planned in this week, and in the two weeks after it.
    public var thisWeek: [String]
    public var nextTwoWeeks: [String]
    public var recentDays: [DayLine]

    public init(jobID: String, station: String, mpNumber: Int? = nil, kWp: Double? = nil,
                input: MasterSchedule.Input, actual: MasterSchedule.Actual,
                dailies: [RoutineReport.Daily] = [], today: Date, days: Int = 14,
                calendar cal: Calendar = MasterSchedule.calendar) {
        let plan = MasterSchedule.plan(input, calendar: cal)
        let status = MasterSchedule.status(plan: plan, actual: actual, through: today, calendar: cal)
        let recovery = Dictionary(uniqueKeysWithValues: MasterSchedule.recovery(plan: plan, actual: actual, today: today, calendar: cal).map { ($0.task, $0) })
        let day = { (d: Date) in Self.day(d, calendar: cal) }

        self.jobID = jobID
        self.station = station
        self.mpNumber = mpNumber
        self.kWp = kWp
        self.today = day(today)
        installStart = day(input.installStart)
        installEnd = day(input.installEnd)
        plannedPercent = Self.round(status.planned)
        actualPercent = Self.round(status.actual)
        variance = Self.round(status.variance)
        parts = MasterSchedule.Part.allCases.map {
            PartLine(part: $0.reportTitle, plannedPercent: Self.round(status.plannedByPart[$0] ?? 0),
                     actualPercent: Self.round(status.actualByPart[$0] ?? 0))
        }
        tasks = plan.filter { $0.weight > 0 }.map { p in
            let r = recovery[p.task]
            return TaskLine(code: p.task.code, title: p.task.title, weight: p.weight,
                            plannedStart: p.start.map(day), plannedEnd: p.end.map(day),
                            plannedPercent: Self.round(status.plannedByTask[p.task] ?? 0),
                            actualPercent: Self.round(status.actualByTask[p.task] ?? 0),
                            actualStart: actual.started[p.task.rawValue].map(day),
                            actualFinish: actual.finished[p.task.rawValue].map(day),
                            lateCause: actual.lateCauses[p.task.rawValue]?.title,
                            state: r?.state, remainingPoints: r.map { Self.round($0.remaining) },
                            neededPointsPerWeek: r?.neededPerWeek.map(Self.round),
                            pacePointsPerWeek: r?.pacePerWeek.map(Self.round),
                            projectedFinish: r?.projectedFinish.map(day), slipDays: r?.slipDays)
        }
        let open = recovery.values.filter { $0.state != .done }
        let latest = open.compactMap(\.projectedFinish).max()
        projectedFinish = latest.map(day)
        projectedSlipDays = latest.map { cal.dateComponents([.day], from: cal.startOfDay(for: input.installEnd), to: $0).day ?? 0 }

        let week = MasterSchedule.weekStart(today, calendar: cal)
        func active(_ from: Date, _ to: Date) -> [String] {
            plan.filter { p in
                guard p.weight > 0, let s = p.start, let e = p.end else { return false }
                return s <= to && e >= from && (recovery[p.task]?.state ?? .done) != .done
            }.map(\.task.code)
        }
        let weekEnd = cal.date(byAdding: .day, value: 6, to: week)!
        thisWeek = active(week, weekEnd)
        nextTwoWeeks = active(cal.date(byAdding: .day, value: 7, to: week)!, cal.date(byAdding: .day, value: 20, to: week)!)

        let from = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: today))!
        recentDays = dailies.filter { $0.date > from && $0.date <= today }.sorted { $0.date < $1.date }.map { d in
            DayLine(date: day(d.date), crew: d.crewTotal, rainHours: d.rainHours,
                    stopReason: d.stopReason.isEmpty ? nil : d.stopReason,
                    progress: d.progress.map { .init(code: $0.task?.code, title: $0.title, percent: Self.round($0.percent)) },
                    openProblems: d.problems.filter { !$0.closed && !$0.description.isEmpty }.map(\.description))
        }
    }

    /// Compact JSON, keys sorted, for the model.
    public func json() -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(data: e.encode(self), encoding: .utf8)) ?? "{}"
    }

    static func round(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    static func day(_ d: Date, calendar cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
