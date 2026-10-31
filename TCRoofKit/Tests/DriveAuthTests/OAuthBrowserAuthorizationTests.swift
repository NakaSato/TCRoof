import XCTest
@testable import DriveSync

@MainActor
private final class BrowserSession: OAuthBrowserSession {
    var starts = 0
    var cancels = 0
    var canStart = true
    var onStart: (() -> Void)?
    var onCancel: (() -> Void)?
    private var started: CheckedContinuation<Void, Never>?

    func start() -> Bool {
        starts += 1
        started?.resume(); started = nil
        onStart?()
        return canStart
    }

    func cancel() { cancels += 1; onCancel?() }

    func waitForStart() async {
        if starts == 0 { await withCheckedContinuation { started = $0 } }
    }
}

@MainActor
final class OAuthBrowserAuthorizationTests: XCTestCase {
    private let callback = URL(string: "app:/callback?code=test-code")!

    func testFailedStartupReturnsWithoutCallback() async throws {
        let session = BrowserSession()
        session.canStart = false
        let browser = OAuthBrowserAuthorization { _ in session }
        do { _ = try await browser.value(); XCTFail("Failed startup succeeded") }
        catch OAuthBrowserAuthorization.Failure.notStarted {}
        XCTAssertEqual(session.starts, 1)
    }

    func testSynchronousCallbackAndDuplicateCompleteOnlyOnce() async throws {
        let session = BrowserSession(), url = callback
        let browser = OAuthBrowserAuthorization { completion in
            session.onStart = {
                completion(.success(url))
                completion(.failure(CancellationError()))
            }
            return session
        }
        let value = try await browser.value()
        XCTAssertEqual(value, url)
        for _ in 0..<3 { await Task.yield() }
        XCTAssertEqual(session.cancels, 0)
    }

    func testFalseStartupWinsOverQueuedCallback() async throws {
        let session = BrowserSession(), url = callback
        session.canStart = false
        let browser = OAuthBrowserAuthorization { completion in
            session.onStart = { completion(.success(url)) }
            return session
        }
        do { _ = try await browser.value(); XCTFail("Failed startup accepted a callback") }
        catch OAuthBrowserAuthorization.Failure.notStarted {}
        for _ in 0..<3 { await Task.yield() }
    }

    func testCallbackFromAnotherExecutorReturnsURL() async throws {
        let session = BrowserSession(), url = callback
        let browser = OAuthBrowserAuthorization { completion in
            session.onStart = { Task.detached { completion(.success(url)) } }
            return session
        }
        let value = try await browser.value()
        XCTAssertEqual(value, url)
    }

    func testParentCancellationClosesBrowserWithoutWaitingForCallback() async throws {
        let session = BrowserSession()
        let browser = OAuthBrowserAuthorization { _ in session }
        let task = Task { try await browser.value() }
        await session.waitForStart()
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request returned") }
        catch is CancellationError {}
        XCTAssertEqual(session.cancels, 1)
    }

    func testLateCallbackAfterExplicitCancellationIsIgnored() async throws {
        let session = BrowserSession(), url = callback
        var callback: OAuthBrowserAuthorization.Completion?
        let browser = OAuthBrowserAuthorization { completion in
            callback = completion
            // The platform may deliver a callback as a side effect of cancel().
            session.onCancel = { completion(.failure(CancellationError())) }
            return session
        }
        let task = Task { try await browser.value() }
        await session.waitForStart()
        browser.cancel()
        browser.cancel()
        callback?(.success(url))
        do { _ = try await task.value; XCTFail("Late callback restored cancelled request") }
        catch is CancellationError {}
        for _ in 0..<3 { await Task.yield() }
        XCTAssertEqual(session.cancels, 1)
    }

    func testCancellationBeforeValueDoesNotCreateSession() async throws {
        var created = false
        let browser = OAuthBrowserAuthorization { _ in created = true; return BrowserSession() }
        browser.cancel()
        do { _ = try await browser.value(); XCTFail("Cancelled request started") }
        catch is CancellationError {}
        XCTAssertFalse(created)
    }

    func testAlreadyCancelledParentDoesNotCreateSession() async throws {
        var created = false
        let browser = OAuthBrowserAuthorization { _ in created = true; return BrowserSession() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await browser.value()
        }
        do { _ = try await task.value; XCTFail("Cancelled caller started") }
        catch is CancellationError {}
        XCTAssertFalse(created)
    }

    func testCompletedRequestCannotBeReused() async throws {
        let session = BrowserSession(), url = callback
        let browser = OAuthBrowserAuthorization { completion in
            session.onStart = { completion(.success(url)) }
            return session
        }
        _ = try await browser.value()
        do { _ = try await browser.value(); XCTFail("Request reused its continuation") }
        catch OAuthBrowserAuthorization.Failure.alreadyStarted {}
        XCTAssertEqual(session.starts, 1)
    }
}
