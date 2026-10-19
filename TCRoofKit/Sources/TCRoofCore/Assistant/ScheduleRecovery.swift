import Foundation

/// What each unfinished MP task needs to finish on its planned date, and when it finishes at the pace booked so far.
/// The project assistant explains these numbers; it never works them out itself.
public extension MasterSchedule {

    struct Recovery: Equatable, Sendable, Identifiable {
        public enum State: String, Codable, Sendable {
            /// Fully booked.
            case done
            /// Planned to start after this week, nothing booked yet.
            case upcoming
            /// Finishes by its planned end at the pace so far.
            case onTrack
            /// Started on paper but nothing booked, or the pace so far finishes after the planned end.
            case atRisk
            /// Past its planned end and not done.
            case overdue
        }

        public let task: Task
        public let weight: Double
        public let plannedStart: Date?
        public let plannedEnd: Date?
        /// Points booked through this week.
        public let done: Double
        public var remaining: Double { max(weight - done, 0) }
        /// Weeks from this week to the week of the planned end, both included; 0 once that week is past.
        public let weeksLeft: Int
        /// Points per week needed to finish by the planned end; nil when no week is left.
        public let neededPerWeek: Double?
        /// Points per week booked so far, over the weeks since the task started (planned or first booking); nil before it starts.
        public let pacePerWeek: Double?
        /// The last day of the week the task finishes in at `pacePerWeek`; nil without a pace.
        public let projectedFinish: Date?
        /// Days `projectedFinish` falls after the planned end (negative: early); nil when either is unknown.
        public let slipDays: Int?
        public let state: State
        public var id: String { task.id }
    }

    /// Each task with weight and dates, as of the week of `today`.
    static func recovery(plan: [PlannedTask], actual: Actual, today: Date,
                         calendar cal: Calendar = calendar) -> [Recovery] {
        let thisWeek = weekStart(today, calendar: cal)
        return plan.compactMap { p -> Recovery? in
            guard p.weight > 0, let start = p.start, let end = p.end else { return nil }
            let done = min(actual.done(p.task, through: today, calendar: cal), p.weight)
            let remaining = p.weight - done
            let endWeek = weekStart(end, calendar: cal)
            let weeksLeft = endWeek < thisWeek ? 0 : weeks(from: thisWeek, to: endWeek, calendar: cal).count

            let firstBooked = (actual.points[p.task.rawValue] ?? [:]).filter { $0.value > 0 }.keys.min()
                .flatMap { date(fromKey: $0, calendar: cal) }
            let began = [start, firstBooked].compactMap { $0 }.min()!
            let pace: Double? = began <= today ? done / Double(weeks(from: began, to: today, calendar: cal).count) : nil

            let finish: Date?
            if remaining <= 1e-9 {
                finish = actual.finished[p.task.rawValue]
            } else if let pace, pace > 1e-9 {
                let n = Int((remaining / pace).rounded(.up))
                finish = cal.date(byAdding: .day, value: 7 * n - 1, to: thisWeek)
            } else {
                finish = nil
            }
            let slip = finish.map { cal.dateComponents([.day], from: cal.startOfDay(for: end), to: cal.startOfDay(for: $0)).day ?? 0 }

            let state: Recovery.State
            if remaining <= 1e-9 { state = .done }
            else if endWeek < thisWeek { state = .overdue }
            else if began > today, done == 0 { state = .upcoming }
            else if let slip, slip <= 0 { state = .onTrack }
            else { state = .atRisk }

            return Recovery(task: p.task, weight: p.weight, plannedStart: start, plannedEnd: end, done: done,
                            weeksLeft: weeksLeft, neededPerWeek: weeksLeft > 0 && remaining > 1e-9 ? remaining / Double(weeksLeft) : nil,
                            pacePerWeek: pace, projectedFinish: finish,
                            slipDays: remaining <= 1e-9 && finish == nil ? nil : slip, state: state)
        }
    }
}
