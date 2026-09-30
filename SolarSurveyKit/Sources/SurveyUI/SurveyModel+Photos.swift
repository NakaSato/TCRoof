#if canImport(UIKit)
import SwiftUI
import UIKit
import Observation
import SurveyCore
import ExcelExport
import PDFReport
import DriveSync

extension SurveyModel {
    // MARK: photos

    /// Scales a picked or captured image to at most `maxSide` px and stores it as JPEG (PNG for signatures).
    public func addPhoto(_ image: UIImage, to job: UUID, maxSide: CGFloat = 1600, png: Bool = false) -> Photo? {
        let img = image.scaled(maxSide: maxSide, opaque: !png)
        guard let data = png ? img.pngData() : img.jpegData(compressionQuality: 0.8) else { return nil }
        let px = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
        let photo = try? store.addPhoto(data, width: Int(px.width), height: Int(px.height), png: png, to: job)
        // the field takes the photo right after this returns; the delay lets that land before the upload looks
        if photo != nil { autoUploadPhotos(job) }
        return photo
    }

    public func image(_ p: Photo, in job: UUID) -> UIImage? {
        _ = photoRevision  // views showing an empty frame look again once a download lands
        let key = "\(job.uuidString)/\(p.fileName)" as NSString
        if let i = cache.object(forKey: key) { return i }
        guard let d = store.data(of: p, in: job), let i = UIImage(data: d) else { return nil }
        cache.setObject(i, forKey: key)
        return i
    }

    // MARK: photos taken on another device

    /// Progress of moving one job's photos to or from Drive.
    public struct PhotoTransfer: Equatable, Sendable {
        public var total = 0, done = 0, failed = 0
        public var error: String?
        public var running: Bool { done + failed < total }
    }

    /// Photos the job refers to whose files aren't on this device (taken on another iPad).
    public func missingPhotos(_ job: Job) -> [Photo] { job.allPhotos.filter { !store.hasPhoto($0, in: job.id) } }

    /// The missing photos that the device which took them already saved to Drive, with their Drive file ids.
    public func downloadablePhotos(_ job: Job) -> [(photo: Photo, fileID: String)] {
        let files = job.drive?.photoFiles ?? [:]
        return missingPhotos(job).compactMap { p in files[p.id.uuidString].map { (p, $0) } }
    }

    /// Downloads the job's missing photos from its Drive folder, four at a time. Does nothing while signed out.
    public func fetchMissingPhotos(_ id: UUID) async {
        guard photoFetch[id]?.running != true, google.isSignedIn, let job = job(id) else { return }
        let todo = downloadablePhotos(job)
        guard !todo.isEmpty else { return }
        photoFetch[id] = PhotoTransfer(total: todo.count)
        let client = DriveClient(tokens: google), store = self.store
        await withTaskGroup(of: String?.self) { group in
            var next = todo.makeIterator()
            func start() -> Bool {
                guard let (p, fileID) = next.next() else { return false }
                group.addTask {
                    do { try store.writePhoto(try await client.download(fileID), for: p, in: id); return nil }
                    catch { return error.localizedDescription }
                }
                return true
            }
            for _ in 0..<4 { if !start() { break } }
            for await failure in group {
                if let failure { photoFetch[id]?.failed += 1; photoFetch[id]?.error = failure }
                else { photoFetch[id]?.done += 1; photoRevision += 1 }
                _ = start()
            }
        }
    }


    /// Photos taken here that Drive doesn't have yet.
    public func photosToUpload(_ job: Job) -> Int {
        let sent = job.drive?.photoFiles ?? [:]
        return job.driveFolders.flatMap(\.photos).filter { sent[$0.photo.id.uuidString] == nil && store.hasPhoto($0.photo, in: job.id) }.count
    }

    /// Sends the job's new photos to Drive a few seconds after the last change, so another iPad can download them.
    /// Waits until the job has a name, so its Drive folder isn't created as "งานสำรวจ <date>".
    public func autoUploadPhotos(_ id: UUID, after seconds: Double = 5) {
        guard settings.autoUploadPhotos, google.isSignedIn else { return }
        uploadWait[id]?.cancel()
        uploadWait[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.uploadRun[id]?.value
            guard !Task.isCancelled, !self.manualDriveSave.contains(id), let job = self.job(id),
                  !(job.projectName.isEmpty && job.docNo.isEmpty), self.photosToUpload(job) > 0 else { return }
            let run = Task { await self.uploadPhotos(id) }
            self.uploadRun[id] = run
            await run.value
            if self.uploadRun[id] == run { self.uploadRun[id] = nil }
        }
    }

    private func uploadPhotos(_ id: UUID) async {
        guard let job = job(id) else { return }
        let store = self.store
        photoUpload[id] = PhotoTransfer(total: photosToUpload(job))
        do {
            let link = try await drive.syncPhotos(job, photos: job.driveFolders, photoData: { store.data(of: $0, in: id) }) { [weak self] step in
                guard case .photos(let done, let total) = step else { return }
                Task { @MainActor in self?.photoUpload[id] = PhotoTransfer(total: total, done: done) }
            }
            keepLink(link, for: id)
            photoUpload[id] = nil
        } catch {
            if let e = error as? DriveSync.Interrupted { keepLink(e.link, for: id) }
            photoUpload[id]?.error = error.localizedDescription
            // offline or a Drive hiccup: try again in a minute (a folder this account can't reach won't fix itself)
            if !(error is DriveSync.FolderUnreachable) { autoUploadPhotos(id, after: 60) }
        }
    }

    /// Satellite picture centred on the job's GPS, stored like any other photo.
    /// Uses the zoom level picked on A1 (`mapZoom`), else the one in settings.
    public func mapPhoto(gps: String, for job: UUID) async throws -> Photo {
        let zoom = self.job(job).flatMap { Int($0.values.text("mapZoom")) } ?? settings.mapZoom
        let img = try await MapImage.fetch(gps: gps, zoom: zoom, googleKey: settings.googleMapsKey)
        guard let p = addPhoto(img, to: job, maxSide: 1600) else { throw MapImage.Failure.badResponse("บันทึกภาพไม่ได้") }
        return p
    }
}
#endif
