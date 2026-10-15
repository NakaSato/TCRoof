import SwiftUI
import TCRoofUI
import TCRoofCore

/// The iPad install tracking page of one station (docs/ui/install-tracking-ipad): the blue header, the project's tab
/// bar and, on `ภาพรวม`, the KPI strip. It is pushed over the PWA home and keeps the dock. `ภาพรวม` and
/// `รายงานประจำวัน` change the page in place; the other tabs push the screens that exist.
struct InstallTrackingPage: View {
    enum Tab: String, CaseIterable { case overview, daily }

    /// A screen the page pushes.
    enum Route: Hashable { case request, weekly, docs, plan, dailies, day(Date), survey(UUID), detail, iec }

    let job: Job
    @State var tab = Debug.tab
    @State var view = Debug.view
    /// Task rows opened or closed against their default (the running task starts open).
    @State var toggled: Set<String> = []
    /// The task whose sheet is open.
    @State var stage: InstallGantt.Row?
    @State var route: Route?
    @State var sheet: Sheet? = Debug.sheet
    @State var siteTab = Debug.site
    /// `ทุกรายงาน`'s segment: all, to do, with a problem.
    @State var dailyFilter = 0
    @State var shared: Shared?
    /// The debug flags apply once: `.task` runs again each time the page reappears (back from a pushed screen).
    @State private var debugApplied = false
    /// `-installDemo YES` keeps its picked late causes here instead of in a job.
    @State private var demoCauses: [String: MasterSchedule.LateCause] = [:]
    @State private var survey = SurveyModel.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        let data = self.data
        VStack(spacing: 0) {
            header(data)
            tabBar(data)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if tab == .overview {
                            kpiStrip(data)
                            if let g = data.gantt { progressCard(data, g) }
                            siteRow(data)
                        } else {
                            dailyTab(dailyData, site: data.site)
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 24)
                    Color.clear.frame(height: 1).id("end")
                }
                .scrollIndicators(.hidden)
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
        .overlay { if let row = stage, let g = data.gantt { stageSheet(row, g) } }
        .overlay { if let s = sheet { pageSheet(s, data) } }
        .sheet(item: $shared) { ActivitySheet(items: [$0.url]) }
        #if DEBUG
        // `-installStage n` opens the nth task's sheet
        .task {
            guard !debugApplied else { return }
            debugApplied = true
            // `-installDetail YES` opens รายละเอียดงาน
            if Debug.detail { route = .detail }
            // `-iecOpen YES` opens ทดสอบ IEC 62446
            if Debug.iec { route = .iec }
            guard let n = Debug.stage, let rows = data.gantt?.rows, rows.indices.contains(n - 1) else { return }
            stage = rows[n - 1]
        }
        #endif
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $route) { destination($0) }
    }

    private var data: InstallPageData {
        #if DEBUG
        if Debug.demo { return .demo() }
        #endif
        return InstallPageData(job: job, survey: survey)
    }

    @ViewBuilder private func destination(_ r: Route) -> some View {
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
        }
    }

    /// The task's sheet over a dimmed page, dock included.
    private func stageSheet(_ row: InstallGantt.Row, _ g: InstallGantt) -> some View {
        ZStack {
            Theme.navySolid.opacity(0.35).ignoresSafeArea()
                .onTapGesture { stage = nil }
                .accessibilityHidden(true)
            InstallStageSheet(row: row, count: g.rows.count, index: (g.rows.firstIndex { $0.id == row.id } ?? 0) + 1,
                              photos: photos(for: row), cause: cause(row.id), setCause: { setCause($0, task: row.id) }, close: { stage = nil },
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
    private func photos(for row: InstallGantt.Row) -> [Data] {
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
            headerButton("รายละเอียดงาน", "info.circle") { route = .detail }
            if let id = data.surveyReport {
                headerButton("รายงานสำรวจ (ดูอย่างเดียว)", "lock") { route = .survey(id) }
            }
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
    }

    /// An outlined button on the blue header.
    private func headerButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.sarabunFixed(15, .semibold))
                .padding(.horizontal, 16).frame(height: 44)
                .background(Theme.onPrimary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.onPrimary.opacity(0.6)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    // MARK: tabs

    /// One tab of the bar: in place (`tab`) or a pushed screen (`route`).
    private struct Item: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var tab: Tab? = nil
        var route: Route? = nil
        var dot = false
    }

    private func items(_ data: InstallPageData) -> [Item] {
        [Item(id: "overview", title: "ภาพรวม", symbol: "chart.line.uptrend.xyaxis", tab: .overview),
         Item(id: "daily", title: "รายงานประจำวัน", symbol: "list.clipboard", tab: .daily, dot: data.dailyUnsent),
         Item(id: "request", title: "คำขอรายสัปดาห์", symbol: "calendar", route: .request),
         Item(id: "weekly", title: "Weekly Report", symbol: "doc.text", route: .weekly),
         Item(id: "iec", title: "ทดสอบ IEC 62446", symbol: "bolt", route: .iec),
         Item(id: "docs", title: "เอกสาร", symbol: "doc.text", route: .docs),
         Item(id: "plan", title: "แผนก่อสร้าง", symbol: "slider.horizontal.3", route: .plan)]
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

    private struct Cell: Identifiable {
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

    /// `ความคืบหน้า · กำหนดการ · คาดส่งมอบ · SPI · ต้องดำเนินการ`. Without an MP plan only the open items are left.
    private func cells(_ data: InstallPageData) -> [Cell] {
        var out: [Cell] = []
        if let t = data.tracking {
            let gain = t.gainThisWeek.map { " · ▲\($0)% สัปดาห์นี้" } ?? ""
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
                        note: open.prefix(3).map(\.title).joined(separator: " · "), weight: 1.4, opensActions: !open.isEmpty))
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

    /// `-installTab overview|daily`, `-installView gantt|curve`, `-installStage n`, `-installDemo YES`, `-installSheet
    /// actions|<tile id>`, `-installSite info|risk|labour`, `-installScrollEnd YES`, `-installDetail YES`. Release builds
    /// get the defaults.
    enum Debug {
        #if DEBUG
        static let tab = UserDefaults.standard.string(forKey: "installTab").flatMap(Tab.init) ?? .overview
        static let view = UserDefaults.standard.string(forKey: "installView").flatMap(ProgressView.init) ?? .gantt
        static let stage: Int? = UserDefaults.standard.object(forKey: "installStage") == nil ? nil : UserDefaults.standard.integer(forKey: "installStage")
        static let demo = UserDefaults.standard.bool(forKey: "installDemo")
        static let sheet: Sheet? = UserDefaults.standard.string(forKey: "installSheet").map { $0 == "actions" ? .actions : .doc($0) }
        static let site = UserDefaults.standard.string(forKey: "installSite").flatMap(SiteTab.init) ?? .info
        static let scrollEnd = UserDefaults.standard.bool(forKey: "installScrollEnd")
        static let detail = UserDefaults.standard.bool(forKey: "installDetail")
        static let iec = UserDefaults.standard.bool(forKey: "iecOpen")
        #else
        static let tab = Tab.overview
        static let view = ProgressView.gantt
        static let sheet: Sheet? = nil
        static let site = SiteTab.info
        #endif
    }
}
