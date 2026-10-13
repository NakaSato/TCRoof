import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore
import SurveyUI

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
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var stations: [Job] { jobs.pwaStations }
    /// The stations being installed: the PWA jobs with an MP plan that aren't handed over.
    private var installing: [Job] { stations.filter { $0.scheduleInput != nil && $0.status != .completed } }

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
                .navigationDestination(item: $station) { JobDetailView(job: $0) }
                .navigationDestination(item: $dailies) { DailyReportListView(job: $0) }
        case .plan:
            // iPad (and a wide split view) keeps the station list
            if sizeClass == .compact { PWAPlanPhoneView() } else { MPOverviewView().toolbar(.visible, for: .navigationBar) }
        case .docs: docs
        case .settings: SolarSurveyEntryView(page: .settings).environment(\.pwaOverview, overview)
        }
    }

    /// `StationDocsScreen` is one station's papers: the first station being installed, else the first PWA station.
    @ViewBuilder private var docs: some View {
        if let job = installing.first ?? stations.first {
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
            installStations: installing.map(\.installSummary),
            openStation: { s in station = installing.first { $0.overviewID == s.id } },
            // one station's list: the first that hasn't sent today's report
            openDailyReports: installing.isEmpty ? nil : { dailies = installing.first { !$0.sentDailyReportToday } ?? installing.first })
    }

    private var items: [TCTabItem<PWATab>] {
        let today = stations.filter { $0.surveyDate.isToday }.count
        let waiting = installing.reduce(0) { $0 + $1.papersWaitingToSend }
        return [
            TCTabItem(.home, title: "หน้าหลัก", symbol: "house", action: goHome),
            TCTabItem(.project, title: "โครงการ", asset: "tab-project", badge: today, accessibilityLabel: today > 0 ? "โครงการ · นัดวันนี้ \(today)" : nil),
            TCTabItem(.plan, title: "แผนงาน", symbol: "calendar"),
            docsItem(waiting),
            TCTabItem(.settings, title: "ตั้งค่า", symbol: "gearshape", accessibilityLabel: "ตั้งค่าโครงการ PWA"),
        ]
    }

    private func docsItem(_ waiting: Int) -> TCTabItem<PWATab> {
        var item = TCTabItem(PWATab.docs, title: "เอกสาร", asset: "tab-docs", badge: waiting,
                             accessibilityLabel: waiting > 0 ? "เอกสารสถานี กปภ. · รอส่ง \(waiting)" : "เอกสารสถานี กปภ.")
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

    /// This station for the survey home's install overview: plan and actual from its MP plan to this week, the task
    /// planned this week and not done, and whether today's daily report is signed. The team stands in for the
    /// contractor, which no record keeps.
    var installSummary: InstallStationSummary {
        var s = InstallStationSummary(id: overviewID, mpNumber: mpNumber, name: projectName, kWp: capacityKW, actual: 0,
                                      contractor: team.rawValue, dueDate: installEnd, reportSentToday: sentDailyReportToday)
        guard let input = scheduleInput else { return s }
        let cal = MasterSchedule.calendar, week = MasterSchedule.weekStart(.now)
        let weekEnd = cal.date(byAdding: .day, value: 6, to: week) ?? week
        let plan = MasterSchedule.plan(input), status = MasterSchedule.status(plan: plan, actual: scheduleActual, through: .now)
        let current = plan.first { p in
            guard p.weight > 0, let start = p.start, let end = p.end, start <= weekEnd, end >= week else { return false }
            return (status.actualByTask[p.task] ?? 0) < 99.95
        }
        s.actual = status.actual
        s.plan = status.planned
        s.currentTask = current.map { "\($0.task.code) \($0.task.title)" } ?? ""
        return s
    }

    /// Papers signed and not yet sent, over the station's packages.
    var papersWaitingToSend: Int {
        let ctx = stationContext, station = stationDocs, library = StationDocsStore.loadLibrary()
        let kinds = Set(StationDocs.packages(ctx).flatMap { StationDocs.papers(in: $0, ctx).map(\.id) })
        return kinds.compactMap(StationDocs.kind).filter { StationDocs.state($0, station: station, library: library).status == .signed }.count
    }
}
