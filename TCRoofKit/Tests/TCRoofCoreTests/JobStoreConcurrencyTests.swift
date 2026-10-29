import Foundation
import XCTest
@testable import TCRoofCore

final class JobStoreConcurrencyTests: XCTestCase {
    private func makeStore() -> JobStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("job-concurrency-" + UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return JobStore(root: root)
    }

    func testDelayedAutosaveCannotOverwriteNewerEdit() async throws {
        let store = makeStore()
        let writer = JobStoreWriter(store: store)
        let older = Job()
        let oldToken = store.reserveSave(older.id)
        var newer = older
        newer.values["projectName"] = .text("newer edit")
        let newToken = store.reserveSave(newer.id)

        let saved = try await writer.save(newer, token: newToken)
        let stale = try await writer.save(older, token: oldToken)
        XCTAssertTrue(saved)
        XCTAssertFalse(stale)
        XCTAssertEqual(store.load(newer.id), newer)
    }

    func testFlushInvalidatesAlreadyQueuedAutosave() async throws {
        let store = makeStore()
        let writer = JobStoreWriter(store: store)
        let older = Job()
        let token = store.reserveSave(older.id)
        var flushed = older
        flushed.values["projectName"] = .text("flushed edit")
        try store.save(flushed)

        let saved = try await writer.save(older, token: token)
        XCTAssertFalse(saved)
        XCTAssertEqual(store.load(flushed.id), flushed)
    }

    func testDeletionInvalidatesAlreadyQueuedAutosave() async throws {
        let store = makeStore()
        let writer = JobStoreWriter(store: store)
        let job = Job()
        try store.save(job)
        let token = store.reserveSave(job.id)
        try store.delete(job.id)

        let saved = try await writer.save(job, token: token)
        XCTAssertFalse(saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(job.id).path))
    }

    func testRecoveryInvalidatesAlreadyQueuedAutosave() async throws {
        let store = makeStore()
        let writer = JobStoreWriter(store: store)
        let local = Job()
        let token = store.reserveSave(local.id)
        var remote = local
        remote.values["projectName"] = .text("cloud recovery")
        try store.save(remote, preservingInvalidFile: true)

        let saved = try await writer.save(local, token: token)
        XCTAssertFalse(saved)
        XCTAssertEqual(store.load(remote.id), remote)
    }

    func testConcurrentStorageOperationsKeepJobsIndependent() async throws {
        let store = makeStore()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<40 {
                group.addTask {
                    let job = Job()
                    try store.save(job)
                    guard store.load(job.id) == job else { throw CocoaError(.fileReadCorruptFile) }
                    let photo = try store.addPhoto(Data([1, 2, 3]), width: 1, height: 1, to: job.id)
                    guard store.data(of: photo, in: job.id) == Data([1, 2, 3]) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    try store.delete(job.id)
                }
            }
            try await group.waitForAll()
        }
        let result = store.loadAll()
        XCTAssertTrue(result.jobs.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testBackgroundLoadFlushesReservedDraftsBeforeReading() async throws {
        let store = makeStore()
        let writer = JobStoreWriter(store: store)
        let job = Job()
        let token = store.reserveSave(job.id)
        let result = try await writer.load(saving: [(job, token)])
        XCTAssertEqual(result.jobs, [job])
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testBackgroundLoadCannotRestoreDraftDeletedWhileQueued() async throws {
        let store = makeStore()
        let writer = JobStoreWriter(store: store)
        let job = Job()
        let token = store.reserveSave(job.id)
        try store.delete(job.id)
        let result = try await writer.load(saving: [(job, token)])
        XCTAssertTrue(result.jobs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(job.id).path))
    }

    func testSessionInvalidationRejectsQueuedRecoveryWrite() async throws {
        let store = makeStore()
        let writer = JobStoreWriter(store: store)
        let job = Job()
        let token = store.reserveSave(job.id)
        store.invalidatePendingSaves()
        let saved = try await writer.save(job, token: token, preservingInvalidFile: true)
        XCTAssertFalse(saved)
        XCTAssertNil(store.load(job.id))
    }

    func testBackgroundRecoveryPreservesInvalidOriginal() async throws {
        let store = makeStore()
        let writer = JobStoreWriter(store: store)
        let job = Job()
        try store.save(job)
        let original = Data("broken JSON".utf8)
        try original.write(to: store.folder(job.id).appendingPathComponent("job.json"))
        let token = store.reserveSave(job.id)
        let saved = try await writer.save(job, token: token, preservingInvalidFile: true)
        XCTAssertTrue(saved)
        let result = try await writer.load()
        XCTAssertEqual(result.jobs, [job])
        let files = try FileManager.default.contentsOfDirectory(at: store.folder(job.id), includingPropertiesForKeys: nil)
        let backup = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("job-recovery-") })
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    func testBackgroundPhotoReadReturnsStoredBytes() async throws {
        let store = makeStore()
        let writer = JobStoreWriter(store: store)
        var job = Job()
        let bytes = Data([1, 2, 3])
        let photo = try store.addPhoto(bytes, width: 1, height: 1, to: job.id)
        job.values["photo"] = .photo(photo)
        let loaded = await writer.photoData(photo, job: job.id)
        let photos = await writer.photos(job)
        let present = await writer.existingPhotoIDs(job)
        XCTAssertEqual(loaded, bytes)
        XCTAssertEqual(photos[photo.id], bytes)
        XCTAssertTrue(present.contains(photo.id))
    }

    func testBackgroundOutputWriteFinishesBeforeReturning() async throws {
        let store = makeStore()
        let writer = JobStoreWriter(store: store)
        let url = store.root.appendingPathComponent("exports/report.pdf")
        let bytes = Data("report".utf8)
        try await writer.write(bytes, to: url)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}
