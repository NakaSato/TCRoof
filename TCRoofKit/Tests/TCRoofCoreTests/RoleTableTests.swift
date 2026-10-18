import XCTest
@testable import TCRoofCore

/// The roles table in `Capability` is docs/reference/roles/user-roles.json, cell for cell.
final class RoleTableTests: XCTestCase {
    private struct File: Decodable {
        struct Role: Decodable { var id: String }
        struct Group: Decodable { var id: String; var label: String; var capabilities: [Cap] }
        struct Cap: Decodable { var id: String; var label: String; var roles: [String: Cell] }
        struct Cell: Decodable { var access: String; var note: String? }
        var roles: [Role]
        var groups: [Group]
    }

    private func file() throws -> File {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../docs/reference/roles/user-roles.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    /// The four roles (the Maintainer included), cell for cell.
    func testTableMatchesTheReference() throws {
        let file = try file()
        XCTAssertEqual(file.roles.map(\.id), UserRole.every.map(\.rawValue))
        let caps = file.groups.flatMap(\.capabilities)
        XCTAssertEqual(Set(caps.map(\.id)), Set(Capability.allCases.map(\.rawValue)))
        for cap in caps {
            let c = try XCTUnwrap(Capability(rawValue: cap.id))
            for role in UserRole.every {
                XCTAssertEqual(c.access(role).rawValue, cap.roles[role.rawValue]?.access, "\(cap.id) · \(role.rawValue)")
            }
        }
    }

    /// The matrix's groups, labels and conditions are the reference's.
    func testLabelsMatchTheReference() throws {
        let file = try file()
        XCTAssertEqual(file.groups.map(\.id), Capability.groups.map(\.id))
        XCTAssertEqual(file.groups.map(\.label), Capability.groups.map(\.label))
        XCTAssertEqual(file.groups.map { $0.capabilities.map(\.id) }, Capability.groups.map { $0.capabilities.map(\.rawValue) })
        for cap in file.groups.flatMap(\.capabilities) {
            let c = try XCTUnwrap(Capability(rawValue: cap.id))
            XCTAssertEqual(c.label, cap.label, cap.id)
            for role in UserRole.allCases { XCTAssertEqual(c.note(role), cap.roles[role.rawValue]?.note, "\(cap.id) · \(role.rawValue)") }
        }
    }

    func testRoleFieldDefaultsToTheTeam() {
        XCTAssertEqual(UserRole(field: nil), .internalTeam)
        XCTAssertEqual(UserRole(field: "boss"), .internalTeam)
        XCTAssertEqual(UserRole(field: "external"), .external)
        XCTAssertEqual(UserRole(field: "manager"), .manager)
        XCTAssertEqual(UserRole(field: "maintainer"), .maintainer)
        // the Maintainer isn't one of the roles a manager sets
        XCTAssertEqual(UserRole.allCases, [.manager, .internalTeam, .external])
    }

    func testTheMaintainerDoesEverythingButBOQ() {
        let dev = Permissions(role: .maintainer, email: "dev@tcroof.co")
        for c in Capability.allCases where c != .boqDraft && c != .boqApprove { XCTAssertTrue(dev.can(c), c.rawValue) }
        XCTAssertFalse(dev.can(.boqDraft))
        for role in UserRole.allCases {
            for c in Capability.maintainerOnly { XCTAssertFalse(Permissions(role: role, email: "a@b.c").can(c), "\(role) · \(c)") }
        }
        // a Maintainer hears every job's news, as a manager does
        XCTAssertTrue(dev.hearsNews(JobAccess(teamMembers: ["eng@tcroof.co"])))
    }

    private let job = JobAccess(externals: ["Contractor@Example.com"], supervisor: "eng@tcroof.co")

    func testExternalActsOnlyOnAssignedJobs() {
        let me = Permissions(role: .external, email: " contractor@example.com ")
        let other = Permissions(role: .external, email: "someone@example.com")
        XCTAssertTrue(me.can(.dailyFill, on: job))
        XCTAssertTrue(me.can(.iecFillSubmit, on: job))
        XCTAssertFalse(other.can(.dailyFill, on: job))
        XCTAssertFalse(me.can(.dailyFill), "no job, nothing to be assigned to")
        XCTAssertFalse(me.can(.iecClose, on: job))
        XCTAssertFalse(me.can(.dailySign, on: job))
        XCTAssertFalse(me.can(.mpProgress, on: job))
        XCTAssertFalse(me.can(.moveToInstall, on: job))
    }

    func testTeamMembersNameTheJobAndHearItsNews() {
        let job = JobAccess(externals: ["con@x.co"], supervisor: "Sup@TCRoof.co", teamMembers: [" Eng@TCRoof.co "])
        let eng = Permissions(role: .internalTeam, email: "eng@tcroof.co")
        let sup = Permissions(role: .internalTeam, email: "sup@tcroof.co")
        let other = Permissions(role: .internalTeam, email: "other@tcroof.co")
        let boss = Permissions(role: .manager, email: "boss@tcroof.co")
        let con = Permissions(role: .external, email: "con@x.co")
        XCTAssertTrue(eng.isOnTeam(job) && eng.isNamed(job))
        XCTAssertTrue(sup.isNamed(job) && !sup.isOnTeam(job))
        XCTAssertTrue(con.isNamed(job))
        XCTAssertFalse(other.isNamed(job))
        // news: the named, and a manager; the rest of the team doesn't hear it
        XCTAssertTrue(eng.hearsNews(job) && sup.hearsNews(job) && con.hearsNews(job) && boss.hearsNews(job))
        XCTAssertFalse(other.hearsNews(job))
        // nobody of ours named (a contractor alone doesn't count): everyone hears it
        let unowned = JobAccess(externals: ["con@x.co"])
        XCTAssertFalse(unowned.hasOwners)
        XCTAssertTrue(other.hearsNews(unowned))
        XCTAssertTrue(other.hearsNews(nil))
        // naming on the team opens nothing: the team sees every job anyway, and an external member only theirs
        XCTAssertTrue(other.can(.dailyFill, on: job))
        XCTAssertFalse(Permissions(role: .external, email: "eng@tcroof.co").can(.dailyFill, on: JobAccess(teamMembers: ["eng@tcroof.co"])))
        XCTAssertTrue(eng.can(.assignTeam) && boss.can(.assignTeam))
        XCTAssertFalse(con.can(.assignTeam, on: job))
    }

    /// Daily reports are signed by the job's own people; a job naming none of ours, by any team member.
    func testDailyReportsAreSignedByTheJobsPeople() {
        let job = JobAccess(externals: ["con@x.co"], supervisor: "sup@tcroof.co", teamMembers: ["eng@tcroof.co"])
        XCTAssertTrue(Permissions(role: .internalTeam, email: "eng@tcroof.co").can(.dailySign, on: job))
        XCTAssertTrue(Permissions(role: .internalTeam, email: "sup@tcroof.co").can(.dailySign, on: job))
        XCTAssertTrue(Permissions(role: .manager, email: "boss@tcroof.co").can(.dailySign, on: job))
        XCTAssertFalse(Permissions(role: .internalTeam, email: "other@tcroof.co").can(.dailySign, on: job), "not on this job")
        XCTAssertFalse(Permissions(role: .external, email: "con@x.co").can(.dailySign, on: job), "the contractor fills, never signs")
        XCTAssertTrue(Permissions(role: .internalTeam, email: "other@tcroof.co").can(.dailySign, on: JobAccess(externals: ["con@x.co"])),
                      "a job naming none of ours: any team member")
    }

    func testViewOnlyCells() {
        let me = Permissions(role: .external, email: "contractor@example.com")
        XCTAssertFalse(me.can(.iclChecklist, on: job))
        XCTAssertTrue(me.canView(.iclChecklist, on: job))
        XCTAssertFalse(Permissions(role: .external, email: "x@y.z").canView(.iclChecklist, on: job))
        XCTAssertTrue(me.canView(.toolsRegister))
        XCTAssertFalse(me.can(.toolsRegister))
        let team = Permissions(role: .internalTeam, email: "a@tcroof.co")
        XCTAssertTrue(team.canView(.companyDocs))
        XCTAssertFalse(team.can(.companyDocs))
    }

    func testFinalSignoffIsTheManagerOrTheSupervisor() {
        XCTAssertTrue(Permissions(role: .manager, email: "m@tcroof.co").can(.finalSignoff, on: job))
        XCTAssertTrue(Permissions(role: .internalTeam, email: "ENG@tcroof.co").can(.finalSignoff, on: job))
        XCTAssertFalse(Permissions(role: .internalTeam, email: "other@tcroof.co").can(.finalSignoff, on: job))
        XCTAssertTrue(Permissions(role: .internalTeam, email: "other@tcroof.co").canView(.finalSignoff, on: job))
    }

    func testTeamAndManager() {
        let team = Permissions.team
        XCTAssertTrue(team.can(.iecClose))
        XCTAssertTrue(team.can(.dailySign))
        XCTAssertFalse(team.can(.jobDelete))
        XCTAssertFalse(team.can(.usersManage))
        XCTAssertTrue(Permissions(role: .manager, email: "m@tcroof.co").can(.jobDelete))
        for role in UserRole.allCases { XCTAssertFalse(Permissions(role: role, email: "a@b.c").can(.boqDraft)) }
    }
}
