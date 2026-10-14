import SwiftUI
import TCRoofUI
import TCRoofCore

/// The iPad install tracking page of one station (docs/ui/install-tracking-ipad): the blue header, the project's tab
/// bar and, on `ภาพรวม`, the KPI strip. It is pushed over the PWA home and keeps the dock. `ภาพรวม` and
/// `รายงานประจำวัน` change the page in place; the other tabs push the screens that exist.
struct InstallTrackingPage: View {
    enum Tab: String, CaseIterable { case overview, daily }

    /// A screen the page pushes.
    enum Route: Hashable { case request, weekly, docs, plan, dailies, day(Date), survey(UUID) }

    let job: Job
    @State var tab = Debug.tab
    @State var view = Debug.view
    /// Task rows opened or closed against their default (the running task starts open).
    @State var toggled: Set<String> = []
    /// The task whose sheet is open.
    @State var stage: InstallGantt.Row?
    @State private var route: Route?
    @State private var survey = SurveyModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let data = self.data
        VStack(spacing: 0) {
            header(data)
            tabBar(data)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tab == .overview {
                        kpiStrip(data)
                        if let g = data.gantt { progressCard(data, g) }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .padDock(fade: nil)
        .overlay { if let row = stage, let g = data.gantt { stageSheet(row, g) } }
        #if DEBUG
        // `-installStage n` opens the nth task's sheet
        .task {
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
        }
    }

    /// The task's sheet over a dimmed page, dock included.
    private func stageSheet(_ row: InstallGantt.Row, _ g: InstallGantt) -> some View {
        ZStack {
            Theme.navySolid.opacity(0.35).ignoresSafeArea()
                .onTapGesture { stage = nil }
                .accessibilityHidden(true)
            InstallStageSheet(row: row, count: g.rows.count, index: (g.rows.firstIndex { $0.id == row.id } ?? 0) + 1,
                              photos: photos(for: row), close: { stage = nil },
                              openDaily: { stage = nil; route = .day(RoutineReport.calendar.startOfDay(for: .now)) })
        }
        .transition(.opacity)
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
            if let id = data.surveyReport {
                Button { route = .survey(id) } label: {
                    Label("รายงานสำรวจ (ดูอย่างเดียว)", systemImage: "lock")
                        .font(.sarabunFixed(15, .semibold))
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(Theme.onPrimary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.onPrimary.opacity(0.6)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .foregroundStyle(Theme.onPrimary)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 14)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15, style: .continuous)
                .fill(Theme.headerGradient).ignoresSafeArea(edges: .top)
        }
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

    /// `ทดสอบ IEC 62446` is left out: the app has no IEC test screen yet.
    private func items(_ data: InstallPageData) -> [Item] {
        [Item(id: "overview", title: "ภาพรวม", symbol: "chart.line.uptrend.xyaxis", tab: .overview),
         Item(id: "daily", title: "รายงานประจำวัน", symbol: "list.clipboard", tab: .daily, dot: data.dailyUnsent),
         Item(id: "request", title: "คำขอรายสัปดาห์", symbol: "calendar", route: .request),
         Item(id: "weekly", title: "Weekly Report", symbol: "doc.text", route: .weekly),
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
                        note: open.prefix(3).map(\.title).joined(separator: " · "), weight: 1.4))
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
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(height: 52)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .cardShadow()
    }

    // MARK: DEBUG

    /// `-installTab overview|daily`, `-installView gantt|curve`, `-installStage n`, `-installDemo YES`. Release builds
    /// get the defaults.
    enum Debug {
        #if DEBUG
        static let tab = UserDefaults.standard.string(forKey: "installTab").flatMap(Tab.init) ?? .overview
        static let view = UserDefaults.standard.string(forKey: "installView").flatMap(ProgressView.init) ?? .gantt
        static let stage: Int? = UserDefaults.standard.object(forKey: "installStage") == nil ? nil : UserDefaults.standard.integer(forKey: "installStage")
        static let demo = UserDefaults.standard.bool(forKey: "installDemo")
        #else
        static let tab = Tab.overview
        static let view = ProgressView.gantt
        #endif
    }
}
