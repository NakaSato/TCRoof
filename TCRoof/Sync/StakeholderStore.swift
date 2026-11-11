import Foundation
import Observation
import TCRoofCore

/// The Master Plan's stakeholder list (`config/stakeholders`, CHA-82), as the team's Google Sheet last wrote it. Read
/// only: the sheet is where it is edited. Team only, like the rule and `RiskRegisterStore`.
@MainActor
@Observable
final class StakeholderStore {
    static let shared = StakeholderStore()
    private static let key = "stakeholders.json"

    private var stored: StakeholderList?
    /// Moves with each new list, for caches keyed on it (the plan page's board).
    private(set) var revision = 0

    private init() {
        stored = UserDefaults.standard.string(forKey: Self.key).flatMap(StakeholderList.decode)
    }

    /// Nil for an external account, or before the sheet has written one.
    var list: StakeholderList? {
        MemberRole.shared.permissions.role == .external ? nil : stored
    }

    /// From the `config/stakeholders` listener.
    func receive(json: String) {
        guard let l = StakeholderList.decode(json), l != stored else { return }
        stored = l
        revision += 1
        UserDefaults.standard.set(json, forKey: Self.key)
    }

    /// The reports due from today for `days` days; the handover rows count back from these jobs' handovers (the PWA
    /// stations not yet completed).
    func dues(jobs: [Job], from: Date = .now, days: Int = 14) -> [StakeholderList.Due] {
        guard let list, !list.stakeholders.isEmpty else { return [] }
        return list.dues(stations: jobs.stakeholderStations, from: from, days: days)
    }
}

extension Array where Element == Job {
    /// The PWA stations not completed, with their handover day (the MP plan's install end, else the job's).
    var stakeholderStations: [StakeholderList.Station] {
        pwaStations.filter { $0.status != .completed }.map { job in
            let label = [job.mpNumber.map { "MP \($0)" } ?? job.code, job.stationName].filter { !$0.isEmpty }.joined(separator: " ")
            return StakeholderList.Station(id: job.overviewID, label: label, handover: job.scheduleInput?.installEnd ?? job.installEnd)
        }
    }
}
