import Foundation
import TCRoofUI
import TCRoofCore

/// The center Drive, from `config/app` (set in the Firebase console, `CloudSync.listenConfig`), kept on the device:
/// the company account's folder shared (Editor) with each TC engineer, and the emails a contractor's job folder is
/// shared with so the team's devices can download its photos.
enum DriveConfig {
    private static let centerKey = "drive.centerFolder", shareKey = "drive.shareWith", claimKey = "drive.claimShareWith"

    static var centerFolderID: String? { UserDefaults.standard.string(forKey: centerKey) }
    static var shareWith: [String] { UserDefaults.standard.stringArray(forKey: shareKey) ?? [] }

    /// Who reads a submitted month's claim folder (the managers who approve claims): `config/app.claimShareWith`.
    static var claimShareWith: [String] { UserDefaults.standard.stringArray(forKey: claimKey) ?? [] }

    static func set(center: String?, shareWith: [String], claimShareWith: [String] = []) {
        UserDefaults.standard.set(center.flatMap(folderID(from:)), forKey: centerKey)
        UserDefaults.standard.set(shareWith.map(Permissions.normalized).filter { $0.contains("@") }, forKey: shareKey)
        UserDefaults.standard.set(claimShareWith.map(Permissions.normalized).filter { $0.contains("@") }, forKey: claimKey)
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
        // the job's contractors and supervisor read its photos too (the team reads the center folder already)
        let assigned = job.externals + (job.supervisorEmail.map { [$0] } ?? [])
        if let center {
            let folder = try await survey.driveFolder(name, in: center)
            await survey.shareJobFolder(folder.id, with: assigned)
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
        // on someone's own Drive (a contractor, or a TC engineer without the center folder): everyone on the job reads it
        await survey.shareJobFolder(folder.id, with: DriveReaders.team() + assigned)
        return folder
    }

    /// A construction record's folder below the job's folder.
    func construction(_ path: [String]) -> [String] {
        center == nil ? path : [HandoverFolders.construction] + path
    }

    /// A document's folders below the job's folder and its name in each: on the center Drive a station paper takes
    /// every hand-over folder that lists it, with its numbered name; anything else is a construction record in its
    /// own folder.
    func places(_ doc: DocumentAsset, in job: Job) -> [(folder: [String], name: String)] {
        let station = job.stationDocs
        if center != nil, let kind = station.docs.first(where: { $0.value.fileName == doc.name })?.key {
            let all = HandoverFolders.places(kind, station: job.projectName, branch: station.branch, region: station.region,
                                             ext: (doc.name as NSString).pathExtension)
            if !all.isEmpty { return all }
        }
        let path = (doc.folderPath ?? "").split(separator: "/").map(String.init)
        return [(construction(path), doc.name)]
    }
}

/// Who should read a job's photos on Drive (the user, 2026-10-19: every photo in a report reaches everyone who can open
/// the job): the team (the directory a team device reads, else `config/app.driveShareWith`) and the job's contractors
/// and supervisor.
@MainActor
enum DriveReaders {
    static func team() -> [String] {
        let directory = TeamDirectory.shared.people.map(\.email)
        return directory.isEmpty ? DriveConfig.shareWith : directory + DriveConfig.shareWith
    }
    /// A survey's readers: the team, and its linked job's contractors and supervisor.
    static func survey(_ access: JobAccess?) -> [String] {
        team() + (access?.externals ?? []) + (access?.supervisor.map { [$0] } ?? [])
    }
}
