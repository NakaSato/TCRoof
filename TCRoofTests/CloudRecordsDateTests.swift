import XCTest
@testable import TCRoof

final class CloudRecordsDateTests: XCTestCase {

    func testDateMillisRoundtrip() {
        let original = Date(timeIntervalSince1970: 1730648400.123)
        let millis = original.millis
        let reconstructed = Date(millis: millis)

        XCTAssertEqual(original.timeIntervalSince1970, reconstructed.timeIntervalSince1970, accuracy: 0.001)
    }

    func testDateMillisPrecision() {
        let now = Date()
        let millis = now.millis
        let fromMillis = Date(millis: millis)

        XCTAssertEqual(now.timeIntervalSince1970, fromMillis.timeIntervalSince1970, accuracy: 0.001)
    }
}
