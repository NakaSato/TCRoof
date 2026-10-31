import XCTest
@testable import TCRoofCore

final class RecordFingerprintCacheTests: XCTestCase {
    private struct Record: Equatable {
        var text: String
        var readers: [String]
    }

    func testUnchangedRecordDoesNotRecomputeFingerprint() {
        let cache = RecordFingerprintCache<Record>()
        let record = Record(text: "survey", readers: [])
        var computations = 0
        func compute(_ record: Record) -> String {
            computations += 1
            return record.text
        }
        XCTAssertEqual(cache.fingerprint(id: "a", record: record, compute: compute), "survey")
        XCTAssertEqual(cache.fingerprint(id: "a", record: record, compute: compute), "survey")
        XCTAssertEqual(computations, 1)
    }

    func testContentAndAccessChangesInvalidateFingerprint() {
        let cache = RecordFingerprintCache<Record>()
        var record = Record(text: "old", readers: [])
        var computations = 0
        func compute(_ record: Record) -> String {
            computations += 1
            return record.text + record.readers.joined()
        }
        _ = cache.fingerprint(id: "a", record: record, compute: compute)
        record.text = "new"
        XCTAssertEqual(cache.fingerprint(id: "a", record: record, compute: compute), "new")
        record.readers = ["reader"]
        XCTAssertEqual(cache.fingerprint(id: "a", record: record, compute: compute), "newreader")
        XCTAssertEqual(computations, 3)
    }

    func testPruningReleasesRemovedRecordsAndKeepsOthersCached() {
        let cache = RecordFingerprintCache<String>()
        var computations = 0
        func compute(_ value: String) -> String { computations += 1; return value }
        _ = cache.fingerprint(id: "a", record: "same", compute: compute)
        _ = cache.fingerprint(id: "b", record: "same", compute: compute)
        cache.retainIDs(["b"])
        _ = cache.fingerprint(id: "b", record: "same", compute: compute)
        XCTAssertEqual(computations, 2)
        _ = cache.fingerprint(id: "a", record: "same", compute: compute)
        XCTAssertEqual(computations, 3)
    }
}
