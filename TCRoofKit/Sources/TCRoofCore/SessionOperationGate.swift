import Foundation

/// Serializes SDK operations that mutate a process-wide account, even after their caller signs out.
@MainActor
public final class SessionOperationGate {
    public private(set) var generation = UUID()
    private var tail: Task<Void, Never>?

    public init() {}

    @discardableResult
    public func invalidate() -> UUID {
        generation = UUID()
        return generation
    }

    public func validate(_ ticket: UUID) throws {
        guard generation == ticket else { throw CancellationError() }
        try Task.checkCancellation()
    }

    /// A stale SDK success is discarded before the next queued operation can change the SDK's account.
    public func run<Value>(ticket: UUID, operation: @escaping @MainActor () async throws -> Value,
                           discard: @escaping @MainActor (Value) -> Void) async throws -> Value {
        try validate(ticket)
        let previous = tail
        let id = UUID()
        let cancellation = Cancellation()
        let work = Task { @MainActor in
            await previous?.value
            try cancellation.check()
            try self.validate(ticket)
            let value = try await operation()
            do { try cancellation.check(); try self.validate(ticket) }
            catch { discard(value); throw error }
            return value
        }
        tailID = id
        tail = Task { @MainActor in _ = try? await work.value }
        defer { if tailID == id { tail = nil; tailID = nil } }
        return try await withTaskCancellationHandler {
            let value = try await work.value
            try validate(ticket)
            return value
        } onCancel: {
            // Cancellation is advisory for SDK calls: keep the queue until their callbacks finish.
            cancellation.cancel()
        }
    }

    private var tailID: UUID?

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        func check() throws {
            lock.lock(); let value = cancelled; lock.unlock()
            if value { throw CancellationError() }
        }
    }
}
