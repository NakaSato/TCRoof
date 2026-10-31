import XCTest
@testable import TCRoofCore

final class ProjectListWindowTests: XCTestCase {
    func testCachedProjectsStartWithTenAndExpandOnlyOnDemand() {
        var window = ProjectListWindow()
        let cached = Array(0..<35)
        XCTAssertEqual(Array(cached.prefix(window.limit)), Array(0..<10))
        XCTAssertTrue(window.hasMore(total: cached.count))
        window.revealMore()
        XCTAssertEqual(Array(cached.prefix(window.limit)), Array(0..<20))
        window.revealMore()
        window.revealMore()
        XCTAssertEqual(Array(cached.prefix(window.limit)), cached)
        XCTAssertFalse(window.hasMore(total: cached.count))
    }

    func testSurveyAndStationRowsShareOnePageBudget() {
        var window = ProjectListWindow()
        XCTAssertEqual(window.stationLimit(surveyCount: 6), 4)
        XCTAssertEqual(window.stationLimit(surveyCount: 15), 0)
        window.revealMore()
        XCTAssertEqual(window.stationLimit(surveyCount: 6), 14)
        XCTAssertEqual(window.stationLimit(surveyCount: 15), 5)
    }

    func testChangingFiltersResetsVisibleRowsWithoutDroppingCachedData() {
        var window = ProjectListWindow()
        window.revealMore()
        window.reset()
        XCTAssertEqual(window.limit, 10)
        XCTAssertFalse(window.hasMore(total: 0))
        XCTAssertFalse(window.hasMore(total: 10))
        XCTAssertTrue(window.hasMore(total: 11))
    }
}
