import XCTest
import TCRoofCore
@testable import TCRoof

final class PermissionsTests: XCTestCase {

    func testEmailNormalization() {
        XCTAssertEqual(Permissions.normalized("  User@Example.COM  "), "user@example.com")
        XCTAssertEqual(Permissions.normalized(""), "")
    }

    func testExternalRoleRestrictions() {
        let external = Permissions(role: .external, email: "subcontractor@example.com")
        XCTAssertFalse(external.role.managesTeam)
        XCTAssertEqual(external.role, .external)
    }

    func testMaintainerCapabilities() {
        let maintainer = Permissions(role: .maintainer, email: "admin@tcroof.com")
        XCTAssertTrue(maintainer.role.managesTeam)
        XCTAssertTrue(maintainer.can(.usersManage))
    }
}
