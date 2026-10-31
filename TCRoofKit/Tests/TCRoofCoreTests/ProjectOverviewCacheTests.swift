import XCTest
@testable import TCRoofCore

final class ProjectOverviewCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func input(_ name: String = "Station") -> InstallSummaryInput {
        .init(base: .init(id: "one", name: name, actual: 12, permits: [.init(.pea, .pending)]), planJSON: nil, actualJSON: nil)
    }
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("cache.json")
    }

    func testReopeningRestoresPersistedSummariesWithPermits() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let inputs = [input()]
        try await ProjectOverviewCache(file: url).save(owner: "a/team", inputs: inputs, summaries: inputs.map(\.base), at: now)
        let restored = await ProjectOverviewCache(file: url).load(owner: "a/team", inputs: inputs, at: now)
        XCTAssertEqual(restored, inputs.map(\.base))
    }

    func testAccountRoleDayAndInputChangesMissTheCache() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = ProjectOverviewCache(file: url), inputs = [input()]
        try await cache.save(owner: "a/team", inputs: inputs, summaries: inputs.map(\.base), at: now)
        let otherAccount = await cache.load(owner: "b/team", inputs: inputs, at: now)
        let otherRole = await cache.load(owner: "a/external", inputs: inputs, at: now)
        let tomorrow = await cache.load(owner: "a/team", inputs: inputs, at: now.addingTimeInterval(86400))
        let edited = await cache.load(owner: "a/team", inputs: [input("Edited")], at: now)
        let removed = await cache.load(owner: "a/team", inputs: [], at: now)
        XCTAssertNil(otherAccount); XCTAssertNil(otherRole); XCTAssertNil(tomorrow)
        XCTAssertNil(edited); XCTAssertNil(removed)
    }

    func testPlanAndActualChangesInvalidateSavedProgress() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = ProjectOverviewCache(file: url), inputs = [input()]
        try await cache.save(owner: "a", inputs: inputs, summaries: inputs.map(\.base), at: now)
        var changed = inputs
        changed[0].planJSON = "new plan"
        let plan = await cache.load(owner: "a", inputs: changed, at: now)
        changed = inputs
        changed[0].actualJSON = "new progress"
        let actual = await cache.load(owner: "a", inputs: changed, at: now)
        XCTAssertNil(plan); XCTAssertNil(actual)
    }

    func testCorruptCacheIsIgnoredAndClearRemovesDiskAndMemory() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: url)
        let cache = ProjectOverviewCache(file: url), inputs = [input()]
        let corrupt = await cache.load(owner: "a", inputs: inputs, at: now)
        XCTAssertNil(corrupt)
        try await cache.save(owner: "a", inputs: inputs, summaries: inputs.map(\.base), at: now)
        await cache.clear()
        let cleared = await cache.load(owner: "a", inputs: inputs, at: now)
        XCTAssertNil(cleared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAnonymousRequestsCannotReadOrWriteAnAccountCache() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = ProjectOverviewCache(file: url), inputs = [input()]
        try await cache.save(owner: "", inputs: inputs, summaries: inputs.map(\.base), at: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let anonymous = await cache.load(owner: "", inputs: inputs, at: now)
        XCTAssertNil(anonymous)
    }

    func testDiskCacheDoesNotDuplicateFullPlanOrProgressData() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var value = input()
        value.planJSON = "PRIVATE_FULL_PLAN"
        value.actualJSON = "PRIVATE_FULL_PROGRESS"
        try await ProjectOverviewCache(file: url).save(owner: "a", inputs: [value], summaries: [value.base], at: now)
        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(saved.contains("PRIVATE_FULL_PLAN"))
        XCTAssertFalse(saved.contains("PRIVATE_FULL_PROGRESS"))
        XCTAssertTrue(saved.contains("inputDigest"))
    }

    func testClearingCachePreservesRealProjectAndPhotoFiles() async throws {
        let url = file(), root = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JobStore(root: root)
        let job = Job.new(template: JobTemplate.all[0])
        try store.save(job)
        let bytes = Data([1, 2, 3, 4])
        let photo = try store.addPhoto(bytes, width: 1, height: 1, to: job.id)
        let cache = ProjectOverviewCache(file: url), inputs = [input()]
        try await cache.save(owner: "a", inputs: inputs, summaries: inputs.map(\.base), at: now)
        await cache.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store.load(job.id), job)
        XCTAssertEqual(store.data(of: photo, in: job.id), bytes)
    }
}
