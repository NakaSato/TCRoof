import Foundation

/// Prepares immutable remote values on a worker actor. The caller retains ownership of its database context
/// and applies the returned values in snapshot order.
public actor SnapshotPreparationWorker {
    public init() {}

    /// Advances by source records, including malformed ones, so an empty prepared batch cannot stall loading.
    public func prepareBatch<Source: Sendable, Prepared: Sendable>(
        _ changes: [Source], startingAt index: Int, limit: Int,
        transform: @Sendable (Source) -> Prepared?
    ) throws -> (values: [Prepared], nextIndex: Int) {
        precondition(limit > 0 && index >= 0 && index <= changes.count)
        let end = index + min(limit, changes.count - index)
        return (try prepare(Array(changes[index..<end]), transform: transform), end)
    }

    public func prepare<Source: Sendable, Prepared: Sendable>(
        _ changes: [Source], transform: @Sendable (Source) -> Prepared?
    ) throws -> [Prepared] {
        var result: [Prepared] = []
        result.reserveCapacity(changes.count)
        for change in changes {
            try Task.checkCancellation()
            if let prepared = transform(change) { result.append(prepared) }
        }
        try Task.checkCancellation()
        return result
    }
}
