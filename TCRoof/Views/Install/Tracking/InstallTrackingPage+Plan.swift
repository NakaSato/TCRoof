import SwiftUI
import TCRoofUI
import TCRoofCore
import PDFReport

/// `แผนก่อสร้าง` (docs/ui/install-tracking-ipad-v2 §6, `states/05`–`07`): the install plan by WBS as a Gantt or a table,
/// with the critical path outlined and the sub-tasks' float dotted, and beside it the planned crew, the milestones and
/// the next stage's make-ready. `แก้ไขแผน` opens the MP plan screen. Crew, links, the baseline and the make-ready show
/// only when there is a source (`InstallPlan`).
extension InstallTrackingPage {
    enum PlanView: String { case gantt, table }

    static let planHeaderHeight: CGFloat = 84
    static let planSideWidth: CGFloat = 340
    /// The grid's columns before the days.
    private enum PlanCol {
        static let wbs: CGFloat = 44, days: CGFloat = 40, crew: CGFloat = 44, after: CGFloat = 60, left: CGFloat = 470
        static let stageRow: CGFloat = 40, subRow: CGFloat = 32
    }

    @ViewBuilder func planTab(_ data: InstallPageData) -> some View {
        if let p = data.plan, let g = data.gantt {
            let body = max(viewport - 14 - Self.planHeaderHeight - 14 - Self.dockClearance, 440)
            VStack(alignment: .leading, spacing: 14) {
                planHeader(p)
                HStack(alignment: .top, spacing: 14) {
                    Group {
                        if planView == .gantt { planGantt(p, axis: InstallAxis(g), waitLabel: data.waitLabel) } else { planTable(p) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: body)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .cardShadow()
                    planSide(p).frame(width: Self.planSideWidth, height: body)
                }
            }
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

    private func planHeader(_ p: InstallPlan) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let range = ThaiFormat.numericDate.string(from: p.start) + " – " + ThaiFormat.numericDate.string(from: p.end)
        let sub = p.baseline.map { "อนุมัติ \(ThaiFormat.numericDate.string(from: $0.approved)) | \($0.by) | " + range } ?? range
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text("แผนก่อสร้าง").font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    if let b = p.baseline {
                        Text(b.revision).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                            .padding(.horizontal, 10).frame(height: 24).background(Theme.primarySoft, in: Capsule())
                    }
                }
                Text(sub).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            .fixedSize()
            HStack(spacing: 8) {
                planChip("ระยะเวลา", "\(p.days.count) วัน", Theme.navy)
                planChip("วันทำงาน", "\(p.workingDays) วัน", Theme.navy)
                if p.subCount > 0 { planChip("งานย่อย", "\(p.subCount) งาน", Theme.navy) }
                if let on = p.onPlan { planChip("สถานะแผน", on ? "ตามแผน" : "ช้ากว่าแผน", on ? Theme.successInk : Theme.dangerText) }
            }
            Spacer(minLength: 8)
            TCCountSegments([.init("Gantt"), .init("ตาราง")],
                            selection: Binding(get: { planView == .gantt ? 0 : 1 }, set: { planView = $0 == 0 ? .gantt : .table }), equalWidths: false, fontSize: 16)
                .fixedSize()
                .accessibilityLabel("มุมมองแผน")
            Button("แก้ไขแผน") { route = .plan }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
            Menu { MPWorkbookMenuItems(flow: workbook, job: job, canImport: permissions.can(.mpSetup)) } label: {
                Label("Excel", systemImage: "tablecells").font(.sarabunFixed(17, .semibold)).frame(minHeight: touchMin)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
            .accessibilityLabel("ไฟล์แผน Excel")
            Button("ส่งออก PDF", action: exportPlanPDF)
                .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                .disabled(job.scheduleInput == nil)
                .accessibilityHint("แผนภูมิแกนต์และ Weekly Update ของสัปดาห์นี้ หนึ่งหน้า A3")
        }
        .padding(.horizontal, 18)
        .frame(height: Self.planHeaderHeight)
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
        .accessibilityElement(children: .combine)
    }

    /// The MP plan's A3 page (the Gantt and this week's Weekly Update), to the share sheet.
    private func exportPlanPDF() {
        guard let input = job.scheduleInput else { return }
        let week = MasterSchedule.weekStart(.now)
        let title = [job.mpNumber.map { "MP \($0)" }, job.projectName.isEmpty ? nil : job.projectName].compactMap { $0 }.joined(separator: " ")
        let sketch = MasterScheduleSheet.page(input: input, actual: job.scheduleActual, week: week, title: title.isEmpty ? job.code : title)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("แผนก่อสร้าง-\(job.stationName)-\(ISODate.string(week)).pdf")
        guard (try? PDFRenderer.pdf(sketch, title: "แผนก่อสร้าง " + title).write(to: url, options: .atomic)) != nil else { return }
        shared = Shared(url: url)
    }

    // MARK: Gantt

    private func showsCrew(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.crew != nil } }
    private func showsLinks(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.after != nil } }

    private func planGantt(_ p: InstallPlan, axis: InstallAxis, waitLabel: String?) -> some View {
        VStack(spacing: 0) {
            planGanttHeader(p, axis: axis)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(p.stages) { s in
                        planStageRow(s, p, axis: axis)
                        if planOpen(s, p) {
                            ForEach(s.subs) { planSubRow($0, stage: s.row, p, axis: axis) }
                        }
                    }
                    if !p.milestones.isEmpty { milestoneRow(p, axis: axis) }
                }
            }
            .background(alignment: .topLeading) { planColumns(axis, p) }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            planLegend(p, waitLabel: waitLabel)
        }
    }

    /// The days' column layer under the rows: Sundays, days off and waiting, today tinted with a red edge.
    private func planColumns(_ axis: InstallAxis, _ p: InstallPlan) -> some View {
        GeometryReader { geo in
            let w = geo.size.width - PlanCol.left - 16
            ZStack(alignment: .topLeading) {
                InstallColumns(axis: axis, nonWorking: p.nonWorking, x: PlanCol.left, width: w, height: geo.size.height)
                Theme.danger.opacity(0.5).frame(width: 1, height: geo.size.height).offset(x: PlanCol.left + axis.x(axis.today, w))
            }
        }
        .allowsHitTesting(false)
    }

    /// The left block of a grid row: `WBS`, the name, `วัน`, then `คน` and `ต่อจาก` when they have a source.
    private func planLeft<Name: View>(_ r: InstallPlan.Row, _ p: InstallPlan, bold: Bool, @ViewBuilder name: () -> Name) -> some View {
        HStack(spacing: 0) {
            Text(r.code).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).frame(width: PlanCol.wbs, alignment: .leading)
            name().frame(maxWidth: .infinity, alignment: .leading)
            Text("\(r.days)").frame(width: PlanCol.days)
            if showsCrew(p) { Text(r.crew.map(String.init) ?? "–").frame(width: PlanCol.crew) }
            if showsLinks(p) { Text(r.after ?? "–").frame(width: PlanCol.after) }
        }
        .font(.sarabunFixed(14, bold ? .bold : .regular)).foregroundStyle(Theme.navy).monospacedDigit()
        .padding(.leading, 16)
        .frame(width: PlanCol.left)
    }

    private func planGanttHeader(_ p: InstallPlan, axis: InstallAxis) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("WBS").frame(width: PlanCol.wbs, alignment: .leading)
                Text("งาน").frame(maxWidth: .infinity, alignment: .leading)
                Text("วัน").frame(width: PlanCol.days)
                if showsCrew(p) { Text("คน").frame(width: PlanCol.crew) }
                if showsLinks(p) { Text("ต่อจาก").frame(width: PlanCol.after) }
            }
            .font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
            .padding(.leading, 16).frame(width: PlanCol.left)
            GeometryReader { geo in
                let w = geo.size.width
                // a week column shows its first day, every other one past 16 weeks
                ForEach(axis.unit == .day ? axis.columns : axis.labelled, id: \.self) { d in
                    planDayLabel(d, axis: axis, dense: axis.columns.count > 20).frame(width: axis.columnWidth(w)).offset(x: axis.x(d, w), y: axis.unit == .day ? 10 : 20)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .accessibilityHidden(true)
    }

    /// The weekday over the date, Sundays rose and today in a red pill; a week column shows only its first day.
    private func planDayLabel(_ d: Date, axis: InstallAxis, dense: Bool) -> some View {
        let week = axis.unit == .week
        let today = week ? axis.contains(axis.today, week: d) : MasterSchedule.calendar.isDate(d, inSameDayAs: axis.today)
        let sunday = !week && InstallPlan.isSunday(d)
        let ink = today ? Theme.dangerText : sunday ? Theme.survey : Theme.inkMuted
        return VStack(spacing: 2) {
            if !week { Text(InstallAxis.weekday.string(from: d)).font(.sarabunFixed(11)).foregroundStyle(ink) }
            Text(week ? ThaiFormat.dayMonth.string(from: d) : "\(MasterSchedule.calendar.component(.day, from: d))")
                .font(.sarabunFixed(week || dense ? 12 : 15, .bold)).foregroundStyle(today ? Theme.onPrimary : ink).monospacedDigit()
                .padding(.horizontal, today ? 4 : 0).frame(height: 20)
                .background { if today { Capsule().fill(Theme.danger) } }
        }
        .fixedSize()
    }

    private func planStageRow(_ s: InstallPlan.Stage, _ p: InstallPlan, axis: InstallAxis) -> some View {
        let open = planOpen(s, p), r = s.row
        return Button { if !s.subs.isEmpty { togglePlan(s.id) } } label: {
            HStack(spacing: 0) {
                planLeft(r, p, bold: true) {
                    HStack(spacing: 8) {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.navy).frame(width: 14).opacity(s.subs.isEmpty ? 0 : 1)
                        // the MP plan's long task names take two lines
                        Text(r.title).font(.sarabunFixed(r.title.count > 34 ? 14 : 16, .bold)).lineLimit(2).lineSpacing(-2)
                    }
                }
                GeometryReader { geo in PlanStageBar(row: r, axis: axis, width: geo.size.width) }
                    .padding(.trailing, 16)
            }
            .frame(height: max(PlanCol.stageRow, 44))
            .background(r.status == .current ? Theme.primary.opacity(0.04) : .clear)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(planAccessibility(r))
        .accessibilityHint(s.subs.isEmpty ? "" : open ? "แตะเพื่อซ่อนงานย่อย" : "แตะเพื่อแสดงงานย่อย")
        .accessibilityIdentifier("plan-stage-\(r.code)")
    }

    private func planSubRow(_ r: InstallPlan.Row, stage: InstallPlan.Row, _ p: InstallPlan, axis: InstallAxis) -> some View {
        HStack(spacing: 0) {
            planLeft(r, p, bold: false) {
                Text(r.title).font(.sarabunFixed(15)).lineLimit(1).padding(.leading, 22)
            }
            GeometryReader { geo in PlanSubBar(row: r, stage: stage, axis: axis, width: geo.size.width) }
                .padding(.trailing, 16)
        }
        .frame(height: PlanCol.subRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(planAccessibility(r))
    }

    private func planAccessibility(_ r: InstallPlan.Row) -> String {
        let status = switch r.status { case .done: "เสร็จ"; case .current: "กำลังทำ"; case .waiting: "ตามแผน" }
        return "\(r.code) \(r.title) | \(ThaiFormat.dayMonth.string(from: r.start))–\(ThaiFormat.dayMonth.string(from: r.end)) | \(status) \(Int(r.percent.rounded()))%"
            + (r.critical ? " | เส้นทางวิกฤต" : "") + ((r.float ?? 0) > 0 ? " | เผื่อ \(r.float ?? 0) วัน" : "")
    }

    /// Diamonds on their days: green filled when passed, navy outlined when ahead.
    private func milestoneRow(_ p: InstallPlan, axis: InstallAxis) -> some View {
        HStack(spacing: 0) {
            Text("Milestone").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                .padding(.leading, 16 + PlanCol.wbs).frame(width: PlanCol.left, alignment: .leading)
            GeometryReader { geo in
                ForEach(p.milestones) { m in
                    let x = (axis.x(m.date, geo.size.width) + axis.xEnd(m.date, geo.size.width)) / 2
                    MilestoneDiamond(passed: m.date < p.today).position(x: x, y: geo.size.height / 2)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Milestone " + p.milestones.map { "\($0.title) \(ThaiFormat.dayMonth.string(from: $0.date))" }.joined(separator: " | "))
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
        static let wbs: CGFloat = 60, date: CGFloat = 80, days: CGFloat = 54, crew: CGFloat = 54, after: CGFloat = 70, status: CGFloat = 100
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
            Text(r.map { "\($0.days)" } ?? "วัน").frame(width: TableCol.days, alignment: .leading)
            if showsCrew(p) { Text(r.map { $0.crew.map(String.init) ?? "–" } ?? "คน").frame(width: TableCol.crew, alignment: .leading) }
            if showsLinks(p) { Text(r.map { $0.after ?? "–" } ?? "ต่อจาก").frame(width: TableCol.after, alignment: .leading) }
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

    private func statusPill(_ s: InstallGantt.Status) -> some View {
        let (title, tone): (String, InstallPageData.Tone) = switch s {
        case .done: ("เสร็จ", .ok)
        case .current: ("กำลังทำ", .info)
        case .waiting: ("ตามแผน", .idle)
        }
        return Text(title).font(.sarabunFixed(13, .bold)).foregroundStyle(Self.ink(tone))
            .padding(.horizontal, 10).frame(height: 24).background(Self.fill(tone), in: Capsule())
    }

    // MARK: right column

    private func planSide(_ p: InstallPlan) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                if !p.crew.isEmpty { crewPlanCard(p) }
                if !p.milestones.isEmpty { milestonesCard(p) }
                if let r = p.ready { readyCard(r) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func sideCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: frame)
            .overlay(frame.strokeBorder(Theme.borderSubtle))
            .cardShadow()
    }

    private func crewPlanCard(_ p: InstallPlan) -> some View {
        let days = p.crewDays, cap = p.teamSize, chart: CGFloat = 88
        let top = CGFloat(max((days.map(\.count).max() ?? 1), (cap ?? 0) + 2, 1))
        let over = p.overTeam
        return sideCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("กำลังคนตามแผน").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 6)
                    Text(cap.map { "เส้นประ = ทีม \($0) คน" } ?? "จากคำขอรายสัปดาห์").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(days, id: \.date) { d in
                        VStack(spacing: 2) {
                            Text(d.count > 0 ? "\(d.count)" : "").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).frame(height: 13)
                            RoundedRectangle(cornerRadius: 2).fill(crewInk(d.date, d.count, p))
                                .frame(height: chart * CGFloat(d.count) / top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: chart + 15, alignment: .bottom)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let cap {
                        Path { q in q.move(to: .zero); q.addLine(to: CGPoint(x: 400, y: 0)) }
                            .stroke(Theme.danger, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1).clipped()
                            .offset(y: -chart * CGFloat(cap) / top)
                    }
                }
                if days.count <= 31 {
                    HStack(spacing: 2) {
                        ForEach(days, id: \.date) { d in
                            Text("\(MasterSchedule.calendar.component(.day, from: d.date))").font(.sarabunFixed(11))
                                .foregroundStyle(d.date == p.today ? Theme.dangerText : InstallPlan.isSunday(d.date) ? Theme.survey : Theme.inkMuted)
                                .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
                        }
                    }
                }
                if cap != nil {
                    Text(over.isEmpty ? "ไม่มีวันที่เกินกำลังทีม"
                         : "เกินกำลัง " + over.map(ThaiFormat.dayMonth.string(from:)).joined(separator: ", ") + " | ขยับงานที่มีเวลาเผื่อ หรือเพิ่มคน")
                        .font(.sarabunFixed(13, .bold)).foregroundStyle(over.isEmpty ? Theme.successInk : Theme.dangerText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("กำลังคนตามแผนรายวัน " + days.map { "\($0.count)" }.joined(separator: ", ") + " คน")
    }

    private func crewInk(_ d: Date, _ n: Int, _ p: InstallPlan) -> Color {
        if let cap = p.teamSize, n > cap { return Theme.danger }
        return d < p.today ? Theme.success.opacity(0.45) : d == p.today ? Theme.primary : Theme.installPlanned
    }

    private func milestonesCard(_ p: InstallPlan) -> some View {
        sideCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Milestone").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                ForEach(p.milestones) { m in
                    let left = MasterSchedule.calendar.dateComponents([.day], from: p.today, to: MasterSchedule.calendar.startOfDay(for: m.date)).day ?? 0
                    HStack(spacing: 12) {
                        MilestoneDiamond(passed: left < 0)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.title).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                            Text("กำหนด " + ThaiFormat.numericDate.string(from: m.date)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer(minLength: 6)
                        chip(left < 0 ? "ผ่านแล้ว" : left == 0 ? "วันนี้" : "อีก \(left) วัน", left < 0 ? .ok : .info)
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func readyCard(_ r: InstallPlan.Ready) -> some View {
        sideCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("ความพร้อมขั้นถัดไป").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 6)
                    Text(r.stage).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                ForEach(r.items, id: \.label) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.ok ? "checkmark" : "exclamationmark").font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(item.ok ? Theme.successInk : Theme.warningInk)
                            .frame(width: 28, height: 28).background(item.ok ? Theme.successSoft : Theme.warningSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.label).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                            Text(item.note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A milestone's diamond: green filled when passed, navy outlined when ahead.
struct MilestoneDiamond: View {
    let passed: Bool

    var body: some View {
        Group {
            if passed {
                Rectangle().fill(Theme.success)
            } else {
                Rectangle().strokeBorder(Theme.navy, lineWidth: 2).background(Theme.surface)
            }
        }
        .frame(width: 12, height: 12)
        .rotationEffect(.degrees(45))
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// A stage's 20 pt bar: the plan's track filled navy (green when done) to its percent with a white `n%`, outlined
/// red while it is critical and not done.
struct PlanStageBar: View {
    let row: InstallPlan.Row
    let axis: InstallAxis
    let width: CGFloat

    var body: some View {
        let x0 = axis.x(row.start, width) + 3, x1 = axis.xEnd(row.end, width) - 3, w = max(x1 - x0, 8)
        let share = CGFloat(min(max(row.percent, 0), 100)) / 100
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack(alignment: .leading) {
            Theme.ganttTrack
            (row.status == .done ? Theme.success : Theme.navy).frame(width: w * share)
            // the label needs room: none on a 1-day bar or a narrow week-axis bar
            if row.days > 1, row.percent > 0, w >= 44 {
                Text("\(Int(row.percent.rounded()))%").font(.sarabunFixed(12, .bold))
                    .foregroundStyle(share >= 0.5 ? Theme.onPrimary : Theme.navy).padding(.leading, 6).fixedSize()
            }
        }
        .frame(width: w, height: 20)
        .clipShape(shape)
        .overlay { if row.critical { shape.strokeBorder(Theme.installCritical, lineWidth: 2) } }
        .offset(x: x0)
        .frame(width: width, height: 44, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// A sub-task's 10 pt bar by its status, ringed red when critical, with a dotted float tail to its stage's end.
struct PlanSubBar: View {
    let row: InstallPlan.Row
    let stage: InstallPlan.Row
    let axis: InstallAxis
    let width: CGFloat

    var body: some View {
        let x0 = axis.x(row.start, width) + 5, x1 = axis.xEnd(row.end, width) - 5, w = max(x1 - x0, 8)
        let ink = switch row.status { case .done: Theme.success; case .current: Theme.primary; case .waiting: Theme.installPlanned }
        ZStack(alignment: .leading) {
            if (row.float ?? 0) > 0 {
                let tail = axis.xEnd(stage.end, width) - 6
                Path { p in p.move(to: CGPoint(x: x1 + 6, y: 16)); p.addLine(to: CGPoint(x: tail, y: 16)) }
                    .stroke(Theme.installFloat, style: StrokeStyle(lineWidth: 2, dash: [1.5, 2.5]))
            }
            Capsule().fill(ink).frame(width: w, height: 10)
                .overlay { if row.critical { Capsule().stroke(Theme.installCritical, lineWidth: 1.5).padding(-1.5) } }
                .offset(x: x0)
        }
        .frame(width: width, height: 32, alignment: .leading)
        .accessibilityHidden(true)
    }
}
