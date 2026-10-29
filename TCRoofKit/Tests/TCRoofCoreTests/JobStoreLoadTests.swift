import Foundation
import XCTest
@testable import TCRoofCore

final class JobStoreLoadTests: XCTestCase {
    private func makeStore() -> JobStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("job-load-" + UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return JobStore(root: root)
    }

    func testEmptyStoreHasNoFailures() {
        let result = makeStore().loadAll()
        XCTAssertTrue(result.jobs.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testValidJobsAreSortedNewestFirst() throws {
        let store = makeStore()
        let older = Job(updated: Date(timeIntervalSince1970: 100))
        let newer = Job(updated: Date(timeIntervalSince1970: 200))
        try store.save(older)
        try store.save(newer)

        let result = store.loadAll()
        XCTAssertEqual(result.jobs, [newer, older])
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testCorruptAndMissingFilesAreReportedAlongsideValidJobs() throws {
        let store = makeStore()
        let valid = Job()
        try store.save(valid)
        let corruptURL = store.folder(UUID()).appendingPathComponent("job.json")
        try FileManager.default.createDirectory(at: corruptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corruptData = Data("not JSON".utf8)
        try corruptData.write(to: corruptURL)
        let missingURL = store.folder(UUID()).appendingPathComponent("job.json")
        try FileManager.default.createDirectory(at: missingURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let result = store.loadAll()
        XCTAssertEqual(result.jobs, [valid])
        XCTAssertEqual(result.failures.count, 2)
        let corrupt = try XCTUnwrap(result.failures.first { $0.url == corruptURL })
        XCTAssertEqual(corrupt.operation, .decode)
        XCTAssertTrue(corrupt.error is DecodingError)
        let corruptID = try XCTUnwrap(UUID(uuidString: corruptURL.deletingLastPathComponent().lastPathComponent))
        XCTAssertTrue(corrupt.affects(corruptID))
        XCTAssertFalse(corrupt.affects(valid.id))
        let missing = try XCTUnwrap(result.failures.first { $0.url == missingURL })
        XCTAssertEqual(missing.operation, .read)
        XCTAssertEqual(try Data(contentsOf: corruptURL), corruptData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: missingURL.deletingLastPathComponent().path))
    }

    func testInvalidJobSchemaIsReportedAndCanBeRetriedAfterRepair() throws {
        let store = makeStore()
        let job = Job()
        try store.save(job)
        let url = store.folder(job.id).appendingPathComponent("job.json")
        try Data("{}".utf8).write(to: url)

        let failed = store.loadAll()
        XCTAssertTrue(failed.jobs.isEmpty)
        XCTAssertEqual(failed.failures.count, 1)
        XCTAssertEqual(failed.failures.first?.operation, .decode)

        try store.save(job)
        let repaired = store.loadAll()
        XCTAssertEqual(repaired.jobs, [job])
        XCTAssertTrue(repaired.failures.isEmpty)
    }

    func testDirectoryListingFailureIsReported() throws {
        let store = makeStore()
        let directory = store.root.appendingPathComponent("Jobs")
        try FileManager.default.removeItem(at: directory)
        try Data("not a directory".utf8).write(to: directory)

        let result = store.loadAll()
        XCTAssertTrue(result.jobs.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.url, directory)
        XCTAssertEqual(result.failures.first?.operation, .list)
        XCTAssertTrue(try XCTUnwrap(result.failures.first).affects(UUID()))
    }

    func testRecoveryPreservesInvalidOriginalAndRestoresJob() throws {
        let store = makeStore()
        let job = Job()
        try store.save(job)
        let url = store.folder(job.id).appendingPathComponent("job.json")
        let original = Data("{broken survey".utf8)
        try original.write(to: url)

        try store.save(job, preservingInvalidFile: true)

        let files = try FileManager.default.contentsOfDirectory(at: store.folder(job.id), includingPropertiesForKeys: nil)
        let backups = files.filter { $0.lastPathComponent.hasPrefix("job-recovery-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
        XCTAssertEqual(store.load(job.id), job)
        let result = store.loadAll()
        XCTAssertEqual(result.jobs, [job])
        XCTAssertTrue(result.failures.isEmpty)

        // Receiving the same healthy record again must not create additional recovery copies.
        try store.save(job, preservingInvalidFile: true)
        let after = try FileManager.default.contentsOfDirectory(at: store.folder(job.id), includingPropertiesForKeys: nil)
        XCTAssertEqual(after.filter { $0.lastPathComponent.hasPrefix("job-recovery-") }, backups)
    }

    func testRecoveryPreservesValidJSONWithInvalidSchema() throws {
        let store = makeStore()
        let job = Job()
        try store.save(job)
        let original = Data("{}".utf8)
        try original.write(to: store.folder(job.id).appendingPathComponent("job.json"))

        try store.save(job, preservingInvalidFile: true)

        let files = try FileManager.default.contentsOfDirectory(at: store.folder(job.id), includingPropertiesForKeys: nil)
        let backup = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("job-recovery-") })
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(store.load(job.id), job)
    }

    func testRecoveryCreatesMissingLocalFile() throws {
        let store = makeStore()
        let job = Job()
        try store.save(job, preservingInvalidFile: true)
        XCTAssertEqual(store.load(job.id), job)
    }

    func testRecoveryReadFailureDoesNotReplaceOriginal() throws {
        let store = makeStore()
        let job = Job()
        let url = store.folder(job.id).appendingPathComponent("job.json")
        // A directory instead of a readable file reliably fails even when tests run as root.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let marker = url.appendingPathComponent("original")
        try Data("keep".utf8).write(to: marker)

        XCTAssertThrowsError(try store.save(job, preservingInvalidFile: true))
        XCTAssertEqual(try Data(contentsOf: marker), Data("keep".utf8))
        XCTAssertTrue(store.loadAll().jobs.isEmpty)
    }

    func testHiddenMetadataIsIgnored() throws {
        let store = makeStore()
        let metadata = store.root.appendingPathComponent("Jobs/.DS_Store")
        try Data([0]).write(to: metadata)

        let result = store.loadAll()
        XCTAssertTrue(result.jobs.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
    }
}
