import Foundation
import UniformTypeIdentifiers
import SurveyUI

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
        job.documents.filter { $0.driveFileID == nil }.count + (pendingInspection(job) == nil ? 0 : 1)
    }

    private static func pendingInspection(_ job: Job) -> Inspection? {
        guard let inspection = job.inspection, inspection.submittedAt != nil, inspection.driveFileID == nil else { return nil }
        return inspection
    }

    /// Records each file's Drive id as soon as it lands, so a failure part-way doesn't re-upload finished files.
    static func run(_ job: Job, session: GoogleSession, progress: (Int, Int) -> Void) async throws {
        let docs = job.documents.filter { $0.driveFileID == nil }.sorted { $0.addedAt < $1.addedAt }
        let inspection = pendingInspection(job)
        let total = docs.count + (inspection == nil ? 0 : 1)
        guard total > 0 else { return }

        progress(0, total)
        let folder = try await session.survey.driveFolder(DriveFolders.name(for: job), root: DriveFolders.root)
        job.driveFolderURL = folder.url.absoluteString

        var done = 0
        for doc in docs {
            let file = DriveUpload(name: doc.name, data: doc.data, mimeType: mimeType(for: doc.name))
            doc.driveFileID = try await session.survey.driveUpload(file, to: folder.id)
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
