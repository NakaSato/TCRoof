import Foundation

/// The answers exactly as issued: what the PDF was made from and what was signed
/// (docs/specs/review-lock-revisions-swift.md §3.1). Written once to `revisions/REVnn.json`.
public struct FormSnapshot: Codable, Hashable, Sendable {
    public var values: Values
    public var modules: [SurveyModule]
    public init(values: Values, modules: [SurveyModule]) { self.values = values; self.modules = modules }
    public var allPhotos: [Photo] { values.allPhotos + modules.flatMap { $0.values.allPhotos } }
    /// A job holding these answers, to reuse `Job`'s section numbering and report helpers.
    public var job: Job { Job(values: values, modules: modules) }
}

/// One issued REV.
public struct Revision: Codable, Hashable, Identifiable, Sendable {
    public var id: String { rev }
    /// "00", "01", …
    public var rev: String
    public var issuedAt: Date
    /// Engineer's name at the time.
    public var issuedBy: String
    /// "" for REV 00; required from REV 01.
    public var reason: String
    /// SHA-256 of the snapshot and its photos, hex, as it was issued.
    public var hash: String
    /// "revisions/REV00.pdf": the report as signed. nil when the PDF could not be written.
    public var pdfFile: String?
    public init(rev: String, issuedAt: Date, issuedBy: String, reason: String, hash: String, pdfFile: String? = nil) {
        self.rev = rev; self.issuedAt = issuedAt; self.issuedBy = issuedBy; self.reason = reason; self.hash = hash; self.pdfFile = pdfFile
    }
    /// "A1B2-C3D4", from the first 8 hex digits of `hash`.
    public var shortCode: String {
        let h = hash.prefix(8).uppercased()
        guard h.count == 8 else { return h }
        return h.prefix(4) + "-" + h.suffix(4)
    }
}

public enum RevisionRule {
    public static let signatureIDs = ["surveyorSign", "customerSign"]
}

public extension Job {
    /// "00" when the field is empty, as printed on the cover.
    var rev: String {
        let r = values.text("rev").trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? "00" : r
    }
    var snapshot: FormSnapshot { FormSnapshot(values: values, modules: modules) }
    var lastRevision: Revision? { revisions?.last }
    /// The last issued REV this draft is compared with (change markers, the รายการแก้ไข page). nil before REV 00 is issued.
    var previousRevision: Revision? { revisions?.last }
}
