import Foundation

/// Runs autosave encoding and disk writes away from the main actor. Only value snapshots cross this boundary.
/// Tokens keep delayed writes from overtaking a newer edit, a synchronous flush or a deletion.
public actor JobStoreWriter {
    private let store: JobStore

    public func photoData(_ photo: Photo, job: UUID) -> Data? {
        store.data(of: photo, in: job)
    }

    public func existingPhotoIDs(_ job: Job) -> Set<UUID> {
        Set(job.allPhotos.filter { store.hasPhoto($0, in: job.id) }.map(\.id))
    }

    public func photos(_ job: Job) -> [UUID: Data] {
        Dictionary(job.allPhotos.compactMap { photo in
            store.data(of: photo, in: job.id).map { (photo.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    public func revisionSnapshots(_ job: Job) -> [String: FormSnapshot] {
        Dictionary((job.revisions ?? []).compactMap { revision in
            store.loadRevision(rev: revision.rev, job: job.id).map { (revision.rev, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    public func revisionDocuments(_ job: Job) -> [String: String] {
        Dictionary((job.revisions ?? []).compactMap { revision in
            store.revisionData(rev: revision.rev, job: job.id).flatMap { String(data: $0, encoding: .utf8) }.map { (revision.rev, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    public func receiveRevision(_ data: Data, rev: String, job: UUID) -> Bool {
        guard !Task.isCancelled else { return false }
        do { try store.saveRevisionData(data, rev: rev, job: job); return true }
        catch JobStore.RevisionError.exists { return true }
        catch { return false }
    }

    public func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func backup(_ jobs: [Job]) throws -> Data { try WebBackup.exportBackup(jobs, store: store) }
    public func driveData(_ job: Job) throws -> Data { try WebBackup.exportDriveData(job, store: store) }

    public enum IssueError: Error { case photosMissing, alreadyIssued }
    public func issueSnapshot(_ job: Job) throws -> String {
        guard let hash = FormHash.of(job.snapshot, photoData: { store.data(of: $0, in: job.id) }) else { throw IssueError.photosMissing }
        do { try store.saveRevision(job.snapshot, rev: job.rev, job: job.id) }
        catch JobStore.RevisionError.exists {
            guard store.loadRevision(rev: job.rev, job: job.id) == job.snapshot else { throw IssueError.alreadyIssued }
        }
        return hash
    }

    public init(store: JobStore) {
        self.store = store
    }

    @discardableResult
    public func save(_ job: Job, token: UUID, preservingInvalidFile: Bool = false) throws -> Bool {
        guard !Task.isCancelled else { return false }
        return try store.saveIfCurrent(job, token: token, preservingInvalidFile: preservingInvalidFile)
    }

    /// Flush reserved drafts before reading, without blocking the model's actor.
    public func load(saving drafts: [(job: Job, token: UUID)] = []) throws -> JobStore.LoadResult {
        try Task.checkCancellation()
        for draft in drafts {
            try Task.checkCancellation()
            try store.saveIfCurrent(draft.job, token: draft.token)
        }
        try Task.checkCancellation()
        return store.loadAll()
    }
}
