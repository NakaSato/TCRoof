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

    func testExternalAccountCannotInheritRecordsWithUnknownOwner() async {
        let transition = AccountDataTransition(defaults: defaults())
        transition.signedIn("external@example.com", external: true)
        XCTAssertTrue(transition.needsCleanup)
    }
}
