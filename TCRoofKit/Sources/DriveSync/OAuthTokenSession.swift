import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OAuth state shared by Drive requests. Persistence callbacks run on the same actor as invalidation.
@MainActor
public final class OAuthTokenSession {
    public struct Tokens: Decodable, Sendable {
        public let access_token: String
        public let expires_in: Int?
        public let refresh_token: String?
        public let id_token: String?
        public let scope: String?
    }

    public enum Failure: Error, LocalizedError {
        case response(String), invalidGrant(String)
        public var errorDescription: String? {
            switch self { case .response(let text), .invalidGrant(let text): return "ลงชื่อเข้าใช้ Google ไม่สำเร็จ: \(text)" }
        }
    }

    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
    public var clientID: String { didSet { if clientID != oldValue { signOut() } } }
    public private(set) var generation = UUID()
    private let readRefresh: () -> String?
    private let onTokens: (Tokens) -> Void
    private let onSignOut: () -> Void
    private let transport: Transport
    private var cached: (tokens: Tokens, expiry: Date)?
    private var pending: (id: UUID, task: Task<Tokens, Error>)?
    private var authorizing = false

    public init(clientID: String, readRefresh: @escaping () -> String?,
                onTokens: @escaping (Tokens) -> Void, onSignOut: @escaping () -> Void,
                transport: @escaping Transport = { try await OAuthTokenSession.send($0) }) {
        self.clientID = clientID
        self.readRefresh = readRefresh
        self.onTokens = onTokens
        self.onSignOut = onSignOut
        self.transport = transport
    }

    public func signOut() { invalidate(); onSignOut() }

    public func beginSignIn() -> UUID {
        invalidate()
        authorizing = true
        return generation
    }

    public func cancelSignIn(_ ticket: UUID) {
        if generation == ticket { invalidate() }
    }

    public func validate(_ ticket: UUID) throws {
        guard generation == ticket else { throw CancellationError() }
    }

    private func invalidate() {
        generation = UUID()
        pending?.task.cancel()
        pending = nil
        cached = nil
        authorizing = false
    }

    public func exchangeCode(_ code: String, verifier: String, redirectURI: String, ticket: UUID) async throws {
        try validate(ticket)
        let tokens = try await Self.request(clientID: clientID, params: ["code": code, "code_verifier": verifier,
            "grant_type": "authorization_code", "redirect_uri": redirectURI], transport: transport)
        try validate(ticket)
        try Task.checkCancellation()
        guard let refresh = tokens.refresh_token, !refresh.isEmpty else {
            throw Failure.response("ไม่มี refresh_token")
        }
        invalidate()
        // Never leave the previous account's refresh token behind if Google omits one.
        onSignOut()
        accept(tokens)
    }

    public func accessToken(validFor seconds: TimeInterval = 60) async throws -> String {
        try Task.checkCancellation()
        guard seconds.isFinite, seconds >= 0 else { throw Failure.response("ระยะเวลาของ access_token ไม่ถูกต้อง") }
        if let cached, cached.expiry > Date().addingTimeInterval(seconds) { return cached.tokens.access_token }
        let ticket = generation
        _ = try await refresh()
        try validate(ticket)
        try Task.checkCancellation()
        guard let cached, cached.expiry > Date().addingTimeInterval(seconds) else {
            throw Failure.response("อายุ access_token สั้นกว่าที่ต้องใช้")
        }
        return cached.tokens.access_token
    }

    public func idAndAccessToken() async throws -> (idToken: String, accessToken: String) {
        let ticket = generation
        let tokens = try await refresh()
        try validate(ticket)
        try Task.checkCancellation()
        guard let id = tokens.id_token else { throw Failure.response("ไม่มี id_token") }
        return (id, tokens.access_token)
    }

    private func refresh() async throws -> Tokens {
        try Task.checkCancellation()
        guard !authorizing else { throw CancellationError() }
        guard let refresh = readRefresh() else { throw DriveError.notSignedIn }
        let ticket = generation
        let work: (id: UUID, task: Task<Tokens, Error>)
        if let pending { work = pending }
        else {
            let clientID = clientID, transport = transport
            // Shared by independent callers: cancelling one waiter must not cancel everyone's refresh.
            work = (UUID(), Task {
                try await Self.request(clientID: clientID, params: ["refresh_token": refresh,
                    "grant_type": "refresh_token"], transport: transport)
            })
            pending = work
        }
        let tokens: Tokens
        do { tokens = try await work.task.value }
        catch {
            try validate(ticket)
            if pending?.id == work.id {
                pending = nil
                if case Failure.invalidGrant = error { signOut() }
            }
            throw error
        }
        try validate(ticket)
        if pending?.id == work.id { pending = nil; accept(tokens) }
        try Task.checkCancellation()
        return tokens
    }

    private func accept(_ tokens: Tokens) {
        cached = (tokens, Date().addingTimeInterval(TimeInterval(tokens.expires_in ?? 3600)))
        onTokens(tokens)
    }

    private nonisolated static func request(clientID: String, params: [String: String], transport: Transport) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var all = params; all["client_id"] = clientID
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = Data(all.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)"
        }.joined(separator: "&").utf8)
        let (data, status) = try await transport(request)
        guard status == 200 else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (obj?["error_description"] as? String) ?? (obj?["error"] as? String) ?? "HTTP \(status)"
            if obj?["error"] as? String == "invalid_grant" { throw Failure.invalidGrant(message) }
            throw Failure.response(message)
        }
        guard let tokens = try? JSONDecoder().decode(Tokens.self, from: data), !tokens.access_token.isEmpty else {
            throw Failure.response("ไม่มี access_token")
        }
        return tokens
    }

    public nonisolated static func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
