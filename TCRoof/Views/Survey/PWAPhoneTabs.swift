import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// Tabs of the PWA module on iPhone (docs/ui/pwa-solar-survey-iphone-v2 §6).
enum PWATab: String {
    /// `home` is only the dock's button back to the TCRoof home, never a selected tab.
    case home, project, plan, docs, settings

    static let stacks: [PWATab] = [.project, .plan, .docs, .settings]
}

/// The PWA module on iPhone: its own floating dock in place of the main one, one `NavigationStack` per tab, each
/// built when first opened and then kept. The dock is the root screens' bottom safe-area inset, so they scroll
/// behind it and a pushed screen covers it. `หน้าหลัก` leaves the module.
struct PWAPhoneTabs: View {
    let goHome: () -> Void

    @State private var tab = Self.initialTab
    @State private var opened: Set<PWATab> = [Self.initialTab]
    /// A station opened from the install overview that has no survey job in the installation stage.
    @State private var station: Job?
    /// The station whose daily report list the overview's strip opened.
    @State private var dailies: Job?
    @Query(sort: \Job.installStart) private var jobs: [Job]
    /// Published background summaries, updated only when station inputs change.
    @State private var summaryCache = InstallSummaryCache()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.permissions) private var permissions

    private var stations: [Job] { jobs.pwaStations }
    private var installing: [Job] { jobs.pwaInstalling }

    var body: some View {
        ZStack {
            ForEach(PWATab.stacks, id: \.self) { t in
                if opened.contains(t) {
                    let shown = t == tab
                    stack(t)
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(shown)
                        .accessibilityHidden(!shown)
                }
            }
        }
        .loadInstallSummaries(into: summaryCache)
    }

    private func select(_ t: PWATab) {
        opened.insert(t)
        tab = t
    }

    private func stack(_ t: PWATab) -> some View {
        NavigationStack {
            root(t)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    TCTabBar(items: items, selection: Binding(get: { tab }, set: select), dividerBefore: .settings)
                        .padding(.horizontal, 12).padding(.bottom, 22)
                        .background(alignment: .bottom) { TCDockFade() }
                }
                // the dock measures from the screen's bottom edge and stays there behind the keyboard
                .ignoresSafeArea(.all, edges: .bottom)
        }
    }

    @ViewBuilder private func root(_ t: PWATab) -> some View {
        switch t {
        case .project, .home:
            SolarSurveyEntryView()
                .environment(\.pwaOverview, overview)
                // a station being installed opens its install tracking page (docs/ui/install-tracking-iphone)
                .navigationDestination(item: $station) { job in
                    if installing.contains(job) { InstallTrackingPage(job: job) } else { JobDetailView(job: job) }
                }
                .navigationDestination(item: $dailies) { DailyReportListView(job: $0) }
        case .plan:
            // iPad (and a wide split view) keeps the station list
            if sizeClass == .compact { PWAPlanPhoneView() } else { MPOverviewView().toolbar(.visible, for: .navigationBar) }
        case .docs: docs
        case .settings: SolarSurveyEntryView(page: .settings).environment(\.pwaOverview, overview)
        }
    }

    /// Every station's papers; a card pushes that station's `StationDocsScreen`.
    @ViewBuilder private var docs: some View {
        if sizeClass == .compact {
            PWADocsHomeView(isActive: tab == .docs)
        } else if let job = installing.first ?? stations.first {
            StationDocsScreen(job: job).toolbar(.visible, for: .navigationBar)
        } else {
            TCEmptyState("ยังไม่มีสถานี กปภ.", systemImage: "doc.text", description: Text("เอกสารสถานีจะแสดงเมื่อมีงาน PWA ในเครื่องนี้"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.phonePage.ignoresSafeArea())
        }
    }

    private var overview: PWAOverviewHost {
        let installing = installing
        return PWAOverviewHost(
            installStations: summaryCache.summaries,
            openStation: { s in station = installing.first { $0.overviewID == s.id } },
            // one station's list: the first that hasn't sent today's report
            openDailyReports: installing.isEmpty ? nil : { dailies = installing.first { !$0.sentDailyReportToday } ?? installing.first },
            mine: jobs.mine(permissions),
            installLoading: summaryCache.isLoading || (!installing.isEmpty && summaryCache.summaries.isEmpty)
                || (jobs.isEmpty && CloudSync.shared.isLoading("jobs")))
    }

    private var items: [TCTabItem<PWATab>] {
        let today = stations.filter { $0.surveyDate.isToday }.count
        let installing = installing
        let library = installing.isEmpty ? StationDocs.Library() : StationDocsStore.loadLibrary()
        let waiting = installing.reduce(0) { $0 + $1.papersWaitingToSend(library: library) }
        return [
            TCTabItem(.home, title: "หน้าหลัก", symbol: "house", action: goHome),
            TCTabItem(.project, title: "โครงการ", asset: "tab-project", badge: today, accessibilityLabel: today > 0 ? "โครงการ | นัดวันนี้ \(today)" : nil),
            TCTabItem(.plan, title: "แผนงาน", symbol: "calendar"),
            docsItem(waiting),
            TCTabItem(.settings, title: "ตั้งค่า", symbol: "gearshape", accessibilityLabel: "ตั้งค่าโครงการ PWA"),
        ]
    }

    private func docsItem(_ waiting: Int) -> TCTabItem<PWATab> {
        var item = TCTabItem(PWATab.docs, title: "เอกสาร", asset: "tab-docs", badge: waiting,
                             accessibilityLabel: waiting > 0 ? "เอกสารสถานี กปภ. | รอส่ง \(waiting)" : "เอกสารสถานี กปภ.")
        item.badgeColor = Theme.warning
        return item
    }

    private static var initialTab: PWATab {
        #if DEBUG
        // `-surveyHomeTab plan|docs|settings` opens that dock tab; `all|install|maintenance` are the project tab's pills
        if let raw = UserDefaults.standard.string(forKey: "surveyHomeTab"), let t = PWATab(rawValue: raw), PWATab.stacks.contains(t) { return t }
        #endif
        return .project
    }
}

extension Job {
    /// The id the install overview knows this station by: the one its survey reports link to.
    var overviewID: String { syncID ?? code }

    var sentDailyReportToday: Bool { dailyLog(on: .now)?.engineerSignedAt != nil }

    /// This handed-over station for the maintenance overview. No monitoring feed yet, so it has no energy or PR.
    var maintenanceSummary: MaintenanceStationSummary {
        MaintenanceStationSummary(id: overviewID, mpNumber: mpNumber, name: projectName, kWp: capacityKW, status: .normal,
                                  note: "ยังไม่มีข้อมูลการผลิต")
    }

    /// Papers signed and not yet sent, over the station's packages.
    var papersWaitingToSend: Int {
        papersWaitingToSend(library: StationDocsStore.loadLibrary())
    }

    func papersWaitingToSend(library: StationDocs.Library) -> Int {
        let station = stationDocs
        let ctx = StationDocs.Context(station, inverterKW: inverterKW ?? (scheduleInput?.over200kVA == true ? 200 : nil))
        let kinds = Set(StationDocs.packages(ctx).flatMap { StationDocs.papers(in: $0, ctx).map(\.id) })
        return kinds.compactMap(StationDocs.kind).filter { StationDocs.state($0, station: station, library: library).status == .signed }.count
    }
}
