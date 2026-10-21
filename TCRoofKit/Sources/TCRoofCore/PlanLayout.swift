import Foundation

/// Wall-planner layout for the construction plan calendar: install jobs as bars across the days they run.
public enum PlanLayout {
    /// One install job's bar inside one week row.
    public struct Bar<ID: Hashable>: Equatable {
        public let id: ID
        /// 0…`maxLanes - 1`, top to bottom under the date.
        public let lane: Int
        /// Columns 0 (Sunday) … 6 (Saturday), clipped to the week, inclusive.
        public let startColumn: Int
        public let endColumn: Int
        /// The job started before this week: square left edge and `ต่อ |`.
        public let continuesBefore: Bool
        /// The job runs on past this week: square right edge.
        public let continuesAfter: Bool

        public var span: Int { endColumn - startColumn + 1 }
    }

    /// Bars for the jobs overlapping the week starting at `weekStart`. `start` and `end` are the first and last
    /// install days (inclusive). Earliest first, longer first on the same day; each takes the first lane free
    /// before its first column. Jobs needing a lane past `maxLanes` get no bar (the day panel still lists them).
    public static func lanes<ID: Hashable>(for jobs: [(id: ID, start: Date, end: Date)], weekStart: Date,
                                           maxLanes: Int = 3, calendar: Calendar = .current) -> [Bar<ID>] {
        let ws = calendar.startOfDay(for: weekStart)
        func column(_ d: Date) -> Int { calendar.dateComponents([.day], from: ws, to: calendar.startOfDay(for: d)).day ?? 0 }
        let all: [(id: ID, s: Int, e: Int)] = jobs.map { (id: $0.id, s: column($0.start), e: column($0.end)) }
        let spans = all.filter { $0.s <= 6 && $0.e >= 0 }.sorted { a, b in
            if a.s != b.s { return a.s < b.s }
            return a.e - a.s > b.e - b.s
        }
        var laneEnds: [Int] = []
        var bars: [Bar<ID>] = []
        for job in spans {
            let c0 = max(job.s, 0), c1 = min(job.e, 6)
            let lane: Int
            if let free = laneEnds.firstIndex(where: { $0 < c0 }) { lane = free } else { lane = laneEnds.count; laneEnds.append(-1) }
            laneEnds[lane] = c1
            guard lane < maxLanes else { continue }
            bars.append(Bar(id: job.id, lane: lane, startColumn: c0, endColumn: c1,
                            continuesBefore: job.s < 0, continuesAfter: job.e > 6))
        }
        return bars
    }

    /// The customer as a bar shows it: without a leading `คุณ` or `บริษัท `.
    public static func shortName(_ customer: String) -> String {
        for prefix in ["บริษัท ", "คุณ"] where customer.hasPrefix(prefix) {
            return String(customer.dropFirst(prefix.count))
        }
        return customer
    }
}
