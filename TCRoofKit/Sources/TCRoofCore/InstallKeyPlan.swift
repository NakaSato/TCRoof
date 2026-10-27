import Foundation

/// The iPad install tracking page's `Key Plan` view (docs/ui/install-tracking-ipad-keyplan): one point per MP install
/// task × one of its locations, placed where the station's key plan has that location (`Settings.keyPoints`), coloured
/// by how the location's progress stands against the task's plan for today. Nothing here is stored.
public struct InstallKeyPlan: Equatable, Sendable {
    public enum State: Equatable, Sendable { case done, onPlan, late, notStarted }

    public struct Point: Equatable, Sendable, Identifiable {
        /// The MP task's raw value (`InstallGantt.Row.id`).
        public var task: String
        /// `2.1`.
        public var code: String
        /// 1-based place in the task's locations.
        public var number: Int
        /// nil when the task has no location: such a point can't be placed.
        public var location: String?
        /// The location's latest reported %, 0…100.
        public var actual: Double
        /// The task's planned % by today, 0…100.
        public var planned: Double
        /// Where it sits on the picture, as fractions; nil while unplaced.
        public var at: (x: Double, y: Double)?

        public var id: String { "\(task)#\(number)" }
        /// `2.1-3`.
        public var label: String { "\(code)-\(number)" }
        public var placed: Bool { at != nil }
        public var state: State { InstallKeyPlan.state(actual: actual, planned: planned) }

        public init(task: String, code: String, number: Int, location: String?, actual: Double, planned: Double,
                    at: (x: Double, y: Double)? = nil) {
            self.task = task; self.code = code; self.number = number; self.location = location
            self.actual = actual; self.planned = planned; self.at = at
        }

        public static func == (a: Point, b: Point) -> Bool {
            a.task == b.task && a.number == b.number && a.location == b.location && a.actual == b.actual
                && a.planned == b.planned && a.at?.x == b.at?.x && a.at?.y == b.at?.y
        }
    }

    public struct Group: Equatable, Sendable, Identifiable {
        public var task: String
        public var code: String
        public var title: String
        public var points: [Point]
        public var id: String { task }
        /// The points' mean %.
        public var average: Double { points.isEmpty ? 0 : points.reduce(0) { $0 + $1.actual } / Double(points.count) }
    }

    public var groups: [Group]

    public init(groups: [Group]) { self.groups = groups }

    /// The Gantt's install tasks (their sub-rows are the task's locations with their latest %), the planned % of each
    /// task by today (`MasterSchedule.Status.plannedByTask`, by raw value) and where each location sits on the plan.
    public init(rows: [InstallGantt.Row], planned: [String: Double], settings: RoutineReport.Settings) {
        groups = rows.map { row in
            let plan = min(max(planned[row.id] ?? 0, 0), 100)
            let subs: [(String?, Double)] = row.subs.isEmpty
                ? [(nil, row.percent)]
                : row.subs.map { ($0.title.isEmpty || $0.title == Self.noLocation ? nil : $0.title, $0.percent) }
            let points = subs.enumerated().map { i, s in
                Point(task: row.id, code: row.code, number: i + 1, location: s.0, actual: min(max(s.1, 0), 100), planned: plan,
                      at: s.0.flatMap { settings.keyPoint($0) })
            }
            return Group(task: row.id, code: row.code, title: row.title, points: points)
        }
    }

    /// `RoutineReport.places`' name for a place reported with no location.
    static let noLocation = "ไม่ระบุตำแหน่ง"

    public var points: [Point] { groups.flatMap(\.points) }
    public var placedCount: Int { points.filter(\.placed).count }
    public var unplaced: [Point] { points.filter { !$0.placed } }

    /// done at 100 %, late under today's plan, not started at 0 % with nothing planned yet, else on plan.
    public static func state(actual: Double, planned: Double) -> State {
        if actual >= 99.95 { return .done }
        if actual + 0.05 < planned { return .late }
        if actual <= 0 && planned <= 0 { return .notStarted }
        return .onPlan
    }

    /// The next point to place after `current`: the first unplaced one with a location after it, else from the top;
    /// nil when every placeable point is placed.
    public func nextUnplaced(after current: String?) -> Point? {
        let all = points.filter { !$0.placed && $0.location != nil }
        guard let current, let i = points.firstIndex(where: { $0.id == current }) else { return all.first }
        let after = points[(i + 1)...].first { !$0.placed && $0.location != nil }
        return after ?? all.first { $0.id != current }
    }

    /// The other points at the same location as `point`.
    public func sharing(_ point: Point) -> [Point] {
        guard let l = point.location else { return [] }
        return points.filter { $0.location == l && $0.id != point.id }
    }

    /// Where each placed point's pin sits relative to its location, in points: those sharing a location fan out on a
    /// small circle, `spacing` apart, so none hides another; a location's only point sits on it.
    public func fanOffsets(spacing: Double = 26) -> [String: (dx: Double, dy: Double)] {
        var out: [String: (dx: Double, dy: Double)] = [:]
        var byLocation: [String: [Point]] = [:], order: [String] = []
        for p in points where p.placed {
            guard let l = p.location else { continue }
            if byLocation[l] == nil { order.append(l) }
            byLocation[l, default: []].append(p)
        }
        for l in order {
            let ps = byLocation[l] ?? []
            for (i, p) in ps.enumerated() { out[p.id] = Self.fan(index: i, count: ps.count, spacing: spacing) }
        }
        return out
    }

    /// The `index`th of `count` places on a circle whose neighbours are `spacing` apart, starting at the top.
    public static func fan(index: Int, count: Int, spacing: Double) -> (dx: Double, dy: Double) {
        guard count > 1 else { return (0, 0) }
        // two points: side by side; more: the circle whose chord between neighbours is `spacing`
        let r = count == 2 ? spacing / 2 : spacing / (2 * sin(Double.pi / Double(count)))
        let a = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(count) + (count == 2 ? Double.pi / 2 : 0)
        return (r * cos(a), r * sin(a))
    }
}
