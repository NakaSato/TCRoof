import Foundation
import UniformTypeIdentifiers
import TCRoofUI
import TCRoofCore

enum DriveFolders {
    /// Top-level folder in the signed-in user's own Drive that holds one folder per job (a contractor's, or a TC
    /// engineer's before the center folder is set: `DriveRoute`).
    static let root = "TCRoof Projects"

    static func name(for job: Job) -> String {
        "\(job.code) \(job.projectName)".trimmingCharacters(in: .whitespaces)
    }
}

/// Uploads a job's documents that aren't on Drive yet, plus the signed ICL report once submitted.
@MainActor
enum ProjectDriveUpload {
    /// Files still to upload for the job.
    static func pendingCount(_ job: Job) -> Int {
        job.documents.filter { $0.driveFileID == nil }.count + (pendingInspection(job) == nil ? 0 : 1) + pendingPhotos(job).count
    }

    /// Photos of daily reports, the ICL and the IEC test not on Drive yet, with the folder and name each goes under.
    /// `PhotoSync` sends them a few seconds after they're taken, so the other devices get them; a daily report's
    /// photos go before it is signed, and one deleted afterwards stays on Drive.
    static func pendingPhotos(_ job: Job) -> [(photo: PhotoAsset, folder: [String], name: String)] {
        let daily = job.dailyLogs.flatMap { log -> [(PhotoAsset, [String], String)] in
            let lines = log.report?.progress ?? []
            return log.sortedPhotos.enumerated().compactMap { i, p in
                guard p.driveFileID == nil else { return nil }
                let line = lines.first { $0.id.uuidString == p.tag }
                return (p, RoutineReport.photoFolder(date: log.date), RoutineReport.photoName(date: log.date, index: i + 1, line: line))
            }
            // the drawn signatures, beside the day's photos
            + [(InstallLog.engineerSignatureTag, "Site Engineer"), (InstallLog.inspectorSignatureTag, "Inspector")].compactMap { tag, role in
                guard let p = log.signature(tag), p.driveFileID == nil else { return nil }
                let day = RoutineReport.photoName(date: log.date, index: 0, line: nil).split(separator: " ").first.map(String.init) ?? ""
                return (p, RoutineReport.photoFolder(date: log.date), "\(day) ลายเซ็น \(role).png")
            }
        }
        return daily + pendingICLPhotos(job) + pendingIECPhotos(job)
    }

    /// The ICL's step photos (`ICL รูปถ่าย/โครงสร้าง 1.jpg`).
    private static func pendingICLPhotos(_ job: Job) -> [(photo: PhotoAsset, folder: [String], name: String)] {
        guard let inspection = job.inspection else { return [] }
        return InspectionStep.all.flatMap { step in
            inspection.photos(for: step.id).enumerated().compactMap { i, p in
                p.driveFileID == nil ? (p, ["ICL รูปถ่าย"], "\(step.short) \(i + 1).jpg") : nil
            }
        }
    }

    /// The IEC test's photos (`IEC 62446/รูปถ่าย/INV1ST3 ก่อน แรงดัน.jpg`), only those the test still uses; a sample's
    /// photos stay on the device, since they aren't this job's.
    static func pendingIECPhotos(_ job: Job) -> [(photo: PhotoAsset, folder: [String], name: String)] {
        guard let r = job.iecReport, r.sampleName == nil else { return [] }
        let names = r.photoFileNames()
        return job.iecPhotos.compactMap { p in
            guard p.driveFileID == nil, let name = names[p.tag] else { return nil }
            return (p, IECReport.photoFolder, name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The IEC photos on Drive over those the test uses, for the install page's line.
    static func iecPhotoUpload(_ job: Job) -> IECReport.Tally? {
        guard let r = job.iecReport, r.sampleName == nil else { return nil }
        let used = Set(r.photoFileNames().keys)
        guard !used.isEmpty else { return nil }
        return .init(job.iecPhotos.filter { $0.driveFileID != nil && used.contains($0.tag) }.count, used.count)
    }

    private static func pendingInspection(_ job: Job) -> Inspection? {
        guard let inspection = job.inspection, inspection.submittedAt != nil, inspection.driveFileID == nil else { return nil }
        return inspection
    }

    /// Records each file's Drive id as soon as it lands, so a failure part-way doesn't re-upload finished files.
    static func run(_ job: Job, session: GoogleSession, progress: (Int, Int) -> Void) async throws {
        // one Drive writer: a background photo upload finishes first, so no photo is sent twice
        await PhotoSync.shared.pause()
        defer { PhotoSync.shared.resume() }
        let docs = job.documents.filter { $0.driveFileID == nil }.sorted { $0.addedAt < $1.addedAt }
        let inspection = pendingInspection(job)
        let photos = pendingPhotos(job)
        let total = docs.count + (inspection == nil ? 0 : 1) + photos.count
        guard total > 0 else { return }

        progress(0, total)
        let route = DriveRoute(survey: session.survey)
        let folder = try await route.jobFolder(job)
        job.driveFolderURL = folder.url.absoluteString

        var done = 0
        var subfolders: [String: String] = [:]
        func target(_ path: [String]) async throws -> String {
            guard !path.isEmpty else { return folder.id }
            let key = path.joined(separator: "/")
            if let id = subfolders[key] { return id }
            let id = try await session.survey.driveSubfolder(path, under: folder.id)
            subfolders[key] = id
            return id
        }
        for doc in docs {
            // a paper in two hand-over folders goes into both; the record keeps the first copy's id
            var first: String?
            for place in route.places(doc, in: job) {
                let file = DriveUpload(name: place.name, data: doc.data, mimeType: mimeType(for: doc.name))
                let id = try await session.survey.driveUpload(file, to: try await target(place.folder))
                if first == nil { first = id }
            }
            doc.driveFileID = first
            done += 1
            progress(done, total)
        }
        for p in photos {
            let file = DriveUpload(name: p.name, data: p.photo.data, mimeType: "image/jpeg")
            p.photo.driveFileID = try await session.survey.driveUpload(file, to: try await target(route.construction(p.folder)))
            done += 1
            progress(done, total)
        }
        if let inspection, let url = InspectionReport.renderPDF(inspection) {
            let data = try Data(contentsOf: url)
            let file = DriveUpload(name: url.lastPathComponent, data: data, mimeType: "application/pdf")
            inspection.driveFileID = try await session.survey.driveUpload(file, to: try await target(route.construction([])))
            progress(total, total)
        }
    }

    static func mimeType(for name: String) -> String {
        UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}
