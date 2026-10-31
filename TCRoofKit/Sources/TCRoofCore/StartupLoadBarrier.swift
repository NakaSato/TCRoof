import Foundation

/// A startup stage advances after its received snapshots finish applying, or after an idle offline fallback.
@MainActor
public final class StartupLoadBarrier {
    public enum Result: Equatable, Sendable { case applied, offline, cancelled }
    private var pending = 0
    private var serverApplied = false
    private var offlineAllowed = false
    private var result: Result?
    private var continuation: CheckedContinuation<Result, Never>?

    public init() {}

    public func received() {
        guard result == nil else { return }
        pending += 1
    }

    public func applied(isFromCache: Bool) {
        guard result == nil else { return }
        precondition(pending > 0)
        pending -= 1
        serverApplied = serverApplied || !isFromCache
        resolveIfReady()
    }

    public func allowOfflineFallback() {
        offlineAllowed = true
        resolveIfReady()
    }

    public func cancel() { finish(.cancelled) }

    public func wait() async -> Result {
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }

    private func resolveIfReady() {
        guard pending == 0 else { return }
        if serverApplied { finish(.applied) }
        else if offlineAllowed { finish(.offline) }
    }

    private func finish(_ value: Result) {
        guard result == nil else { return }
        result = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}
