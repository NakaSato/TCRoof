import Foundation
import SwiftData
import TCRoofUI

/// Moves the app's photos (daily reports, the ICL, the IEC 62446 test) through the job's Google Drive folder, so every
/// device has them: a photo taken here uploads a few seconds after it is saved and then syncs as a `photos` record
/// (`CloudSync`), and a photo received that way downloads here. Survey photos have their own (`SurveyModel.autoUploadPhotos`);
/// both follow the survey setting `ซิงก์รูปขึ้น Google Drive อัตโนมัติ`. Every device reads the photos from the Drive of the
/// account that took them, so a teammate on another Google account needs that `TCRoof Projects` folder shared.
@MainActor
final class PhotoSync {
    static let shared = PhotoSync()

    private var context: ModelContext?
    private var survey: SurveyModel?
    private var wait: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var again = false
    private var paused = 0

    func start(context: ModelContext, survey: SurveyModel) {
        self.context = context
        self.survey = survey
        schedule(after: 2)
    }

    func stop() {
        wait?.cancel(); wait = nil
        context = nil; survey = nil
    }

    /// Runs a few seconds after the last save, so a burst of photos goes in one pass.
    func schedule(after seconds: Double = 5) {
        guard context != nil else { return }
        wait?.cancel()
        wait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.run()
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
        guard paused == 0, let context, let survey, survey.google.isSignedIn, survey.settings.autoUploadPhotos else { return }
        running = Task { [weak self] in
            var failed = false
            do { try await self?.download(context, survey) } catch { failed = true; print("PhotoSync: download: \(error.localizedDescription)") }
            do { try await self?.upload(context, survey) } catch { failed = true; print("PhotoSync: upload: \(error.localizedDescription)") }
            guard let self else { return }
            self.running = nil
            // offline or a Drive hiccup: try again in a minute
            if self.again || failed { self.again = false; self.schedule(after: failed ? 60 : 1) }
        }
    }

    /// The photos other devices took, four at a time; each shows as soon as it lands.
    private func download(_ context: ModelContext, _ survey: SurveyModel) async throws {
        let todo = (try? context.fetch(FetchDescriptor<PhotoAsset>(predicate: #Predicate { $0.needsDownload }))) ?? []
        let files = todo.compactMap { p in p.driveFileID.map { (p, $0) } }
        guard !files.isEmpty else { return }
        var failure: Error?
        await withTaskGroup(of: (PhotoAsset, Result<Data, Error>).self) { group in
            var next = files.makeIterator()
            func start() {
                guard let (photo, id) = next.next() else { return }
                group.addTask { @MainActor in
                    do { return (photo, .success(try await survey.driveDownload(id))) } catch { return (photo, .failure(error)) }
                }
            }
            for _ in 0..<4 { start() }
            for await (photo, result) in group {
                switch result {
                case .success(let data) where !photo.isDeleted:
                    photo.data = data
                    photo.needsDownload = false
                    try? context.save()
                case .failure(let error): failure = error
                default: break
                }
                start()
            }
        }
        if let failure { throw failure }
    }

    /// The photos taken here that Drive doesn't have yet, job by job, into the job's Drive folder.
    private func upload(_ context: ModelContext, _ survey: SurveyModel) async throws {
        let waiting = (try? context.fetch(FetchDescriptor<PhotoAsset>(predicate: #Predicate { $0.driveFileID == nil && !$0.needsDownload }))) ?? []
        var jobs: [Job] = []
        for p in waiting {
            guard let job = p.log?.job ?? p.inspection?.job ?? p.iecJob, !jobs.contains(where: { $0 === job }) else { continue }
            jobs.append(job)
        }
        for job in jobs where paused == 0 {
            let photos = ProjectDriveUpload.pendingPhotos(job)
            guard !photos.isEmpty else { continue }
            let folder = try await survey.driveFolder(DriveFolders.name(for: job), root: DriveFolders.root)
            if job.driveFolderURL == nil { job.driveFolderURL = folder.url.absoluteString }
            var subfolders: [String: String] = [:]
            for p in photos where paused == 0 && !p.photo.isDeleted && p.photo.driveFileID == nil {
                let path = p.folder.joined(separator: "/")
                if subfolders[path] == nil { subfolders[path] = try await survey.driveSubfolder(p.folder, under: folder.id) }
                let file = DriveUpload(name: p.name, data: p.photo.data, mimeType: "image/jpeg")
                let id = try await survey.driveUpload(file, to: subfolders[path] ?? folder.id)
                // deleted while it uploaded: the Drive file stays, the record isn't made
                guard !p.photo.isDeleted else { continue }
                p.photo.driveFileID = id
                try? context.save()
            }
        }
    }
}
