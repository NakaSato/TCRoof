import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DriveSync

private actor TokenEndpoint {
    private var replies: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    private var started: [(Int, CheckedContinuation<Void, Never>)] = []
    private var automatic: (Data, Int)?
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let index = requests.count
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation in
            if let automatic { continuation.resume(returning: automatic) }
            else { replies[index] = continuation }
            let ready = started.filter { $0.0 <= requests.count }
            started.removeAll { $0.0 <= requests.count }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { started.append((count, $0)) }
    }

    func reply(_ index: Int, _ json: String, status: Int = 200) {
        replies.removeValue(forKey: index)!.resume(returning: (Data(json.utf8), status))
    }

    func replyToAll(_ json: String) {
        automatic = (Data(json.utf8), 200)
        let pending = replies.values
        replies = [:]
        for waiter in pending { waiter.resume(returning: automatic!) }
    }
}

@MainActor
final class OAuthTokenSessionTests: XCTestCase {
    private var refresh: String? = "old-refresh"
    private var accepted: [String] = []
    private var clears = 0
    private let success = #"{"access_token":"new-access","expires_in":3600,"id_token":"new-id"}"#

    private func session(_ endpoint: TokenEndpoint) -> OAuthTokenSession {
        OAuthTokenSession(clientID: "client", readRefresh: { self.refresh }, onTokens: {
            self.accepted.append($0.access_token)
            if let refresh = $0.refresh_token { self.refresh = refresh }
        }, onSignOut: { self.refresh = nil; self.clears += 1 }, transport: { try await endpoint.send($0) })
    }

    func testConcurrentCallersShareRefresh() async throws {
        let endpoint = TokenEndpoint()
        // All callers enter on the same actor; the network remains suspended until they have joined.
        let shared = session(endpoint)
        let calls = (0..<10).map { _ in Task { try await shared.accessToken() } }
        await endpoint.waitForRequests(1)
        for _ in 0..<20 { await Task.yield() }
        await endpoint.replyToAll(success)
        for call in calls {
            let token = try await call.value
            XCTAssertEqual(token, "new-access")
        }
        let requests = await endpoint.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(accepted, ["new-access"])
        let cached = try await shared.accessToken()
        XCTAssertEqual(cached, "new-access")
    }

    func testCancelledWaiterDoesNotCancelSharedRefresh() async throws {
        let endpoint = TokenEndpoint()
        let auth = session(endpoint)
        let cancelled = Task { try await auth.accessToken() }
        await endpoint.waitForRequests(1)
        cancelled.cancel()
        let other = Task { try await auth.idAndAccessToken() }
        for _ in 0..<20 { await Task.yield() }
        await endpoint.replyToAll(success)
        do { _ = try await cancelled.value; XCTFail("Cancelled caller returned a token") }
        catch is CancellationError {}
        let tokens = try await other.value
        XCTAssertEqual(tokens.idToken, "new-id")
        XCTAssertEqual(tokens.accessToken, "new-access")
        let count = await endpoint.requests.count
        XCTAssertEqual(count, 1)
    }

    func testOldSuccessCannotRestoreSignedOutCredentials() async throws {
        let endpoint = TokenEndpoint()
        let shared = session(endpoint)
        let call = Task { try await shared.accessToken() }
        await endpoint.waitForRequests(1)
        shared.signOut()
        // Transport intentionally ignores cancellation, as a late callback may still arrive.
        await endpoint.reply(0, success)
        do { _ = try await call.value; XCTFail("Old session returned a token") }
        catch is CancellationError {}
        XCTAssertNil(refresh)
        XCTAssertTrue(accepted.isEmpty)
        XCTAssertEqual(clears, 1)
    }

    func testOldFailureCannotSignOutNewAccount() async throws {
        let endpoint = TokenEndpoint()
        let auth = session(endpoint)
        let old = Task { try await auth.accessToken() }
        await endpoint.waitForRequests(1)
        auth.signOut()
        refresh = "new-refresh"
        let current = Task { try await auth.accessToken() }
        await endpoint.waitForRequests(2)
        await endpoint.reply(1, success)
        _ = try await current.value
        await endpoint.reply(0, #"{"error":"invalid_grant"}"#, status: 400)
        do { _ = try await old.value; XCTFail("Old request succeeded") }
        catch is CancellationError {}
        XCTAssertEqual(refresh, "new-refresh")
        XCTAssertEqual(accepted, ["new-access"])
        XCTAssertEqual(clears, 1)
    }

    func testClientChangeInvalidatesPendingCodeExchange() async throws {
        let endpoint = TokenEndpoint()
        let auth = session(endpoint)
        let ticket = auth.beginSignIn()
        let call = Task { try await auth.exchangeCode("code", verifier: "verifier", redirectURI: "app:/callback", ticket: ticket) }
        await endpoint.waitForRequests(1)
        auth.clientID = "different-client"
        await endpoint.reply(0, #"{"access_token":"stale","refresh_token":"stale-refresh"}"#)
        do { try await call.value; XCTFail("Stale authorization was accepted") }
        catch is CancellationError {}
        XCTAssertNil(refresh)
        XCTAssertTrue(accepted.isEmpty)
    }

    func testFailedRefreshCanBeRetried() async throws {
        let endpoint = TokenEndpoint()
        let auth = session(endpoint)
        let first = Task { try await auth.accessToken() }
        await endpoint.waitForRequests(1)
        await endpoint.reply(0, #"{"error":"temporarily_unavailable"}"#, status: 503)
        do { _ = try await first.value; XCTFail("Expected server error") }
        catch is OAuthTokenSession.Failure {}
        let retry = Task { try await auth.accessToken() }
        await endpoint.waitForRequests(2)
        await endpoint.reply(1, success)
        let value = try await retry.value
        XCTAssertEqual(value, "new-access")
        XCTAssertEqual(clears, 0)
    }

    func testCodeExchangeReplacesPreviousAccountAndCachesToken() async throws {
        let endpoint = TokenEndpoint()
        let auth = session(endpoint)
        let ticket = auth.beginSignIn()
        let exchange = Task { try await auth.exchangeCode("code", verifier: "verifier", redirectURI: "app:/callback", ticket: ticket) }
        await endpoint.waitForRequests(1)
        await endpoint.reply(0, #"{"access_token":"signed-in","expires_in":3600,"refresh_token":"signed-in-refresh"}"#)
        try await exchange.value
        XCTAssertEqual(refresh, "signed-in-refresh")
        XCTAssertEqual(accepted, ["signed-in"])
        XCTAssertEqual(clears, 1)
        let cached = try await auth.accessToken()
        XCTAssertEqual(cached, "signed-in")
        let requests = await endpoint.requests
        XCTAssertEqual(requests.count, 1)
        let body = String(decoding: try XCTUnwrap(requests.first?.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code_verifier=verifier"))
    }

    func testCancelledSignInPreservesExistingRefreshToken() async throws {
        let endpoint = TokenEndpoint()
        let auth = session(endpoint)
        let ticket = auth.beginSignIn()
        auth.cancelSignIn(ticket)
        XCTAssertEqual(refresh, "old-refresh")
        XCTAssertEqual(clears, 0)
        let request = Task { try await auth.accessToken() }
        await endpoint.waitForRequests(1)
        await endpoint.reply(0, success)
        let token = try await request.value
        XCTAssertEqual(token, "new-access")
    }

    func testSignedOutBrowserCallbackCannotStartExchange() async throws {
        let endpoint = TokenEndpoint()
        let auth = session(endpoint)
        let ticket = auth.beginSignIn()
        auth.signOut()
        do {
            try await auth.exchangeCode("old-code", verifier: "verifier", redirectURI: "app:/callback", ticket: ticket)
            XCTFail("Stale browser callback started a request")
        } catch is CancellationError {}
        let count = await endpoint.requests.count
        XCTAssertEqual(count, 0)
    }
}
