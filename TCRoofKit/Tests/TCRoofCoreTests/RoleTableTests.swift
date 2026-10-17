import XCTest
@testable import TCRoofCore

/// The roles table in `Capability` is docs/reference/roles/user-roles.json, cell for cell.
final class RoleTableTests: XCTestCase {
    private struct File: Decodable {
        struct Group: Decodable { var capabilities: [Cap] }
        struct Cap: Decodable { var id: String; var roles: [String: Cell] }
        struct Cell: Decodable { var access: String }
        var groups: [Group]
    }

    func testTableMatchesTheReference() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../docs/reference/roles/user-roles.json")
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        let caps = file.groups.flatMap(\.capabilities)
        XCTAssertEqual(Set(caps.map(\.id)), Set(Capability.allCases.map(\.rawValue)))
        for cap in caps {
            let c = try XCTUnwrap(Capability(rawValue: cap.id))
            for role in UserRole.allCases {
                XCTAssertEqual(c.access(role).rawValue, cap.roles[role.rawValue]?.access, "\(cap.id) · \(role.rawValue)")
            }
        }
    }

    func testRoleFieldDefaultsToTheTeam() {
        XCTAssertEqual(UserRole(field: nil), .internalTeam)
        XCTAssertEqual(UserRole(field: "boss"), .internalTeam)
        XCTAssertEqual(UserRole(field: "external"), .external)
        XCTAssertEqual(UserRole(field: "manager"), .manager)
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
