import SwiftUI
import SwiftData
import TCRoofCore

@MainActor
@Observable final class InstallSummaryCache {
    private(set) var summaries: [InstallStationSummary] = []
    private(set) var isLoading = true
    @ObservationIgnored private let worker = InstallSummaryWorker()
    private static let disk = ProjectOverviewCache(file: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ProjectOverview/summaries.json"))

    static func clearPersistentCache() async {
        await disk.clear()
    }

    func refresh(_ inputs: [InstallSummaryInput], owner: String, at now: Date) async {
        if let cached = await Self.disk.load(owner: owner, inputs: inputs, at: now) {
            guard !Task.isCancelled else { return }
            if summaries != cached { summaries = cached }
            isLoading = false
            return
        }
        let result = await worker.summaries(inputs, at: now)
        guard !Task.isCancelled else { return }
        if summaries != result { summaries = result }
        isLoading = false
        do { try await Self.disk.save(owner: owner, inputs: inputs, summaries: result, at: now) }
        catch { print("Project cache: save failed: \(error.localizedDescription)") }
    }
}

/// Only this small view observes daily-report fields and the clock. Opening a sheet or scrolling the project
/// screen reuses the published summaries without scanning every station's logs again.
private struct InstallSummaryLoader: ViewModifier {
    let cache: InstallSummaryCache
    @Environment(\.scenePhase) private var scenePhase
    @State private var foreground = Date.now

    func body(content: Content) -> some View {
        content.background {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                InstallSummaryRequestView(cache: cache, now: max(timeline.date, foreground))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { foreground = .now }
        }
    }
}

private struct InstallSummaryRequestView: View {
    let cache: InstallSummaryCache
    let now: Date
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @Query private var reports: [InstallLog]
    @Environment(\.permissions) private var permissions

    init(cache: InstallSummaryCache, now: Date) {
        self.cache = cache
        self.now = now
        let calendar = RoutineReport.calendar
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        _reports = Query(filter: #Predicate<InstallLog> {
            $0.reportJSON != nil && $0.date >= start && $0.date < end
        }, sort: \InstallLog.date)
    }

    private struct Request: Equatable {
        let inputs: [InstallSummaryInput]
        let day: Date
        let owner: String
    }

    private func request(at now: Date) -> Request {
        let calendar = RoutineReport.calendar
        var sent: [PersistentIdentifier: Bool] = [:]
        // The earliest daily report wins, matching Job.dailyLog(on:), in one pass for all stations.
        for report in reports where calendar.isDate(report.date, inSameDayAs: now) {
            guard let id = report.job?.persistentModelID, sent[id] == nil else { continue }
            sent[id] = report.engineerSignedAt != nil
        }
        let inputs = jobs.pwaInstalling.map { job in
            InstallSummaryInput(base: InstallStationSummary(id: job.overviewID, mpNumber: job.mpNumber,
                                name: job.projectName, kWp: job.capacityKW, actual: 0, contractor: job.team.rawValue,
                                dueDate: job.installEnd, reportSentToday: sent[job.persistentModelID] ?? false),
                                planJSON: job.scheduleInputJSON, actualJSON: job.scheduleActualJSON)
        }
        let email = Permissions.normalized(permissions.email)
        let owner = email.isEmpty ? "" : email + "/" + permissions.role.rawValue
        return Request(inputs: inputs, day: MasterSchedule.calendar.startOfDay(for: now), owner: owner)
    }

    var body: some View {
        let request = request(at: now)
        Color.clear.task(id: request) { await cache.refresh(request.inputs, owner: request.owner, at: now) }
    }

}

extension View {
    func loadInstallSummaries(into cache: InstallSummaryCache) -> some View {
        modifier(InstallSummaryLoader(cache: cache))
    }
}
