#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// Issued REVs: their snapshots, changes, PDFs and sync (docs/specs/review-lock-revisions-swift.md).
extension SurveyModel {
    /// The snapshot `rev` of a job, as issued.
    func snapshot(_ job: Job, rev: String) -> FormSnapshot? { store.loadRevision(rev: rev, job: job.id) }

    /// Changes from the previous issued REV: the report's รายการแก้ไข and the change markers. Empty before REV 01.
    func revisionChanges(_ job: Job) -> [FieldChange] {
        guard let prev = job.previousRevision, let snap = snapshot(job, rev: prev.rev) else { return [] }
        return FormDiff.changes(from: snap, to: job.snapshot)
    }

    // MARK: other devices

    /// One issued REV's snapshot as the host's cloud stores it: written once, never changed.
    public struct RevisionDoc: Sendable {
        public let job: UUID
        public let rev: String
        public let json: String
        public init(job: UUID, rev: String, json: String) { self.job = job; self.rev = rev; self.json = json }
    }

    /// The issued REVs of a job that this device holds.
    public func revisionDocs(_ job: Job) -> [RevisionDoc] {
        (job.revisions ?? []).compactMap { r in
            store.revisionData(rev: r.rev, job: job.id).flatMap { String(data: $0, encoding: .utf8) }.map { RevisionDoc(job: job.id, rev: r.rev, json: $0) }
        }
    }

    /// A REV issued on another device. One already here is kept as it is.
    public func receiveRevision(_ doc: RevisionDoc) {
        guard (try? store.saveRevisionData(Data(doc.json.utf8), rev: doc.rev, job: doc.job)) != nil else { return }
        revisionArrivals += 1
    }

    /// The PDF as signed; on a device without the file, the report rebuilt from the REV's snapshot (kept once every
    /// photo is here, so it matches the signed one).
    func revisionPDF(_ job: Job, rev: String) -> URL? {
        let url = store.revisionPDF(rev: rev, job: job.id)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let list = job.revisions, let i = list.firstIndex(where: { $0.rev == rev }), let snap = snapshot(job, rev: rev) else { return nil }
        var j = job
        j.values = snap.values; j.modules = snap.modules
        j.revisions = Array(list[...i])
        let complete = missingPhotos(j).isEmpty
        let out = complete ? url : tempURL("REV\(rev) " + baseName(j) + ".pdf")
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? pdfData(j).write(to: out, options: .atomic)) != nil else { return nil }
        return out
    }
}
#endif
