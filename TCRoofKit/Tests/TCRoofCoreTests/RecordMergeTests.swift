import XCTest
@testable import TCRoofCore

final class RecordMergeTests: XCTestCase {
    private struct Record: Codable, Equatable {
        var name: String
        var count: Int
        var note: String?
        var tags: [String]
        var ratio: Double
        var done: Bool
    }

    private let base = Record(name: "สถานี A", count: 1, note: "เดิม", tags: ["a"], ratio: 0.1, done: false)

    func testFieldsChangedOnOneSideEachAreBothKept() throws {
        var local = base; local.name = "สถานี A (แก้)"
        var remote = base; remote.count = 2
        let result = try XCTUnwrap(RecordMerge.merge(base: base, local: local, remote: remote))
        XCTAssertEqual(result.merged, Record(name: "สถานี A (แก้)", count: 2, note: "เดิม", tags: ["a"], ratio: 0.1, done: false))
        XCTAssertEqual(result.conflicts, [])
    }

    func testAFieldBothSidesChangedKeepsTheLocalValueAndIsNamed() throws {
        var local = base; local.name = "ของเครื่องนี้"; local.done = true
        var remote = base; remote.name = "ของอีกเครื่อง"; remote.tags = ["a", "b"]
        let result = try XCTUnwrap(RecordMerge.merge(base: base, local: local, remote: remote))
        XCTAssertEqual(result.merged.name, "ของเครื่องนี้")
        XCTAssertEqual(result.merged.done, true)
        XCTAssertEqual(result.merged.tags, ["a", "b"])
        XCTAssertEqual(result.conflicts, ["name"])
    }

    func testTheSameChangeOnBothSidesIsNoConflict() throws {
        var local = base; local.count = 5
        var remote = base; remote.count = 5
        let result = try XCTUnwrap(RecordMerge.merge(base: base, local: local, remote: remote))
        XCTAssertEqual(result.merged.count, 5)
        XCTAssertEqual(result.conflicts, [])
    }

    func testAnOptionalFieldTheServerClearedIsCleared() throws {
        var local = base; local.count = 9
        var remote = base; remote.note = nil
        let result = try XCTUnwrap(RecordMerge.merge(base: base, local: local, remote: remote))
        XCTAssertNil(result.merged.note)
        XCTAssertEqual(result.merged.count, 9)
    }

    func testAnOptionalFieldOnlyThisDeviceSetIsKept() throws {
        var start = base; start.note = nil
        var local = start; local.note = "ใหม่"
        var remote = start; remote.ratio = 0.25
        let result = try XCTUnwrap(RecordMerge.merge(base: start, local: local, remote: remote))
        XCTAssertEqual(result.merged.note, "ใหม่")
        XCTAssertEqual(result.merged.ratio, 0.25)
    }

    func testNoServerChangeGivesTheLocalRecord() throws {
        var local = base; local.tags = []; local.ratio = 0.1 + 0.2
        let result = try XCTUnwrap(RecordMerge.merge(base: base, local: local, remote: base))
        XCTAssertEqual(result.merged, local)
    }

    func testFractionsComeBackExactly() throws {
        var local = base; local.name = "x"
        var remote = base; remote.ratio = 0.1 + 0.2
        let result = try XCTUnwrap(RecordMerge.merge(base: base, local: local, remote: remote))
        XCTAssertEqual(result.merged.ratio, 0.1 + 0.2)
    }

    func testARecordThatIsNoJSONObjectGivesNil() {
        XCTAssertNil(RecordMerge.merge(base: "a", local: "b", remote: "c"))
    }
}
