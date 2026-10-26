#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport
import DriveSync

/// Issued REVs: issuing, their snapshots, changes, PDFs and sync.
extension SurveyModel {
    /// The snapshot `rev` of a job, as issued.
    func snapshot(_ job: Job, rev: String) -> FormSnapshot? { store.loadRevision(rev: rev, job: job.id) }

    /// Changes from the previous issued REV: the report's รายการแก้ไข and the change markers. Empty before REV 01.
    func revisionChanges(_ job: Job) -> [FieldChange] {
        guard let prev = job.previousRevision, let snap = snapshot(job, rev: prev.rev) else { return [] }
        return FormDiff.changes(from: snap, to: job.snapshot)
    }

    /// The answers differ from the last issued REV, or none has been issued: there is something to issue.
    func hasUnissuedChanges(_ job: Job) -> Bool {
        guard let last = job.lastRevision else { return true }
        return snapshot(job, rev: last.rev) != job.snapshot
    }

    enum IssueError: LocalizedError {
        case photosNotHere, alreadyIssued(String)
        var errorDescription: String? {
            switch self {
            case .photosNotHere: return "รูปบางรูปยังไม่อยู่ในเครื่องนี้ | ดึงรูปจาก Drive ให้ครบก่อนออก REV"
            case .alreadyIssued(let r): return "REV \(r) ออกไปแล้วด้วยข้อมูลอื่น"
            }
        }
    }

    /// ออก REV nn: the number (the next one once the current is issued), the snapshot and its hash in
    /// `revisions/REVnn.json`, the report as `REVnn.pdf`, then the `Revision`. Nothing is locked.
    func issue(_ id: UUID, reason: String, now: Date = Date()) throws {
        flush(id)
        guard var j = job(id) else { return }
        j.values["rev"] = .text(j.nextIssueRev)
        let store = store
        guard let hash = FormHash.of(j.snapshot, photoData: { store.data(of: $0, in: id) }) else { throw IssueError.photosNotHere }
        do { try store.saveRevision(j.snapshot, rev: j.rev, job: id) }
        catch JobStore.RevisionError.exists {
            // an issue that stopped after writing the snapshot may finish; another REV with this number may not
            guard snapshot(j, rev: j.rev) == j.snapshot else { throw IssueError.alreadyIssued(j.rev) }
        }
        let path = JobStore.revisionPDFPath(rev: j.rev)
        j.issue(reason: reason, hash: hash, pdfFile: path, now: now)
        // the PDF as issued: its รายการแก้ไข lists the changes from the REV before
        let pdfOK = (try? pdfData(j).write(to: store.revisionPDF(rev: j.rev, job: id), options: .atomic)) != nil
        if !pdfOK, var list = j.revisions, !list.isEmpty {
            list[list.count - 1].pdfFile = nil
            j.revisions = list
        }
        update(j)
        flush(id)
        // the REV's PDF and snapshot go to Drive's REV folder with the next background upload
        autoUploadPhotos(id, after: 1)
    }

    /// The issued REV files on this device that Drive doesn't have yet: each REV's PDF and snapshot, for `REV/`.
    func revisionUploads(_ job: Job) -> [DriveSync.RevisionUpload] {
        let sent = job.drive?.revisionFiles ?? [:], fm = FileManager.default, name = baseName(job)
        return (job.revisions ?? []).flatMap { r in
            ["pdf", "json"].map { ext in DriveSync.RevisionUpload(key: "REV\(r.rev).\(ext)", name: "REV\(r.rev) \(name).\(ext)") }
        }
        .filter { sent[$0.key] == nil && fm.fileExists(atPath: store.revisionFile($0.key, job: job.id).path) }
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
