import Foundation
import Observation
import TCRoofCore

/// The Master Plan's project risk register (`config/risks`, CHA-81), as the team's Google Sheet last wrote it. Read
/// only: the sheet is where risks are edited. Team only, like the rule: an external account never sees it, even one
/// signed in on an iPad where a team member's copy is kept.
@MainActor
@Observable
final class RiskRegisterStore {
    static let shared = RiskRegisterStore()
    private static let key = "riskRegister.json"

    private var stored: RiskRegister?

    private init() {
        stored = UserDefaults.standard.string(forKey: Self.key).flatMap(RiskRegister.decode)
    }

    /// Nil for an external account, or before the sheet has written one.
    var register: RiskRegister? {
        MemberRole.shared.permissions.role == .external ? nil : stored
    }

    /// From the `config/risks` listener.
    func receive(json: String) {
        guard let r = RiskRegister.decode(json), r != stored else { return }
        stored = r
        UserDefaults.standard.set(json, forKey: Self.key)
    }

    /// The register's open risks that touch a station (`Job.overviewID`), high first.
    func open(for jobID: String, highOnly: Bool = false) -> [ProjectRisk] {
        register?.open(for: jobID, highOnly: highOnly) ?? []
    }
}
