import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// Root of the main dock's PWA stack, `กปภ.` on iPhone and `โครงการ` on iPad (docs/ui/pwa-solar-survey-iphone-v3 §1,
/// docs/ui/pwa-solar-survey-ipad-v3 §2): the PWA project home, with what its header and nav open. The MP plans, the
/// daily reports and the notifications are the app's, so they go to the survey home as a `PWAOverviewHost`.
/// `PhoneTabs` or `PadTabs` puts the dock under it.
struct PWARoot: View {
    /// A station opened from an overview that has no survey job in that stage.
    @State private var station: Job?
    /// The station whose daily report list the install overview's strip opened.
    @State private var dailies: Job?
    @State private var showPlan = false
    @State private var showNotifications = false
    @AppStorage("notifications.read") private var readRaw = ""
    @State private var liveFeed = LiveFeed.shared
    @State private var instruments = InstrumentStore.shared
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @Environment(GoogleSession.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPad: the dock over this stack (`PadTabs`).
    @Environment(PadDock.self) private var dock: PadDock?
    @Environment(\.modelContext) private var context

    var body: some View {
        SolarSurveyEntryView()
            .environment(\.pwaOverview, overview)
            .navigationDestination(item: $station) { job in
                // iPad: a station being installed opens its install tracking page (docs/ui/install-tracking-ipad)
                if sizeClass != .compact, jobs.pwaInstalling.contains(job) { InstallTrackingPage(job: job) } else { JobDetailView(job: job) }
            }
            .navigationDestination(item: $dailies) { DailyReportListView(job: $0) }
            .navigationDestination(isPresented: $showPlan) { PWAPlanPhoneView() }
            .fullScreenCover(isPresented: Binding(get: { sizeClass == .compact && showNotifications }, set: { showNotifications = $0 })) {
                notificationsView().environment(\.homeInk, .outdoor)
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
            // `-installOpen YES` (iPad): the first installing station's install tracking page, seeding one with an MP
            // plan and daily reports when none is installing. It changes that job for good.
            .task {
                guard sizeClass != .compact, UserDefaults.standard.bool(forKey: "installOpen") else { return }
                if jobs.pwaInstalling.isEmpty, let job = jobs.first(where: { $0.kind == .pwa }) ?? jobs.first {
                    job.kind = .pwa
                    job.seedRoutineDemo(context)
                }
                try? await Task.sleep(for: .milliseconds(600))
                station = jobs.pwaInstalling.first
            }
            #endif
    }

    private var overview: PWAOverviewHost {
        let installing = jobs.pwaInstalling, stations = jobs.pwaStations
        let read = readIDs
        return PWAOverviewHost(
            installStations: installing.map(\.installSummary),
            openStation: { s in station = installing.first { $0.overviewID == s.id } },
            // one station's list: the first that hasn't sent today's report
            openDailyReports: installing.isEmpty ? nil : { dailies = installing.first { !$0.sentDailyReportToday } ?? installing.first },
            maintenanceStations: stations.filter { $0.status == .completed }.map(\.maintenanceSummary),
            openMaintenanceStation: { s in station = stations.first { $0.overviewID == s.id } ?? demoStation(stations) },
            handOver: { id in stations.first { $0.overviewID == id }?.status = .completed },
            returnToInstall: { id in stations.first { $0.overviewID == id }?.status = .installing },
            openPlan: { showPlan = true },
            planBody: { search in AnyView(PWAPlanPhoneView(padSearch: search)) },
            unread: notifications.filter { !read.contains($0.id) }.count,
            openNotifications: { showNotifications.toggle() })
    }

    /// `-surveyHomeDemo maintenance`: the example stations are no jobs, so a row opens the first PWA station.
    private func demoStation(_ stations: [Job]) -> Job? {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "surveyHomeDemo") == "maintenance" { return stations.first }
        #endif
        return nil
    }

    // MARK: notifications

    // The bell's list, read marks and row actions, as `HomeView` has them. A row's screen opens on the home stack:
    // `PhoneTabs` switches to it when `NotificationService.link` is set.

    private var notifications: [AppNotification] {
        AppNotification.list(jobs: jobs.filter { $0.installDay(on: .now) != nil || $0.surveyDate.isToday },
                             survey: session.survey, posts: liveFeed.posts, tools: instruments.all)
    }

    private var readIDs: Set<String> { Set(readRaw.split(separator: "\n").map(String.init)) }

    private func notificationsView(large: Bool = false, close: (() -> Void)? = nil) -> PhoneNotificationsView {
        PhoneNotificationsView(items: notifications, read: readIDs, markRead: markRead, sync: { session.survey.cloudPush?() },
                               surveyHint: surveyHint,
                               openSurvey: { n in if let job = n.job { openLater(.survey(job: job.syncID ?? job.code)) } },
                               openLink: openLater, large: large, close: close)
    }

    /// The home bell's panel (`PadHome`: 440 wide, r18) under this header's bell, without its arrow. The page is
    /// dimmed lightly; a tap on it closes the panel, while the header's and the dock's buttons stay live.
    private var bellPanel: some View {
        // the header is 88 pt high; the panel starts 11 pt under its bell and ends 27 pt right of the bell's centre
        ZStack(alignment: .topTrailing) {
            Theme.popoverDim.ignoresSafeArea().allowsHitTesting(false)
            Color.clear.contentShape(Rectangle()).onTapGesture { showNotifications = false }.padding(.top, 88)
            notificationsView(large: true) { showNotifications = false }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Theme.navy.opacity(0.28), radius: 20, y: 16)
                .padding(.top, 88 - 22 + 11).padding(.trailing, 58)
        }
        .transition(.opacity)
    }

    /// Marks these read; ids no longer shown are dropped so the stored list stays small.
    private func markRead(_ list: [AppNotification]) {
        let shown = Set(notifications.map(\.id))
        readRaw = readIDs.intersection(shown).union(list.map(\.id)).sorted().joined(separator: "\n")
        NotificationService.shared.bellRead(Set(list.map(\.id)))
    }

    private func surveyHint(_ n: AppNotification) -> String {
        guard let job = n.job else { return "" }
        let report = job.syncID.flatMap { session.survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
        guard report != nil else { return "แตะเพื่อเริ่มสำรวจ A1" }
        return TodayAppointment(job: job, report: report).nextStepLabel.map { "แตะเพื่อทำต่อ \($0)" } ?? "แตะเพื่อเปิดแบบสำรวจ"
    }

    /// After the cover has gone, so the push lands on the home stack.
    private func openLater(_ link: DeepLink) {
        Task { try? await Task.sleep(for: .milliseconds(350)); NotificationService.shared.link = link }
    }
}

/// `ตั้งค่าโครงการ PWA` (`SurveyHome+Settings`), pushed from the settings sheet now that the PWA module has no dock of
/// its own. Its project rows count the stations of the install overview.
struct PWASettingsPage: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]

    var body: some View {
        SolarSurveyEntryView(page: .settings)
            .environment(\.pwaOverview, PWAOverviewHost(installStations: jobs.pwaInstalling.map(\.installSummary)))
    }
}

extension Array where Element == Job {
    /// The PWA stations being installed: those with an MP plan that aren't handed over.
    var pwaInstalling: [Job] { pwaStations.filter { $0.scheduleInput != nil && $0.status != .completed } }
}
