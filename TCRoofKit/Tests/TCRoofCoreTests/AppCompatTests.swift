import XCTest
@testable import TCRoofCore

final class AppCompatTests: XCTestCase {
    func testNoMinimumStopsNothing() {
        XCTAssertFalse(AppCompat.isOutdated(minimum: nil, current: 1))
        XCTAssertFalse(AppCompat.isOutdated(minimum: 0, current: 1))
        XCTAssertFalse(AppCompat.isOutdated(minimum: -3, current: 1))
    }

    func testAnOlderBuildIsStopped() {
        XCTAssertTrue(AppCompat.isOutdated(minimum: 2, current: 1))
        XCTAssertFalse(AppCompat.isOutdated(minimum: 2, current: 2))
        XCTAssertFalse(AppCompat.isOutdated(minimum: 2, current: 3))
    }

    func testThisBuildPassesItsOwnNumber() {
        XCTAssertFalse(AppCompat.isOutdated(minimum: AppCompat.syncVersion))
        XCTAssertTrue(AppCompat.isOutdated(minimum: AppCompat.syncVersion + 1))
    }
}
