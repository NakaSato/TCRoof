import XCTest
@testable import TCRoofCore

final class JobStoreBackgroundSaveTests: XCTestCase {
    func testDelayedRemoteSaveCannotReplaceNewerLocalSave() throws {
        try withStore { store in
            let remote = Job.new(template: JobTemplate.all[0])
            let version = store.reserveSave(remote.id)
            var local = remote
            local.values["projectName"] = .text("Local edit")
            try store.save(local)
            _ = try store.saveIfCurrent(remote, token: version)
            XCTAssertEqual(store.load(local.id), local)
        }
    }

    func testDelayedRemoteSaveCannotRecreateDeletedProject() throws {
        try withStore { store in
            let job = Job.new(template: JobTemplate.all[0])
            try store.save(job)
            let version = store.reserveSave(job.id)
            try store.delete(job.id)
            _ = try store.saveIfCurrent(job, token: version)
            XCTAssertNil(store.load(job.id))
        }
    }

    func testOnlyLatestReservedSnapshotIsSaved() throws {
        try withStore { store in
            let first = Job.new(template: JobTemplate.all[0])
            let oldVersion = store.reserveSave(first.id)
            var latest = first
            latest.values["projectName"] = .text("Latest remote")
            let version = store.reserveSave(first.id)
            _ = try store.saveIfCurrent(latest, token: version)
            _ = try store.saveIfCurrent(first, token: oldVersion)
            XCTAssertEqual(store.load(first.id), latest)
        }
    }

    func testLocalEditInvalidatesQueuedRemoteWriteBeforeLocalSave() throws {
        try withStore { store in
            let job = Job.new(template: JobTemplate.all[0])
            let version = store.reserveSave(job.id)
            _ = store.reserveSave(job.id)
            _ = try store.saveIfCurrent(job, token: version)
            XCTAssertNil(store.load(job.id))
        }
    }

    private func withStore(_ body: (JobStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(JobStore(root: root))
    }
}
