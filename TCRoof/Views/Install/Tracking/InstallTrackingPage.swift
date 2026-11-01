import SwiftUI
import TCRoofUI
import TCRoofCore
import ExcelExport

/// The iPad install tracking page of one station (docs/ui/install-tracking-ipad): the blue header, the project's tab
/// bar and, on `ภาพรวม`, the KPI strip. It is pushed over the PWA home and keeps the dock; its tabs change in place.
struct InstallTrackingPage: View {
    enum Tab: String, CaseIterable { case overview, daily, plan, docs, request, weekly, iec, settings }

    /// A screen the page pushes.
    enum Route: Hashable { case request, weekly, docs, plan, dailies, day(Date), survey(UUID), detail, iec, devices }

    let job: Job
    @State var tab = Debug.tab
    @State var view = Debug.view
    /// `Key Plan`'s settings with `-installDemo YES`: the board's example, kept in memory.
    @State var keyDemo: RoutineReport.Settings?
    /// `แผนก่อสร้าง`'s `Gantt | ตาราง`.
    @State var planView = Debug.planView
    /// Stages opened or closed against their default: the running stage and the next start open, or none with
    /// `-installPlanCollapsed YES`.
    @State var planToggled: Set<String> = []
    @State var planAllClosed = Debug.planCollapsed
    /// The scroll view's height: the Gantt card ends above the dock.
    @State var viewport: CGFloat = 0
    /// Task rows opened or closed against their default (the running task starts open).
    @State var toggled: Set<String> = []
    /// The task whose sheet is open.
    @State var stage: InstallGantt.Row?
    @State var route: Route?
    @State var sheet: Sheet? = Debug.sheet
    @State var siteTab = Debug.site
    /// `ทุกรายงาน`'s segment: all, to do, with a problem.
    @State var dailyFilter = Debug.dailyFilter
    @State var ackingAllDailies = false
    @State var shared: Shared?
    /// `แผนก่อสร้าง`'s plan file: import and export of the station's own workbook.
    @State var workbook = MPWorkbookFlow()
    @Environment(\.permissions) var permissions
    /// The debug flags apply once: `.task` runs again each time the page reappears (back from a pushed screen).
    @State private var debugApplied = false
    /// ผู้ช่วยโครงการ, opened on this station.
    @State var assistant = false
    @State var showWBSDependencies = false
    /// `-installDemo YES` keeps its picked late causes here instead of in a job.
    @State private var demoCauses: [String: MasterSchedule.LateCause] = [:]
    @State private var survey = SurveyModel.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) var context
    @Environment(\.horizontalSizeClass) var sizeClass

    /// `start` opens the page at that tab (links from the job screen, notifications and the feed on iPad).
    init(job: Job, start: Tab? = nil) {
        self.job = job
        _tab = State(initialValue: start ?? Debug.tab)
    }

    // iPhone (docs/ui/install-tracking-iphone): every tab in place, and the header's gear
    @State var phoneTab = Debug.phoneTab
    @State var phoneSettings = Debug.settings
    @State var settingsCategory: SettingsCategory? = Debug.settingsCategory
    /// `แผนก่อสร้าง`'s edit mode: the stages' new start and days by id, and the reason.
    @State var planEditing = false
    @State var planDraft: [String: PlanDraft] = [:]
    @State var planReason = ""
    /// `คำขอรายสัปดาห์` and `Weekly Report`: weeks from their default one.
    @State var requestWeek = Debug.requestWeek
    /// The page's width: `คำขอรายสัปดาห์` takes the one-page request from 1000 pt.
    @State var pageWidth: CGFloat = 0
    /// iPad `คำขอรายสัปดาห์` (docs/ui/install-tracking-ipad-weekly-request): the week's request as edited, the
    /// requester's drawn signature and name (kept only until it is sent: `engineerSignedAt` records the signing), the open
    /// sheet, a short note, and `ดึงจากแผน MP`'s time and spinner.
    @State var request: RoutineReport.WeeklyRequest?
    @State var reqSignature: Data?
    @State var reqSignedAt: Date?
    @State var reqName = ""
    @State var reqSheet: RequestSheet?
    @State var reqToast: String?
    @State var reqPulledAt: Date?
    @State var reqPulling = false
    @State var reportWeek = Debug.reportWeek
    /// iPad `Weekly Report` (docs/ui/install-tracking-ipad-weekly-report): the selected slide (0…7), the recipients picked
    /// for a week not sent yet (nil: the default two), the download menu, the .pptx sheet, the share sheet's files, the
    /// week's content and photos (worked out when the week changes), a short note, and `-installDemo YES`'s sends.
    @State var reportSlide = Debug.reportSlide
    @State var reportTo: [String]?
    @State var reportDownload = false
    @State var reportPptx = false
    @State var reportShare: WeeklyShare?
    @State var reportDeckShare: WeeklyShare?
    @State var reportContent: WeeklySlides.Content?
    @State var reportPhotos: [UUID: UIImage] = [:]
    @State var reportNote: String?
    @State var reportDemoSent: [String: RoutineReport.WeeklySent] = [:]
    /// The Weekly Report tab's width: under `weeklyNarrow` (a portrait iPad) it takes its portrait layout.
    @State var weeklyWidth: CGFloat = 0
    /// `เอกสาร`'s selected permit stage.
    @State var docsStage: StationDocs.Package? = Debug.docsPackage
    /// iPad `เอกสาร`: the selected paper, the paper whose sheet is open, the shared library, the selected file's first
    /// page, and a note after an export with nothing to put in.
    @State var docsPaper: String? = Debug.docsPaper
    @State var docsSheet: StationDocs.Kind?
    @State var docsLibrary = StationDocsStore.loadLibrary()
    @State var docsThumbnail: UIImage?
    @State var docsNote: String?
    @Environment(PadDock.self) var dock: PadDock?
    /// The phone page's pushed screens that the iPad routes don't cover.
    @State var phoneRoute: PhoneRoute?
    @State var phoneSheet: PhoneSheet?
    /// iPad `ตั้งค่าโครงการ` (docs/ui/install-tracking-ipad-settings): the category shown, the edits not saved yet, the
    /// open sheet, where the person was going when asked about unsaved edits, and `-installDemo YES`'s station.
    @State var padCategory = Debug.padCategory
    @State var settingsDraft = SettingsDraft()
    @State var padSheet: PadSettingsSheet?
    @State var leaving: Leave?
    @State var padDemo = PadSettingsDemo.initial

    var body: some View {
        let data = self.data
        Group {
            if sizeClass == .compact { phoneBody(data) } else { padBody(data) }
        }
        .overlay { if let row = stage, let g = data.gantt { stageSheet(row, g) } }
        .overlay { if let s = sheet { pageSheet(s, data) } }
        .sheet(item: $shared) { ActivitySheet(items: [$0.url]) }
        .sheet(isPresented: $ackingAllDailies) {
            InspectorAckSheet(title: "รับทราบทั้งหมด (\(job.pendingAckLogs.count) วัน)", name: job.routineSettings.inspector, date: .now, signs: true) { name, when, drawn in
                job.recordInspectorAckAll(job.pendingAckLogs, name: name, at: when, signature: drawn, context: context)
            }
        }
        .sheet(isPresented: $assistant) { AssistantChatView(focus: job) }
        .sheet(isPresented: $showWBSDependencies) { WBSDependenciesSheet(job: job) }
        .alert(docsNote ?? "", isPresented: Binding(get: { docsNote != nil }, set: { if !$0 { docsNote = nil } })) {
            Button("ตกลง", role: .cancel) {}
        }
        .mpWorkbook(workbook, job: job)
        .onAppear(perform: enforceRoleTabAccess)
        .onChange(of: permissions.role) { _, _ in enforceRoleTabAccess() }
        .task { CloudSync.shared.loadSiteICLSheets() }
        #if DEBUG
        // `-installStage n` opens the nth task's sheet
        .task {
            guard !debugApplied else { return }
            debugApplied = true
            // `-installDetail YES` opens รายละเอียดงาน
            if Debug.detail { route = .detail }
            // `-iecOpen YES` opens ทดสอบ IEC 62446
            if Debug.iec {
                if sizeClass == .compact { route = .iec } else { tab = .iec }
            }
            // `-installPlanEdit YES` opens แผนก่อสร้าง's edit mode (iPhone)
            if Debug.planEdit, sizeClass == .compact { startPlanEdit(data) }
            guard let n = Debug.stage, let rows = data.gantt?.rows, rows.indices.contains(n - 1) else { return }
            stage = rows[n - 1]
        }
        #endif
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $route) { r in
            destination(r).environment(\.installTab) { t in route = nil; if canOpen(t) { tab = t } }
        }
        .navigationDestination(item: $phoneRoute) { phoneDestination($0) }
    }

    /// The iPad page (docs/ui/install-tracking-ipad, -v2). On `คำขอรายสัปดาห์` at full width the request's own bottom
    /// bar takes the dock's place (docs/ui/install-tracking-ipad-request-map), as a pushed screen covers it.
    @ViewBuilder private func padBody(_ data: InstallPageData) -> some View {
        let page = padPage(data)
        if requestOnePage { page } else { page.padDock(fade: nil) }
    }

    /// `คำขอรายสัปดาห์` shows the one-page key-plan request: iPads at least 1000 pt wide, unless DEBUG's
    /// `-installRequestForm YES` asks for the R1 form.
    var requestOnePage: Bool { tab == .request && pageWidth >= 1000 && !Debug.requestForm }

    private func padPage(_ data: InstallPageData) -> some View {
        VStack(spacing: 0) {
            header(data)
            tabBar(data)
            // Weekly Report doesn't scroll: its rail and panel scroll inside themselves
            if tab == .weekly {
                weeklyTab()
                    .task(id: reportWeek) { loadReport() }
            // คำขอรายสัปดาห์: the one-page request through its own screen (saving, signing, the PDF and sending stay there)
            } else if requestOnePage {
                WeeklyRequestScreen(job: job, week: requestWeekStart, embedded: true) { w in
                    requestWeek = Int((MasterSchedule.weekStart(w).timeIntervalSince(nextRequestWeek) / (7 * 86_400)).rounded())
                }
            // the width isn't known for the first frame: neither layout yet
            } else if tab == .request && pageWidth == 0 {
                Spacer(minLength: 0)
            // narrower, the R1 form scrolls and keeps its panel still
            } else if tab == .request {
                requestTab()
                    .task(id: requestWeek) {
                        loadRequest()
                        #if DEBUG
                        applyRequestState()
                        #endif
                    }
            } else if tab == .settings {
                padSettingsTab(data)
            } else if tab == .iec {
                IECTestScreen(job: job, embedded: true)
            } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch tab {
                        case .overview:
                            kpiStrip(data)
                            if let g = data.gantt { progressCard(data, g) }
                            siteRow(data)
                        case .daily:
                            dailyTab(dailyData)
                        case .plan:
                            planTab(data)
                        case .docs:
                            docsTab()
                        case .request, .weekly, .iec, .settings:
                            EmptyView()
                        }
                    }
                    // the last cards end above the dock
                    .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, Self.dockClearance)
                    Color.clear.frame(height: 1).id("end")
                }
                .scrollIndicators(.hidden)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
                #if DEBUG
                // `-installScrollEnd YES` opens the overview at its end
                .task {
                    guard Debug.scrollEnd else { return }
                    try? await Task.sleep(for: .milliseconds(400))
                    proxy.scrollTo("end", anchor: .bottom)
                }
                #endif
            }
            }
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .alert("ยังไม่ได้บันทึกการแก้ไข", isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } })) {
            Button("บันทึก") { saveSettingsDraft(); go(leaving) }
            Button("ทิ้ง", role: .destructive) { settingsDraft = SettingsDraft(); go(leaving) }
            Button("อยู่ต่อ", role: .cancel) { leaving = nil }
        } message: {
            Text("แก้ไข \(settingsChanges.count) รายการในตั้งค่าโครงการ")
        }
    }

    /// Where the page goes from `ตั้งค่าโครงการ`: another tab, a pushed screen, or back to the list.
    enum Leave: Equatable { case tab(Tab), route(Route), back }

    /// Goes there, asking first while `ตั้งค่าโครงการ` holds edits not saved.
    func leave(to target: Leave) {
        if tab == .settings, !settingsChanges.isEmpty { leaving = target } else { go(target) }
    }

    private func go(_ target: Leave?) {
        leaving = nil
        switch target {
        case .tab(let t): if canOpen(t) { tab = t }
        case .route(let r): route = r
        case .back: dismiss()
        case nil: break
        }
    }

    /// Next week's start, which `requestWeek` counts from.
    private var nextRequestWeek: Date { MasterSchedule.weekStart(RoutineReport.add(.now, 7)) }

    var data: InstallPageData {
        #if DEBUG
        if Debug.demo {
            // the board's header has `รายงานสำรวจ`: any survey on the device stands in for the station's
            var d = InstallPageData.demo(late: Debug.demoLate)
            d.surveyReport = survey.jobs.first?.id
            return d
        }
        #endif
        return InstallPageData(job: job, survey: survey)
    }

    @ViewBuilder func destination(_ r: Route) -> some View {
        switch r {
        case .request: WeeklyRequestScreen(job: job)
        case .weekly: RoutineSummaryScreen(job: job, period: .week)
        case .docs: StationDocsScreen(job: job)
        case .plan: MPScheduleScreen(job: job)
        case .dailies: DailyReportListView(job: job)
        case .day(let d): DailyReportScreen(job: job, date: d)
        case .survey(let id): SurveyReportEditor(jobID: id)
        case .detail: JobDetailView(job: job)
        case .iec: IECTestScreen(job: job)
        case .devices: JobDevicesView(job: job)
        }
    }

    /// The task's sheet over a dimmed page, dock included.
    func stageSheet(_ row: InstallGantt.Row, _ g: InstallGantt) -> some View {
        ZStack {
            Theme.navySolid.opacity(0.35).ignoresSafeArea()
                .onTapGesture { stage = nil }
                .accessibilityHidden(true)
            InstallStageSheet(row: row, count: g.rows.count, index: (g.rows.firstIndex { $0.id == row.id } ?? 0) + 1,
                              photos: photos(for: row), cause: cause(row.id), setCause: { setCause($0, task: row.id) },
                              confirmation: job.scheduleActual.confirmations.last { $0.task == row.id }, close: { stage = nil },
                              openDaily: { stage = nil; route = .day(RoutineReport.calendar.startOfDay(for: .now)) },
                              wbs: wbsItems(row.id), ticks: job.wbsTicks, canTick: permissions.mayTickWBS(on: job.access),
                              canTakeBack: { permissions.mayTakeBack($0, on: job.access) },
                              canEditWBS: permissions.can(.mpSetup, on: job.access),
                              toggleWBS: toggleWBS, setDocument: setWBSDocument, updateWBSItem: updateWBSItem)
        }
        .transition(.opacity)
    }

    /// The task's WBS sub-tasks, without the other case's rows.
    private func wbsItems(_ task: String) -> [MasterSchedule.WorkItem] {
        guard let t = MasterSchedule.Task(rawValue: task) else { return [] }
        return job.scheduleWBS.items(for: t).filter { !$0.notForThisStation }
    }

    /// Ticks a WBS row done today, or takes the tick back; the job books it into the plan (`Job.wbsTicks`). A contractor's
    /// device sends it signed with their email.
    private func toggleWBS(_ item: MasterSchedule.WorkItem) {
        var ticks = job.wbsTicks
        if let tick = ticks[item.code] {
            guard permissions.mayTakeBack(tick, on: job.access) else { return }
            ticks[item.code] = nil
        } else {
            guard permissions.mayTickWBS(on: job.access) else { return }
            ticks[item.code] = .init(by: permissions.email, at: MasterSchedule.calendar.startOfDay(for: .now))
        }
        saveWBS(ticks)
    }

    private func setWBSDocument(_ item: MasterSchedule.WorkItem, _ text: String) {
        var ticks = job.wbsTicks
        guard let tick = ticks[item.code], permissions.mayTakeBack(tick, on: job.access) else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        ticks[item.code]?.document = t.isEmpty ? nil : t
        saveWBS(ticks)
    }

    private func saveWBS(_ ticks: [String: MasterSchedule.WBSTick]) {
        job.wbsTicks = ticks
        if permissions.role == .external { job.wbsTicksUnsent = true }
        try? context.save()
    }

    private func updateWBSItem(_ updated: MasterSchedule.WorkItem) {
        guard permissions.can(.mpSetup, on: job.access) else { return }
        var rows = job.scheduleWBS
        guard let i = rows.firstIndex(where: { $0.code == updated.code }) else { return }
        rows[i] = updated
        job.scheduleWBS = rows
        try? context.save()
    }

    private func cause(_ task: String) -> MasterSchedule.LateCause? {
        #if DEBUG
        if Debug.demo { return demoCauses[task] }
        #endif
        return job.scheduleActual.lateCauses[task]
    }

    /// Keeps the cause in the job's MP actual, which syncs with the plan.
    private func setCause(_ c: MasterSchedule.LateCause?, task: String) {
        #if DEBUG
        if Debug.demo { demoCauses[task] = c; return }
        #endif
        var a = job.scheduleActual
        a.lateCauses[task] = c
        job.scheduleActual = a
        try? context.save()
    }

    /// The daily reports' photos tagged with a progress line of the task.
    func photos(for row: InstallGantt.Row) -> [Data] {
        guard let task = MasterSchedule.Task(rawValue: row.id) else { return [] }
        return job.dailyLogs.flatMap { log -> [Data] in
            guard let r = log.report else { return [] }
            let lines = Set(r.progress.filter { $0.task == task }.map(\.id.uuidString))
            return log.sortedPhotos.filter { lines.contains($0.tag) }.map(\.data)
        }
    }
}
