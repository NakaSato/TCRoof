import SwiftUI
import TCRoofUI
import TCRoofCore
import PDFReport

/// Extension on `InstallTrackingPage` for opening the isolated iPad plan tab.
extension InstallTrackingPage {
    enum PlanView: String { case gantt, table }

    @ViewBuilder func planTab(_ data: InstallPageData) -> some View {
        InstallPlanTabView(
            job: job,
            data: data,
            viewport: viewport,
            viewportInset: viewportInset,
            route: $route,
            showWBSDependencies: $showWBSDependencies,
            workbook: $workbook
        )
    }

    /// A row's slip from its baseline: red when later, green otherwise, a dash without one.
    static func slipLabel(_ slip: Int?) -> some View {
        Text(slip.map(InstallPlan.slipText) ?? "–")
            .foregroundStyle(slip.map { $0 > 0 ? Theme.dangerText : Theme.successInk } ?? Theme.inkMuted)
    }

    func slipLabel(_ slip: Int?) -> some View {
        Self.slipLabel(slip)
    }
}

/// `แผนก่อสร้าง` (docs/ui/install-tracking-ipad-v2 §6, `states/05`–`07`): the install plan by WBS as a Gantt or a table,
/// with the critical path outlined and the sub-tasks' float dotted, and beside it the planned crew, the milestones and
/// the next stage's make-ready. `แก้ไขแผน` opens the MP plan screen. Crew, links, the baseline and the make-ready show
/// only when there is a source (`InstallPlan`).
struct InstallPlanTabView: View {
    let job: Job
    let data: InstallPageData
    let viewport: CGFloat
    let viewportInset: CGFloat
    @Binding var route: InstallTrackingPage.Route?
    @Binding var showWBSDependencies: Bool
    @Binding var workbook: MPWorkbookFlow

    @State var planView = InstallTrackingPage.Debug.planView
    @State var planToggled: Set<String> = []
    @State var planAllClosed = InstallTrackingPage.Debug.planCollapsed
    @State private var shared: InstallTrackingPage.Shared?
    @State private var zoomLevel: InstallAxis.Unit = .week
    @State private var showMilestones: Bool = true
    @State private var compactTaskCol: Bool = false
    @State private var scrollPos = ScrollPosition()
    /// The header as laid out (two rows; taller when its chips or buttons wrap).
    @State private var headerHeight: CGFloat = InstallPlanTabView.planHeaderHeight
    /// The timeline's sideways position: opened at today (CHA-64).
    @State private var timelinePos = ScrollPosition()

    @Environment(\.permissions) var permissions

    static let planHeaderHeight: CGFloat = 114
    static let planSideWidth: CGFloat = 280
    /// The grid's columns before the days.
    enum PlanCol {
        static let wbs: CGFloat = 44, days: CGFloat = 58, crew: CGFloat = 44, after: CGFloat = 60, left: CGFloat = 340
        static let stageRow: CGFloat = 40, subRow: CGFloat = 32
    }

    private func currentTaskColWidth(_ p: InstallPlan) -> CGFloat {
        let base: CGFloat = compactTaskCol ? 260 : 330
        let extraCrew: CGFloat = showsCrew(p) ? PlanCol.crew : 0
        let extraAfter: CGFloat = showsLinks(p) ? PlanCol.after : 0
        return base + extraCrew + extraAfter
    }

    var body: some View {
        if let p = data.plan, let g = data.gantt {
            // the card fills the page down to the dock (CHA-64): the scroll view's height less its own bottom inset (the
            // dock when it runs under it, none when it already ends above it) and a margin, with the header as measured;
            // a fixed dock clearance counted the dock twice when the scroll view ended above it
            let body = max(viewport - 14 - headerHeight - 14 - viewportInset - 16, 440)
            let axis = InstallAxis(g, forecast: p, explicitUnit: zoomLevel)
            VStack(alignment: .leading, spacing: 14) {
                planHeader(p, axis: axis)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                if !p.dependencyIssues.isEmpty {
                    Text(p.dependencyIssues.map(\.message).joined(separator: "\n")).foregroundStyle(Theme.dangerText)
                }
                HStack(alignment: .top, spacing: 14) {
                    Group {
                        if planView == .gantt {
                            planGantt(p, axis: axis, waitLabel: data.waitLabel)
                        } else {
                            planTable(p)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: body)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .cardShadow()

                    if showMilestones {
                        planSide(p)
                            .frame(width: Self.planSideWidth, height: body)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .sheet(item: $shared) { ActivitySheet(items: [$0.url]) }
        } else {
            VStack(spacing: 16) {
                TCEmptyState("ยังไม่มีแผน MP", systemImage: "calendar", description: Text("สร้างแผนจากการ์ดแผนงาน MP ของงาน หรือนำเข้าไฟล์แผนของสถานี"))
                if permissions.can(.mpSetup) {
                    Button { workbook.startImport() } label: { Label("นำเข้าไฟล์แผน (Excel)", systemImage: "square.and.arrow.down") }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private func planOpen(_ s: InstallPlan.Stage, _ p: InstallPlan) -> Bool {
        let byDefault = !planAllClosed && (s.row.status == .current || s.id == p.nextStage?.id)
        return !s.subs.isEmpty && (byDefault != planToggled.contains(s.id))
    }

    private func togglePlan(_ id: String) {
        if planToggled.contains(id) { planToggled.remove(id) } else { planToggled.insert(id) }
    }

    // MARK: header

    private func planHeader(_ p: InstallPlan, axis: InstallAxis) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let range = ThaiFormat.numericDate.string(from: p.start) + " – " + ThaiFormat.numericDate.string(from: p.end)
        let sub = p.baseline.map { "อนุมัติ \(ThaiFormat.numericDate.string(from: $0.approved)) | \($0.by) | " + range } ?? range
        return VStack(alignment: .leading, spacing: 10) {
            // Row 1: Title + Info Chips
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("แผนก่อสร้าง").font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                        if let b = p.baseline {
                            Text(b.revision).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                                .padding(.horizontal, 8).frame(height: 22).background(Theme.primarySoft, in: Capsule())
                        }
                    }
                    Text(sub).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                .fixedSize()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // one schedule status, from the progress to date with its days (CHA-64)
                        if let status = p.scheduleText {
                            planChip("สถานะแผน", status, p.schedule == .behind ? Theme.dangerText : Theme.successInk)
                        }
                        planChip("ระยะเวลา", "\(p.days.count) วันปฏิทิน", Theme.navy)
                        planChip("วันทำงาน", "\(p.workingDays) วัน", Theme.navy)
                        if p.subCount > 0 { planChip("งานย่อย", "\(p.subCount) งาน", Theme.navy) }
                        // the planned finish against the baseline's: a date, not a status
                        if let slip = p.slip {
                            planChip("วันเสร็จเทียบ Baseline", slip == 0 ? "ไม่เลื่อน" : slip > 0 ? "เลื่อน \(slip) วัน" : "เร็วขึ้น \(-slip) วัน",
                                     slip > 0 ? Theme.dangerText : Theme.navy)
                        }
                    }
                }
            }

            // Row 2: View Switcher, Zoom, Controls & Actions
            HStack(spacing: 10) {
                TCCountSegments([.init("Gantt"), .init("ตาราง")],
                                selection: Binding(get: { planView == .gantt ? 0 : 1 }, set: { planView = $0 == 0 ? .gantt : .table }),
                                equalWidths: false, fontSize: 14)
                    .accessibilityLabel("มุมมองแผน")
                    .accessibilityIdentifier("plan.view")

                if planView == .gantt {
                    Picker("การซูม", selection: $zoomLevel) {
                        ForEach(InstallAxis.Unit.allCases) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                    .accessibilityLabel("ระดับการซูมแผนภูมิ")

                    Button {
                        withAnimation(.snappy) { compactTaskCol.toggle() }
                    } label: {
                        Label(compactTaskCol ? "ขยายชื่องาน" : "ย่อชื่องาน", systemImage: compactTaskCol ? "arrow.left.and.right" : "arrow.right.and.left")
                    }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                    .accessibilityLabel(compactTaskCol ? "ขยายคอลัมน์ชื่องาน" : "ย่อคอลัมน์ชื่องาน")
                }

                Button(planAllClosed ? "เปิดทั้งหมด" : "ปิดทั้งหมด") {
                    withAnimation(.snappy) {
                        planAllClosed.toggle()
                        planToggled = []
                    }
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                .accessibilityLabel(planAllClosed ? "เปิดงานย่อยทั้งหมด" : "ปิดงานย่อยทั้งหมด")

                Spacer(minLength: 4)

                Button {
                    withAnimation(.snappy) { showMilestones.toggle() }
                } label: {
                    Label("Milestone", systemImage: showMilestones ? "checkmark" : "sidebar.right")
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                .accessibilityLabel("Milestone")
                .accessibilityValue(showMilestones ? "แสดงอยู่" : "ซ่อนอยู่")
                .accessibilityAddTraits(showMilestones ? .isSelected : [])

                if permissions.can(.mpSetup, on: job.access), !job.scheduleWBS.isEmpty {
                    Button("งานก่อนหน้า WBS") { showWBSDependencies = true }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                        .accessibilityLabel("งานก่อนหน้า WBS")
                }
                Menu { MPWorkbookMenuItems(flow: workbook, job: job, canImport: permissions.can(.mpSetup)) } label: {
                    Label("Excel", systemImage: "tablecells").font(.sarabunFixed(15, .semibold)).frame(minHeight: touchMin)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                .accessibilityLabel("ไฟล์แผน Excel")
                Button { exportPDF(p) } label: {
                    Label("ส่งออก PDF", systemImage: "square.and.arrow.up")
                        .font(.sarabunFixed(15, .semibold))
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                .disabled(job.scheduleInput == nil)
                .accessibilityLabel("ส่งออก PDF แผนก่อสร้าง")
                .accessibilityHint("แผนภูมิแกนต์และ Weekly Update ของสัปดาห์นี้ หนึ่งหน้า A3")
                if permissions.can(.mpSetup, on: job.access) || InstallTrackingPage.Debug.demo {
                    Button("แก้ไขแผน") { route = .plan }
                        .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                        .accessibilityIdentifier("plan.edit")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: Self.planHeaderHeight)
        .background(Theme.surface, in: frame)
        .overlay(frame.strokeBorder(Theme.borderSubtle))
        .cardShadow()
    }

    private func planChip(_ label: String, _ value: String, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabunFixed(17, .bold)).foregroundStyle(ink).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The MP plan's A3 page, as the job screen's `ส่งออก PDF`.
    private func exportPDF(_ p: InstallPlan) {
        guard let input = job.scheduleInput else { return }
        let week = MasterSchedule.weekStart(.now)
        let title = [job.mpNumber.map { "MP \($0)" }, job.projectName.isEmpty ? nil : job.projectName].compactMap { $0 }.joined(separator: " ")
        let sketch = MasterScheduleSheet.page(input: input, actual: job.scheduleActual, week: week, title: title.isEmpty ? job.code : title)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("แผนก่อสร้าง-\(job.stationName)-\(ISODate.string(week)).pdf")
        guard (try? PDFRenderer.pdf(sketch, title: "แผนก่อสร้าง " + title).write(to: url, options: .atomic)) != nil else { return }
        shared = InstallTrackingPage.Shared(url: url)
    }

    // MARK: Gantt

    private func showsCrew(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.crew != nil } }
    private func showsLinks(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.after != nil } }
    private func showsBaseline(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.baselineEnd != nil } }

    private func planGantt(_ p: InstallPlan, axis: InstallAxis, waitLabel: String?) -> some View {
        GeometryReader { geo in
            let taskW = currentTaskColWidth(p)
            let availableTimelineW = max(geo.size.width - taskW - 1, 200)
            let minTimelineW: CGFloat = switch axis.unit {
            case .day:
                CGFloat(axis.columns.count) * 32
            case .week:
                max(availableTimelineW, CGFloat(axis.columns.count) * 54)
            case .month:
                availableTimelineW
            }
            let timelineW = max(availableTimelineW, minTimelineW)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Pinned Left Task Column
                    VStack(spacing: 0) {
                        planLeftHeader(p, width: taskW)
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(p.stages) { s in
                                    let open = planOpen(s, p)
                                    planStageLeftRow(s, p, width: taskW)
                                    if open {
                                        ForEach(s.subs) { r in
                                            planSubLeftRow(r, p, width: taskW)
                                        }
                                    }
                                }
                                if !p.milestones.isEmpty {
                                    milestoneLeftRow(p, width: taskW)
                                }
                            }
                        }
                        .scrollPosition($scrollPos)
                    }
                    .frame(width: taskW)

                    // Vertical divider
                    Rectangle().fill(Theme.borderSubtle).frame(width: 1)

                    // Horizontally and Vertically scrollable Timeline
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            planTimelineHeader(p, axis: axis, width: timelineW)
                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVStack(spacing: 0) {
                                    ForEach(p.stages) { s in
                                        let open = planOpen(s, p)
                                        planStageBarRow(s, p, axis: axis, width: timelineW)
                                        if open {
                                            ForEach(s.subs) { r in
                                                planSubBarRow(r, stage: s.row, p, axis: axis, width: timelineW)
                                            }
                                        }
                                    }
                                    if !p.milestones.isEmpty {
                                        milestoneBarRow(p, axis: axis, width: timelineW)
                                    }
                                }
                                .background(alignment: .topLeading) {
                                    planColumns(axis, p, width: timelineW)
                                }
                            }
                            .scrollPosition($scrollPos)
                        }
                        .frame(width: timelineW)
                    }
                    .scrollPosition($timelinePos)
                    // today a third of the way in, or the nearest the chart can scroll to it
                    .onAppear { scrollToToday(axis, timelineW: timelineW, visible: availableTimelineW) }
                    .onChange(of: zoomLevel) { scrollToToday(axis, timelineW: timelineW, visible: availableTimelineW) }
                }
                Rectangle().fill(Theme.hairline).frame(height: 1)
                planLegend(p, waitLabel: waitLabel)
            }
        }
    }

    private func scrollToToday(_ axis: InstallAxis, timelineW: CGFloat, visible: CGFloat) {
        let x = axis.x(axis.today, timelineW) - visible / 3
        timelinePos.scrollTo(x: min(max(x, 0), max(timelineW - visible, 0)))
    }

    private func planColumns(_ axis: InstallAxis, _ p: InstallPlan, width: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                InstallColumns(axis: axis, nonWorking: p.nonWorking, x: 0, width: width, height: geo.size.height)
                ForEach(axis.columns, id: \.self) { d in
                    let gx = axis.x(d, width)
                    Rectangle().fill(Theme.hairline.opacity(0.35)).frame(width: 1, height: geo.size.height).offset(x: gx)
                }
                Theme.danger.opacity(0.6).frame(width: 1.5, height: geo.size.height).offset(x: axis.x(axis.today, width))
            }
        }
        .allowsHitTesting(false)
    }

    private func planLeftHeader(_ p: InstallPlan, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("WBS").frame(width: PlanCol.wbs, alignment: .leading)
            Text("งาน").frame(maxWidth: .infinity, alignment: .leading)
            Text("วันทำงาน").lineLimit(1).minimumScaleFactor(0.8).frame(width: PlanCol.days)
            if showsCrew(p) { Text("คน").frame(width: PlanCol.crew) }
            if showsLinks(p) { Text("ต่อจาก").frame(width: PlanCol.after) }
        }
        .font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
        .padding(.leading, 16)
        .frame(width: width, height: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func planTimelineHeader(_ p: InstallPlan, axis: InstallAxis, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // the month and year over its days (the month axis names them on its columns)
            if axis.unit != .month {
                ForEach(axis.months, id: \.self) { m in
                    let x = axis.x(m, width)
                    HStack(spacing: 0) {
                        Rectangle().fill(Theme.borderSubtle).frame(width: 1, height: 14)
                        Text(Self.monthYear.string(from: m)).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.navy)
                            .padding(.leading, 5).fixedSize()
                    }
                    .offset(x: x, y: 3)
                }
            }
            ForEach(axis.unit == .day ? axis.columns : axis.labelled, id: \.self) { d in
                planDayLabel(d, axis: axis, dense: axis.columns.count > 20)
                    .frame(width: axis.columnWidth(width))
                    .offset(x: axis.x(d, width), y: axis.unit == .month ? 20 : 21)
            }
        }
        .frame(width: width, height: 58, alignment: .topLeading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func planDayLabel(_ d: Date, axis: InstallAxis, dense: Bool) -> some View {
        let week = axis.unit == .week
        let month = axis.unit == .month
        let today = week ? axis.contains(axis.today, week: d) : MasterSchedule.calendar.isDate(d, inSameDayAs: axis.today)
        let sunday = !week && !month && InstallPlan.isSunday(d)
        let ink = today ? Theme.dangerText : sunday ? Theme.survey : Theme.inkMuted
        return VStack(spacing: 2) {
            if axis.unit == .day {
                Text(InstallAxis.weekday.string(from: d)).font(.sarabunFixed(11)).foregroundStyle(ink)
            }
            // the day's number alone under its weekday, so the first column isn't wider than its 32 pt
            Text(axis.unit == .day ? "\(MasterSchedule.calendar.component(.day, from: d))" : axis.label(d))
                .font(.sarabunFixed(month ? 13 : week || dense ? 12 : 15, .bold)).foregroundStyle(today ? Theme.onPrimary : ink).monospacedDigit()
                .padding(.horizontal, today ? 6 : 0).frame(height: 20)
                .background { if today { Capsule().fill(Theme.danger) } }
        }
        .fixedSize()
    }

    /// `ส.ค. 2569`: the timeline's month row.
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = ThaiFormat.locale
        f.calendar = Calendar(identifier: .buddhist)
        f.dateFormat = "MMM yyyy"
        return f
    }()

    private func planStageLeftRow(_ s: InstallPlan.Stage, _ p: InstallPlan, width: CGFloat) -> some View {
        let open = planOpen(s, p), r = s.row
        return Button { if !s.subs.isEmpty { togglePlan(s.id) } } label: {
            HStack(spacing: 0) {
                Text(r.code).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.inkMuted).frame(width: PlanCol.wbs, alignment: .leading)
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.navy).frame(width: 14).opacity(s.subs.isEmpty ? 0 : 1)
                    Text(r.title).font(.sarabunFixed(r.title.count > 34 ? 14 : 16, .bold))
                        .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("\(p.workingDays(of: r))").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).monospacedDigit().frame(width: PlanCol.days)
                if showsCrew(p) { Text(r.crew.map(String.init) ?? "–").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).monospacedDigit().frame(width: PlanCol.crew) }
                if showsLinks(p) { Text(r.after ?? "–").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy).monospacedDigit().frame(width: PlanCol.after) }
            }
            .padding(.leading, 16)
            .frame(width: width, height: max(PlanCol.stageRow, 44))
            .background(r.status == .current ? Theme.primary.opacity(0.04) : .clear)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(r.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(planAccessibility(r, p))
        .accessibilityHint(s.subs.isEmpty ? "" : open ? "แตะเพื่อซ่อนงานย่อย" : "แตะเพื่อแสดงงานย่อย")
        .accessibilityIdentifier("plan-stage-\(r.code)")
    }

    private func planStageBarRow(_ s: InstallPlan.Stage, _ p: InstallPlan, axis: InstallAxis, width: CGFloat) -> some View {
        let r = s.row
        return Button { if !s.subs.isEmpty { togglePlan(s.id) } } label: {
            PlanStageBar(row: r, axis: axis, width: width)
                .frame(width: width, height: max(PlanCol.stageRow, 44), alignment: .leading)
                .background(r.status == .current ? Theme.primary.opacity(0.04) : .clear)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(r.title)
        .accessibilityHidden(true)
    }

    private func planSubLeftRow(_ r: InstallPlan.Row, _ p: InstallPlan, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(r.code).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).frame(width: PlanCol.wbs, alignment: .leading)
            Text(r.title).font(.sarabunFixed(14)).lineLimit(1).truncationMode(.tail)
                .padding(.leading, 12).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(p.workingDays(of: r))").font(.sarabunFixed(14)).foregroundStyle(Theme.navy).monospacedDigit().frame(width: PlanCol.days)
            if showsCrew(p) { Text(r.crew.map(String.init) ?? "–").font(.sarabunFixed(14)).foregroundStyle(Theme.navy).monospacedDigit().frame(width: PlanCol.crew) }
            if showsLinks(p) { Text(r.after ?? "–").font(.sarabunFixed(14)).foregroundStyle(Theme.navy).monospacedDigit().frame(width: PlanCol.after) }
        }
        .padding(.leading, 16)
        .frame(width: width, height: PlanCol.subRow)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1) }
        .help(r.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(planAccessibility(r, p))
    }

    private func planSubBarRow(_ r: InstallPlan.Row, stage: InstallPlan.Row, _ p: InstallPlan, axis: InstallAxis, width: CGFloat) -> some View {
        PlanSubBar(row: r, stage: stage, axis: axis, width: width)
            .frame(width: width, height: PlanCol.subRow, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1) }
            .help(r.title)
            .accessibilityHidden(true)
    }

    private func milestoneLeftRow(_ p: InstallPlan, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("Milestone").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                .padding(.leading, 16 + PlanCol.wbs).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width, height: 44)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Milestone " + p.milestones.map { "\($0.title) \(ThaiFormat.dayMonth.string(from: $0.date))" }.joined(separator: " | "))
    }

    private func milestoneBarRow(_ p: InstallPlan, axis: InstallAxis, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(p.milestones) { m in
                let x = (axis.x(m.date, width) + axis.xEnd(m.date, width)) / 2
                MilestoneDiamond(state: m.state(today: p.today)).position(x: x, y: 22)
            }
        }
        .frame(width: width, height: 44, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func planAccessibility(_ r: InstallPlan.Row, _ p: InstallPlan) -> String {
        let status = switch r.status { case .done: "เสร็จ"; case .current: "กำลังทำ"; case .waiting: "ตามแผน" }
        return "\(r.code) \(r.title) | \(ThaiFormat.dayMonth.string(from: r.start))–\(ThaiFormat.dayMonth.string(from: r.end)) | \(status) \(Int(r.percent.rounded()))%"
            + (r.overdue(today: p.today) ? " | เลยกำหนด" : "")
            + (r.critical ? " | เส้นทางวิกฤต" : "") + ((r.float ?? 0) > 0 ? " | เผื่อ \(r.float ?? 0) วัน" : "")
            + (r.slip.map { " | เทียบ Baseline " + InstallPlan.slipText($0) } ?? "")
    }

    private func planLegend(_ p: InstallPlan, waitLabel: String?) -> some View {
        HStack(spacing: 16) {
            legendSwatch("เสร็จ") { Capsule().fill(Theme.success) }
            legendSwatch("กำลังทำ") { Capsule().fill(Theme.primary) }
            legendSwatch("ตามแผน") { Capsule().fill(Theme.installPlanned) }
            legendSwatch("เส้นทางวิกฤต") { Capsule().strokeBorder(Theme.installCritical, lineWidth: 2) }
            HStack(spacing: 6) {
                Path { q in q.move(to: CGPoint(x: 0, y: 1)); q.addLine(to: CGPoint(x: 22, y: 1)) }
                    .stroke(Theme.installFloat, style: StrokeStyle(lineWidth: 2, dash: [1.5, 2.5])).frame(width: 22, height: 2)
                Text("เผื่อเวลา (Float)")
            }
            legendSwatch(waitLabel == nil ? "วันหยุด" : "รอการไฟฟ้า") {
                InstallHatch(ink: Theme.installFloat.opacity(0.5), line: 2).clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if showsBaseline(p) {
                legendSwatch("Baseline") { Capsule().fill(Theme.installBaseline).frame(height: 4) }
            }
            Spacer(minLength: 8)
            if showsLinks(p) { Text("ต่อจาก = งานก่อนหน้า (เสร็จ → เริ่ม)") }
        }
        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 16).frame(height: 40)
        .accessibilityHidden(true)
    }

    private func legendSwatch<S: View>(_ title: String, @ViewBuilder _ swatch: () -> S) -> some View {
        HStack(spacing: 6) {
            swatch().frame(width: 22, height: 10)
            Text(title)
        }
    }

    // MARK: table

    private enum TableCol {
        static let wbs: CGFloat = 60, date: CGFloat = 80, days: CGFloat = 72, crew: CGFloat = 54, after: CGFloat = 70, status: CGFloat = 100
        static let slip: CGFloat = 104
    }

    private func planTable(_ p: InstallPlan) -> some View {
        VStack(spacing: 0) {
            tableRow(nil, p, stage: true)
                .font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
                .frame(height: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
                .accessibilityHidden(true)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(p.stages) { s in
                        tableRow(s.row, p, stage: true).frame(minHeight: 44).background(Theme.phonePage)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        ForEach(s.subs) { r in
                            tableRow(r, p, stage: false).frame(minHeight: 44)
                                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("plan-table")
    }

    /// One line of the table; nil is the header.
    private func tableRow(_ r: InstallPlan.Row?, _ p: InstallPlan, stage: Bool) -> some View {
        HStack(spacing: 0) {
            Text(r?.code ?? "WBS").frame(width: TableCol.wbs, alignment: .leading)
            Text(r?.title ?? "งาน").lineLimit(1).padding(.leading, r != nil && !stage ? 24 : 0).frame(maxWidth: .infinity, alignment: .leading)
            Text(r.map { ThaiFormat.dayMonth.string(from: $0.start) } ?? "เริ่ม").frame(width: TableCol.date, alignment: .leading)
            Text(r.map { ThaiFormat.dayMonth.string(from: $0.end) } ?? "เสร็จ").frame(width: TableCol.date, alignment: .leading)
            Text(r.map { "\(p.workingDays(of: $0))" } ?? "วันทำงาน").frame(width: TableCol.days, alignment: .leading)
            if showsCrew(p) { Text(r.map { $0.crew.map(String.init) ?? "–" } ?? "คน").frame(width: TableCol.crew, alignment: .leading) }
            if showsLinks(p) { Text(r.map { $0.after ?? "–" } ?? "ต่อจาก").frame(width: TableCol.after, alignment: .leading) }
            if showsBaseline(p) {
                Group {
                    if let r { slipLabel(r.slip) } else { Text("เทียบ Baseline") }
                }
                .frame(width: TableCol.slip, alignment: .leading)
            }
            Group {
                if let r { statusPill(r.status) } else { Text("สถานะ") }
            }
            .frame(width: TableCol.status, alignment: .leading)
        }
        .font(r == nil ? .sarabunFixed(13, .bold) : .sarabunFixed(15, stage ? .bold : .regular))
        .foregroundStyle(r == nil ? Theme.inkMuted : Theme.navy)
        .monospacedDigit()
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }

    /// A row's slip from its baseline: red when later, green otherwise, a dash without one.
    func slipLabel(_ slip: Int?) -> some View {
        InstallTrackingPage.slipLabel(slip)
    }

    private func statusPill(_ s: InstallGantt.Status) -> some View {
        let (title, tone): (String, InstallPageData.Tone) = switch s {
        case .done: ("เสร็จ", .ok)
        case .current: ("กำลังทำ", .info)
        case .waiting: ("ตามแผน", .idle)
        }
        return Text(title).font(.sarabunFixed(13, .bold)).foregroundStyle(InstallTrackingPage.ink(tone))
            .padding(.horizontal, 10).frame(height: 24).background(InstallTrackingPage.fill(tone), in: Capsule())
    }
}
