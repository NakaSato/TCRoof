import XCTest
@testable import TCRoofCore

final class UploadScanStateTests: XCTestCase {
    func testStartupAndManualRefreshScanEverything() throws {
        var state = UploadScanState()
        let startup = try XCTUnwrap(state.takePlan())
        XCTAssertNil(startup.collections)
        XCTAssertNil(state.takePlan(), "idle scheduled uploads do no work")
        let manual = try XCTUnwrap(state.takePlan(fullScan: true))
        XCTAssertNil(manual.collections)
    }

    func testEditsCoalesceAndLaterEditsRemainPending() throws {
        var state = UploadScanState()
        _ = state.takePlan()
        state.mark(["installLogs", "photos"])
        state.mark(["installLogs"])
        let plan = try XCTUnwrap(state.takePlan())
        XCTAssertEqual(plan.collections, ["installLogs", "photos"])
        XCTAssertFalse(plan.includes("trips"))
        state.mark(["jobs"])
        XCTAssertEqual(state.takePlan()?.collections, ["jobs"])
        XCTAssertNil(state.takePlan())
    }

    func testUnknownSaveFallsBackToFullScanAndFailuresAreRetried() {
        var state = UploadScanState()
        _ = state.takePlan()
        state.mark(["photos"])
        state.mark(nil)
        XCTAssertNil(state.takePlan()?.collections)
        state.retry(keys: ["photos/failed", "installLogs/report"])
        state.mark(["trips"])
        XCTAssertEqual(state.takePlan()?.collections, ["photos", "installLogs", "trips"])
    }

    func testUnscannedOrFailedCollectionsCannotProduceDeletions() throws {
        var state = UploadScanState()
        _ = state.takePlan()
        state.mark(["installLogs", "photos"])
        let plan = try XCTUnwrap(state.takePlan())
        let known: Set<String> = ["jobs/still-here", "installLogs/kept", "installLogs/deleted", "photos/fetch-failed"]
        XCTAssertEqual(plan.deletions(known: known, present: ["installLogs/kept"], scanned: ["installLogs"]), ["installLogs/deleted"])
        XCTAssertTrue(plan.deletions(known: known, present: [], scanned: []).isEmpty)
        let full = try XCTUnwrap(state.takePlan(fullScan: true))
        XCTAssertEqual(full.deletions(known: known, present: ["installLogs/kept"], scanned: ["installLogs", "jobs"]),
                       ["jobs/still-here", "installLogs/deleted"])
    }
}
