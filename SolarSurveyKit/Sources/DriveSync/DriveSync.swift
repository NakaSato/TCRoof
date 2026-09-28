import Foundation
import SurveyCore

/// Project folders on Drive: <root>/<NO.215 project name>/ with timestamped PDF, Excel and survey-data JSON,
/// plus รูปภาพ/<section>/ holding each photo once.
/// Same layout and file format as the web app, so either can open the other's saves.
public struct DriveSync: Sendable {
    public let client: DriveClient
    public var rootName: String
    public init(client: DriveClient, rootName: String = "Solar Survey Projects") { self.client = client; self.rootName = rootName }

    public enum Kind: String, CaseIterable, Sendable { case pdf, xlsx, json
        public var label: String { ["pdf": "รายงาน PDF", "xlsx": "ไฟล์ Excel (ข้อมูล + รูป)", "json": "ข้อมูลงาน — สำหรับเปิดต่อบน iPad เครื่องอื่น"][rawValue]! }
        var mime: String { ["pdf": "application/pdf", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "json": "application/json"][rawValue]! }
    }
    public enum Step: Sendable { case folder(String), building(Kind), uploading(Kind, Int), uploaded(Kind, DriveFile), photos(done: Int, total: Int) }
    public static let photosFolderName = "รูปภาพ"

    /// A save that stopped part-way; `link` still records what was uploaded so the next save continues from there.
    public struct Interrupted: Error, LocalizedError {
        public let link: DriveLink
        public let underlying: any Error
        public var errorDescription: String? { underlying.localizedDescription }
    }

    public static func folderName(_ job: Job) -> String {
        let s = [job.docNo.isEmpty ? "" : "NO." + job.docNo, job.projectName].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "งานสำรวจ " + job.values.text("date") : s
    }
    static func stamp(_ d: Date = Date()) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d-%02d-%02d_%02d%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }

    /// Finds or creates the root and job folders, reusing the ids saved on the job while they still exist.
    public func ensureJobFolder(_ job: Job) async throws -> DriveLink {
        var link = job.drive ?? DriveLink()
        let root: String
        if let r = link.rootID, await client.exists(r) { root = r }
        else { root = try await client.ensureFolder(rootName, parent: "root").id }
        if let f = link.folderID, link.rootID == root, await client.exists(f) { return link }
        let name = Self.folderName(job)
        let folder = try await client.ensureFolder(name, parent: root)
        link.rootID = root; link.folderID = folder.id; link.folderName = name
        link.folderURL = folder.webViewLink ?? "https://drive.google.com/drive/folders/\(folder.id)"
        return link
    }

    /// Saves the chosen files. `build` produces the bytes for each kind (PDF / Excel / JSON) on demand.
    /// `photos` go to รูปภาพ/<section>/ — only those not uploaded by an earlier save.
    public func save(_ job: Job, kinds: [Kind], build: @Sendable (Kind) async throws -> Data,
                     photos: [PhotoFolder] = [], photoData: @Sendable (Photo) -> Data? = { _ in nil },
                     progress: @Sendable (Step) -> Void = { _ in }) async throws -> (DriveLink, [DriveFile]) {
        var link = try await ensureJobFolder(job)
        progress(.folder(link.folderName ?? ""))
        let t = Self.stamp(), prefix = job.docNo.isEmpty ? "" : "NO.\(job.docNo) "
        var saved: [DriveFile] = []
        for k in kinds {
            progress(.building(k))
            let data = try await build(k)
            progress(.uploading(k, data.count))
            let name = k == .json ? "survey-data \(prefix)\(t).json" : "\(prefix)แบบสำรวจ \(t).\(k.rawValue)"
            let f = try await client.upload(data, name: name, mimeType: k.mime, parent: link.folderID!)
            saved.append(f); progress(.uploaded(k, f))
        }
        if !photos.isEmpty {
            do { try await uploadPhotos(photos, link: &link, photoData: photoData, progress: progress) }
            catch { throw Interrupted(link: link, underlying: error) }
        }
        link.lastSaved = Date()
        return (link, saved)
    }

    /// Uploads photos Drive doesn't have yet, one sub-folder per section, recording each on `link` as it lands.
    func uploadPhotos(_ folders: [PhotoFolder], link: inout DriveLink, photoData: @Sendable (Photo) -> Data?,
                      progress: @Sendable (Step) -> Void) async throws {
        var uploaded = link.photoFiles ?? [:]
        let root: String
        if let id = link.photosFolderID, await client.exists(id) { root = id }
        else {
            // folder gone (or first save): start over so deleted photos are sent again
            root = try await client.ensureFolder(Self.photosFolderName, parent: link.folderID!).id
            uploaded = [:]
        }
        link.photosFolderID = root
        link.photoFiles = uploaded
        let pending = folders.map { f in (f.name, f.photos.filter { uploaded[$0.photo.id.uuidString] == nil }) }.filter { !$0.1.isEmpty }
        let total = pending.reduce(0) { $0 + $1.1.count }
        var done = 0
        progress(.photos(done: 0, total: total))
        for (name, photos) in pending {
            let folder = try await client.ensureFolder(name, parent: root).id
            for p in photos {
                if let data = photoData(p.photo) {
                    let f = try await client.upload(data, name: p.fileName, mimeType: p.photo.isPNG ? "image/png" : "image/jpeg", parent: folder)
                    link.photoFiles?[p.photo.id.uuidString] = f.id
                }
                done += 1
                progress(.photos(done: done, total: total))
            }
        }
    }

    /// Every survey-data file this account can see, newest first.
    public func listSaves() async throws -> [DriveFile] {
        try await client.search("name contains 'survey-data' and mimeType = 'application/json' and trashed = false", orderBy: "modifiedTime desc", pageSize: 50)
    }

    /// Downloads a survey-data file and imports it (photos included) into the local store.
    public func open(_ file: DriveFile, into store: JobStore) async throws -> Job {
        let data = try await client.download(file.id)
        guard var job = try WebBackup.importJobs(data, into: store).first else { throw WebBackup.Failure.notSurveyFile }
        if job.drive == nil { job.drive = DriveLink() }
        try store.save(job)
        return job
    }
}
