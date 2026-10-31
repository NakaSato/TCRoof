import Foundation
import SwiftData
import TCRoofUI
import ExcelExport
import TCRoofCore

/// Moves the app's photos (daily reports, the ICL, the IEC 62446 test) through the job's Google Drive folder, so every
/// device has them: a photo taken here uploads a few seconds after it is saved and then syncs as a `photos` record
/// (`CloudSync`), and a photo received that way downloads here. Survey photos have their own (`SurveyModel.autoUploadPhotos`);
/// both follow the survey setting `ซิงก์รูปขึ้น Google Drive อัตโนมัติ`. Every device reads the photos from the Drive of the
/// account that took them, so a teammate on another Google account needs that `TCRoof Projects` folder shared.
/// A station's MP plan workbook (`Job.scheduleWorkbook`) travels the same way, its Drive id on the job record.
@MainActor
final class PhotoSync {
    static let shared = PhotoSync()

    private var context: ModelContext?
    private var survey: SurveyModel?
    private var wait: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var again = false
    private var paused = 0
    private var projectBrowsing = BackgroundFileDeferral()
    private var canRunAutomatically: Bool { paused == 0 && !projectBrowsing.isDeferred }

    func setProjectListVisible(_ visible: Bool, owner: UUID) {
        if visible {
            projectBrowsing.setVisible(true, owner: owner)
            wait?.cancel(); wait = nil
        } else if projectBrowsing.setVisible(false, owner: owner) {
            schedule(after: 1)
        }
    }

    func start(context: ModelContext, survey: SurveyModel) {
        self.context = context
        self.survey = survey
        schedule(after: 2)
        // job document uploads started earlier that didn't finish (the person left, offline, the app closed)
        ProjectDriveUpload.resumeRequested(context: context, survey: survey)
    }

    func stop() {
        wait?.cancel(); wait = nil
        context = nil; survey = nil
    }

    /// Runs a few seconds after the last save, so a burst of photos goes in one pass.
    func schedule(after seconds: Double = 5) {
        guard context != nil else { return }
        guard !projectBrowsing.isDeferred else { return }
        wait?.cancel()
        wait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.run()
        }
    }

    /// One upload pass outside the timer, for iOS's background task while the app is closed (`DriveBackgroundWork`):
    /// the photos and plan workbooks not on Drive yet, after a pass already running. False when one failed.
    func uploadNow(context: ModelContext, survey: SurveyModel) async -> Bool {
        await running?.value
        guard canRunAutomatically, survey.google.isSignedIn, survey.settings.autoUploadPhotos else { return true }
        do {
            try await upload(context, survey)
            try await workbooks(context, survey)
            return true
        } catch {
            print("PhotoSync: background pass: \(error.localizedDescription)")
            return false
        }
    }

    /// Holds the background pass while the job screen's own Drive upload runs (`ProjectDriveUpload.run`).
    func pause() async {
        paused += 1
        await running?.value
    }

    func resume() {
        paused = max(0, paused - 1)
        if paused == 0 { schedule(after: 1) }
    }

    private func run() {
        guard running == nil else { again = true; return }
        guard canRunAutomatically, let context, let survey, survey.google.isSignedIn, survey.settings.autoUploadPhotos else { return }
        // time to hand the photos over if the person leaves the app mid-pass; iOS sends them from there
        let time = BackgroundTime("Drive photos")
        running = Task { [weak self] in
            defer { time.end() }
            var failed = false
            do { try await self?.download(context, survey) } catch { failed = true; print("PhotoSync: download: \(error.localizedDescription)") }
            do { try await self?.upload(context, survey) } catch { failed = true; print("PhotoSync: upload: \(error.localizedDescription)") }
            do { try await self?.workbooks(context, survey) } catch { failed = true; print("PhotoSync: workbooks: \(error.localizedDescription)") }
            await self?.shareFolders(context, survey)
            guard let self else { return }
            self.running = nil
            // offline or a Drive hiccup: try again in a minute
            if self.again || failed { self.again = false; self.schedule(after: failed ? 60 : 1) }
        }
    }

    /// Every job folder this device knows is shared with everyone who can open the job (the user, 2026-10-19): a
    /// contractor assigned later, or a folder made before this, gets access without waiting for a new photo. Each
    /// address is sent once per folder (`shareJobFolder` remembers), so an up-to-date pass makes no request; a folder
    /// this account doesn't own is refused by Drive and tried again on a later pass.
    private func shareFolders(_ context: ModelContext, _ survey: SurveyModel) async {
        guard canRunAutomatically else { return }
        let jobs = (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.driveFolderURL != nil }))) ?? []
        for job in jobs where canRunAutomatically {
            guard let url = job.driveFolderURL, let id = DriveConfig.folderID(from: url) else { continue }
            await survey.shareJobFolder(id, with: DriveReaders.team() + job.externals + (job.supervisorEmail.map { [$0] } ?? []))
        }
        for report in survey.jobs where canRunAutomatically {
            guard let id = report.drive?.folderID, let readers = survey.driveReaders?(report) else { continue }
            await survey.shareJobFolder(id, with: readers)
        }
    }

    /// The photos other devices took, four at a time; each shows as soon as it lands.
    private func download(_ context: ModelContext, _ survey: SurveyModel) async throws {
        guard canRunAutomatically else { return }
        let todo = (try? context.fetch(FetchDescriptor<PhotoAsset>(predicate: #Predicate { $0.needsDownload }))) ?? []
        let files = todo.compactMap { p in p.driveFileID.map { (p, $0) } }
        guard !files.isEmpty else { return }
        var failure: Error?
        await withTaskGroup(of: (PhotoAsset, Result<Data, Error>).self) { group in
            var next = files.makeIterator()
            func start(allowed: Bool) {
                guard allowed else { return }
                guard let (photo, id) = next.next() else { return }
                group.addTask { @MainActor in
                    do { return (photo, .success(try await survey.driveDownload(id))) } catch { return (photo, .failure(error)) }
                }
            }
            for _ in 0..<4 { start(allowed: canRunAutomatically) }
            for await (photo, result) in group {
                switch result {
                case .success(let data) where !photo.isDeleted:
                    photo.data = data
                    photo.needsDownload = false
                    try? context.save()
                case .failure(let error): failure = error
                default: break
                }
                start(allowed: canRunAutomatically)
            }
        }
        if let failure { throw failure }
    }

    /// The photos taken here that Drive doesn't have yet, job by job, into the job's Drive folder.
    private func upload(_ context: ModelContext, _ survey: SurveyModel) async throws {
        guard canRunAutomatically else { return }
        let waiting = (try? context.fetch(FetchDescriptor<PhotoAsset>(predicate: #Predicate { $0.driveFileID == nil && !$0.needsDownload }))) ?? []
        var jobs: [Job] = []
        for p in waiting {
            guard let job = p.ownerJob, !jobs.contains(where: { $0 === job }) else { continue }
            jobs.append(job)
        }
        for job in jobs where canRunAutomatically {
            let photos = ProjectDriveUpload.pendingPhotos(job)
            guard !photos.isEmpty else { continue }
            let route = DriveRoute(survey: survey)
            let folder = try await route.jobFolder(job)
            if job.driveFolderURL == nil { job.driveFolderURL = folder.url.absoluteString }
            var subfolders: [String: String] = [:]
            // every photo handed to the background transfer first, so iOS sends them all if the app goes to the
            // background; a failure part-way still records those handed over
            var waits: [(photo: PhotoAsset, wait: Task<String, Error>)] = []
            var failure: Error?
            do {
                for p in photos where canRunAutomatically && !p.photo.isDeleted && p.photo.driveFileID == nil {
                    let place = route.construction(p.folder)
                    let path = place.joined(separator: "/")
                    if subfolders[path] == nil { subfolders[path] = try await survey.driveSubfolder(place, under: folder.id) }
                    // signatures are PNG (they keep their transparent background); photos JPEG
                    let png = p.photo.data.starts(with: [0x89, 0x50, 0x4E, 0x47])
                    let file = DriveUpload(name: p.name, data: p.photo.data, mimeType: png ? "image/png" : "image/jpeg")
                    waits.append((p.photo, try await survey.driveStartUpload(file, to: subfolders[path] ?? folder.id)))
                }
            } catch { failure = error }
            for w in waits {
                do {
                    let id = try await w.wait.value
                    // deleted while it uploaded: the Drive file stays, the record isn't made
                    guard !w.photo.isDeleted else { continue }
                    w.photo.driveFileID = id
                    try? context.save()
                } catch { failure = failure ?? error }
            }
            if let failure { throw failure }
        }
    }

    /// MP plan workbooks: one imported here goes up into the job's `แผนงาน MP` folder, one imported elsewhere comes down.
    /// Each job on its own: one that fails (offline, or a file this account can't read) doesn't hold back the others.
    private func workbooks(_ context: ModelContext, _ survey: SurveyModel) async throws {
        guard canRunAutomatically else { return }
        let jobs = (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.scheduleWorkbookName != nil }))) ?? []
        var failure: Error?
        for job in jobs where canRunAutomatically {
            do { try await workbook(job, context, survey) } catch {
                failure = failure ?? error
                print("PhotoSync: workbook of \(job.code): \(error.localizedDescription)")
            }
        }
        if let failure { throw failure }
    }

    /// Downloads that failed, by Drive id, and when to try again: a file this account can't read (another account's
    /// Drive not shared with it, or deleted there) waits an hour rather than failing every minute.
    private var workbookRetry: [String: Date] = [:]
    private static let workbookRetryDelay: TimeInterval = 3600

    private func workbook(_ job: Job, _ context: ModelContext, _ survey: SurveyModel) async throws {
        if job.scheduleWorkbookDownloading, let id = job.scheduleWorkbookDriveID {
            if let at = workbookRetry[id], at > .now { return }
            let data: Data
            do { data = try await survey.driveDownload(id) } catch {
                workbookRetry[id] = Date.now.addingTimeInterval(Self.workbookRetryDelay)
                throw error
            }
            workbookRetry[id] = nil
            // replaced while it downloaded: the next pass takes the new one
            guard !job.isDeleted, job.scheduleWorkbookDriveID == id else { return }
            job.scheduleWorkbook = data
            try? context.save()
        } else if job.scheduleWorkbookUnsent, let data = job.scheduleWorkbook {
            let route = DriveRoute(survey: survey)
            let folder = try await route.jobFolder(job)
            if job.driveFolderURL == nil { job.driveFolderURL = folder.url.absoluteString }
            let sub = try await survey.driveSubfolder(route.construction([Self.workbookFolder]), under: folder.id)
            let name = MPWorkbook.fileName(original: job.scheduleWorkbookName, fallback: "แผนงาน MP " + job.stationName)
            let mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            let id = try await survey.driveUpload(DriveUpload(name: name, data: data, mimeType: mime), to: sub)
            // another file imported while this one uploaded: it goes up next pass
            guard !job.isDeleted, job.scheduleWorkbook == data else { return }
            job.scheduleWorkbookDriveID = id
            try? context.save()
        }
    }

    static let workbookFolder = "แผนงาน MP"
}
