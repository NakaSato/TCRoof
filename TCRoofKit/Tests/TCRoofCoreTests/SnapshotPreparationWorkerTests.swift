import XCTest
@testable import TCRoofCore

final class SnapshotPreparationWorkerTests: XCTestCase {
    private struct Source: Sendable {
        let id: String
        let removed: Bool
        let json: String
    }
    private struct Record: Codable, Equatable, Sendable { let name: String }
    private enum Prepared: Equatable, Sendable {
        case removed(String)
        case updated(String, Record)
    }

    func testBatchLoadingAdvancesPastMalformedRecordsAndKeepsSourceOrder() async throws {
        let worker = SnapshotPreparationWorker()
        let source = ["bad", "bad", "1", "2", "3"]
        let empty = try await worker.prepareBatch(source, startingAt: 0, limit: 2) { Int($0) }
        XCTAssertTrue(empty.values.isEmpty)
        XCTAssertEqual(empty.nextIndex, 2)
        let next = try await worker.prepareBatch(source, startingAt: empty.nextIndex, limit: 2) { Int($0) }
        XCTAssertEqual(next.values, [1, 2])
        let last = try await worker.prepareBatch(source, startingAt: next.nextIndex, limit: 2) { Int($0) }
        XCTAssertEqual(last.values, [3])
        XCTAssertEqual(last.nextIndex, source.count)
    }

    func testBatchDoesNotPrepareLaterProjectsUntilRequested() async throws {
        let worker = SnapshotPreparationWorker()
        let first = try await worker.prepareBatch([1, 2, 3], startingAt: 0, limit: 2) { value in
            XCTAssertLessThan(value, 3, "the first batch must be available before later projects are prepared")
            return value
        }
        XCTAssertEqual(first.values, [1, 2])
        let end = try await worker.prepareBatch([1, 2, 3], startingAt: 3, limit: 2) { $0 }
        XCTAssertTrue(end.values.isEmpty)
        XCTAssertEqual(end.nextIndex, 3)
    }

    func testDecodingPreservesUpdateDeleteOrderAndSkipsMalformedDocuments() async throws {
        let sources = [
            Source(id: "one", removed: false, json: "{\"name\":\"first\"}"),
            Source(id: "bad", removed: false, json: "invalid"),
            Source(id: "one", removed: true, json: ""),
            Source(id: "one", removed: false, json: "{\"name\":\"latest\"}")
        ]
        let result = try await SnapshotPreparationWorker().prepare(sources) { source -> Prepared? in
            if source.removed { return .removed(source.id) }
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(source.json.utf8)) else { return nil }
            return .updated(source.id, record)
        }
        XCTAssertEqual(result, [.updated("one", Record(name: "first")), .removed("one"), .updated("one", Record(name: "latest"))])
    }

    @MainActor
    func testPreparationLeavesTheUIActor() async throws {
        XCTAssertTrue(Thread.isMainThread)
        let ranOnMain = try await SnapshotPreparationWorker().prepare([1, 2, 3]) { _ in Thread.isMainThread }
        XCTAssertEqual(ranOnMain, [false, false, false])
    }

    @MainActor
    func testCancelledSessionDoesNotProduceAnApplicableBatch() async throws {
        let worker = SnapshotPreparationWorker()
        let task = Task { try await worker.prepare(Array(0..<1_000)) { $0 } }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a stopped sync session must not return a batch to apply")
        } catch is CancellationError {
            // Expected: callers discard the whole preparation rather than applying a partial result.
        }
    }
}
