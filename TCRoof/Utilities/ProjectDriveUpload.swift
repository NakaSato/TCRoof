import Foundation
import UniformTypeIdentifiers
import TCRoofUI
import TCRoofCore

enum DriveFolders {
    /// Top-level folder in the signed-in user's Drive that holds one folder per job.
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

    /// Photos of signed daily reports not on Drive yet, with the folder and name each goes under.
    private static func pendingPhotos(_ job: Job) -> [(photo: PhotoAsset, folder: [String], name: String)] {
        job.dailyLogs.filter { $0.engineerSignedAt != nil }.flatMap { log -> [(PhotoAsset, [String], String)] in
            let lines = log.report?.progress ?? []
            return log.sortedPhotos.enumerated().compactMap { i, p in
                guard p.driveFileID == nil else { return nil }
                let line = lines.first { $0.id.uuidString == p.tag }
                return (p, RoutineReport.photoFolder(date: log.date), RoutineReport.photoName(date: log.date, index: i + 1, line: line))
            }
        }
    }

    private static func pendingInspection(_ job: Job) -> Inspection? {
        guard let inspection = job.inspection, inspection.submittedAt != nil, inspection.driveFileID == nil else { return nil }
        return inspection
    }

    /// Records each file's Drive id as soon as it lands, so a failure part-way doesn't re-upload finished files.
    static func run(_ job: Job, session: GoogleSession, progress: (Int, Int) -> Void) async throws {
        let docs = job.documents.filter { $0.driveFileID == nil }.sorted { $0.addedAt < $1.addedAt }
        let inspection = pendingInspection(job)
        let photos = pendingPhotos(job)
        let total = docs.count + (inspection == nil ? 0 : 1) + photos.count
        guard total > 0 else { return }

        progress(0, total)
        let folder = try await session.survey.driveFolder(DriveFolders.name(for: job), root: DriveFolders.root)
        job.driveFolderURL = folder.url.absoluteString

        var done = 0
        var subfolders: [String: String] = [:]
        for doc in docs {
            var target = folder.id
            if let path = doc.folderPath, !path.isEmpty {
                if subfolders[path] == nil {
                    subfolders[path] = try await session.survey.driveSubfolder(path.components(separatedBy: "/"), under: folder.id)
                }
                target = subfolders[path] ?? folder.id
            }
            let file = DriveUpload(name: doc.name, data: doc.data, mimeType: mimeType(for: doc.name))
            doc.driveFileID = try await session.survey.driveUpload(file, to: target)
            done += 1
            progress(done, total)
        }
        for p in photos {
            let path = p.folder.joined(separator: "/")
            if subfolders[path] == nil { subfolders[path] = try await session.survey.driveSubfolder(p.folder, under: folder.id) }
            let file = DriveUpload(name: p.name, data: p.photo.data, mimeType: "image/jpeg")
            p.photo.driveFileID = try await session.survey.driveUpload(file, to: subfolders[path] ?? folder.id)
            done += 1
            progress(done, total)
        }
        if let inspection, let url = InspectionReport.renderPDF(inspection) {
            let data = try Data(contentsOf: url)
            let file = DriveUpload(name: url.lastPathComponent, data: data, mimeType: "application/pdf")
            inspection.driveFileID = try await session.survey.driveUpload(file, to: folder.id)
            progress(total, total)
        }
    }

    static func mimeType(for name: String) -> String {
        UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}
