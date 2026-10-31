import Foundation

/// One in-memory documents overview; hidden tab redraws can reuse it without decoding projects or plans.
@MainActor
public final class PWADocsOverviewCache {
    public struct Result: Sendable {
        public let stations: [PWAPlan.Station]
        public let sourceLibrary: StationDocs.Library
        public let summary: PWADocs.Summary
        public let rows: [PWADocs.StationRow]
        public let groups: [PWADocs.Group]
        public let libraryRows: [PWADocs.LibraryRow]
        public let expiring: PWADocs.LibraryRow?
        public let ours: Int
    }
    private struct Key: Equatable {
        let stations: [PWAPlan.Station]
        let library: StationDocs.Library
        let day: Date
        let warnDays: Int
    }
    private var key: Key?
    public private(set) var cached = Result(stations: [], sourceLibrary: .init(), summary: .init(bands: [:], open: [:]),
                                           rows: [], groups: [], libraryRows: [], expiring: nil, ours: 0)
    private(set) var buildCount = 0

    public init() {}

    public func result(stations: [PWAPlan.Station], library: StationDocs.Library, today: Date, warnDays: Int = 30) -> Result {
        let next = Key(stations: stations, library: library, day: MasterSchedule.calendar.startOfDay(for: today), warnDays: warnDays)
        if next == key { return cached }
        let groups = PWADocs.todo(stations, library: library)
        let papers = PWADocs.library(library, today: today, warnDays: warnDays)
        cached = Result(stations: stations, sourceLibrary: library, summary: PWADocs.summary(stations, library: library),
                        rows: PWADocs.rows(stations, library: library, today: today), groups: groups, libraryRows: papers,
                        expiring: PWADocs.nearestExpiry(papers), ours: groups.flatMap(\.items).filter(\.isOurs).count)
        key = next
        buildCount += 1
        return cached
    }
}
