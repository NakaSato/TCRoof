#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// Issuing a REV, opening the next one and checking a locked job (docs/specs/review-lock-revisions-swift.md §4).
extension SurveyModel {
    enum ReviewError: LocalizedError {
        case photosNotHere, alreadyIssued(String)
        var errorDescription: String? {
            switch self {
            case .photosNotHere: return "รูปบางรูปยังไม่อยู่ในเครื่องนี้ · ดึงรูปจาก Drive ให้ครบก่อนล็อก"
            case .alreadyIssued(let r): return "REV \(r) ออกไปแล้วด้วยข้อมูลอื่น · เปิด REV ใหม่ก่อนลงนาม"
            }
        }
    }

    /// The snapshot `rev` of a job, as issued.
    func snapshot(_ job: Job, rev: String) -> FormSnapshot? { store.loadRevision(rev: rev, job: job.id) }

    /// Changes from the previous issued REV: the report's รายการแก้ไข and the change markers. Empty before REV 01.
    func revisionChanges(_ job: Job) -> [FieldChange] {
        guard let prev = job.previousRevision, let snap = snapshot(job, rev: prev.rev) else { return [] }
        return FormDiff.changes(from: snap, to: job.snapshot)
    }

    /// nil when a photo isn't on this device yet.
    func formHash(_ job: Job) -> String? {
        let store = store
        return FormHash.of(job.snapshot) { store.data(of: $0, in: job.id) }
    }

    /// The answers no longer match what was signed (`job.json` edited by hand, a restore of other content).
    /// False while a photo is missing here: that's not proof of a change.
    func integrityBroken(_ job: Job) -> Bool {
        guard let lock = job.lock, let h = formHash(job) else { return false }
        return h != lock.hash
    }

    /// ล็อกและออก REV nn (§4.2): snapshot and hash, `revisions/REVnn.json`, the report as `REVnn.pdf`, then the lock.
    func issue(_ id: UUID, now: Date = Date()) throws {
        flush(id)
        guard let j = job(id), !j.isLocked else { return }
        guard let hash = formHash(j) else { throw ReviewError.photosNotHere }
        do { try store.saveRevision(j.snapshot, rev: j.rev, job: id) }
        catch JobStore.RevisionError.exists {
            // an issue that stopped after writing the snapshot may finish; another REV with this number may not
            guard snapshot(j, rev: j.rev) == j.snapshot else { throw ReviewError.alreadyIssued(j.rev) }
        }
        let path = JobStore.revisionPDFPath(rev: j.rev)
        var issued = j
        issued.issue(hash: hash, pdfFile: path, now: now)
        // the PDF as signed: its footer carries the code, its รายการแก้ไข the changes from the REV before
        let pdf = pdfData(issued)
        let pdfOK = (try? pdf.write(to: store.revisionPDF(rev: j.rev, job: id), options: .atomic)) != nil
        if !pdfOK, var list = issued.revisions, !list.isEmpty {
            list[list.count - 1].pdfFile = nil
            issued.revisions = list
        }
        update(issued)
        flush(id)
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
        j.revisions = Array(list[...i]); j.pendingReason = nil
        j.lock = FormLock(rev: rev, lockedAt: list[i].issuedAt, hash: list[i].hash)
        let complete = missingPhotos(j).isEmpty
        let out = complete ? url : tempURL("REV\(rev) " + baseName(j) + ".pdf")
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? pdfData(j).write(to: out, options: .atomic)) != nil else { return nil }
        return out
    }

    /// แก้ไข (เปิด REV nn+1) (§4.4).
    func openNextRevision(_ id: UUID, reason: String, updateDate: Bool) {
        guard var j = job(id), j.isLocked else { return }
        j.openNextRevision(reason: reason, updateDate: updateDate)
        update(j)
        flush(id)
    }
}
#endif
