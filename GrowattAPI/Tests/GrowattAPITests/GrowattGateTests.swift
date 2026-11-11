import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GrowattAPI

/// `GrowattGate`: a call repeated within the window is refused before it is sent, calls on a token are spaced, and a
/// 10012 starts the window again without a retry.
final class GrowattGateTests: XCTestCase {
    override func tearDown() {
        GrowattStub.reset()
        super.tearDown()
    }

    /// A clock the test moves.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date { lock.lock(); defer { lock.unlock() }; return t }
        func advance(_ s: TimeInterval) { lock.lock(); t += s; lock.unlock() }
    }

    private let ok = Data(#"{"data":{"count":0,"plants":[]},"error_code":0}"#.utf8)
    private let busy = Data(#"{"error_msg":"error_frequently_access","data":"","error_code":10012}"#.utf8)

    private func api(_ gate: GrowattGate) -> GrowattAPI {
        var a = GrowattStub.api()
        a.gate = gate
        return a
    }

    func testTheSameCallWithinTheWindowIsRefusedWithoutBeingSent() async throws {
        let clock = Clock()
        let gate = GrowattGate(window: 300, spacing: 0, clock: { clock.now })
        GrowattStub.replies = [ok, ok]
        _ = try await api(gate).plants()
        clock.advance(299)
        do {
            _ = try await api(gate).plants()
            XCTFail("refused")
        } catch let f as GrowattAPI.Failure {
            XCTAssertEqual(f, .tooFrequent)
        }
        XCTAssertEqual(GrowattStub.requests.count, 1, "nothing sent the second time")
        clock.advance(1)
        _ = try await api(gate).plants()
        XCTAssertEqual(GrowattStub.requests.count, 2, "free once the window has passed")
    }

    func testOtherCallsGoButSpacedOnTheToken() async throws {
        let gate = GrowattGate(window: 300, spacing: 0.2)
        GrowattStub.replies = [ok, ok]
        let start = Date()
        _ = try await api(gate).plants(page: 1)
        _ = try await api(gate).plants(page: 2)
        XCTAssertEqual(GrowattStub.requests.count, 2, "another page is another call")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.19, "the second waited for the spacing")
    }

    func test10012IsNotRetriedAndStartsTheWindow() async throws {
        let clock = Clock()
        let gate = GrowattGate(window: 300, spacing: 0, clock: { clock.now })
        GrowattStub.replies = [busy, ok]
        do {
            _ = try await api(gate).plants()
            XCTFail("10012")
        } catch let f as GrowattAPI.Failure {
            XCTAssertEqual(f, .tooFrequent)
        }
        XCTAssertEqual(GrowattStub.requests.count, 1, "no retry")
        clock.advance(200)
        let free = await gate.isFree(token: "abc", call: "plant/list?page=1&perpage=20")
        XCTAssertFalse(free)
    }

    /// A call that didn't reach Growatt's API doesn't take its slot: trying again goes at once.
    func testAFailedCallCanGoAgainAtOnce() async throws {
        let gate = GrowattGate(window: 300, spacing: 0)
        GrowattStub.replies = [Data("nope".utf8), ok]
        GrowattStub.statuses = [502]
        do {
            _ = try await api(gate).plants()
            XCTFail("502")
        } catch let f as GrowattAPI.Failure {
            XCTAssertEqual(f, .http(502))
        }
        _ = try await api(gate).plants()
        XCTAssertEqual(GrowattStub.requests.count, 2)
    }

    /// Cancelled while waiting out the spacing: nothing was sent, so the call isn't counted.
    func testACallCancelledWhileSpacedIsNotCounted() async throws {
        let gate = GrowattGate(window: 300, spacing: 5)
        try await gate.admit(token: "abc", call: "a")
        let waiting = Task { try await gate.admit(token: "abc", call: "b") }
        try await Task.sleep(nanoseconds: 50_000_000)
        waiting.cancel()
        _ = try? await waiting.value
        let free = await gate.isFree(token: "abc", call: "b")
        XCTAssertTrue(free)
    }

    func testWithoutAGateCallsAreRetriedAsBefore() async throws {
        GrowattStub.replies = [busy, ok]
        _ = try await GrowattStub.api().plants()
        XCTAssertEqual(GrowattStub.requests.count, 2)
    }

    /// After a 10012 the endpoint is held on the token: another page, or the list with no paging, isn't sent either,
    /// and `freeAt` says when it is free.
    func testA10012HoldsTheEndpointUntilItsTime() async throws {
        let clock = Clock()
        let gate = GrowattGate(window: 270, hold: 315, spacing: 0, clock: { clock.now })
        GrowattStub.replies = [busy, ok]
        _ = try? await api(gate).plants()
        do {
            _ = try await api(gate).plants(page: 2)
            XCTFail("held")
        } catch let f as GrowattAPI.Failure {
            XCTAssertEqual(f, .tooFrequent)
        }
        XCTAssertEqual(GrowattStub.requests.count, 1, "nothing sent while held")
        let at = await gate.freeAt(token: "abc", path: "plant/list")
        XCTAssertEqual(at, clock.now.addingTimeInterval(315))
        clock.advance(315)
        _ = try await api(gate).plants(page: 2)
        XCTAssertEqual(GrowattStub.requests.count, 2, "free once the hold has passed")
    }

    /// The waits outlive a relaunch (a new gate on the same storage), stored without the token.
    func testTheWaitsOutliveARelaunchWithoutTheToken() async throws {
        final class Box: @unchecked Sendable { var saved: [String: Double] = [:] }
        let box = Box()
        let storage = GrowattGate.Storage(load: { box.saved }, save: { box.saved = $0 })
        let clock = Clock()
        let first = GrowattGate(window: 270, hold: 315, spacing: 0, storage: storage, clock: { clock.now })
        await first.refused(token: "secret-token", call: "plant/list?page=1&perpage=20")
        XCTAssertFalse(box.saved.keys.contains { $0.contains("secret") }, "no token in what is stored")
        clock.advance(60)
        let again = GrowattGate(window: 270, hold: 315, spacing: 0, storage: storage, clock: { clock.now })
        let held = await again.freeAt(token: "secret-token", path: "plant/list")
        XCTAssertNotNil(held)
        let other = await again.freeAt(token: "other-token", path: "plant/list")
        XCTAssertNil(other, "another token isn't held")
        clock.advance(260)
        let later = GrowattGate(window: 270, hold: 315, spacing: 0, storage: storage, clock: { clock.now })
        let free = await later.isFree(token: "secret-token", call: "plant/list?page=1&perpage=20")
        XCTAssertTrue(free, "an expired wait isn't kept")
    }
}
