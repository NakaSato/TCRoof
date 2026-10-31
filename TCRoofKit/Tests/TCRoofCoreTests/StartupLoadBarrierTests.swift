import XCTest
@testable import TCRoofCore

@MainActor
final class StartupLoadBarrierTests: XCTestCase {
    func testOfflineTimeoutCannotStartNextStageWhileSnapshotIsApplying() async {
        let barrier = StartupLoadBarrier()
        barrier.received()
        var nextStageStarted = false
        let sequence = Task { @MainActor in
            let result = await barrier.wait()
            nextStageStarted = true
            return result
        }
        barrier.allowOfflineFallback()
        await Task.yield()
        XCTAssertFalse(nextStageStarted)
        barrier.applied(isFromCache: true)
        let result = await sequence.value
        XCTAssertEqual(result, .offline)
        XCTAssertTrue(nextStageStarted)
    }

    func testQueuedCacheAndServerSnapshotsBothFinishBeforeNextStage() async {
        let barrier = StartupLoadBarrier()
        barrier.received()
        barrier.received()
        var advanced = false
        let sequence = Task { @MainActor in
            let result = await barrier.wait()
            advanced = true
            return result
        }
        barrier.applied(isFromCache: false)
        barrier.allowOfflineFallback()
        await Task.yield()
        XCTAssertFalse(advanced)
        barrier.applied(isFromCache: true)
        let result = await sequence.value
        XCTAssertEqual(result, .applied)
    }

    func testServerMetadataAcknowledgementBeforeWaitDoesNotLoseCompletion() async {
        let barrier = StartupLoadBarrier()
        barrier.received()
        barrier.applied(isFromCache: false)
        let result = await barrier.wait()
        XCTAssertEqual(result, .applied)
    }

    func testOfflineWithoutAnySnapshotCanContinue() async {
        let barrier = StartupLoadBarrier()
        barrier.allowOfflineFallback()
        let result = await barrier.wait()
        XCTAssertEqual(result, .offline)
    }

    func testStopCancelsWaitAndLateCallbacksCannotResumeItAgain() async {
        let barrier = StartupLoadBarrier()
        barrier.received()
        let sequence = Task { @MainActor in await barrier.wait() }
        await Task.yield()
        barrier.cancel()
        barrier.received()
        barrier.applied(isFromCache: false)
        barrier.allowOfflineFallback()
        let result = await sequence.value
        XCTAssertEqual(result, .cancelled)
    }
}
