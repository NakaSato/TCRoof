import Foundation

/// The crew each contractor (or our own team) says it has, per week (CHA-78, PMBOK 5th §6.4): the supply that the
/// all-station loads (`Assistant.Strategy.priorities`) set the stations' demand against. One copy for the team, kept in
/// Firestore `config/crewSupply` and changed by whoever may set up the MP plan (`mp.setup`); the app syncs it through
/// `Store` (`onChange` out, `receive` in, the higher revision wins), as `TankStandard` does.
public struct CrewSupply: Codable, Equatable, Sendable {
    /// One crew group's people: `crew` every week, unless `weeks` names another number for a week.
    public struct Group: Codable, Equatable, Sendable {
        public var crew: Int
        /// The week's first day (`MasterSchedule.weekStart`, a Sunday; `yyyy-MM-dd`, Bangkok) → the people that week.
        public var weeks: [String: Int]

        public init(crew: Int, weeks: [String: Int] = [:]) { self.crew = crew; self.weeks = weeks }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            crew = try c.decodeIfPresent(Int.self, forKey: .crew) ?? 0
            weeks = try c.decodeIfPresent([String: Int].self, forKey: .weeks) ?? [:]
        }
    }

    /// Keyed by the crew group's label (`Assistant.Job.crewGroup`: `ผู้รับเหมา <name>`, `ทีม <team>`).
    public var groups: [String: Group]
    /// Raised by each save; who saved it and when.
    public var revision = 0
    public var savedBy: String?
    public var savedAt: Date?

    public init(groups: [String: Group] = [:]) { self.groups = groups }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = try c.decodeIfPresent([String: Group].self, forKey: .groups) ?? [:]
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        savedBy = try c.decodeIfPresent(String.self, forKey: .savedBy)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt)
    }

    /// The people `group` has in the week holding `week`; nil when nobody said.
    public func crew(_ group: String, week: Date, calendar cal: Calendar = MasterSchedule.calendar) -> Int? {
        guard let g = groups[group] else { return nil }
        return g.weeks[Self.key(week, cal)] ?? g.crew
    }

    /// Sets the people of `group` in one week; the group's usual number clears the week's own.
    public mutating func set(_ crew: Int, group: String, week: Date, calendar cal: Calendar = MasterSchedule.calendar) {
        var g = groups[group] ?? Group(crew: crew)
        g.weeks[Self.key(week, cal)] = crew == g.crew ? nil : max(crew, 0)
        groups[group] = g
    }

    /// Sets the usual people of `group`; 0 and no week of its own forgets the group.
    public mutating func set(usual crew: Int, group: String) {
        var g = groups[group] ?? Group(crew: 0)
        g.crew = max(crew, 0)
        g.weeks = g.weeks.filter { $0.value != g.crew }
        groups[group] = g.crew == 0 && g.weeks.isEmpty ? nil : g
    }

    /// The same numbers, whatever the revision and who saved them.
    public func sameValues(_ o: CrewSupply) -> Bool { groups == o.groups }

    public var problems: [String] {
        groups.compactMap { k, g in
            g.crew < 0 || g.crew > 1000 || g.weeks.values.contains { $0 < 0 || $0 > 1000 } ? "\(k): จำนวนคน 0–1000" : nil
        }
    }

    static func key(_ week: Date, _ cal: Calendar) -> String {
        ScheduleBrief.day(MasterSchedule.weekStart(week, calendar: cal), calendar: cal)
    }

    // MARK: JSON

    public var json: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return (try? String(data: e.encode(self), encoding: .utf8)) ?? "{}"
    }

    public static func decode(_ json: String) -> CrewSupply? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(CrewSupply.self, from: Data(json.utf8))
    }

    // MARK: Store

    public final class Store: @unchecked Sendable {
        public static let shared = Store()
        private let lock = NSLock()
        private var value: CrewSupply?
        private var url: URL?
        /// Called with each supply saved here (not with ones received), for the app to send.
        public var onChange: ((CrewSupply) -> Void)?

        public init() {}

        public func configure(url: URL) {
            lock.lock(); defer { lock.unlock() }
            self.url = url
            value = (try? String(contentsOf: url, encoding: .utf8)).flatMap(CrewSupply.decode)
        }

        /// The team's supply; nil until someone saves one.
        public var current: CrewSupply? { lock.lock(); defer { lock.unlock() }; return value }

        /// Saves `s` as the next revision, signed by `by`; nil and nothing saved when it has problems.
        @discardableResult
        public func save(_ s: CrewSupply, by: String?, at date: Date = Date()) -> CrewSupply? {
            guard s.problems.isEmpty else { return nil }
            var s = s
            lock.lock()
            s.revision = (value?.revision ?? 0) + 1
            s.savedBy = by; s.savedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
            value = s
            persist()
            lock.unlock()
            onChange?(s)
            return s
        }

        /// A supply from Firestore: kept when of a higher revision (the same: the later save).
        @discardableResult
        public func receive(_ s: CrewSupply) -> Bool {
            guard s.problems.isEmpty else { return false }
            lock.lock(); defer { lock.unlock() }
            if let old = value {
                guard s.revision > old.revision || (s.revision == old.revision && (s.savedAt ?? .distantPast) > (old.savedAt ?? .distantPast))
                else { return false }
            }
            value = s
            persist()
            return true
        }

        /// Tests, and a sign-out: forget the saved supply.
        public func reset() { lock.lock(); value = nil; lock.unlock() }

        private func persist() {
            guard let url, let value else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? value.json.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
