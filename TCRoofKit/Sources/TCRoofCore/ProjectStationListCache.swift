import Foundation

/// Keeps the project home's station rows across redraws. Retains only the latest request and result.
@MainActor
public final class ProjectStationListCache {
    private struct Key: Equatable {
        let owner: ObjectIdentifier
        let revision: Int
        let stations: [InstallStationSummary]
        let search: String
        let threshold: Double
    }
    private var key: Key?
    private var value: [InstallStationSummary] = []
    private var linked = Set<String>()
    private(set) var buildCount = 0

    public init() {}

    public func rows(owner: ObjectIdentifier, revision: Int, jobs: [Job],
                     stations: [InstallStationSummary], search: String, threshold: Double) -> [InstallStationSummary] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let next = Key(owner: owner, revision: revision, stations: stations, search: query, threshold: threshold)
        if key == next { return value }
        if key?.owner != owner || key?.revision != revision {
            linked = Set(jobs.compactMap(\.jobSyncID) + jobs.map(\.id.uuidString))
        }
        let matching = stations.filter { station in
            !linked.contains(station.id) && (query.isEmpty
                || station.name.localizedCaseInsensitiveContains(query)
                || station.contractor.localizedCaseInsensitiveContains(query)
                || station.mpNumber.map { "MP \($0)".localizedCaseInsensitiveContains(query) } == true)
        }
        value = InstallOverview.rows(matching, filter: .all, threshold: threshold)
        key = next
        buildCount += 1
        return value
    }
}
