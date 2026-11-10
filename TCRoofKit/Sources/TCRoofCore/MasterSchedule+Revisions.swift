import Foundation

/// The MP plan's approved baselines (CHA-79, PMBOK 5th §6.6.3.1 schedule baseline, §4.5 integrated change control):
/// each confirmed re-plan keeps the plan it approved as the next `REV`, with who approved it, when, why and the change
/// request it came from. REV 00 is the plan before the first re-plan (`Input.baseline`); progress is always measured
/// against the latest, which is the plan itself.
public extension MasterSchedule {
    struct Revision: Codable, Equatable, Sendable, Identifiable {
        /// 0 for the first plan, then one more per confirmed re-plan.
        public var number: Int
        /// When it was approved; nil for a REV 00 kept from a plan made before revisions were recorded.
        public var at: Date?
        /// The email of who confirmed it; nil for REV 00.
        public var by: String?
        public var reason: String
        /// The change request it came from (`site.change_request`), as its number or title; nil when none.
        public var changeRequest: String?
        /// The plan as approved: task raw value → dates and weight.
        public var tasks: [String: FixedTask]

        public init(number: Int, at: Date?, by: String?, reason: String, changeRequest: String? = nil,
                    tasks: [String: FixedTask]) {
            self.number = number; self.at = at; self.by = by; self.reason = reason
            self.changeRequest = changeRequest; self.tasks = tasks
        }

        public var id: Int { number }

        /// `REV 02`.
        public var label: String { MasterSchedule.revisionLabel(number) }

        /// The last end of its site tasks (parts 2 and 3), as `ScheduleBrief.installEnd` reads a plan.
        public var installEnd: Date? {
            Task.allCases.filter { $0.part != .permit }.compactMap { tasks[$0.rawValue]?.end }.max()
        }
    }

    /// `REV 00`, `REV 02`: the plan files' and the plan screen's way of naming a revision.
    static func revisionLabel(_ number: Int) -> String { String(format: "REV %02d", number) }
}

public extension MasterSchedule.Input {
    /// The plan's current revision: the last one recorded, else `replans` (re-plans confirmed before revisions were
    /// recorded, `Actual.confirmations`), so a station re-planned twice before reads REV 02.
    func revisionNumber(replans: Int = 0) -> Int {
        revisions?.last?.number ?? replans
    }

    /// Records this plan, the result of a re-plan of `previous`, as the next revision. The first one recorded also
    /// keeps REV 00, the plan before the first re-plan (the baseline when there is one, else `previous`), so the history
    /// starts where the plan did. `replans` counts the re-plans confirmed before revisions were recorded.
    mutating func recordRevision(from previous: MasterSchedule.Input, replans: Int = 0, by: String, at: Date,
                                 reason: String, changeRequest: String? = nil,
                                 calendar cal: Calendar = MasterSchedule.calendar) {
        var list = previous.revisions ?? []
        if list.isEmpty {
            list.append(.init(number: 0, at: nil, by: nil, reason: "",
                              tasks: previous.baseline ?? previous.fixedTasks(calendar: cal)))
        }
        let cr = changeRequest?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = max(list.last?.number ?? 0, replans) + 1
        list.append(.init(number: next, at: at, by: by, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                          changeRequest: cr?.isEmpty == false ? cr : nil, tasks: fixedTasks(calendar: cal)))
        revisions = list
    }
}
