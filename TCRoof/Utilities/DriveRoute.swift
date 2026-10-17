import Foundation
import TCRoofUI
import TCRoofCore

/// The center Drive, from `config/app` (set in the Firebase console, `CloudSync.listenConfig`), kept on the device:
/// the company account's folder shared (Editor) with each TC engineer, and the emails a contractor's job folder is
/// shared with so the team's devices can download its photos.
enum DriveConfig {
    private static let centerKey = "drive.centerFolder", shareKey = "drive.shareWith"

    static var centerFolderID: String? { UserDefaults.standard.string(forKey: centerKey) }
    static var shareWith: [String] { UserDefaults.standard.stringArray(forKey: shareKey) ?? [] }

    static func set(center: String?, shareWith: [String]) {
        UserDefaults.standard.set(center.flatMap(folderID(from:)), forKey: centerKey)
        UserDefaults.standard.set(shareWith.map(Permissions.normalized).filter { $0.contains("@") }, forKey: shareKey)
    }

    /// A folder id, or the id in a `drive.google.com/drive/folders/<id>` link.
    static func folderID(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let r = t.range(of: "/folders/") {
            let id = t[r.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            return id.isEmpty ? nil : String(id)
        }
        return t.contains("/") ? nil : t
    }
}

/// Where a job's files go on Drive, by role (user, 2026-10-17):
/// - a TC engineer (manager or internal team): the center folder, `<job>/1. เอกสารส่งมอบ/` laid out as the PWA hand-over
///   (`HandoverFolders`) and `<job>/2. เอกสารระหว่างก่อสร้าง/` for the construction records;
/// - an external contractor: their own Drive's `TCRoof Projects/<job>/`, as before, shared read only with the team.
/// A TC engineer with no center folder set yet, or signed in before full Drive was asked, still uploads to their own.
@MainActor
struct DriveRoute {
    let center: String?
    let survey: SurveyModel

    init(survey: SurveyModel) {
        self.survey = survey
        let me = MemberRole.shared.permissions
        center = me.role != .external && survey.google.hasFullDrive ? DriveConfig.centerFolderID : nil
    }

    /// The job's folder, made when missing: on the center Drive with every hand-over folder, on a contractor's
    /// Drive shared with the team.
    func jobFolder(_ job: Job) async throws -> (id: String, url: URL) {
        let name = DriveFolders.name(for: job)
        if let center {
            let folder = try await survey.driveFolder(name, in: center)
            let key = "drive.laidOut.\(folder.id)"
            if !UserDefaults.standard.bool(forKey: key) {
                for path in HandoverFolders.folders(over200kVA: job.stationContext.over200kVA) {
                    _ = try await survey.driveSubfolder(path, under: folder.id)
                }
                UserDefaults.standard.set(true, forKey: key)
            }
            return folder
        }
        let folder = try await survey.driveFolder(name, root: DriveFolders.root)
        if MemberRole.shared.permissions.role == .external, !DriveConfig.shareWith.isEmpty {
            let key = "drive.shared.\(folder.id)"
            if !UserDefaults.standard.bool(forKey: key) {
                // a refused share (an address Google doesn't know) mustn't stop the upload; tried again next time
                if (try? await survey.driveShare(folder.id, with: DriveConfig.shareWith)) != nil { UserDefaults.standard.set(true, forKey: key) }
            }
        }
        return folder
    }

    /// A construction record's folder below the job's folder.
    func construction(_ path: [String]) -> [String] {
        center == nil ? path : [HandoverFolders.construction] + path
    }

    /// A document's folder below the job's folder and its name on Drive: on the center Drive a station paper takes
    /// its hand-over folder and numbered name; anything else is a construction record in its own folder.
    func place(_ doc: DocumentAsset, in job: Job) -> (folder: [String], name: String) {
        if center != nil, let kind = job.stationDocs.docs.first(where: { $0.value.fileName == doc.name })?.key,
           let p = HandoverFolders.place(kind, station: job.projectName, ext: (doc.name as NSString).pathExtension) {
            return p
        }
        let path = (doc.folderPath ?? "").split(separator: "/").map(String.init)
        return (construction(path), doc.name)
    }
}
