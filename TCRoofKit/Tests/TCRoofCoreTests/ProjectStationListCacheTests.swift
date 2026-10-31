import XCTest
@testable import TCRoofCore

@MainActor
final class ProjectStationListCacheTests: XCTestCase {
    private final class Owner {}

    func testRedrawReusesRowsAndIncomingStationUpdateInvalidatesThem() async {
        let owner = Owner(), cache = ProjectStationListCache()
        var station = InstallStationSummary(id: "one", name: "First", kWp: 10, actual: 0)
        let first = cache.rows(owner: ObjectIdentifier(owner), revision: 0, jobs: [], stations: [station], search: "", threshold: 10)
        XCTAssertEqual(first.map(\.name), ["First"])
        _ = cache.rows(owner: ObjectIdentifier(owner), revision: 0, jobs: [], stations: [station], search: "  ", threshold: 10)
        XCTAssertEqual(cache.buildCount, 1)
        station.name = "Updated"
        let updated = cache.rows(owner: ObjectIdentifier(owner), revision: 0, jobs: [], stations: [station], search: "", threshold: 10)
        XCTAssertEqual(updated.map(\.name), ["Updated"])
        XCTAssertEqual(cache.buildCount, 2)
    }

    func testLinkChangesAndModelReplacementDoNotReuseStaleExclusions() async {
        let owner = Owner(), replacement = Owner(), cache = ProjectStationListCache()
        let station = InstallStationSummary(id: "one", name: "First", kWp: 10, actual: 0)
        var job = Job.new(template: JobTemplate.all[0])
        job.jobSyncID = "one"
        XCTAssertTrue(cache.rows(owner: ObjectIdentifier(owner), revision: 1, jobs: [job], stations: [station], search: "", threshold: 10).isEmpty)
        job.jobSyncID = nil
        XCTAssertEqual(cache.rows(owner: ObjectIdentifier(owner), revision: 2, jobs: [job], stations: [station], search: "", threshold: 10).count, 1)
        job.jobSyncID = "one"
        XCTAssertTrue(cache.rows(owner: ObjectIdentifier(replacement), revision: 2, jobs: [job], stations: [station], search: "", threshold: 10).isEmpty)
    }

    func testSearchSettingsAndRemovalInvalidateRows() async {
        let owner = Owner(), cache = ProjectStationListCache()
        let station = InstallStationSummary(id: "one", mpNumber: 42, name: "First", kWp: 10, actual: 0)
        XCTAssertEqual(cache.rows(owner: ObjectIdentifier(owner), revision: 0, jobs: [], stations: [station], search: "MP 42", threshold: 10).count, 1)
        XCTAssertTrue(cache.rows(owner: ObjectIdentifier(owner), revision: 0, jobs: [], stations: [station], search: "other", threshold: 10).isEmpty)
        _ = cache.rows(owner: ObjectIdentifier(owner), revision: 0, jobs: [], stations: [station], search: "other", threshold: 20)
        XCTAssertEqual(cache.buildCount, 3)
        XCTAssertTrue(cache.rows(owner: ObjectIdentifier(owner), revision: 0, jobs: [], stations: [], search: "", threshold: 20).isEmpty)
    }
}
