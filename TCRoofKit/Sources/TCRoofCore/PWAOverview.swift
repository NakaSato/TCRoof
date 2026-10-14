import Foundation

/// One permit of a station on the iPad install row's `งานขออนุญาต` block (docs/ui/pwa-solar-survey-ipad-v3 FIX-01).
public struct InstallPermit: Hashable, Sendable {
    /// Who the permit is from, in the row's order: อปท. · กกพ. · กฟภ. · กว.
    public enum Authority: String, CaseIterable, Sendable {
        case local, erc, pea, engineer

        public var title: String {
            switch self {
            case .local: "อปท."
            case .erc: "กกพ."
            case .pea: "กฟภ."
            case .engineer: "กว."
            }
        }
    }

    /// Got, handed in and waiting, not handed in yet, or past its planned end.
    public enum State: String, Sendable { case done, submitted, pending, overdue }

    public var authority: Authority
    public var state: State

    public init(_ authority: Authority, _ state: State) { self.authority = authority; self.state = state }
}

/// One station of the PWA project in its installation phase, as the survey home's `งานติดตั้ง` overview shows it
/// (docs/ui/pwa-solar-survey-iphone-v2 §4). The host app fills it from the station's MP plan and daily reports.
public struct InstallStationSummary: Identifiable, Hashable, Sendable {
    public var id: String
    public var mpNumber: Int?
    public var name: String
    public var kWp: Double
    /// Percent done, 0…100.
    public var actual: Double
    /// Percent planned to date; nil when the station has no MP plan, so it is neither behind nor ahead.
    public var plan: Double?
    public var currentTask: String
    public var contractor: String
    public var dueDate: Date?
    /// Today's daily report is signed; nil when the station keeps no daily reports.
    public var reportSentToday: Bool?
    /// The permits the MP plan has tasks for; nil when it has none, or the station has no plan.
    public var permits: [InstallPermit]?

    public init(id: String, mpNumber: Int? = nil, name: String, kWp: Double = 0, actual: Double, plan: Double? = nil,
                currentTask: String = "", contractor: String = "", dueDate: Date? = nil, reportSentToday: Bool? = nil,
                permits: [InstallPermit]? = nil) {
        self.id = id; self.mpNumber = mpNumber; self.name = name; self.kWp = kWp; self.actual = actual; self.plan = plan
        self.currentTask = currentTask; self.contractor = contractor; self.dueDate = dueDate; self.reportSentToday = reportSentToday
        self.permits = permits
    }

    /// Actual minus plan in whole percent, as the row prints it; nil without a plan.
    public var variance: Int? { plan.map { Int(actual.rounded()) - Int($0.rounded()) } }
}

public enum InstallOverview {
    public enum Pace: Sendable { case behind, onPlan, ahead }
    /// `permit` (`ขออนุญาตค้าง`) is a filter of the iPad rows only.
    public enum RowFilter: String, CaseIterable, Sendable { case behind, noReport, permit, all }

    /// `เกณฑ์ "ช้ากว่าแผน"` when the setting is unset.
    public static let defaultThreshold = 2.0

    /// Behind at `threshold` percent or more under the plan, ahead at as much over it; nil without a plan.
    public static func pace(_ s: InstallStationSummary, threshold: Double = defaultThreshold) -> Pace? {
        guard let v = s.variance else { return nil }
        if Double(v) <= -threshold { return .behind }
        if Double(v) >= threshold { return .ahead }
        return .onPlan
    }

    /// One segment of a project card's install bar.
    public enum BarSegment: Sendable { case done, current, overdue, ahead }

    /// The install-phase card's bar (docs/ui/pwa-solar-survey-iphone-v3 §4): `count` equal segments over 0…100 %.
    /// Those the actual percent has passed are done and the one it is in is current; behind the plan, the ones the
    /// plan has reached by now are overdue.
    public static func bar(_ s: InstallStationSummary, threshold: Double = defaultThreshold, count: Int = 10) -> [BarSegment] {
        let step = 100 / Double(max(count, 1))
        let done = Int((min(max(s.actual.rounded(), 0), 100) / step).rounded(.down))
        let planned = pace(s, threshold: threshold) == .behind ? Int(((s.plan ?? 0).rounded() / step).rounded(.up)) : 0
        return (0..<max(count, 1)).map { i in i < done ? .done : i == done ? .current : i < planned ? .overdue : .ahead }
    }

    /// The values averaged by their stations' kWp, or equally when no station has one. nil for no values.
    public static func weighted(_ values: [(value: Double, kWp: Double)]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sum = values.reduce(0) { $0 + max($1.kWp, 0) }
        if sum <= 0 { return values.reduce(0) { $0 + $1.value } / Double(values.count) }
        return values.reduce(0) { $0 + $1.value * max($1.kWp, 0) } / sum
    }

    public struct Totals: Equatable, Sendable {
        public var count = 0
        public var kWp = 0.0
        /// kWp-weighted actual percent of every station.
        public var actual = 0
        /// kWp-weighted plan percent of the stations that have a plan; nil when none has.
        public var plan: Int?
        public var behind = 0, onPlan = 0, ahead = 0
        /// Stations that keep daily reports, and how many of them sent today's.
        public var reporting = 0, sent = 0
        public var unsent: Int { reporting - sent }
    }

    public static func totals(_ stations: [InstallStationSummary], threshold: Double = defaultThreshold) -> Totals {
        var t = Totals()
        t.count = stations.count
        t.kWp = stations.reduce(0) { $0 + max($1.kWp, 0) }
        t.actual = Int((weighted(stations.map { ($0.actual, $0.kWp) }) ?? 0).rounded())
        t.plan = weighted(stations.compactMap { s in s.plan.map { ($0, s.kWp) } }).map { Int($0.rounded()) }
        for s in stations {
            switch pace(s, threshold: threshold) {
            case .behind: t.behind += 1
            case .onPlan: t.onPlan += 1
            case .ahead: t.ahead += 1
            case nil: break
            }
            if let sent = s.reportSentToday { t.reporting += 1; if sent { t.sent += 1 } }
        }
        return t
    }

    public struct Contractor: Identifiable, Equatable, Sendable {
        public var name: String
        public var stations: Int
        public var behind: Int
        public var id: String { name }
    }

    /// The contractors of the stations by name, without the stations that name none.
    public static func contractors(_ stations: [InstallStationSummary], threshold: Double = defaultThreshold) -> [Contractor] {
        Dictionary(grouping: stations.filter { !$0.contractor.isEmpty }, by: \.contractor)
            .map { name, list in Contractor(name: name, stations: list.count, behind: list.filter { pace($0, threshold: threshold) == .behind }.count) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func matches(_ s: InstallStationSummary, _ filter: RowFilter, threshold: Double = defaultThreshold) -> Bool {
        switch filter {
        case .behind: pace(s, threshold: threshold) == .behind
        case .noReport: s.reportSentToday == false
        case .permit: permitsOpen(s)
        case .all: true
        }
    }

    // MARK: Permits

    /// The MP plan's permit tasks behind the four chips: 1.4 building permit or notice (อปท.), 1.5 พค.2 (กกพ.),
    /// 1.7 grid connection (กฟภ.) and 1.2 Engineering Approve, the engineer's signed design (กว.). Kick Off, the site
    /// handover and COP have no chip.
    public static let permitTasks: [(task: MasterSchedule.Task, authority: InstallPermit.Authority)] =
        [(.buildingPermit, .local), (.pk2, .erc), (.gridConnection, .pea), (.engineering, .engineer)]

    /// The chips of a station from `RoutineReport.permits`: a task under way counts as handed in, one past its
    /// planned end as overdue, and one not started, not due or undated as not handed in. A task the plan leaves out
    /// (พค.2 under 200 kVA) has no chip; nil when none of the four is in the plan.
    public static func permits(_ rows: [RoutineReport.PermitRow]) -> [InstallPermit]? {
        let out = permitTasks.compactMap { pair -> InstallPermit? in
            guard let row = rows.first(where: { $0.task == pair.task }) else { return nil }
            let state: InstallPermit.State = switch row.state {
            case .done: .done
            case .inProgress: .submitted
            case .late: .overdue
            case .notStarted, .notDue, .unplanned: .pending
            }
            return InstallPermit(pair.authority, state)
        }
        return out.isEmpty ? nil : out
    }

    /// Any permit not done yet.
    public static func permitsOpen(_ s: InstallStationSummary) -> Bool { s.permits?.contains { $0.state != .done } == true }

    /// The line beside `งานขออนุญาต x/n`: the overdue permits first, then those not handed in, then those waiting.
    public static func permitNote(_ permits: [InstallPermit]) -> String {
        func names(_ state: InstallPermit.State) -> String { permits.filter { $0.state == state }.map(\.authority.title).joined(separator: " ") }
        if permits.contains(where: { $0.state == .overdue }) { return names(.overdue) + " เกินกำหนด" }
        let pending = permits.filter { $0.state == .pending }.count
        if pending > 1 { return "ยังไม่ยื่น \(pending) รายการ" }
        if pending == 1 { return "ยังไม่ยื่น " + names(.pending) }
        if permits.contains(where: { $0.state == .submitted }) { return names(.submitted) + " ยื่นแล้ว รอผล" }
        return "ได้ครบทุกใบแล้ว"
    }

    /// The rows of a filter and, when set, one contractor: furthest behind the plan first, stations without a plan last.
    public static func rows(_ stations: [InstallStationSummary], filter: RowFilter, contractor: String? = nil,
                            threshold: Double = defaultThreshold) -> [InstallStationSummary] {
        stations.filter { matches($0, filter, threshold: threshold) && (contractor == nil || $0.contractor == contractor) }
            .sorted { a, b in
                switch (a.variance, b.variance) {
                case let (x?, y?): x != y ? x < y : a.name < b.name
                case (nil, nil): a.name < b.name
                case (let x, _): x != nil
                }
            }
    }
}

/// One handed-over station as the `บำรุงรักษา` overview shows it (§5). There is no monitoring feed yet, so nothing
/// fills it outside the DEBUG seed.
public struct MaintenanceStationSummary: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable { case normal, alarm, offline }

    public var id: String
    public var mpNumber: Int?
    public var name: String
    public var kWp: Double
    /// Today's energy and the energy expected today, kWh.
    public var energy: Double
    public var expected: Double
    /// Performance ratio, percent.
    public var pr: Double
    public var status: Status
    public var openRepairs: Int
    public var nextPM: Date?
    public var note: String

    public init(id: String, mpNumber: Int? = nil, name: String, kWp: Double = 0, energy: Double = 0, expected: Double = 0, pr: Double = 0,
                status: Status = .normal, openRepairs: Int = 0, nextPM: Date? = nil, note: String = "") {
        self.id = id; self.mpNumber = mpNumber; self.name = name; self.kWp = kWp; self.energy = energy; self.expected = expected
        self.pr = pr; self.status = status; self.openRepairs = openRepairs; self.nextPM = nextPM; self.note = note
    }

    /// False for an offline station and for one with no monitoring yet: its PR is shown as a dash and left out of the average.
    public var reportsPR: Bool { status != .offline && pr > 0 }

    /// Energy over expected, 0…1.
    public var yield: Double { expected > 0 ? min(max(energy / expected, 0), 1) : 0 }
}

/// A maintenance job coming due, for the overview's `งานที่ถึงกำหนดใน 14 วัน`.
public struct MaintenanceTask: Identifiable, Hashable, Sendable {
    public var id: String
    public var date: Date
    public var title: String
    public var assignee: String

    public init(id: String, date: Date, title: String, assignee: String) {
        self.id = id; self.date = date; self.title = title; self.assignee = assignee
    }
}

public enum MaintenanceOverview {
    public enum RowFilter: String, CaseIterable, Sendable { case issue, pmSoon, all }

    /// Days ahead that count as `ใกล้ถึง PM`.
    public static let soonDays = 14

    public struct Totals: Equatable, Sendable {
        public var count = 0
        public var kWp = 0.0
        public var energy = 0.0, expected = 0.0
        /// Energy over expected, percent.
        public var yield = 0
        /// kWp-weighted PR of the stations that report (`reportsPR`); nil when none does.
        public var pr: Int?
        public var normal = 0, alarm = 0, offline = 0
    }

    public static func totals(_ stations: [MaintenanceStationSummary]) -> Totals {
        var t = Totals()
        t.count = stations.count
        t.kWp = stations.reduce(0) { $0 + max($1.kWp, 0) }
        t.energy = stations.reduce(0) { $0 + $1.energy }
        t.expected = stations.reduce(0) { $0 + $1.expected }
        t.yield = t.expected > 0 ? Int((t.energy / t.expected * 100).rounded()) : 0
        t.pr = InstallOverview.weighted(stations.filter(\.reportsPR).map { ($0.pr, $0.kWp) }).map { Int($0.rounded()) }
        t.normal = stations.filter { $0.status == .normal }.count
        t.alarm = stations.filter { $0.status == .alarm }.count
        t.offline = stations.filter { $0.status == .offline }.count
        return t
    }

    public static func matches(_ s: MaintenanceStationSummary, _ filter: RowFilter, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch filter {
        case .issue: return s.status != .normal
        case .pmSoon:
            guard let pm = s.nextPM else { return false }
            let today = calendar.startOfDay(for: now)
            guard let limit = calendar.date(byAdding: .day, value: soonDays, to: today) else { return false }
            return pm >= today && pm <= limit
        case .all: return true
        }
    }

    /// The tasks due from today through `soonDays`, soonest first.
    public static func due(_ tasks: [MaintenanceTask], now: Date = .now, calendar: Calendar = .current) -> [MaintenanceTask] {
        let today = calendar.startOfDay(for: now)
        guard let limit = calendar.date(byAdding: .day, value: soonDays, to: today) else { return [] }
        return tasks.filter { $0.date >= today && $0.date <= limit }.sorted { $0.date < $1.date }
    }
}
