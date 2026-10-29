#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport
import DriveSync

/// Issued REVs: issuing, their snapshots, changes, PDFs and sync.
extension SurveyModel {
    /// The snapshot `rev` of a job, as issued.
    func snapshot(_ job: Job, rev: String) -> FormSnapshot? {
        _ = revisionArrivals
        let key = "\(job.id)/\(rev)"
        if let snapshot = revisionSnapshots[key] { return snapshot }
        if !revisionReads.contains(key), revisionLoads[job.id] == nil {
            revisionLoads[job.id] = Task { [weak self] in await self?.prepareRevisionSnapshots(job) }
        }
        return nil
    }

    func prepareRevisionSnapshots(_ job: Job) async {
        guard (job.revisions ?? []).contains(where: { !revisionReads.contains("\(job.id)/\($0.rev)") }) else { revisionLoads[job.id] = nil; return }
        let session = storageSession
        let revision = revisionArrivals
        let snapshots = await writer.revisionSnapshots(job)
        let documents = await writer.revisionDocuments(job)
        guard !Task.isCancelled, storageSession == session else { return }
        revisionLoads[job.id] = nil
        guard revisionArrivals == revision else { return }
        for item in job.revisions ?? [] {
            let key = "\(job.id)/\(item.rev)"
            revisionSnapshots[key] = snapshots[item.rev]
            revisionJSONs[key] = documents[item.rev]
            revisionReads.insert(key)
        }
        revisionArrivals += 1
        onChange?()
    }

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
    func issue(_ id: UUID, reason: String, now: Date = Date()) async throws {
        try await flushAndWait(id)
        guard var j = job(id) else { return }
        await prepareRevisionSnapshots(j)
        j.values["rev"] = .text(j.nextIssueRev)
        let store = store
        let original = self.job(id)?.snapshot
        let hash: String
        do { hash = try await writer.issueSnapshot(j) }
        catch JobStoreWriter.IssueError.photosMissing { throw IssueError.photosNotHere }
        catch JobStoreWriter.IssueError.alreadyIssued { throw IssueError.alreadyIssued(j.rev) }
        let path = JobStore.revisionPDFPath(rev: j.rev)
        j.issue(reason: reason, hash: hash, pdfFile: path, now: now)
        // the PDF as issued: its รายการแก้ไข lists the changes from the REV before
        let data = await pdfData(j)
        let pdfOK = (try? await writer.write(data, to: store.revisionPDF(rev: j.rev, job: id))) != nil
        if !pdfOK, var list = j.revisions, !list.isEmpty {
            list[list.count - 1].pdfFile = nil
            j.revisions = list
        }
        guard self.job(id)?.snapshot == original, !Task.isCancelled else { throw CancellationError() }
        update(j)
        try await flushAndWait(id)
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
            _ = snapshot(job, rev: r.rev)
            return revisionJSONs["\(job.id)/\(r.rev)"].map { RevisionDoc(job: job.id, rev: r.rev, json: $0) }
        }
    }

    /// A REV issued on another device. One already here is kept as it is.
    public func receiveRevision(_ doc: RevisionDoc) async -> Bool {
        let session = storageSession
        let saved = await writer.receiveRevision(Data(doc.json.utf8), rev: doc.rev, job: doc.job)
        guard saved, !Task.isCancelled, storageSession == session else { return false }
        revisionReads.remove("\(doc.job)/\(doc.rev)")
        revisionSnapshots["\(doc.job)/\(doc.rev)"] = nil
        revisionJSONs["\(doc.job)/\(doc.rev)"] = nil
        revisionArrivals += 1
        return true
    }

    /// The PDF as signed; on a device without the file, the report rebuilt from the REV's snapshot (kept once every
    /// photo is here, so it matches the signed one).
    func revisionPDF(_ job: Job, rev: String) async -> URL? {
        await prepareRevisionSnapshots(job)
        let url = store.revisionPDF(rev: rev, job: job.id)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let list = job.revisions, let i = list.firstIndex(where: { $0.rev == rev }), let snap = snapshot(job, rev: rev) else { return nil }
        var j = job
        j.values = snap.values; j.modules = snap.modules
        j.revisions = Array(list[...i])
        let present = await writer.existingPhotoIDs(j)
        let complete = Set(j.allPhotos.map(\.id)).isSubset(of: present)
        let out = complete ? url : tempURL("REV\(rev) " + baseName(j) + ".pdf")
        let data = await pdfData(j)
        guard (try? await writer.write(data, to: out)) != nil else { return nil }
        return out
    }
}
#endif
