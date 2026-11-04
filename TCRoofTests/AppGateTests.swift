import XCTest
import TCRoofCore
@testable import TCRoof

@MainActor
final class AppGateTests: XCTestCase {
    private var savedMinimum: Int?
    private var savedLink: String?

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        savedMinimum = d.object(forKey: "appGate.minSyncVersion") as? Int
        savedLink = d.string(forKey: "appGate.installLink")
    }

    override func tearDown() {
        let d = UserDefaults.standard
        d.set(savedMinimum, forKey: "appGate.minSyncVersion")
        d.set(savedLink, forKey: "appGate.installLink")
        AppGate.shared.update(minimum: savedMinimum, installLink: savedLink)
        super.tearDown()
    }

    func testAppGateWhenBuildPassesMinimum() {
        let gate = AppGate.shared
        _ = gate.update(minimum: AppCompat.syncVersion, installLink: "https://testflight.apple.com/join/demo")
        XCTAssertEqual(gate.minimum, AppCompat.syncVersion)
        XCTAssertEqual(gate.installLink?.absoluteString, "https://testflight.apple.com/join/demo")
        XCTAssertFalse(gate.outdated)
    }

    func testAppGateWhenBuildIsOutdated() {
        let gate = AppGate.shared
        _ = gate.update(minimum: AppCompat.syncVersion + 1, installLink: "https://apps.apple.com/app/tcroof")
        XCTAssertEqual(gate.minimum, AppCompat.syncVersion + 1)
        XCTAssertEqual(gate.installLink?.absoluteString, "https://apps.apple.com/app/tcroof")
        XCTAssertTrue(gate.outdated)
    }

    func testAppGateRecoveryReturnsTrueWhenUnblocked() {
        let gate = AppGate.shared
        // Put gate into outdated state
        gate.update(minimum: AppCompat.syncVersion + 1, installLink: nil)
        XCTAssertTrue(gate.outdated)

        // Lower the minimum so this build is now valid again
        let unblocked = gate.update(minimum: AppCompat.syncVersion, installLink: nil)
        XCTAssertTrue(unblocked, "update() should return true when transitioning from outdated to valid")
        XCTAssertFalse(gate.outdated)
    }

    func testAppGateIgnoresEmptyOrNilLink() {
        let gate = AppGate.shared
        gate.update(minimum: AppCompat.syncVersion, installLink: "")
        XCTAssertNil(gate.installLink)

        gate.update(minimum: AppCompat.syncVersion, installLink: nil)
        XCTAssertNil(gate.installLink)
    }
}
