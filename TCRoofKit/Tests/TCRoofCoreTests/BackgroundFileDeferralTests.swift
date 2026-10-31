import XCTest
@testable import TCRoofCore

final class BackgroundFileDeferralTests: XCTestCase {
    func testTransfersResumeOnlyAfterEveryVisibleSurfaceLeaves() {
        var gate = BackgroundFileDeferral()
        let phone = UUID(), pad = UUID()
        gate.setVisible(true, owner: phone)
        gate.setVisible(true, owner: pad)
        XCTAssertTrue(gate.isDeferred)
        XCTAssertFalse(gate.setVisible(false, owner: phone))
        XCTAssertTrue(gate.isDeferred)
        XCTAssertTrue(gate.setVisible(false, owner: pad))
        XCTAssertFalse(gate.isDeferred)
    }

    func testDuplicateAppearDisappearDoesNotLeaveTransfersPausedOrRestartTwice() {
        var gate = BackgroundFileDeferral()
        let owner = UUID()
        gate.setVisible(true, owner: owner)
        gate.setVisible(true, owner: owner)
        XCTAssertTrue(gate.setVisible(false, owner: owner))
        XCTAssertFalse(gate.isDeferred)
        XCTAssertFalse(gate.setVisible(false, owner: owner))
    }

    func testUnrelatedHiddenTabCannotReleaseTheActiveListsDeferral() {
        var gate = BackgroundFileDeferral()
        gate.setVisible(true, owner: UUID())
        XCTAssertFalse(gate.setVisible(false, owner: UUID()))
        XCTAssertTrue(gate.isDeferred)
    }
}
