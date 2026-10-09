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
    /// `FormHash` of the snapshot, hex.
    public var hash: String
    /// "revisions/REV00.pdf": the report as signed. nil when the PDF could not be written.
    public var pdfFile: String?
    public init(rev: String, issuedAt: Date, issuedBy: String, reason: String, hash: String, pdfFile: String? = nil) {
        self.rev = rev; self.issuedAt = issuedAt; self.issuedBy = issuedBy; self.reason = reason; self.hash = hash; self.pdfFile = pdfFile
    }
    /// "A1B2-C3D4"
    public var shortCode: String { FormHash.short(hash) }
}

/// The form is locked as REV `rev` (§4).
public struct FormLock: Codable, Hashable, Sendable {
    public var rev: String
    public var lockedAt: Date
    public var hash: String
    public init(rev: String, lockedAt: Date, hash: String) { self.rev = rev; self.lockedAt = lockedAt; self.hash = hash }
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
    var isLocked: Bool { lock != nil }
    var bothSigned: Bool { values.photo("surveyorSign") != nil && values.photo("customerSign") != nil }
    /// "00" when the field is empty, as printed on the cover.
    var rev: String {
        let r = values.text("rev").trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? "00" : r
    }
    var snapshot: FormSnapshot { FormSnapshot(values: values, modules: modules) }
    var lastRevision: Revision? { revisions?.last }
    /// Signed by both but not locked: the E1 banner "ลงนามครบแต่ยังไม่ล็อก".
    var signedUnlocked: Bool { bothSigned && !isLocked }

    /// Whether `other` changes anything but the two signatures, i.e. data a signature in `self` was given for.
    func contentDiffers(from other: Job) -> Bool {
        var a = values, b = other.values
        for id in RevisionRule.signatureIDs { a.storage[id] = nil; b.storage[id] = nil }
        return a.storage != b.storage || modules != other.modules
    }

    /// Issues the current answers as REV `rev` and locks the form (§4.2 step 5). `hash` is `FormHash.of(snapshot)`.
    mutating func issue(hash: String, pdfFile: String?, now: Date = Date()) {
        let r = Revision(rev: rev, issuedAt: now, issuedBy: values.text("engineer"), reason: pendingReason ?? "", hash: hash, pdfFile: pdfFile)
        var list = (revisions ?? []).filter { $0.rev != r.rev }
        list.append(r)
        revisions = list
        lock = FormLock(rev: r.rev, lockedAt: now, hash: hash)
        pendingReason = nil
    }

    /// Opens the next REV for editing (§4.4): new number, signatures cleared, unlocked. The issued REV's files stay.
    mutating func openNextRevision(reason: String, updateDate: Bool, now: Date = Date()) {
        values["rev"] = .text(RevisionRule.next(after: rev))
        for id in RevisionRule.signatureIDs { values[id] = nil }
        if updateDate { values["date"] = .text(ISODate.string(now)) }
        lock = nil
        pendingReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The last issued REV this draft is compared with (change markers, the รายการแก้ไข page). nil before REV 00 is issued
    /// or while the issued REV is the current one.
    var previousRevision: Revision? {
        guard let last = revisions?.last else { return nil }
        return last.rev == rev && isLocked ? revisions?.dropLast().last : last
    }
}
