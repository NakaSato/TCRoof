import Foundation
import XCTest
@testable import TCRoofCore

@MainActor
final class SessionOperationGateTests: XCTestCase {
    /// Models a non-cancellable SDK that changes its global account before returning its callback.
    private final class Auth {
        var account: String?
        var events: [String] = []
        var pending: [String: CheckedContinuation<String, Error>] = [:]
        var starters: [String: CheckedContinuation<Void, Never>] = [:]

        func signIn(_ account: String) async throws -> String {
            events.append("start " + account)
            return try await withCheckedThrowingContinuation { continuation in
                pending[account] = continuation
                starters.removeValue(forKey: account)?.resume()
            }
        }

        func waitForStart(_ account: String) async {
            if pending[account] != nil { return }
            await withCheckedContinuation { starters[account] = $0 }
        }

        func finish(_ account: String) {
            self.account = account
            events.append("finish " + account)
            pending.removeValue(forKey: account)!.resume(returning: account)
        }

        func fail(_ account: String) {
            events.append("fail " + account)
            pending.removeValue(forKey: account)!.resume(throwing: CocoaError(.fileReadUnknown))
        }

        func discard(_ account: String) {
            events.append("discard " + account)
            self.account = nil
        }
    }

    func testSignOutDiscardsLateSDKSuccess() async throws {
        let gate = SessionOperationGate(), auth = Auth()
        let ticket = gate.generation
        let old = Task { try await gate.run(ticket: ticket, operation: { try await auth.signIn("A") }, discard: auth.discard) }
        await auth.waitForStart("A")
        gate.invalidate()
        auth.account = nil
        auth.finish("A")
        do { _ = try await old.value; XCTFail("Signed-out operation returned a user") }
        catch is CancellationError { }
        XCTAssertNil(auth.account)
    }

    func testAccountSwitchDrainsOldCompletionBeforeStartingNewSignIn() async throws {
        let gate = SessionOperationGate(), auth = Auth()
        let ticket = gate.generation
        let old = Task { try await gate.run(ticket: ticket, operation: { try await auth.signIn("A") }, discard: auth.discard) }
        await auth.waitForStart("A")
        let next = gate.invalidate()
        let newer = Task { try await gate.run(ticket: next, operation: { try await auth.signIn("B") }, discard: auth.discard) }
        auth.finish("A")
        await auth.waitForStart("B")
        XCTAssertEqual(auth.events, ["start A", "finish A", "discard A", "start B"])
        auth.finish("B")
        do { _ = try await old.value; XCTFail("Old account was accepted") }
        catch is CancellationError { }
        let result = try await newer.value
        XCTAssertEqual(result, "B")
        XCTAssertEqual(auth.account, "B")
    }

    func testCancelledCallerStillDiscardsNonCancellableSDKCompletion() async throws {
        let gate = SessionOperationGate(), auth = Auth()
        let ticket = gate.generation
        let call = Task { try await gate.run(ticket: ticket, operation: { try await auth.signIn("A") }, discard: auth.discard) }
        await auth.waitForStart("A")
        call.cancel()
        auth.finish("A")
        do { _ = try await call.value; XCTFail("Cancelled caller returned a user") }
        catch is CancellationError { }
        XCTAssertNil(auth.account)
    }

    func testQueuedOldOperationDoesNotStartAfterInvalidation() async throws {
        let gate = SessionOperationGate()
        let old = gate.generation
        gate.invalidate()
        do {
            _ = try await gate.run(ticket: old, operation: { XCTFail("Stale operation started"); return "A" }, discard: { _ in })
            XCTFail("Stale ticket was accepted")
        } catch is CancellationError { }
    }

    func testOldFailureDoesNotDiscardNewAccountsCredentials() async throws {
        let gate = SessionOperationGate(), auth = Auth()
        let ticket = gate.generation
        let old = Task { try await gate.run(ticket: ticket, operation: { try await auth.signIn("A") }, discard: auth.discard) }
        await auth.waitForStart("A")
        let next = gate.invalidate()
        let newer = Task { try await gate.run(ticket: next, operation: { try await auth.signIn("B") }, discard: auth.discard) }
        auth.fail("A")
        await auth.waitForStart("B")
        auth.finish("B")
        _ = try await newer.value
        do { _ = try await old.value; XCTFail("Old operation should fail") }
        catch { }
        XCTAssertEqual(auth.account, "B")
        XCTAssertFalse(auth.events.contains("discard A"))
    }

    func testLateMembershipResultCannotPublishAnOldAccount() async throws {
        let gate = SessionOperationGate(), auth = Auth()
        let ticket = gate.generation
        var published: String?
        let call = Task {
            let result = try await auth.signIn("membership A")
            try gate.validate(ticket)
            published = result
        }
        await auth.waitForStart("membership A")
        gate.invalidate()
        auth.finish("membership A")
        do { try await call.value; XCTFail("Stale membership was accepted") }
        catch is CancellationError { }
        XCTAssertNil(published)
    }
}
