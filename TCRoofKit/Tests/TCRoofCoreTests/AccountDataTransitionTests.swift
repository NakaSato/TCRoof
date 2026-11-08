import Foundation
import XCTest
@testable import TCRoofCore

@MainActor
final class AccountDataTransitionTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "account-transition-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testFailedCleanupBlocksActivationAndSurvivesRestart() async throws {
        let defaults = defaults()
        let transition = AccountDataTransition(defaults: defaults)
        transition.adopt("team@example.com")
        XCTAssertFalse(transition.signedIn("external@example.com", external: true))
        var activated = false
        do {
            try transition.cleanupIfNeeded { throw CocoaError(.fileWriteNoPermission) }
            activated = true
        } catch { }
        XCTAssertFalse(activated)
        let restored = AccountDataTransition(defaults: defaults)
        XCTAssertTrue(restored.needsCleanup)
        XCTAssertEqual(restored.owner, "external@example.com")
        var attempts = 0
        try restored.cleanupIfNeeded { attempts += 1 }
        try restored.cleanupIfNeeded { attempts += 1 }
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(restored.needsCleanup)
    }

    func testRepeatedSignInAndAnotherAccountCannotCancelPendingCleanup() async {
        let transition = AccountDataTransition(defaults: defaults())
        transition.adopt("team@example.com")
        transition.signedIn("external@example.com", external: true)
        transition.signedIn("external@example.com", external: true)
        XCTAssertTrue(transition.needsCleanup)
        XCTAssertFalse(transition.signedIn("other-team@example.com", external: false))
        XCTAssertTrue(transition.needsCleanup)
    }

    func testTeamHandoffPreservesRecordsWithoutRunningCleanup() async throws {
        let transition = AccountDataTransition(defaults: defaults())
        transition.adopt("first@example.com")
        XCTAssertTrue(transition.signedIn("second@example.com", external: false))
        try transition.cleanupIfNeeded { XCTFail("Internal handoff should retain local records") }
        XCTAssertFalse(transition.needsCleanup)
    }

    func testTheSameAccountMadeExternalLosesTheTeamsRecords() async throws {
        let transition = AccountDataTransition(defaults: defaults())
        transition.signedIn("member@example.com", external: false)
        XCTAssertFalse(transition.needsCleanup)
        XCTAssertFalse(transition.signedIn("member@example.com", external: true))
        XCTAssertTrue(transition.needsCleanup)
        var cleaned = 0
        try transition.cleanupIfNeeded { cleaned += 1 }
        XCTAssertEqual(cleaned, 1)
        // signed in again as external: the records are theirs now
        transition.signedIn("member@example.com", external: true)
        XCTAssertFalse(transition.needsCleanup)
    }

    func testAnExternalAccountMadeTeamKeepsItsRecords() async {
        let transition = AccountDataTransition(defaults: defaults())
        transition.signedIn("contractor@example.com", external: true)
        try? transition.cleanupIfNeeded { }
        transition.signedIn("contractor@example.com", external: false)
        XCTAssertFalse(transition.needsCleanup)
    }

    func testRecordsKeptBeforeTheRoleWasRecordedStay() async {
        let defaults = defaults()
        // an owner from an app version that didn't record the role
        defaults.set("contractor@example.com", forKey: "session.owner")
        let transition = AccountDataTransition(defaults: defaults)
        transition.signedIn("contractor@example.com", external: true)
        XCTAssertFalse(transition.needsCleanup)
        // the device's records decide, once: only the contractor's own jobs here
        XCTAssertTrue(transition.needsRecordCheck)
        transition.checkedRecords(teamRecordsFound: false)
        XCTAssertFalse(transition.needsRecordCheck)
        XCTAssertFalse(transition.needsCleanup)
        transition.signedIn("contractor@example.com", external: true)
        XCTAssertFalse(transition.needsRecordCheck)
        // from then on the role is known, and a later demotion is caught
        transition.signedIn("contractor@example.com", external: false)
        transition.signedIn("contractor@example.com", external: true)
        XCTAssertTrue(transition.needsCleanup)
    }

    func testAMemberMadeExternalBeforeTheRoleWasRecordedLosesTheTeamsRecords() async throws {
        let defaults = defaults()
        defaults.set("member@example.com", forKey: "session.owner")
        let transition = AccountDataTransition(defaults: defaults)
        transition.signedIn("member@example.com", external: true)
        XCTAssertTrue(transition.needsRecordCheck)
        transition.checkedRecords(teamRecordsFound: true)
        XCTAssertTrue(transition.needsCleanup)
        XCTAssertFalse(transition.needsRecordCheck)
    }

    func testATeamOwnerNeedsNoRecordCheck() async {
        let defaults = defaults()
        defaults.set("member@example.com", forKey: "session.owner")
        let transition = AccountDataTransition(defaults: defaults)
        transition.signedIn("member@example.com", external: false)
        XCTAssertFalse(transition.needsRecordCheck)
    }

    func testExternalAccountCannotInheritRecordsWithUnknownOwner() async {
        let transition = AccountDataTransition(defaults: defaults())
        transition.signedIn("external@example.com", external: true)
        XCTAssertTrue(transition.needsCleanup)
    }
}
