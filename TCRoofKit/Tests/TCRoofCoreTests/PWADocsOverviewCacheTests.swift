import XCTest
@testable import TCRoofCore

@MainActor
final class PWADocsOverviewCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func station() -> PWAPlan.Station {
        .init(id: "one", name: "Station", input: .init(installStart: now, installEnd: now.addingTimeInterval(86400 * 60),
              kickoff: now, engineeringStart: now, siteHandover: now, over200kVA: true))
    }

    func testRepeatedOverviewRendersReuseScheduleAndDocumentResults() async {
        let cache = PWADocsOverviewCache(), stations = [station()]
        let expected = PWADocs.todo(stations, library: .init()).flatMap(\.items)
        for _ in 0..<20 {
            let result = cache.result(stations: stations, library: .init(), today: now)
            XCTAssertEqual(result.groups.flatMap(\.items).map(\.id), expected.map(\.id))
            XCTAssertEqual(result.groups.flatMap(\.items).map(\.due), expected.map(\.due))
        }
        XCTAssertEqual(cache.buildCount, 1)
        _ = cache.cached
        XCTAssertEqual(cache.buildCount, 1, "hidden tabs read the last overview without rebuilding it")
    }

    func testProjectEditsLibraryEditsAndDayChangesRefreshOverview() async {
        let cache = PWADocsOverviewCache()
        var value = station()
        _ = cache.result(stations: [value], library: .init(), today: now)
        value.name = "Changed"
        let updated = cache.result(stations: [value], library: .init(), today: now)
        XCTAssertEqual(updated.rows.first?.station.name, "Changed")
        var library = StationDocs.Library()
        library.docs["pwa_act"] = .init(status: .approved)
        _ = cache.result(stations: [value], library: library, today: now)
        _ = cache.result(stations: [value], library: library, today: now.addingTimeInterval(86400))
        XCTAssertEqual(cache.buildCount, 4)
    }

    func testBatchedDueDatesPreserveOverridesAndEveryPackagesOriginalDates() async {
        var value = station()
        value.docs.setDue(now.addingTimeInterval(86400 * 3), for: .building)
        let dates = PWADocs.dueDates(value)
        for package in StationDocs.Package.allCases {
            XCTAssertEqual(dates[package], PWADocs.due(package, value), package.rawValue)
        }
        value.input = nil
        let withoutPlan = PWADocs.dueDates(value)
        for package in StationDocs.Package.allCases {
            XCTAssertEqual(withoutPlan[package], PWADocs.due(package, value), package.rawValue)
        }
    }
}
