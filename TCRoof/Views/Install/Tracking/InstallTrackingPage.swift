import SwiftUI
import TCRoofUI
import TCRoofCore

/// The iPad install tracking page of one station (docs/ui/install-tracking-ipad): the blue header, the project's tab
/// bar and, on `ภาพรวม`, the KPI strip. It is pushed over the PWA home and keeps the dock. `ภาพรวม` and
/// `รายงานประจำวัน` change the page in place; the other tabs push the screens that exist.
struct InstallTrackingPage: View {
    enum Tab: String, CaseIterable { case overview, daily, plan }

    /// A screen the page pushes.
    enum Route: Hashable { case request, weekly, docs, plan, dailies, day(Date), survey(UUID), detail, iec, devices }

    let job: Job
    @State var tab = Debug.tab
    @State var view = Debug.view
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
    @State var shared: Shared?
    /// `แผนก่อสร้าง`'s plan file: import and export of the station's own workbook.
    @State var workbook = MPWorkbookFlow()
    @Environment(\.permissions) var permissions
    /// The debug flags apply once: `.task` runs again each time the page reappears (back from a pushed screen).
    @State private var debugApplied = false
    /// ผู้ช่วยโครงการ, opened on this station.
    @State var assistant = false
    /// `-installDemo YES` keeps its picked late causes here instead of in a job.
    @State private var demoCauses: [String: MasterSchedule.LateCause] = [:]
    @State private var survey = SurveyModel.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) var context
    @Environment(\.horizontalSizeClass) private var sizeClass

    // iPhone (docs/ui/install-tracking-iphone): every tab in place, and the header's gear
    @State var phoneTab = Debug.phoneTab
    @State var phoneSettings = Debug.settings
    @State var settingsCategory: SettingsCategory? = Debug.settingsCategory
    /// `แผนก่อสร้าง`'s edit mode: the stages' new start and days by id, and the reason.
    @State var planEditing = false
    @State var planDraft: [String: PlanDraft] = [:]
    @State var planReason = ""
    /// `คำขอรายสัปดาห์` and `Weekly Report`: weeks from their default one.
    @State var requestWeek = 0
    @State var reportWeek = 0
    /// `เอกสาร`'s selected permit stage.
    @State var docsStage: StationDocs.Package?
    /// The phone page's pushed screens that the iPad routes don't cover.
    @State var phoneRoute: PhoneRoute?
    @State var phoneSheet: PhoneSheet?

    var body: some View {
        let data = self.data
        Group {
            if sizeClass == .compact { phoneBody(data) } else { padBody(data) }
        }
        .overlay { if let row = stage, let g = data.gantt { stageSheet(row, g) } }
        .overlay { if let s = sheet { pageSheet(s, data) } }
        .sheet(item: $shared) { ActivitySheet(items: [$0.url]) }
        .sheet(isPresented: $assistant) { AssistantChatView(focus: job) }
        .mpWorkbook(workbook, job: job)
        #if DEBUG
        // `-installStage n` opens the nth task's sheet
        .task {
            guard !debugApplied else { return }
            debugApplied = true
            // `-installDetail YES` opens รายละเอียดงาน
            if Debug.detail { route = .detail }
            // `-iecOpen YES` opens ทดสอบ IEC 62446
            if Debug.iec { route = .iec }
            // `-installPlanEdit YES` opens แผนก่อสร้าง's edit mode (iPhone)
            if Debug.planEdit, sizeClass == .compact { startPlanEdit(data) }
            guard let n = Debug.stage, let rows = data.gantt?.rows, rows.indices.contains(n - 1) else { return }
            stage = rows[n - 1]
        }
        #endif
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $route) { destination($0) }
        .navigationDestination(item: $phoneRoute) { phoneDestination($0) }
    }

    /// The iPad page (docs/ui/install-tracking-ipad, -v2).
    private func padBody(_ data: InstallPageData) -> some View {
        VStack(spacing: 0) {
            header(data)
            tabBar(data)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch tab {
                        case .overview:
                            kpiStrip(data)
                            if let g = data.gantt { progressCard(data, g) }
                            siteRow(data)
                        case .daily:
                            dailyTab(dailyData, site: data.site)
                        case .plan:
                            planTab(data)
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
        .background(Theme.phonePage.ignoresSafeArea())
        .padDock(fade: nil)
    }

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
                              openDaily: { stage = nil; route = .day(RoutineReport.calendar.startOfDay(for: .now)) })
        }
        .transition(.opacity)
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

    // MARK: header

    private func header(_ data: InstallPageData) -> some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.onPrimary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.onPrimary.opacity(0.6)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("กลับหน้ารายการงาน")
            VStack(alignment: .leading, spacing: 0) {
                Text(data.title).font(.sarabunFixed(22, .bold)).frame(height: 28)
                    .accessibilityAddTraits(.isHeader)
                Text(data.subtitle).font(.sarabunFixed(15)).opacity(0.92).frame(height: 20)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            // the job's own screen: customer, schedule, scans, install logs, ICL, R4, survey link, documents and Drive
            if permissions.can(.assistantUse), job.scheduleInput != nil {
                headerButton("ผู้ช่วย AI", "sparkles", primary: true) { assistant = true }
            }
            headerButton("รายละเอียดงาน", "info.circle") { route = .detail }
            if let id = data.surveyReport {
                headerButton("รายงานสำรวจ", "lock", accessibility: "รายงานสำรวจ (ดูอย่างเดียว)") { route = .survey(id) }
            }
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
    }

    /// A button on the blue header: outlined, or filled white with a blue label (`primary`, the board's `ผู้ช่วย AI`).
    private func headerButton(_ title: String, _ symbol: String, primary: Bool = false, accessibility: String? = nil,
                              action: @escaping () -> Void) -> some View {
        let frame = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.sarabunFixed(15, primary ? .bold : .semibold))
                .foregroundStyle(primary ? Theme.primary : Theme.onPrimary)
                .padding(.horizontal, 16).frame(height: 44)
                .background(primary ? Theme.surface : Theme.onPrimary.opacity(0.14), in: frame)
                .overlay { if !primary { frame.strokeBorder(Theme.onPrimary.opacity(0.6)) } }
                .shadow(color: primary ? Theme.navySolid.opacity(0.18) : .clear, radius: 4, y: 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(accessibility ?? title)
    }

    // MARK: tabs

    /// One tab of the bar: in place (`tab`) or a pushed screen (`route`).
    struct Item: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var tab: Tab? = nil
        var route: Route? = nil
        var dot = false
    }

    func items(_ data: InstallPageData) -> [Item] {
        [Item(id: "overview", title: "ภาพรวม", symbol: "chart.line.uptrend.xyaxis", tab: .overview),
         Item(id: "daily", title: "รายงานประจำวัน", symbol: "list.clipboard", tab: .daily, dot: data.dailyUnsent),
         Item(id: "request", title: "คำขอรายสัปดาห์", symbol: "calendar", route: .request),
         Item(id: "weekly", title: "Weekly Report", symbol: "doc.text", route: .weekly),
         Item(id: "iec", title: "ทดสอบ IEC 62446", symbol: "bolt", route: .iec),
         Item(id: "docs", title: "เอกสาร", symbol: "doc.text", route: .docs),
         Item(id: "plan", title: "แผนก่อสร้าง", symbol: "slider.horizontal.3", tab: .plan)]
    }

    private func tabBar(_ data: InstallPageData) -> some View {
        HStack(spacing: 4) {
            ForEach(items(data)) { item in
                let on = item.tab != nil && item.tab == tab
                Button {
                    if let t = item.tab { tab = t } else { route = item.route }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item.symbol).font(.system(size: 16, weight: .semibold))
                        Text(item.title).font(.sarabunFixed(15, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                        if item.dot {
                            Circle().fill(Theme.warning).frame(width: 8, height: 8).accessibilityLabel("วันนี้ยังไม่ส่ง")
                        }
                    }
                    .foregroundStyle(on ? Theme.navy : Theme.projectTabInk)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.surface)
                                .shadow(color: Theme.navySolid.opacity(0.15), radius: 1.5, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.projectTabTrack, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 24).padding(.top, 12)
    }

    // MARK: KPI strip

    struct Cell: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let ink: Color
        let note: String
        /// Its share of the strip's width, as on the board.
        let weight: CGFloat
        /// `ต้องดำเนินการ`: tapped, it opens the open items' sheet.
        var opensActions = false
    }

    /// `ความคืบหน้า | กำหนดการ | คาดส่งมอบ | SPI | ต้องดำเนินการ`. Without an MP plan only the open items are left.
    func cells(_ data: InstallPageData) -> [Cell] {
        var out: [Cell] = []
        if let t = data.tracking {
            let gain = t.gainThisWeek.map { " | ▲\($0)% สัปดาห์นี้" } ?? ""
            out.append(Cell(label: "ความคืบหน้า", value: "\(Int(t.actual.rounded()))%", ink: Theme.primary,
                            note: "แผน \(Int(t.planned.rounded()))%" + gain, weight: 1.45))
            let (title, ink): (String, Color) = switch t.schedule {
            case .onPlan: ("ตามแผน", Theme.successInk)
            case .behind: ("ช้ากว่าแผน", Theme.dangerText)
            case .ahead: ("เร็วกว่าแผน", Theme.primary)
            }
            out.append(Cell(label: "กำหนดการ", value: title, ink: ink, note: (t.variance > 0 ? "+" : "") + "\(t.variance)%", weight: 0.85))
            let slack = t.slackDays()
            out.append(Cell(label: "คาดส่งมอบ", value: ThaiFormat.dayMonth.string(from: t.forecastEnd()),
                            ink: slack < 0 ? Theme.dangerText : slack == 0 ? Theme.pending : Theme.navy,
                            note: slack < 0 ? "ช้า \(-slack) วัน" : slack == 0 ? "ตามกำหนดพอดี" : "ตามกำหนด เผื่อ \(slack) วัน", weight: 1.12))
            if let spi = t.spi {
                out.append(Cell(label: "SPI", value: spi.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US"))),
                                ink: spi >= 0.95 ? Theme.successInk : Theme.dangerText, note: spi >= 0.95 ? "ปกติ" : "ต่ำกว่าแผน", weight: 0.68))
            }
        }
        let open = data.actions
        out.append(Cell(label: "ต้องดำเนินการ", value: open.isEmpty ? "ไม่มี" : "\(open.count) เรื่อง", ink: open.isEmpty ? Theme.successInk : Theme.pending,
                        note: open.prefix(3).map(\.title).joined(separator: " | "), weight: 1.4, opensActions: !open.isEmpty))
        return out
    }

    private func kpiStrip(_ data: InstallPageData) -> some View {
        let cells = cells(data), total = cells.reduce(0) { $0 + $1.weight }
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.element.id) { i, c in
                    HStack(spacing: 8) {
                        Text(c.label).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize()
                        // a long value (`ช้ากว่าแผน`) gives way before a short note (`-6%`) does
                        Text(c.value).font(.sarabunFixed(18, .bold)).foregroundStyle(c.ink).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
                        Text(c.note).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                            .layoutPriority(c.note.count <= 6 ? 2 : 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: g.size.width * c.weight / total, height: g.size.height, alignment: .leading)
                    .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Theme.hairline).frame(width: 1) } }
                    .contentShape(Rectangle())
                    .onTapGesture { if c.opensActions { sheet = .actions } }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(c.opensActions ? .isButton : [])
                }
            }
        }
        .frame(height: 52)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .cardShadow()
    }

    // MARK: DEBUG

    /// `-installTab overview|daily|plan`, `-installView gantt|curve`, `-installPlanView gantt|table`, `-installPlanCollapsed
    /// YES`, `-installStage n`, `-installDemo YES`, `-installSheet actions|<tile id>`, `-installSite info|risk|labour`,
    /// `-installScrollEnd YES`, `-installDetail YES`. Release builds get the defaults.
    enum Debug {
        #if DEBUG
        static let tab = UserDefaults.standard.string(forKey: "installTab").flatMap(Tab.init) ?? .overview
        static let view = UserDefaults.standard.string(forKey: "installView").flatMap(ProgressView.init) ?? .gantt
        static let planView = UserDefaults.standard.string(forKey: "installPlanView").flatMap(PlanView.init) ?? .gantt
        static let planCollapsed = UserDefaults.standard.bool(forKey: "installPlanCollapsed")
        static let stage: Int? = UserDefaults.standard.object(forKey: "installStage") == nil ? nil : UserDefaults.standard.integer(forKey: "installStage")
        /// `-installDemo YES`, or `late` for a station behind its plan (iPhone board state 02).
        static let demo = UserDefaults.standard.bool(forKey: "installDemo") || demoLate
        static let demoLate = UserDefaults.standard.string(forKey: "installDemo") == "late"
        /// `-installDailyFilter todo|problem` (iPhone): `รายงานประจำวัน`'s filter.
        static let dailyFilter = ["todo": 1, "problem": 2][UserDefaults.standard.string(forKey: "installDailyFilter") ?? ""] ?? 0
        static let sheet: Sheet? = UserDefaults.standard.string(forKey: "installSheet").map { $0 == "actions" ? .actions : .doc($0) }
        static let site = UserDefaults.standard.string(forKey: "installSite").flatMap(SiteTab.init) ?? .info
        static let scrollEnd = UserDefaults.standard.bool(forKey: "installScrollEnd")
        static let detail = UserDefaults.standard.bool(forKey: "installDetail")
        static let iec = UserDefaults.standard.bool(forKey: "iecOpen")
        /// iPhone: `-installTab request|weekly|iec|docs|settings` too, `-installSettings team|routine|connection` and
        /// `-installPlanEdit YES`.
        static let phoneTab = UserDefaults.standard.string(forKey: "installTab").flatMap(PhoneTab.init) ?? .overview
        static let settings = UserDefaults.standard.string(forKey: "installTab") == "settings" || settingsCategory != nil
        static let settingsCategory = UserDefaults.standard.string(forKey: "installSettings").flatMap(SettingsCategory.init)
        static let planEdit = UserDefaults.standard.bool(forKey: "installPlanEdit")
        #else
        static let phoneTab = PhoneTab.overview
        static let settings = false
        static let settingsCategory: SettingsCategory? = nil
        static let demo = false
        static let dailyFilter = 0
        static let tab = Tab.overview
        static let view = ProgressView.gantt
        static let planView = PlanView.gantt
        static let planCollapsed = false
        static let sheet: Sheet? = nil
        static let site = SiteTab.info
        #endif
    }
}
