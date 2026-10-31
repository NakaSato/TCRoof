import XCTest
@testable import TCRoofCore

final class ProjectCacheReconciliationTests: XCTestCase {
    func testCachedRecordsOnlyFillMissingLocalData() {
        XCTAssertTrue(ProjectCacheReconciliation.canRestore(existsLocally: false, wasPreviouslySynced: false, hasPendingWrite: false))
        XCTAssertFalse(ProjectCacheReconciliation.canRestore(existsLocally: true, wasPreviouslySynced: false, hasPendingWrite: false))
    }

    func testCacheCannotResurrectPendingLocalDeletionOrOverwritePendingWrite() {
        XCTAssertFalse(ProjectCacheReconciliation.canRestore(existsLocally: false, wasPreviouslySynced: true, hasPendingWrite: false))
        XCTAssertFalse(ProjectCacheReconciliation.canRestore(existsLocally: false, wasPreviouslySynced: false, hasPendingWrite: true))
    }

    func testServerRemovalOnlyAppliesToUnchangedConfirmedCacheRecords() {
        XCTAssertTrue(ProjectCacheReconciliation.canRemove(serverContainsID: false, knownFingerprint: "saved", localFingerprint: "saved", hasPendingWrite: false))
        XCTAssertFalse(ProjectCacheReconciliation.canRemove(serverContainsID: false, knownFingerprint: "saved", localFingerprint: "edited", hasPendingWrite: false))
        XCTAssertFalse(ProjectCacheReconciliation.canRemove(serverContainsID: false, knownFingerprint: nil, localFingerprint: "draft", hasPendingWrite: false))
        XCTAssertFalse(ProjectCacheReconciliation.canRemove(serverContainsID: false, knownFingerprint: "saved", localFingerprint: "saved", hasPendingWrite: true))
        XCTAssertFalse(ProjectCacheReconciliation.canRemove(serverContainsID: true, knownFingerprint: "saved", localFingerprint: "saved", hasPendingWrite: false))
    }
}
