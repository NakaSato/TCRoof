/// Reuses an expensive fingerprint while the complete record value is unchanged.
/// Keep each instance on one actor; this cache does not provide its own synchronization.
public final class RecordFingerprintCache<Record: Equatable> {
    private var entries: [String: (record: Record, fingerprint: String)] = [:]

    public init() {}

    public func fingerprint(id: String, record: Record, compute: (Record) -> String) -> String {
        if let entry = entries[id], entry.record == record { return entry.fingerprint }
        let value = compute(record)
        entries[id] = (record, value)
        return value
    }

    /// Release records no longer present in the collection.
    public func retainIDs(_ ids: Set<String>) {
        entries = entries.filter { ids.contains($0.key) }
    }
}
