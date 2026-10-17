import Foundation

/// The answers exactly as issued: what the PDF was made from and what was signed.
/// Written once to `revisions/REVnn.json`.
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

    /// "00" → "01", "09" → "10", "A" → "A-1", "A-1" → "A-2"; empty counts as "00".
    public static func next(after rev: String) -> String {
        let r = rev.trimmingCharacters(in: .whitespaces)
        if r.isEmpty { return "01" }
        if let n = Int(r) { return String(format: "%0\(max(2, r.count))d", n + 1) }
        if let dash = r.lastIndex(of: "-"), let n = Int(r[r.index(after: dash)...]) { return r[..<dash] + "-\(n + 1)" }
        return r + "-1"
    }
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
    var bothSigned: Bool { RevisionRule.signatureIDs.allSatisfy { values.photo($0) != nil } }

    /// The number the next issue takes: the current one until it has been issued, then the one after.
    var nextIssueRev: String { (revisions ?? []).contains { $0.rev == rev } ? RevisionRule.next(after: rev) : rev }
    /// Every REV after the first says why it was issued.
    var issueNeedsReason: Bool { !(revisions ?? []).isEmpty }

    /// Records the current answers as an issued REV (nothing is locked: the form stays editable, and the next issue
    /// takes the next number). `rev` must already hold the number; `hash` is `FormHash.of(snapshot)`.
    mutating func issue(reason: String, hash: String, pdfFile: String?, now: Date = Date()) {
        let r = Revision(rev: rev, issuedAt: now, issuedBy: values.text("engineer"),
                         reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), hash: hash, pdfFile: pdfFile)
        revisions = (revisions ?? []).filter { $0.rev != r.rev } + [r]
    }
}
