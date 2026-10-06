import Foundation

/// iPhone plan calendar (docs/ui/tcroof-plan-calendar-iphone): every install job gets one lane for the whole
/// visible range, so its range line stays on the same row from week to week.
public enum PlanLanes {
    /// Greedy interval packing: earliest start first, each job taking the first lane whose last job ended on an
    /// earlier day. `start` and `end` are the first and last install days (inclusive).
    public static func assign<ID: Hashable>(_ jobs: [(id: ID, start: Date, end: Date)],
                                            calendar: Calendar = .current) -> [ID: Int] {
        let days = jobs.enumerated().map { i, j in
            (i: i, id: j.id, s: calendar.startOfDay(for: j.start), e: calendar.startOfDay(for: j.end))
        }
        .sorted { $0.s != $1.s ? $0.s < $1.s : $0.i < $1.i }
        var laneEnds: [Date] = []
        var lanes: [ID: Int] = [:]
        for job in days {
            if let free = laneEnds.firstIndex(where: { $0 < job.s }) {
                laneEnds[free] = job.e
                lanes[job.id] = free
            } else {
                lanes[job.id] = laneEnds.count
                laneEnds.append(job.e)
            }
        }
        return lanes
    }

    /// The jobs' segments in the week starting at `weekStart`, each on its lane from `lanes` (0 when missing),
    /// earliest first. Edges carried over from or into another week are flagged so the line can run on square.
    public static func segments<ID: Hashable>(_ jobs: [(id: ID, start: Date, end: Date)], lanes: [ID: Int],
                                              weekStart: Date, calendar: Calendar = .current) -> [PlanLayout.Bar<ID>] {
        let ws = calendar.startOfDay(for: weekStart)
        func column(_ d: Date) -> Int { calendar.dateComponents([.day], from: ws, to: calendar.startOfDay(for: d)).day ?? 0 }
        typealias Span = (i: Int, id: ID, s: Int, e: Int)
        let spans: [Span] = jobs.enumerated().map { i, j in (i: i, id: j.id, s: column(j.start), e: column(j.end)) }
        let inWeek = spans.filter { $0.s <= 6 && $0.e >= 0 }.sorted { a, b in a.s != b.s ? a.s < b.s : a.i < b.i }
        return inWeek.map { j -> PlanLayout.Bar<ID> in
            PlanLayout.Bar(id: j.id, lane: lanes[j.id] ?? 0, startColumn: max(j.s, 0), endColumn: min(j.e, 6),
                           continuesBefore: j.s < 0, continuesAfter: j.e > 6)
        }
    }
}
