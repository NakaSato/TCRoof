import SwiftUI
import TCRoofUI
import TCRoofCore
import PDFReport

/// iPhone `แผนก่อสร้าง` (docs/ui/install-tracking-iphone §4.8): the iPad tab's header, Gantt and table at phone width,
/// with the crew, milestones and make-ready cards under them (each only with a source, as on iPad). `แก้ไขแผน` edits
/// the MP stages' start and days in the table; `บันทึก` needs a reason and saves a re-plan as the assistant's confirmed
/// re-plan does (`PendingAction.replanned`: the dates become fixed, the first re-plan keeps the old plan as the
/// baseline, the change goes into the plan's audit lines). Its REV number is the count of those re-plans.
extension InstallTrackingPage {
    enum PCol {
        static let name: CGFloat = 150, stage: CGFloat = 50, sub: CGFloat = 34
        static let date: CGFloat = 64, days: CGFloat = 44, crew: CGFloat = 44, after: CGFloat = 60, status: CGFloat = 92
        static let slip: CGFloat = 92
    }

    /// Re-plans saved on this station so far: `REV 0n`. The board's example starts from its baseline, REV 01.
    private var revisions: Int {
        #if DEBUG
        if Debug.demo { return 1 }
        #endif
        return job.scheduleActual.confirmations.filter(\.replan).count
    }

    private static func rev(_ n: Int) -> String { String(format: "REV %02d", n) }

    private var mayEditPlan: Bool { permissions.can(.mpSetup, on: job.access) && job.scheduleInput != nil }

    @ViewBuilder func phonePlanTab(_ data: InstallPageData) -> some View {
        if let p = data.plan, let g = data.gantt {
            phonePlanHeader(p)
            if mayEditPlan, !job.scheduleWBS.isEmpty {
                Button("งานก่อนหน้า WBS") { showWBSDependencies = true }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
            }
            if !p.dependencyIssues.isEmpty {
                Text(p.dependencyIssues.map(\.message).joined(separator: "\n")).foregroundStyle(Theme.dangerText)
            }
            if planEditing { editStrip }
            Group {
                if planView == .gantt && !planEditing { phonePlanGantt(p, axis: InstallAxis(g, dayLimit: 31, forecast: p), waitLabel: data.waitLabel) } else { phonePlanTable(p) }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
            .cardShadow()
            if !planEditing {
                if !p.crew.isEmpty { phoneCrewCard(p) }
                if !p.milestones.isEmpty { phoneMilestones(p) }
                if let r = p.ready { phoneReady(r) }
            }
        } else {
            VStack(spacing: 16) {
                TCEmptyState("ยังไม่มีแผน MP", systemImage: "calendar", description: Text("สร้างแผนจากการ์ดแผนงาน MP ของงาน หรือนำเข้าไฟล์แผนของสถานี"))
                if permissions.can(.mpSetup) {
                    Button { startImport() } label: { Label("นำเข้าไฟล์แผน (Excel)", systemImage: "square.and.arrow.down") }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private func startImport() {
        workbook.confirmsInSheet = true
        workbook.startImport()
    }

    // MARK: header

    private func phonePlanHeader(_ p: InstallPlan) -> some View {
        let range = ThaiFormat.numericDate.string(from: p.start) + " – " + ThaiFormat.numericDate.string(from: p.end)
        let sub = p.baseline.map { "อนุมัติ \(ThaiFormat.numericDate.string(from: $0.approved)) | " + range } ?? range
        let changed = planChanges(p).count
        return phoneCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("แผนก่อสร้าง").font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                        if planEditing {
                            revChip("ร่าง " + Self.rev(revisions + 1), ink: Theme.warningInk, fill: Theme.warningSoft)
                        } else if let b = p.baseline {
                            revChip(b.revision, ink: Theme.primary, fill: Theme.primarySoft)
                        } else if revisions > 0 {
                            revChip(Self.rev(revisions), ink: Theme.primary, fill: Theme.primarySoft)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(sub).foregroundStyle(Theme.inkMuted)
                        if let slip = p.slip {
                            Text("Baseline " + InstallPlan.slipText(slip)).fontWeight(.bold)
                                .foregroundStyle(slip > 0 ? Theme.dangerText : Theme.successInk)
                        }
                    }
                    .font(.sarabunFixed(13)).lineLimit(1).minimumScaleFactor(0.8)
                }
                HStack(spacing: 6) {
                    factTile("ระยะเวลา", "\(p.days.count) วัน")
                    factTile("วันทำงาน", "\(p.workingDays) วัน")
                    if p.subCount > 0 { factTile("งานย่อย", "\(p.subCount) งาน") }
                    if let on = p.onPlan { factTile("สถานะแผน", on ? "ตามแผน" : "ช้ากว่าแผน", ink: on ? Theme.successInk : Theme.dangerText) }
                }
                if !planEditing {
                    TCCountSegments([.init("Gantt"), .init("ตาราง")],
                                    selection: Binding(get: { planView == .gantt ? 0 : 1 }, set: { planView = $0 == 0 ? .gantt : .table }), fontSize: 16)
                        .accessibilityLabel("มุมมองแผน")
                        .accessibilityIdentifier("plan.view")
                }
                HStack(spacing: 8) {
                    if planEditing {
                        Button("ยกเลิก") { withAnimation(.snappy) { cancelPlanEdit() } }
                            .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                            .accessibilityIdentifier("plan.cancel")
                        Button("บันทึก \(Self.rev(revisions + 1)) | \(changed) งาน") { savePlanEdit(p) }
                            .buttonStyle(TCButtonStyle(.primary, size: .card, fullWidth: true))
                            .disabled(changed == 0 || planReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("plan.save")
                    } else {
                        if mayEditPlan || Debug.demo {
                            Button("แก้ไขแผน") { withAnimation(.snappy) { startPlanEdit(nil) } }
                                .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                                .accessibilityIdentifier("plan.edit")
                        }
                        Menu {
                            if permissions.can(.mpSetup) {
                                Button { startImport() } label: { Label("นำเข้าไฟล์แผน (.xlsx)", systemImage: "square.and.arrow.down") }
                                if job.scheduleWorkbook != nil {
                                    Button { workbook.reviewSetup(job) } label: { Label("ตั้งค่าโครงการจากไฟล์…", systemImage: "list.bullet.clipboard") }
                                }
                            }
                            Button { workbook.export(job) } label: {
                                Label(job.scheduleWorkbook == nil ? "ส่งออก Excel (นำเข้าไฟล์ก่อน)" : "ส่งออก Excel", systemImage: "square.and.arrow.up")
                            }
                            .disabled(job.scheduleWorkbook == nil || job.scheduleInput == nil)
                            Button { route = .plan } label: { Label("แผนงาน MP ทั้งหมด", systemImage: "calendar") }
                        } label: {
                            Label("Excel", systemImage: "tablecells").font(.sarabunFixed(15, .semibold))
                                .frame(maxWidth: .infinity, minHeight: touchMin)
                        }
                        .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                        .accessibilityLabel("ไฟล์แผน Excel")
                        Button("PDF", action: phonePlanPDF)
                            .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                            .disabled(job.scheduleInput == nil)
                            .accessibilityHint("แผนภูมิแกนต์และ Weekly Update ของสัปดาห์นี้ หนึ่งหน้า A3")
                    }
                }
            }
        }
    }

    private func revChip(_ text: String, ink: Color, fill: Color) -> some View {
        Text(text).font(.sarabunFixed(13, .bold)).foregroundStyle(ink)
            .padding(.horizontal, 10).frame(height: 24).background(fill, in: Capsule())
    }

    /// The MP plan's A3 page, as the iPad's `ส่งออก PDF`.
    private func phonePlanPDF() {
        guard let input = job.scheduleInput else { return }
        let week = MasterSchedule.weekStart(.now)
        let title = [job.mpNumber.map { "MP \($0)" }, job.projectName.isEmpty ? nil : job.projectName].compactMap { $0 }.joined(separator: " ")
        let sketch = MasterScheduleSheet.page(input: input, actual: job.scheduleActual, week: week, title: title.isEmpty ? job.code : title)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("แผนก่อสร้าง-\(job.stationName)-\(ISODate.string(week)).pdf")
        guard (try? PDFRenderer.pdf(sketch, title: "แผนก่อสร้าง " + title).write(to: url, options: .atomic)) != nil else { return }
        shared = Shared(url: url)
    }

    // MARK: edit mode

    /// Opens the edit mode on the table; `data` is nil from the button (the stages come from the page's plan then).
    func startPlanEdit(_ data: InstallPageData?) {
        planDraft = [:]
        planReason = ""
        planEditing = true
    }

    private func cancelPlanEdit() {
        planDraft = [:]
        planReason = ""
        planEditing = false
    }

    /// A stage can move while it isn't done.
    func editable(_ r: InstallPlan.Row) -> Bool { r.status != .done }

    func draft(_ r: InstallPlan.Row) -> PlanDraft { planDraft[r.id] ?? PlanDraft(days: r.days) }

    func setDraft(_ r: InstallPlan.Row, _ change: (inout PlanDraft) -> Void) {
        var d = draft(r)
        change(&d)
        d.days = max(d.days, 1)
        planDraft[r.id] = d.shift == 0 && d.days == r.days ? nil : d
    }

    func editedDates(_ r: InstallPlan.Row) -> (start: Date, end: Date) {
        let cal = MasterSchedule.calendar, d = draft(r)
        let start = cal.date(byAdding: .day, value: d.shift, to: r.start) ?? r.start
        return (start, cal.date(byAdding: .day, value: d.days - 1, to: start) ?? start)
    }

    private func planChanges(_ p: InstallPlan) -> [InstallPlan.Row] {
        p.stages.map(\.row).filter { planDraft[$0.id] != nil }
    }

    private var editStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pencil").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.onPrimary)
                .frame(width: 40, height: 40).background(Theme.warning, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("กำลังแก้ไข | ร่าง " + Self.rev(revisions + 1)).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.warningInk)
                Text("‹ › เลื่อนวันเริ่ม | − + จำนวนวัน | งานที่เสร็จแล้วแก้ไม่ได้ | แก้แล้ว \(planDraft.count) งาน")
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.warningInk)
                TextField("เหตุผลที่แก้แผน (ต้องระบุ)", text: $planReason)
                    .font(.sarabunFixed(16))
                    .padding(12).frame(minHeight: 52)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.warning.opacity(0.45)))
                    .accessibilityIdentifier("plan.reason")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.warning.opacity(0.35)))
    }

    /// Saves the changed stages as one re-plan with the reason. The board's example (`-installDemo YES`) saves nothing.
    private func savePlanEdit(_ p: InstallPlan) {
        let reason = planReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = planChanges(p)
        let tasks = changed.compactMap { r -> Assistant.PendingAction.TaskDates? in
            guard let t = MasterSchedule.Task(rawValue: r.id) else { return nil }
            let d = editedDates(r)
            return .init(task: t, start: RoutineReport.dayKey(d.start), end: RoutineReport.dayKey(d.end))
        }
        func span(_ a: Date, _ b: Date) -> String { ThaiFormat.dayMonth.string(from: a) + "–" + ThaiFormat.dayMonth.string(from: b) }
        if !tasks.isEmpty {
            let before = changed.map { "\($0.code) " + span($0.start, $0.end) }.joined(separator: ", ")
            let after = changed.map { r in let d = editedDates(r); return "\(r.code) " + span(d.start, d.end) }.joined(separator: ", ")
            let action = Assistant.PendingAction(id: UUID().uuidString, jobID: job.overviewID, station: job.assistantStation,
                                                 change: .replan(tasks: tasks, reason: reason),
                                                 title: "แก้แผน " + Self.rev(revisions + 1), before: before, after: after + " | เหตุผล: " + reason)
            _ = context.applyAssistant(action, by: permissions.email)
        }
        withAnimation(.snappy) { cancelPlanEdit() }
    }

    // MARK: Gantt

    private func phonePlanGantt(_ p: InstallPlan, axis: InstallAxis, waitLabel: String?) -> some View {
        let cw = Self.phoneColumn(axis), width = cw * CGFloat(axis.columns.count)
        let todayIndex = axis.columns.firstIndex { axis.unit == .day ? MasterSchedule.calendar.isDate($0, inSameDayAs: axis.today) : axis.contains(axis.today, week: $0) }
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text("WBS | งาน").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
                        .padding(.leading, 12).padding(.bottom, 6)
                        .frame(maxWidth: .infinity, minHeight: InstallAxis.headerHeight, maxHeight: InstallAxis.headerHeight, alignment: .bottomLeading)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
                        .accessibilityHidden(true)
                    ForEach(p.stages) { s in
                        planStageName(s, p)
                        if planOpen(s, p) { ForEach(s.subs) { planSubName($0) } }
                    }
                    if !p.milestones.isEmpty {
                        Text("Milestone").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
                            .padding(.leading, 12)
                            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
                            .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
                    }
                }
                .frame(width: PCol.name)
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSubtle).frame(width: 1) }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            planDayHeader(axis, cw: cw)
                            ForEach(p.stages) { s in
                                PlanStageBar(row: s.row, axis: axis, width: width)
                                    .frame(width: width, height: PCol.stage)
                                    .background(s.row.status == .current ? Theme.primary.opacity(0.04) : .clear)
                                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                                if planOpen(s, p) {
                                    ForEach(s.subs) { r in
                                        PlanSubBar(row: r, stage: s.row, axis: axis, width: width).frame(width: width, height: PCol.sub)
                                    }
                                }
                            }
                            if !p.milestones.isEmpty {
                                ZStack(alignment: .topLeading) {
                                    ForEach(p.milestones) { m in
                                        MilestoneDiamond(passed: m.date < p.today)
                                            .position(x: (axis.x(m.date, width) + axis.xEnd(m.date, width)) / 2, y: 22)
                                    }
                                }
                                .frame(width: width, height: 44, alignment: .topLeading)
                                .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Milestone " + p.milestones.map { "\($0.title) \(ThaiFormat.dayMonth.string(from: $0.date))" }.joined(separator: " | "))
                            }
                        }
                        .frame(width: width)
                        .background(alignment: .topLeading) {
                            GeometryReader { geo in
                                ZStack(alignment: .topLeading) {
                                    InstallColumns(axis: axis, nonWorking: p.nonWorking, x: 0, width: width, height: geo.size.height)
                                    Theme.danger.opacity(0.5).frame(width: 1, height: geo.size.height)
                                        .offset(x: (axis.x(axis.today, width) + axis.xEnd(axis.today, width)) / 2)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onAppear { if let i = todayIndex { proxy.scrollTo("pcol-\(i)", anchor: .center) } }
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            planKey(waitLabel: waitLabel)
        }
    }

    private func planOpen(_ s: InstallPlan.Stage, _ p: InstallPlan) -> Bool {
        let byDefault = !planAllClosed && (s.row.status == .current || s.id == p.nextStage?.id)
        return !s.subs.isEmpty && (byDefault != planToggled.contains(s.id))
    }

    private func planDayHeader(_ axis: InstallAxis, cw: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(axis.columns.enumerated()), id: \.offset) { i, d in
                let week = axis.unit == .week
                let today = week ? axis.contains(axis.today, week: d) : MasterSchedule.calendar.isDate(d, inSameDayAs: axis.today)
                let sunday = !week && InstallPlan.isSunday(d)
                VStack(spacing: 2) {
                    if !week { Text(InstallAxis.weekday.string(from: d)).font(.sarabunFixed(11)).foregroundStyle(today ? Theme.dangerText : sunday ? Theme.survey : Theme.inkMuted) }
                    Text(week ? ThaiFormat.dayMonth.string(from: d) : "\(MasterSchedule.calendar.component(.day, from: d))")
                        .font(.sarabunFixed(week ? 11 : 14, .bold)).monospacedDigit()
                        .foregroundStyle(today ? Theme.onPrimary : sunday ? Theme.survey : Theme.navy)
                        .padding(.horizontal, today ? 4 : 0).frame(height: 20)
                        .background { if today { Capsule().fill(Theme.danger) } }
                        .fixedSize()
                }
                .padding(.bottom, 4)
                .frame(width: cw, height: InstallAxis.headerHeight, alignment: .bottom)
                .id("pcol-\(i)")
            }
        }
        .frame(height: InstallAxis.headerHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func planStageName(_ s: InstallPlan.Stage, _ p: InstallPlan) -> some View {
        let open = planOpen(s, p), r = s.row
        return Button {
            guard !s.subs.isEmpty else { return }
            withAnimation(.snappy) { if planToggled.contains(s.id) { planToggled.remove(s.id) } else { planToggled.insert(s.id) } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.navy).frame(width: 10).opacity(s.subs.isEmpty ? 0 : 1)
                Text(r.code).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).frame(width: 24, alignment: .leading)
                Text(r.title).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy).lineLimit(2).lineSpacing(-2)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8).padding(.trailing, 4)
            .frame(height: PCol.stage)
            .background(r.status == .current ? Theme.primary.opacity(0.04) : .clear)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(r.code) \(r.title) | \(Int(r.percent.rounded()))%" + (s.subs.isEmpty ? "" : open ? " | ซ่อนงานย่อย" : " | แสดงงานย่อย"))
        .accessibilityIdentifier("plan-stage-\(r.code)")
    }

    private func planSubName(_ r: InstallPlan.Row) -> some View {
        HStack(spacing: 6) {
            Text(r.code).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).frame(width: 30, alignment: .leading)
            Text(r.title).font(.sarabunFixed(13)).foregroundStyle(Theme.navy).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 26).padding(.trailing, 4)
        .frame(height: PCol.sub)
        .accessibilityElement(children: .combine)
    }

    private func planKey(waitLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                key("เสร็จ") { Capsule().fill(Theme.success) }
                key("กำลังทำ") { Capsule().fill(Theme.primary) }
                key("ตามแผน") { Capsule().fill(Theme.installPlanned) }
                key("เส้นทางวิกฤต") { Capsule().strokeBorder(Theme.installCritical, lineWidth: 2) }
            }
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Path { q in q.move(to: CGPoint(x: 0, y: 1)); q.addLine(to: CGPoint(x: 18, y: 1)) }
                        .stroke(Theme.installFloat, style: StrokeStyle(lineWidth: 2, dash: [1.5, 2.5])).frame(width: 18, height: 2)
                    Text("เผื่อเวลา (Float)")
                }
                key(waitLabel == nil ? "วันหยุด" : "รอการไฟฟ้า") { InstallHatch(ink: Theme.installFloat.opacity(0.5), line: 2).clipShape(RoundedRectangle(cornerRadius: 3)) }
            }
            Text("แตะขั้นเพื่อแสดง / ซ่อนงานย่อย")
        }
        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func key<S: View>(_ title: String, @ViewBuilder _ swatch: () -> S) -> some View {
        HStack(spacing: 5) {
            swatch().frame(width: 18, height: 9)
            Text(title)
        }
    }
}
