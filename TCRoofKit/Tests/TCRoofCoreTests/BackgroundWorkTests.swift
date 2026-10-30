import XCTest
@testable import TCRoofCore

private actor WorkGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var entered = false

    func run() async -> Int {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered = true
            waiter?.resume(); waiter = nil
        }
        return 42
    }

    func waitForStart() async {
        if !entered { await withCheckedContinuation { waiter = $0 } }
    }

    func finish() { continuation?.resume(); continuation = nil }
}

final class BackgroundWorkTests: XCTestCase {
    enum Context { @TaskLocal static var value = "default" }

    func testReturnsValueAndInheritsTaskContext() async throws {
        let result = try await Context.$value.withValue("parent") {
            try await BackgroundWork.value { Context.value }
        }
        XCTAssertEqual(result, "parent")
    }

    func testCancellationDoesNotPublishCompletedWork() async throws {
        let gate = WorkGate()
        let work = Task { try await BackgroundWork.value { await gate.run() } }
        await gate.waitForStart()
        work.cancel()
        // Work may ignore cancellation until its current synchronous decode has finished.
        await gate.finish()
        do { _ = try await work.value; XCTFail("Cancelled work returned a value") }
        catch is CancellationError {}
    }

    func testCancelledParentDoesNotStartOperation() async throws {
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await BackgroundWork.value { XCTFail("Cancelled operation ran"); return 42 }
        }
        do { _ = try await work.value; XCTFail("Cancelled parent returned a value") }
        catch is CancellationError {}
    }
}
