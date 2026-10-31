import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import ExcelExport

/// Root of the main dock's PWA stack, `กปภ.` on iPhone and `โครงการ` on iPad (docs/ui/pwa-solar-survey-iphone-v3 §1,
/// docs/ui/pwa-solar-survey-ipad-v3 §2): the PWA project home, with what its header and nav open. The MP plans, the
/// daily reports and the notifications are the app's, so they go to the survey home as a `PWAOverviewHost`.
/// `PhoneTabs` or `PadTabs` puts the dock under it.
struct PWARoot: View {
    /// A station opened from an overview that has no survey job in that stage.
    @State private var station: Job?
    /// The station whose daily report list the install overview's strip opened.
    @State private var dailies: Job?
    /// Handed-over station opened for maintenance details (reference/PhonePwaStation.dc.html).
    @State private var maintenanceStation: MaintenanceStationSummary?
    @State private var showPlan = false
    @State private var showSettings = false
    @State private var showNotifications = false
    private var bell = PWABell()
    @Query(sort: \Job.installStart) private var jobs: [Job]
    /// Published background summaries, updated only when station inputs change.
    @State private var summaryCache = InstallSummaryCache()
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPad: the dock over this stack (`PadTabs`).
    @Environment(PadDock.self) private var dock: PadDock?
    @Environment(\.modelContext) private var context
    @Environment(\.permissions) private var permissions

    var body: some View {
        SolarSurveyEntryView()
            .deferBackgroundFilesWhileBrowsingProjects()
            .environment(\.pwaOverview, overview)
            .loadInstallSummaries(into: summaryCache)
            .navigationDestination(item: $station) { job in
                // a station being installed opens its install tracking page (docs/ui/install-tracking-ipad, and on
                // iPhone docs/ui/install-tracking-iphone)
                if jobs.pwaInstalling.contains(job) { InstallTrackingPage(job: job) } else { JobDetailView(job: job) }
            }
            .navigationDestination(item: $dailies) { DailyReportListView(job: $0) }
            .navigationDestination(item: $maintenanceStation) { s in
                PWAMaintenanceStationView(station: s)
            }
            .navigationDestination(isPresented: $showPlan) { PWAPlanPhoneView() }
            .navigationDestination(isPresented: $showSettings) { PWASettingsPage() }
            .fullScreenCover(isPresented: Binding(get: { sizeClass == .compact && showNotifications }, set: { showNotifications = $0 })) {
                bell.view().environment(\.homeInk, .outdoor)
            }
            // iPad: the panel of the home's bell (`PadHome`), under this header's bell
            .overlay(alignment: .topTrailing) { if sizeClass != .compact && showNotifications { bellPanel } }
            // the dock closes the bell's panel
            .onChange(of: dock?.tab) { showNotifications = false }
            .onChange(of: dock?.showSettings) { showNotifications = false }
            #if DEBUG
            // `-surveyHomeTab plan` opens แผนงาน. Not at launch: iOS 27 leaves a screen pushed then blank.
            .task {
                // iPad shows the plan in the home, under its nav
                guard sizeClass == .compact, UserDefaults.standard.string(forKey: "surveyHomeTab") == "plan" else { return }
                try? await Task.sleep(for: .milliseconds(600))
                showPlan = true
            }
            // `-installOpen YES`: the first installing station's install tracking page, seeding one with an MP plan and
            // daily reports when none is installing. It changes that job for good.
            .task {
                guard UserDefaults.standard.bool(forKey: "installOpen") else { return }
                if jobs.pwaInstalling.isEmpty, let job = jobs.first(where: { $0.kind == .pwa }) ?? jobs.first {
                    job.kind = .pwa
                    job.seedRoutineDemo(context)
                }
                try? await Task.sleep(for: .milliseconds(600))
                // the same station on every launch: the seeding below moves its install dates, which order `jobs`
                let key = "debug.installStation", remembered = UserDefaults.standard.string(forKey: key)
                let pick = jobs.pwaInstalling.first { remembered != nil && $0.syncID == remembered } ?? jobs.pwaInstalling.first
                UserDefaults.standard.set(pick?.syncID, forKey: key)
                // `-installSeed YES`: that station gets the routine demo's reports, for a real daily tab
                if UserDefaults.standard.bool(forKey: "installSeed") { pick?.seedRoutineDemo(context) }
                // `-installLate YES`: that station's 2.2 runs late, for the task sheet's causes
                if UserDefaults.standard.bool(forKey: "installLate") { pick?.seedLatePlan(); try? context.save() }
                // `-installWBS YES`: that station gets the first plan file's (P3-001) WBS rows with no ticks, for the task sheet's
                // งานย่อย WBS (for good), moved so the template's 2.1 starts on the station's 2.1, as a plan started
                // from the template would have them
                if UserDefaults.standard.bool(forKey: "installWBS"), let pick, let c = MPTemplates.cases().first,
                   let data = try? Data(contentsOf: c.url), var wbs = try? MPWorkbook.read(data).wbs {
                    let cal = MasterSchedule.calendar
                    if let input = pick.scheduleInput,
                       let start = MasterSchedule.plan(input).first(where: { $0.task.code == "2.1" })?.start,
                       let line = wbs.first(where: { $0.code == "2.1" })?.baselineStart,
                       let days = cal.dateComponents([.day], from: cal.startOfDay(for: line), to: cal.startOfDay(for: start)).day {
                        wbs = wbs.map { $0.shifted(days: days) }
                    }
                    pick.wbsTicks = [:]
                    pick.scheduleWBS = wbs
                    try? context.save()
                }
                station = pick
            }
            #endif
    }

    private var overview: PWAOverviewHost {
        let installing = jobs.pwaInstalling, stations = jobs.pwaStations
        return PWAOverviewHost(
            installStations: summaryCache.summaries,
            openStation: { s in station = installing.first { $0.overviewID == s.id } },
            // one station's list: the first that hasn't sent today's report
            openDailyReports: installing.isEmpty ? nil : { dailies = installing.first { !$0.sentDailyReportToday } ?? installing.first },
            maintenanceStations: stations.filter { $0.status == .completed }.map(\.maintenanceSummary),
            openMaintenanceStation: { s in maintenanceStation = s },
            handOver: { id in stations.first { $0.overviewID == id }?.status = .completed },
            returnToInstall: { id in stations.first { $0.overviewID == id }?.status = .installing },
            openPlan: { showPlan = true },
            planBody: { search in AnyView(PWAPlanPhoneView(padSearch: search)) },
            unread: bell.unread,
            openNotifications: { showNotifications.toggle() },
            openSettings: { showSettings = true },
            mine: jobs.mine(permissions),
            installLoading: summaryCache.isLoading || (!installing.isEmpty && summaryCache.summaries.isEmpty)
                || (jobs.isEmpty && CloudSync.shared.isLoading("jobs")))
    }

    /// `-surveyHomeDemo maintenance`: the example stations are no jobs, so a row opens the first PWA station.
    private func demoStation(_ stations: [Job]) -> Job? {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "surveyHomeDemo") == "maintenance" { return stations.first }
        #endif
        return nil
    }

    /// The home bell's panel (`PadHome`: 440 wide, r18) under this header's bell, without its arrow. The page is
    /// dimmed lightly; a tap on it closes the panel, while the header's and the dock's buttons stay live.
    private var bellPanel: some View {
        // the header is 88 pt high; the panel starts 11 pt under its bell and ends 27 pt right of the bell's centre
        ZStack(alignment: .topTrailing) {
            Theme.popoverDim.ignoresSafeArea().allowsHitTesting(false)
            Color.clear.contentShape(Rectangle()).onTapGesture { showNotifications = false }.padding(.top, 88)
            bell.view(large: true) { showNotifications = false }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Theme.navy.opacity(0.28), radius: 20, y: 16)
                .padding(.top, 88 - 22 + 11).padding(.trailing, 58)
        }
        .transition(.opacity)
    }
}

/// `ตั้งค่าโครงการ PWA` (`SurveyHome+Settings`), pushed from the settings sheet now that the PWA module has no dock of
/// its own. Its project rows count the stations of the install overview.
struct PWASettingsPage: View {
    @State private var summaryCache = InstallSummaryCache()

    var body: some View {
        SolarSurveyEntryView(page: .settings)
            .environment(\.pwaOverview, PWAOverviewHost(installStations: summaryCache.summaries, installLoading: summaryCache.isLoading))
            .loadInstallSummaries(into: summaryCache)
    }
}

extension Array where Element == Job {
    /// The PWA stations being installed: those with an MP plan that aren't handed over, and those set กำลังติดตั้ง
    /// with no plan yet, such as a survey just moved to installation.
    var pwaInstalling: [Job] {
        filter(\.opensInstallPage)
    }
}
