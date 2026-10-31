import Foundation

/// The platform browser session, isolated with the sign-in UI.
@MainActor
public protocol OAuthBrowserSession: AnyObject {
    func start() -> Bool
    func cancel()
}

/// Bridges a browser callback to one async result, including failed startup and caller cancellation.
@MainActor
public final class OAuthBrowserAuthorization {
    public typealias Completion = @Sendable (Result<URL, Error>) -> Void

    public enum Failure: Error, LocalizedError {
        case notStarted, alreadyStarted
        public var errorDescription: String? {
            switch self {
            case .notStarted: return "เปิดหน้าลงชื่อเข้าใช้ไม่ได้ กรุณาลองอีกครั้ง"
            case .alreadyStarted: return "คำขอลงชื่อเข้าใช้นี้ถูกใช้แล้ว"
            }
        }
    }

    private let makeSession: (@escaping Completion) -> any OAuthBrowserSession
    private var session: (any OAuthBrowserSession)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var outcome: Result<URL, Error>?
    private var started = false

    public init(makeSession: @escaping (@escaping Completion) -> any OAuthBrowserSession) {
        self.makeSession = makeSession
    }

    public func value() async throws -> URL {
        guard !started else { throw Failure.alreadyStarted }
        started = true
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            let url: URL = try await withCheckedThrowingContinuation { continuation in
                if let outcome { continuation.resume(with: outcome); return }
                self.continuation = continuation
                let session = makeSession { [weak self] result in
                    Task { @MainActor in self?.finish(result) }
                }
                self.session = session
                if !session.start() { finish(.failure(Failure.notStarted)) }
            }
            try Task.checkCancellation()
            return url
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    public func cancel() {
        let session = session
        // Resume first: cancel() itself may synchronously deliver another callback.
        finish(.failure(CancellationError()))
        session?.cancel()
    }

    private func finish(_ result: Result<URL, Error>) {
        guard outcome == nil else { return }
        outcome = result
        let continuation = continuation
        self.continuation = nil
        session = nil
        continuation?.resume(with: result)
    }
}
