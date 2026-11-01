import SwiftUI
import TCRoofUI
import TCRoofCore

extension InstallTrackingPage {
    // MARK: header

    func header(_ data: InstallPageData) -> some View {
        HStack(spacing: 14) {
            Button { leave(to: .back) } label: {
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
        let all = [Item(id: "overview", title: "ภาพรวม", symbol: "chart.line.uptrend.xyaxis", tab: .overview),
         Item(id: "daily", title: "รายงานประจำวัน", symbol: "list.clipboard", tab: .daily, dot: data.dailyUnsent),
         // the one-page request in the page (docs/ui/install-tracking-ipad-request-map), the R1 form below 1000 pt
         Item(id: "request", title: "คำขอรายสัปดาห์", symbol: "calendar", tab: .request),
         Item(id: "weekly", title: "Weekly Report", symbol: "doc.text", tab: .weekly),
         Item(id: "iec", title: "ทดสอบ IEC 62446", symbol: "bolt", tab: .iec),
         Item(id: "docs", title: "เอกสาร", symbol: "doc.text", tab: .docs),
         Item(id: "plan", title: "แผนก่อสร้าง", symbol: "slider.horizontal.3", tab: .plan),
         Item(id: "settings", title: "ตั้งค่าโครงการ", symbol: "gearshape", tab: .settings)]
        return all.filter { item in item.tab.map(canOpen) ?? true }
    }

    /// External users can work in the daily report, weekly request and IEC tabs, but the four team-only tabs stay hidden.
    func canOpen(_ tab: Tab) -> Bool {
        guard permissions.role == .external else { return true }
        return ![Tab.weekly, .docs, .plan, .settings].contains(tab)
    }

    func enforceRoleTabAccess() {
        guard permissions.role == .external else { return }
        if !canOpen(tab) { tab = .overview }
        if [.weekly, .docs, .plan].contains(phoneTab) { phoneTab = .overview }
        phoneSettings = false
    }

    func tabBar(_ data: InstallPageData) -> some View {
        HStack(spacing: 4) {
            ForEach(items(data)) { item in
                let on = item.tab != nil && item.tab == tab
                Button {
                    if let t = item.tab { leave(to: .tab(t)) } else if let r = item.route { leave(to: .route(r)) }
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
            out.append(Cell(label: "คาดส่งมอบ", value: Self.forecastDay(t),
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

    func kpiStrip(_ data: InstallPageData) -> some View {
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

    /// `-installTab overview|daily|plan|docs|request|weekly|settings`, `-installSettings team|header|drawings|routine|connection|reference`,
    /// `-installSettingsState edit|dirty|history|upload|person`, `-installReportWeek n`, `-installReportSlide 1…8`,
    /// `-installReportState ready|menu|pptx|sent`, `-installRequestWeek n`, `-installRequestState …`, `-installDocsPackage building|grid_connection|pk2`, `-installDocsPaper <kind id>`,
    /// `-installView gantt|curve|keyplan` (`-installKeyPlanState selected|placing|placed`), `-installPlanView gantt|table`, `-installPlanCollapsed
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
        static let docsPackage = UserDefaults.standard.string(forKey: "installDocsPackage").flatMap(StationDocs.Package.init)
        /// `-installRequestWeek 0|1|2`: next week, the week before, the one before that.
        static let requestWeek = -UserDefaults.standard.integer(forKey: "installRequestWeek")
        /// `-installRequestState sign|signed|sent|approved|pdf|edited`.
        static let requestState = UserDefaults.standard.string(forKey: "installRequestState")
        /// `-installRequestForm YES`: `คำขอรายสัปดาห์` keeps the R1 form at any width (the simulator can't be turned).
        static let requestForm = UserDefaults.standard.bool(forKey: "installRequestForm")
        static let docsPaper = UserDefaults.standard.string(forKey: "installDocsPaper")
        /// `-installReportWeek 0|1|2`: the week being reported or one of the two before.
        static let reportWeek = -UserDefaults.standard.integer(forKey: "installReportWeek")
        /// `-installReportSlide n`: the deck's nth slide.
        static let reportSlide = max(0, UserDefaults.standard.integer(forKey: "installReportSlide") - 1)
        /// `-installReportState ready|menu|pptx|sent`.
        static let reportState = UserDefaults.standard.string(forKey: "installReportState")
        /// iPhone: `-installTab request|weekly|iec|docs|settings` too, `-installSettings team|routine|connection` and
        /// `-installPlanEdit YES`.
        static let phoneTab = UserDefaults.standard.string(forKey: "installTab").flatMap(PhoneTab.init) ?? .overview
        static let settings = UserDefaults.standard.string(forKey: "installTab") == "settings" || settingsCategory != nil
        static let settingsCategory = UserDefaults.standard.string(forKey: "installSettings").flatMap(SettingsCategory.init)
        static let planEdit = UserDefaults.standard.bool(forKey: "installPlanEdit")
        /// iPad: `-installSettings team|header|drawings|routine|connection|reference` picks `ตั้งค่าโครงการ`'s category.
        static let padCategory = UserDefaults.standard.string(forKey: "installSettings").flatMap(PadSettingsCategory.init) ?? .team
        /// iPad, with `-installDemo YES`: `-installSettingsState edit|dirty|history|upload|person` opens states 09–13.
        static let settingsState = UserDefaults.standard.string(forKey: "installSettingsState")
        #else
        static let padCategory = PadSettingsCategory.team
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
        static let docsPackage: StationDocs.Package? = nil
        static let docsPaper: String? = nil
        static let requestWeek = 0
        static let requestForm = false
        static let reportWeek = 0
        static let reportSlide = 0
        #endif
    }
}
