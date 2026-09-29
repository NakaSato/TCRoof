#if canImport(UIKit)
import SwiftUI
import UIKit
import Observation
import SurveyCore
import ExcelExport
import PDFReport
import DriveSync

extension SurveyModel {
    // MARK: Google Drive

    public var drive: DriveSync { DriveSync(client: DriveClient(tokens: google), rootName: settings.driveRoot) }

    public func saveToDrive(_ job: Job, kinds: [DriveSync.Kind], photos: Bool = false,
                            progress: @escaping @Sendable (DriveSync.Step) -> Void) async throws -> [DriveFile] {
        // one Drive writer per job: finish a background photo upload first so nothing is sent twice
        manualDriveSave.insert(job.id)
        defer { manualDriveSave.remove(job.id) }
        await uploadRun[job.id]?.value
        let job = self.job(job.id) ?? job
        flush(job.id)
        let excel = try kinds.contains(.xlsx) ? excelData(job).data : Data()
        let pdf = kinds.contains(.pdf) ? pdfData(job) : Data()
        let json = try kinds.contains(.json) ? WebBackup.exportDriveData(job, store: store) : Data()
        let store = self.store, id = job.id
        do {
            let (link, files) = try await drive.save(job, kinds: kinds, build: { k in k == .xlsx ? excel : k == .pdf ? pdf : json },
                                                     photos: photos ? job.driveFolders : [], photoData: { store.data(of: $0, in: id) },
                                                     progress: progress)
            keepLink(link, for: id)
            return files
        } catch let e as DriveSync.Interrupted {
            // remember the photos that did upload so a retry sends only the rest
            keepLink(e.link, for: id)
            throw e
        }
    }

    /// Jobs whose Drive copy is older than their answers. Unnamed drafts wait, as the photo upload does,
    /// so no "งานสำรวจ <date>" folder is made for them.
    public var jobsToSync: [Job] { jobs.filter(waitsForSync) }
    public func waitsForSync(_ j: Job) -> Bool {
        if let cloudPending { return cloudPending.contains(j.id) }
        return j.needsDriveSave && !(j.projectName.isEmpty && j.docNo.isEmpty)
    }
    /// Stored where "sync" sends it: the host's cloud, or else Google Drive.
    public func isSynced(_ j: Job) -> Bool { cloudPending.map { !$0.contains(j.id) } ?? !j.needsDriveSave }

    /// Saves each of `jobsToSync` to Drive in turn; one failing doesn't stop the rest. Returns the failures.
    public func saveAllToDrive(kinds: [DriveSync.Kind], photos: Bool,
                               progress: @escaping (_ done: Int, _ total: Int, _ job: Job) -> Void) async -> [(job: Job, error: Error)] {
        let todo = jobsToSync
        var failed: [(job: Job, error: Error)] = []
        for (i, j) in todo.enumerated() {
            progress(i, todo.count, j)
            do { _ = try await saveToDrive(j, kinds: kinds, photos: photos) { _ in } }
            catch { failed.append((j, error)) }
        }
        return failed
    }

    func keepLink(_ link: DriveLink, for id: UUID) {
        if var j = self.job(id) { j.drive = link; update(j); flush(j.id) }
    }

    public func openFromDrive(_ file: DriveFile) async throws -> Job {
        let j = try await drive.open(file, into: store)
        reload()
        return j
    }
}
#endif
