import Foundation
import SwiftData
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
        // the station's uploaded key plan, beside the daily reports
        let keyPlan = job.uploadedKeyPlan.flatMap { p -> (PhotoAsset, [String], String)? in
            p.driveFileID == nil && !p.data.isEmpty ? (p, ["Key Plan"], "Key Plan \(job.stationName).jpg") : nil
        }
        // each week's request signature, beside the request's PDF
        let signatures = job.requestSignatures.compactMap { r, p -> (PhotoAsset, [String], String)? in
            p.driveFileID == nil ? (p, RoutineReport.folder(.request, date: r.weekStart), "\(r.id) ลายเซ็น Site Engineer.png") : nil
        }
        return daily + (keyPlan.map { [$0] } ?? []) + signatures + pendingICLPhotos(job) + pendingIECPhotos(job)
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
        try await run(job, survey: session.survey, progress: progress)
    }

    /// Hands every pending file to the background transfer first, then records each one's Drive id as it lands: iOS
    /// goes on sending them when the person leaves the app, or after the system ends it (`DriveBackground`). The job is
    /// remembered until a run ends with nothing left, and `resumeRequested` runs it again when sync next starts; a
    /// file that landed while the app was closed is found on Drive then, not sent twice.
    static func run(_ job: Job, survey: SurveyModel, progress: (Int, Int) -> Void) async throws {
        // one Drive writer: a background photo upload finishes first, so no photo is sent twice
        await PhotoSync.shared.pause()
        defer { PhotoSync.shared.resume() }
        let docs = job.documents.filter { $0.driveFileID == nil }.sorted { $0.addedAt < $1.addedAt }
        let inspection = pendingInspection(job)
        let photos = pendingPhotos(job)
        let total = docs.count + (inspection == nil ? 0 : 1) + photos.count
        guard total > 0 else { forget(job); return }
        remember(job)
        // time to look up the folders and hand the files over if the person leaves the app now
        let time = BackgroundTime("Drive upload \(job.code)")
        defer { time.end() }

        progress(0, total)
        let route = DriveRoute(survey: survey)
        let folder = try await route.jobFolder(job)
        job.driveFolderURL = folder.url.absoluteString

        var subfolders: [String: String] = [:]
        func target(_ path: [String]) async throws -> String {
            guard !path.isEmpty else { return folder.id }
            let key = path.joined(separator: "/")
            if let id = subfolders[key] { return id }
            let id = try await survey.driveSubfolder(path, under: folder.id)
            subfolders[key] = id
            return id
        }

        // 1. every file handed over; a failure here (offline) still records what was handed over before it
        var waits: [(record: Landing, wait: Task<String, Error>)] = []
        var failure: Error?
        do {
            for doc in docs {
                // a paper in two hand-over folders goes into both; the record keeps the first copy's id
                for (i, place) in route.places(doc, in: job).enumerated() {
                    let file = DriveUpload(name: place.name, data: doc.data, mimeType: mimeType(for: doc.name))
                    waits.append((.document(doc, counts: i == 0), try await survey.driveStartUpload(file, to: try await target(place.folder))))
                }
            }
            for p in photos {
                let file = DriveUpload(name: p.name, data: p.photo.data, mimeType: "image/jpeg")
                waits.append((.photo(p.photo), try await survey.driveStartUpload(file, to: try await target(route.construction(p.folder)))))
            }
            if let inspection, let url = InspectionReport.renderPDF(inspection) {
                let data = try Data(contentsOf: url)
                let file = DriveUpload(name: url.lastPathComponent, data: data, mimeType: "application/pdf")
                waits.append((.inspection(inspection), try await survey.driveStartUpload(file, to: try await target(route.construction([])))))
            }
        } catch { failure = error }

        // 2. each one recorded as it lands
        var done = 0
        for w in waits {
            do {
                let id = try await w.wait.value
                switch w.record {
                case .document(let doc, let counts):
                    guard counts else { continue }
                    if !doc.isDeleted, doc.driveFileID == nil { doc.driveFileID = id }
                case .photo(let photo):
                    if !photo.isDeleted { photo.driveFileID = id }
                case .inspection(let inspection):
                    if !inspection.isDeleted { inspection.driveFileID = id }
                }
                done += 1
                progress(done, total)
            } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
        if pendingCount(job) == 0 { forget(job) }
    }

    /// What a landed upload records its id on.
    private enum Landing {
        /// `counts`: the paper's first place, whose id the record keeps.
        case document(DocumentAsset, counts: Bool)
        case photo(PhotoAsset)
        case inspection(Inspection)
    }

    // MARK: Resume

    /// Jobs whose upload was started and hasn't finished (`job.syncID ?? job.code`), kept on the device.
    static let resumeKey = "drive.resumeJobs"
    private static func key(_ job: Job) -> String { job.syncID ?? job.code }

    private static func remember(_ job: Job) {
        var keys = Set(UserDefaults.standard.stringArray(forKey: resumeKey) ?? [])
        if keys.insert(key(job)).inserted { UserDefaults.standard.set(keys.sorted(), forKey: resumeKey) }
    }

    private static func forget(_ job: Job) {
        var keys = Set(UserDefaults.standard.stringArray(forKey: resumeKey) ?? [])
        if keys.remove(key(job)) != nil { UserDefaults.standard.set(keys.sorted(), forKey: resumeKey) }
    }

    /// A job upload was started and hasn't finished.
    static var hasRequested: Bool { !(UserDefaults.standard.stringArray(forKey: resumeKey) ?? []).isEmpty }

    /// Runs again, quietly, the uploads that were started and didn't finish (left mid-way, offline, the app closed):
    /// when sync starts (`PhotoSync.start`), then a minute after each failure while the app is open. A job gone from
    /// the device is forgotten.
    static func resumeRequested(context: ModelContext, survey: SurveyModel) {
        guard hasRequested, survey.google.isSignedIn else { return }
        Task {
            let ok = await resumeNow(context: context, survey: survey)
            guard !ok else { return }
            try? await Task.sleep(for: .seconds(60))
            resumeRequested(context: context, survey: survey)
        }
    }

    /// One pass over the started uploads; false when one failed. Also iOS's background task's (`DriveBackgroundWork`).
    static func resumeNow(context: ModelContext, survey: SurveyModel) async -> Bool {
        let keys = Set(UserDefaults.standard.stringArray(forKey: resumeKey) ?? [])
        guard !keys.isEmpty, survey.google.isSignedIn else { return true }
        let jobs = ((try? context.fetch(FetchDescriptor<Job>())) ?? []).filter { keys.contains(key($0)) }
        let found = Set(jobs.map(key))
        if found != keys { UserDefaults.standard.set(found.sorted(), forKey: resumeKey) }
        var ok = true
        for job in jobs {
            do { try await run(job, survey: survey) { _, _ in } } catch {
                ok = false
                print("Drive: resume \(job.code): \(error.localizedDescription)")
            }
        }
        return ok
    }

    static func mimeType(for name: String) -> String {
        UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}
