import Foundation

/// Jobs on disk: <root>/Jobs/<uuid>/job.json and <root>/Jobs/<uuid>/photos/<photo-id>.jpg|png
public final class JobStore: @unchecked Sendable {
    public let root: URL
    private let fm = FileManager.default
    private let lock = NSLock()

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("Jobs"), withIntermediateDirectories: true)
    }

    /// Documents/SolarSurvey inside the app container.
    public static func documents() -> JobStore {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return JobStore(root: docs.appendingPathComponent("SolarSurvey", isDirectory: true))
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
    public static let decoder: JSONDecoder = {
        JSONDecoder()
    }()

    public func folder(_ id: UUID) -> URL { root.appendingPathComponent("Jobs").appendingPathComponent(id.uuidString) }
    public func photosFolder(_ id: UUID) -> URL { folder(id).appendingPathComponent("photos") }
    public func url(of photo: Photo, in job: UUID) -> URL { photosFolder(job).appendingPathComponent(photo.fileName) }

    /// A failed load leaves the original file in place so it can be recovered or retried.
    public struct LoadFailure {
        public enum Operation: Equatable { case list, read, decode }

        public let url: URL
        public let operation: Operation
        public let error: Error

        /// A listing failure may hide any job; a file failure identifies its job by the folder's UUID.
        public func affects(_ jobID: UUID) -> Bool {
            operation == .list || UUID(uuidString: url.deletingLastPathComponent().lastPathComponent) == jobID
        }
    }

    public struct LoadResult {
        public let jobs: [Job]
        public let failures: [LoadFailure]
    }

    /// Returns readable jobs and reports every failure, including failure to list the Jobs directory.
    public func loadAll() -> LoadResult {
        let dir = root.appendingPathComponent("Jobs")
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        } catch {
            return LoadResult(jobs: [], failures: [LoadFailure(url: dir, operation: .list, error: error)])
        }
        var jobs: [Job] = []
        var failures: [LoadFailure] = []
        for item in items.sorted(by: { $0.path < $1.path }) {
            let url = item.appendingPathComponent("job.json")
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                failures.append(LoadFailure(url: url, operation: .read, error: error))
                continue
            }
            do {
                jobs.append(try Self.decoder.decode(Job.self, from: data))
            } catch {
                failures.append(LoadFailure(url: url, operation: .decode, error: error))
            }
        }
        return LoadResult(jobs: jobs.sorted { $0.updated > $1.updated }, failures: failures)
    }

    public func load(_ id: UUID) -> Job? {
        guard let d = try? Data(contentsOf: folder(id).appendingPathComponent("job.json")) else { return nil }
        return try? Self.decoder.decode(Job.self, from: d)
    }

    /// Recovery keeps an invalid original beside job.json before replacing it. An unreadable original is never replaced.
    public func save(_ job: Job, preservingInvalidFile: Bool = false) throws {
        lock.lock(); defer { lock.unlock() }
        try fm.createDirectory(at: photosFolder(job.id), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(job)
        let url = folder(job.id).appendingPathComponent("job.json")
        if preservingInvalidFile {
            let previous: Data?
            do {
                previous = try Data(contentsOf: url)
            } catch {
                let e = error as NSError
                guard e.domain == NSCocoaErrorDomain, e.code == NSFileReadNoSuchFileError else { throw error }
                previous = nil
            }
            if let previous, (try? Self.decoder.decode(Job.self, from: previous)) == nil {
                let backup = folder(job.id).appendingPathComponent("job-recovery-\(UUID().uuidString).json")
                try previous.write(to: backup, options: .withoutOverwriting)
            }
        }
        try data.write(to: url, options: .atomic)
    }

    public func delete(_ id: UUID) throws {
        let f = folder(id)
        if fm.fileExists(atPath: f.path) { try fm.removeItem(at: f) }
    }

    /// Stores encoded image bytes (JPEG or PNG) and returns the reference to put in a field.
    public func addPhoto(_ data: Data, width: Int, height: Int, png: Bool = false, takenAt: Date = Date(), to job: UUID) throws -> Photo {
        try fm.createDirectory(at: photosFolder(job), withIntermediateDirectories: true)
        let id = UUID()
        let p = Photo(id: id, fileName: id.uuidString + (png ? ".png" : ".jpg"), width: width, height: height, takenAt: takenAt)
        try data.write(to: url(of: p, in: job), options: .atomic)
        return p
    }

    public func data(of photo: Photo, in job: UUID) -> Data? { try? Data(contentsOf: url(of: photo, in: job)) }

    /// False for a photo taken on another device whose file hasn't been downloaded here.
    public func hasPhoto(_ photo: Photo, in job: UUID) -> Bool { fm.fileExists(atPath: url(of: photo, in: job).path) }

    /// Stores the bytes of a photo taken on another device under the reference the job already holds.
    public func writePhoto(_ data: Data, for photo: Photo, in job: UUID) throws {
        try fm.createDirectory(at: photosFolder(job), withIntermediateDirectories: true)
        try data.write(to: url(of: photo, in: job), options: .atomic)
    }

    // MARK: issued REVs

    public enum RevisionError: Error { case exists }
    public func revisionsFolder(_ job: UUID) -> URL { folder(job).appendingPathComponent("revisions") }
    /// "revisions/REV00.pdf", relative to the job folder, as stored in `Revision.pdfFile`.
    public static func revisionPDFPath(rev: String) -> String { "revisions/REV\(rev).pdf" }
    public func revisionPDF(rev: String, job: UUID) -> URL { folder(job).appendingPathComponent(Self.revisionPDFPath(rev: rev)) }
    /// A file in the job's `revisions/` folder by its name ("REV00.pdf", "REV00.json").
    public func revisionFile(_ name: String, job: UUID) -> URL { revisionsFolder(job).appendingPathComponent(name) }
    public func revisionJSON(rev: String, job: UUID) -> URL { revisionsFolder(job).appendingPathComponent("REV\(rev).json") }

    /// Writes an issued REV's answers once; an issued REV is never rewritten.
    public func saveRevision(_ snapshot: FormSnapshot, rev: String, job: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let u = revisionJSON(rev: rev, job: job)
        guard !fm.fileExists(atPath: u.path) else { throw RevisionError.exists }
        try fm.createDirectory(at: revisionsFolder(job), withIntermediateDirectories: true)
        try Self.encoder.encode(snapshot).write(to: u, options: .withoutOverwriting)
    }

    /// A snapshot received from another device, stored as it came. It must decode, and an issued REV here is never replaced.
    public func saveRevisionData(_ data: Data, rev: String, job: UUID) throws {
        _ = try Self.decoder.decode(FormSnapshot.self, from: data)
        lock.lock(); defer { lock.unlock() }
        let u = revisionJSON(rev: rev, job: job)
        guard !fm.fileExists(atPath: u.path) else { throw RevisionError.exists }
        try fm.createDirectory(at: revisionsFolder(job), withIntermediateDirectories: true)
        try data.write(to: u, options: .withoutOverwriting)
    }

    /// The stored bytes of an issued REV, to send to other devices.
    public func revisionData(rev: String, job: UUID) -> Data? { try? Data(contentsOf: revisionJSON(rev: rev, job: job)) }

    public func loadRevision(rev: String, job: UUID) -> FormSnapshot? {
        guard let d = try? Data(contentsOf: revisionJSON(rev: rev, job: job)) else { return nil }
        return try? Self.decoder.decode(FormSnapshot.self, from: d)
    }

    /// Every snapshot stored for the job, whatever `job.revisions` says, so their photos are never purged.
    public func snapshots(of job: UUID) -> [FormSnapshot] {
        let files = (try? fm.contentsOfDirectory(at: revisionsFolder(job), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? Self.decoder.decode(FormSnapshot.self, from: Data(contentsOf: $0)) }
    }

    /// Removes photo files no longer referenced by the job or by any issued REV (after a photo is replaced or deleted).
    @discardableResult
    public func purgeUnusedPhotos(of job: Job) -> Int {
        let used = Set(job.allPhotos.map(\.fileName)).union(snapshots(of: job.id).flatMap(\.allPhotos).map(\.fileName))
        let files = (try? fm.contentsOfDirectory(atPath: photosFolder(job.id).path)) ?? []
        var n = 0
        for f in files where !used.contains(f) {
            if (try? fm.removeItem(at: photosFolder(job.id).appendingPathComponent(f))) != nil { n += 1 }
        }
        return n
    }

    /// Copy of a job with new ids and its own photo files. It starts at REV 00, unsigned, with no issued REVs.
    public func duplicate(_ job: Job, now: Date = Date()) throws -> Job {
        var copy = job
        copy.id = UUID(); copy.created = now; copy.updated = now; copy.drive = nil
        // a copy of a survey already moved on is a new survey
        copy.stage = .survey; copy.install = nil
        copy.revisions = nil
        copy.values["rev"] = .text("00")
        for id in RevisionRule.signatureIDs { copy.values[id] = nil }
        copy.values["projectName"] = .text(job.projectName.isEmpty ? "(สำเนา)" : job.projectName + " (สำเนา)")
        copy.modules = job.modules.map { var m = $0; m.id = UUID(); return m }
        try fm.createDirectory(at: photosFolder(copy.id), withIntermediateDirectories: true)
        for p in job.allPhotos {
            let dst = url(of: p, in: copy.id)
            if !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: url(of: p, in: job.id), to: dst) }
        }
        try save(copy)
        return copy
    }
}
