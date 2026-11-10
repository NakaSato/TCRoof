import Foundation

/// The handover as a likely date and a late case (CHA-80, PMBOK 5th §6.5.2.4 three-point estimating). The tasks the team
/// doesn't control decide it: PPIM's design review (1.2), the อ.1 permit (1.4), พพ.'s comments on พค.2 (1.5) and the
/// กฟภ. inspection (1.7). Each open one gets an optimistic, most likely and pessimistic duration (multiples of its planned
/// duration, a triangular distribution), and 1,000 seeded runs push the point forecast (`InstallTracking.forecastEnd`) by
/// the days a task overruns past its spare days to the install end. Other tasks keep their one duration.
public enum HandoverRange {
    /// Multiples of a task's planned duration.
    public struct Estimate: Codable, Equatable, Sendable {
        public var optimistic: Double
        public var mostLikely: Double
        public var pessimistic: Double

        public init(_ optimistic: Double, _ mostLikely: Double, _ pessimistic: Double) {
            self.optimistic = optimistic; self.mostLikely = mostLikely; self.pessimistic = pessimistic
        }
    }

    /// The defaults per authority task; the plan's other tasks have none.
    public static let defaults: [MasterSchedule.Task: Estimate] = [
        .engineering: Estimate(0.8, 1, 2),       // PPIM design review
        .buildingPermit: Estimate(0.8, 1, 1.75), // อ.1
        .pk2: Estimate(0.8, 1, 2.5),             // พพ. comments on พค.2
        .gridConnection: Estimate(0.8, 1, 2.5),  // กฟภ. inspection
    ]

    public struct Result: Equatable, Sendable {
        /// P50 and P90 handover days.
        public var likely: Date
        public var late: Date
        /// The open authority tasks the range comes from, in plan order.
        public var tasks: [MasterSchedule.Task]

        public init(likely: Date, late: Date, tasks: [MasterSchedule.Task]) {
            self.likely = likely; self.late = late; self.tasks = tasks
        }
    }

    /// The range around `base` (the point forecast); nil when no authority task with dates is still open.
    public static func forecast(plan: [MasterSchedule.PlannedTask], actual: MasterSchedule.Actual, base: Date, installEnd: Date,
                                today: Date, estimates: [MasterSchedule.Task: Estimate] = defaults, runs: Int = 1000,
                                seed: UInt64 = 0x7C_80, calendar cal: Calendar = MasterSchedule.calendar) -> Result? {
        let day = cal.startOfDay(for: today), end = cal.startOfDay(for: installEnd), base = cal.startOfDay(for: base)
        func days(_ a: Date, _ b: Date) -> Int { cal.dateComponents([.day], from: a, to: b).day ?? 0 }
        struct Open { let task: MasterSchedule.Task; let estimate: Estimate; let begin: Date; let duration: Int; let plannedEnd: Date; let spare: Int }
        let open: [Open] = plan.compactMap { p in
            guard let e = estimates[p.task], let s = p.start, let f = p.end, p.weight > 0 else { return nil }
            let raw = p.task.rawValue
            guard actual.finished[raw] == nil, actual.done(p.task, through: day, calendar: cal) < p.weight - 1e-9 else { return nil }
            let s0 = cal.startOfDay(for: s), f0 = cal.startOfDay(for: f), duration = days(s0, f0)
            guard duration > 0 else { return nil }
            let begin = actual.started[raw].map { cal.startOfDay(for: $0) } ?? s0
            return Open(task: p.task, estimate: e, begin: begin, duration: duration, plannedEnd: f0, spare: max(0, days(f0, end)))
        }
        guard !open.isEmpty, runs > 0 else { return nil }
        var rng = SplitMix64(seed: seed)
        var pushes: [Int] = []
        pushes.reserveCapacity(runs)
        for _ in 0..<runs {
            var push = 0
            for o in open {
                let x = triangular(o.estimate, rng.unit())
                // days past its planned end; an open task ends today at the soonest
                let overrun = max(days(o.plannedEnd, o.begin) + Int((x * Double(o.duration)).rounded()), days(o.plannedEnd, day))
                push = max(push, overrun - o.spare)
            }
            pushes.append(max(push, 0))
        }
        pushes.sort()
        let p50 = pushes[(runs - 1) / 2], p90 = pushes[min(runs - 1, Int((Double(runs) * 0.9).rounded(.up)) - 1)]
        func move(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: base) ?? base }
        return Result(likely: move(p50), late: move(p90), tasks: open.map(\.task))
    }

    /// A triangular draw for `u` in [0, 1).
    static func triangular(_ e: Estimate, _ u: Double) -> Double {
        let a = e.optimistic, m = e.mostLikely, b = e.pessimistic
        guard b - a > 1e-12 else { return m }
        let c = (m - a) / (b - a)
        return u < c ? a + ((u * (b - a) * (m - a)).squareRoot()) : b - (((1 - u) * (b - a) * (b - m)).squareRoot())
    }

    /// A small seeded generator, so the same plan always gives the same range.
    struct SplitMix64 {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    }
}
