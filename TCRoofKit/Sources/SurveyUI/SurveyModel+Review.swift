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

    /// แก้ไข (เปิด REV nn+1) (§4.4).
    func openNextRevision(_ id: UUID, reason: String, updateDate: Bool) {
        guard var j = job(id), j.isLocked else { return }
        j.openNextRevision(reason: reason, updateDate: updateDate)
        update(j)
        flush(id)
    }
}
#endif
