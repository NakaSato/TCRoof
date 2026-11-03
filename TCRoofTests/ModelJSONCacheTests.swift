import XCTest
@testable import TCRoof

final class ModelJSONCacheTests: XCTestCase {

    private struct TestModel: Codable, Equatable {
        let name: String
        let count: Int
    }

    func testCacheHitsWhenRawMatches() {
        let cache = ModelJSONCache()
        let raw = #"{"name":"Inverter A","count":42}"#

        let first: TestModel? = cache.decode(TestModel.self, for: "key1", raw: raw)
        XCTAssertEqual(first, TestModel(name: "Inverter A", count: 42))

        // Same raw JSON string should return the cached instance
        let second: TestModel? = cache.decode(TestModel.self, for: "key1", raw: raw)
        XCTAssertEqual(second, first)
    }

    func testCacheInvalidatesWhenRawChanges() {
        let cache = ModelJSONCache()
        let raw1 = #"{"name":"Inverter A","count":42}"#
        let raw2 = #"{"name":"Inverter B","count":99}"#

        let first: TestModel? = cache.decode(TestModel.self, for: "key1", raw: raw1)
        XCTAssertEqual(first?.name, "Inverter A")

        let second: TestModel? = cache.decode(TestModel.self, for: "key1", raw: raw2)
        XCTAssertEqual(second?.name, "Inverter B")
        XCTAssertEqual(second?.count, 99)
    }

    func testValueFunctionCachesResult() {
        let cache = ModelJSONCache()
        var computeCount = 0

        let v1 = cache.value(for: "valKey", raw: "sample") { raw in
            computeCount += 1
            return (raw ?? "").uppercased()
        }
        XCTAssertEqual(v1, "SAMPLE")
        XCTAssertEqual(computeCount, 1)

        let v2 = cache.value(for: "valKey", raw: "sample") { raw in
            computeCount += 1
            return (raw ?? "").uppercased()
        }
        XCTAssertEqual(v2, "SAMPLE")
        XCTAssertEqual(computeCount, 1, "Should reuse cached result without re-executing block")
    }

    func testEncodeWithSortedKeys() {
        let model = TestModel(name: "Test", count: 10)
        let json = ModelJSONCache.encode(model, sortedKeys: true)
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("\"count\":10"))
        XCTAssertTrue(json!.contains("\"name\":\"Test\""))
    }
}
