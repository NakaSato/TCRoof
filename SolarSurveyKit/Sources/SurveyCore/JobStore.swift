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

    public func loadAll() -> [Job] {
        let dir = root.appendingPathComponent("Jobs")
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.compactMap { u -> Job? in
            guard let d = try? Data(contentsOf: u.appendingPathComponent("job.json")) else { return nil }
            return try? Self.decoder.decode(Job.self, from: d)
        }.sorted { $0.updated > $1.updated }
    }

    public func load(_ id: UUID) -> Job? {
        guard let d = try? Data(contentsOf: folder(id).appendingPathComponent("job.json")) else { return nil }
        return try? Self.decoder.decode(Job.self, from: d)
    }

    public func save(_ job: Job) throws {
        lock.lock(); defer { lock.unlock() }
        try fm.createDirectory(at: photosFolder(job.id), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(job)
        try data.write(to: folder(job.id).appendingPathComponent("job.json"), options: .atomic)
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

    /// Removes photo files no longer referenced by the job (after a photo is replaced or deleted).
    @discardableResult
    public func purgeUnusedPhotos(of job: Job) -> Int {
        let used = Set(job.allPhotos.map(\.fileName))
        let files = (try? fm.contentsOfDirectory(atPath: photosFolder(job.id).path)) ?? []
        var n = 0
        for f in files where !used.contains(f) {
            if (try? fm.removeItem(at: photosFolder(job.id).appendingPathComponent(f))) != nil { n += 1 }
        }
        return n
    }

    /// Copy of a job with new ids and its own photo files.
    public func duplicate(_ job: Job, now: Date = Date()) throws -> Job {
        var copy = job
        copy.id = UUID(); copy.created = now; copy.updated = now; copy.drive = nil
        // a copy of a survey already moved on is a new survey
        copy.stage = .survey; copy.install = nil
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
