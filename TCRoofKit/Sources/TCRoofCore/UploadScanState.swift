import Foundation

/// Tracks which collections a scheduled upload must inspect. A full recovery scan is still required at startup
/// and whenever the caller cannot identify the saved records.
public struct UploadScanState: Sendable {
    public struct Plan: Equatable, Sendable {
        /// nil means every supported collection.
        public let collections: Set<String>?

        public func includes(_ collection: String) -> Bool { collections?.contains(collection) ?? true }

        /// Missing records count as deletions only after their collection was successfully enumerated.
        public func deletions(known: Set<String>, present: Set<String>, scanned: Set<String>) -> Set<String> {
            Set(known.filter { key in
                let collection = Self.collection(of: key)
                return includes(collection) && scanned.contains(collection) && !present.contains(key)
            })
        }

        fileprivate static func collection(of key: String) -> String {
            String(key.split(separator: "/", maxSplits: 1).first ?? "")
        }
    }

    private var fullScanPending = true
    private var dirty = Set<String>()

    public init() {}

    /// nil requests a full scan; an empty set means the changed models do not travel through this uploader.
    public mutating func mark(_ collections: Set<String>?) {
        if let collections { dirty.formUnion(collections) }
        else { fullScanPending = true }
    }

    public mutating func takePlan(fullScan: Bool = false) -> Plan? {
        guard fullScan || fullScanPending || !dirty.isEmpty else { return nil }
        let plan = Plan(collections: fullScan || fullScanPending ? nil : dirty)
        fullScanPending = false
        dirty.removeAll(keepingCapacity: true)
        return plan
    }

    /// Failed writes must be included when an unrelated edit next triggers an upload.
    public mutating func retry(keys: Set<String>) {
        dirty.formUnion(keys.map(Plan.collection))
    }
}
