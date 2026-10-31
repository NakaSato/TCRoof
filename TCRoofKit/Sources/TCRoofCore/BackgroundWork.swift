import Foundation

/// Runs a value-producing operation off the caller's actor, scoped to the caller's task.
public enum BackgroundWork {
    public static func value<Value: Sendable>(priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask(priority: priority) {
                try Task.checkCancellation()
                let value = try await operation()
                try Task.checkCancellation()
                return value
            }
            guard let value = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return value
        }
    }
}
