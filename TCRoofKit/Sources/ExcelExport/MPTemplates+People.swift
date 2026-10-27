import Foundation
import TCRoofCore

/// Whose job each WBS row is (docs/specs/project-plan-wbs.md): the install cases name a role in `ผู้รับผิดชอบ` (`วศ.`,
/// `Admin`, `ผรม.`) where the 102 station files name that station's people (`เปรม`, `บีม`, `ผรม. B`). The rows' roles are
/// `wbs-roles.json`, made from the 20 cases by `tools/plan-template/wbs_roles.py`; every station file agrees with it.
public extension MPTemplates {
    enum Role: String, Codable, Sendable {
        case engineer, admin, contractor

        /// What a row says for the role when it names no one.
        public var word: String {
            switch self {
            case .engineer: "วศ."
            case .admin: "Admin"
            case .contractor: "ผรม."
            }
        }

        /// The job's person for the role, as a row names them (`ผรม. B` for the subcontractor).
        func person(in people: ProjectSetup) -> String? {
            switch self {
            case .engineer: people.engineer
            case .admin: people.admin
            case .contractor: people.contractor.map { "ผรม. " + $0 }
            }
        }
    }

    private struct Roles: Decodable { let roles: [String: Role] }

    /// Each row's role, by WBS code; rows of the utility (`กฟภ.`, `พพ.`) and rows without an owner are not in it.
    static let roles: [String: Role] = {
        guard let url = Bundle.module.url(forResource: "wbs-roles", withExtension: "json"),
              let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(Roles.self, from: data) else { return [:] }
        return file.roles
    }()

    /// What a row's `ผู้รับผิดชอบ` becomes for a station with `people`: a person (another station's, a case's `วศ.01`)
    /// gives way to the station's own for the row's role, or to the role when the station has no one for it. Nil keeps
    /// the text: a role, an empty cell, a row the table doesn't have, or the station's own person already.
    static func responsible(_ text: String?, code: String, people: ProjectSetup, inherit: Bool = false) -> String? {
        guard let role = role(code, inherit: inherit), let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
              !["วศ.", "Admin", "ผรม.", "ผรม"].contains(t) else { return nil }
        let want = role.person(in: people) ?? role.word
        return want == t ? nil : want
    }

    /// A row's role; `inherit` also takes the nearest row above it in the WBS that has one (the Inverter station's steps,
    /// `2.5.1.1`, carry 2.5.1's owner).
    static func role(_ code: String, inherit: Bool = false) -> Role? {
        if let r = roles[code] { return r }
        guard inherit, let dot = code.lastIndex(of: ".") else { return nil }
        return role(String(code[..<dot]), inherit: true)
    }

    /// The rows with `people` in `ผู้รับผิดชอบ` (`responsible`), a step taking its row's role.
    static func withPeople(_ wbs: [MasterSchedule.WorkItem], _ people: ProjectSetup) -> [MasterSchedule.WorkItem] {
        wbs.map { item in
            guard let want = responsible(item.responsible, code: item.code, people: people, inherit: true) else { return item }
            var i = item
            i.responsible = want
            return i
        }
    }
}
