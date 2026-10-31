import Foundation

/// Deletions stay in sequence with updates, and malformed updates are omitted during preparation.
enum PreparedDocumentChange<Record: Sendable>: Sendable {
    case removed(id: String)
    case updated(id: String, record: Record, fingerprint: String)

    var id: String {
        switch self {
        case .removed(let id), .updated(let id, _, _): id
        }
    }
}
