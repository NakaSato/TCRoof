import XCTest
@testable import TCRoofCore

/// จัดการผู้ใช้และสิทธิ์: role overrides, locked cells, role changes and the developer key.
final class UserAdminTests: XCTestCase {
    func testAnOverrideChangesTheResult() {
        var o = RoleOverrides()
        o[.internalTeam, .toolsRegister] = .view
        let team = Permissions(role: .internalTeam, email: "a@tcroof.co", overrides: o)
        XCTAssertFalse(team.can(.toolsRegister))
        XCTAssertTrue(team.canView(.toolsRegister))
        XCTAssertTrue(Permissions(role: .internalTeam, email: "a@tcroof.co").can(.toolsRegister), "no override: the table")
        // a manager's cell isn't touched by the team's override
        XCTAssertTrue(Permissions(role: .manager, email: "m@tcroof.co", overrides: o).can(.toolsRegister))
    }

    func testALockedCapabilityIgnoresAnOverride() {
        let o = RoleOverrides(document: ["internal|job.delete": "deny", "external|iec.close": "allow", "manager|users.manage": "deny",
                                         "internal|users.suspend": "allow", "manager|boq.draft": "allow", "maintainer|job.list": "deny"])
        XCTAssertTrue(Permissions(role: .internalTeam, email: "a@tcroof.co", overrides: o).can(.jobDelete), "firestore.rules decides")
        XCTAssertFalse(Permissions(role: .external, email: "c@x.co", overrides: o).can(.iecClose))
        XCTAssertTrue(Permissions(role: .manager, email: "m@tcroof.co", overrides: o).can(.usersManage))
        XCTAssertFalse(Permissions(role: .internalTeam, email: "a@tcroof.co", overrides: o).can(.usersSuspend))
        XCTAssertFalse(Permissions(role: .manager, email: "m@tcroof.co", overrides: o).can(.boqDraft))
        XCTAssertNil(o[.maintainer, .jobList], "the Maintainer has no column")
        XCTAssertTrue(Capability.jobDelete.isLocked(for: .internalTeam))
        XCTAssertFalse(Capability.toolsRegister.isLocked(for: .external))
    }

    func testOverridesReadOnlyKnownCells() {
        let o = RoleOverrides(document: ["internal|tools.register": "view", "boss|tools.register": "view", "internal|nope": "allow",
                                         "external|drive.upload": "maybe", "external|feed.ack_fix": 1, "external|punch": "disabled"])
        XCTAssertEqual(o.document, ["internal|tools.register": "view"])
        XCTAssertEqual(RoleOverrides(json: o.json), o)
        XCTAssertEqual(RoleOverrides(json: nil), RoleOverrides())
    }

    func testCellsCycle() {
        XCTAssertEqual([RoleAccess.allow, .conditional, .view, .deny].map(\.next), [.conditional, .view, .deny, .allow])
    }

    func testARoleChangeListsWhatIsGainedAndLost() {
        let c = RoleChange(from: .external, to: .internalTeam)
        XCTAssertTrue(c.gained.contains(.jobEdit))
        XCTAssertTrue(c.lost.isEmpty)
        let back = RoleChange(from: .internalTeam, to: .external)
        XCTAssertEqual(Set(back.lost), Set(c.gained))
        XCTAssertTrue(RoleChange(from: .manager, to: .internalTeam).lost.contains(.usersManage))
    }

    func testTheKeyHashMatchesNodesPBKDF2() throws {
        // node: crypto.pbkdf2Sync('246810', 'tcroof-test-salt', 1000, 32, 'sha256') (tools/dev-key)
        let key = try XCTUnwrap(DevKey(hash: "vQkbH3Q0RWHKLeYUfklFu4dTOKqOniUBiOBU3vfcgG8=",
                                       salt: Data("tcroof-test-salt".utf8).base64EncodedString(), iterations: 1000))
        XCTAssertTrue(key.matches("246810"))
        XCTAssertFalse(key.matches("246811"))
        XCTAssertFalse(key.matches("24681"))
        XCTAssertFalse(key.matches("２４６８１０"), "full-width digits")
        XCTAssertNil(DevKey(hash: nil, salt: "c2FsdA==", iterations: 1000))
        XCTAssertNil(DevKey(hash: "aGFzaA==", salt: "c2FsdA==", iterations: 0))
    }

    func testTheKeyExpires() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let key = DevKey.make(digits: "135790", salt: Data([1, 2, 3]), iterations: 100, expiresAt: now)
        XCTAssertTrue(key.isExpired(now: now))
        XCTAssertFalse(key.isExpired(now: now.addingTimeInterval(-1)))
        XCTAssertFalse(DevKey.make(digits: "135790", salt: Data([1]), iterations: 100).isExpired())
    }

    func testFiveWrongKeysLockTenMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var a = DevKeyAttempts()
        for i in 1...4 { a.fail(now: now); XCTAssertEqual(a.left, 5 - i); XCTAssertFalse(a.isLocked(now: now)) }
        a.fail(now: now)
        XCTAssertTrue(a.isLocked(now: now.addingTimeInterval(599)))
        XCTAssertFalse(a.isLocked(now: now.addingTimeInterval(600)))
        // after the lock, the count starts again
        a.fail(now: now.addingTimeInterval(601))
        XCTAssertEqual(a.failures, 1)
        XCTAssertFalse(a.isLocked(now: now.addingTimeInterval(601)))
    }
}
