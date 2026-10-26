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
    private enum PCol {
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
            if planEditing { editStrip }
            Group {
                if planView == .gantt && !planEditing { phonePlanGantt(p, axis: InstallAxis(g, dayLimit: 31), waitLabel: data.waitLabel) } else { phonePlanTable(p) }
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
    private func editable(_ r: InstallPlan.Row) -> Bool { r.status != .done }

    private func draft(_ r: InstallPlan.Row) -> PlanDraft { planDraft[r.id] ?? PlanDraft(days: r.days) }

    private func setDraft(_ r: InstallPlan.Row, _ change: (inout PlanDraft) -> Void) {
        var d = draft(r)
        change(&d)
        d.days = max(d.days, 1)
        planDraft[r.id] = d.shift == 0 && d.days == r.days ? nil : d
    }

    private func editedDates(_ r: InstallPlan.Row) -> (start: Date, end: Date) {
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

    // MARK: table

    private func showsCrewPhone(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.crew != nil } }
    private func showsLinksPhone(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.after != nil } }
    private func showsBaselinePhone(_ p: InstallPlan) -> Bool { p.stages.contains { $0.row.baselineEnd != nil } }

    /// A sideways-scrolling grid with the WBS and name pinned. In edit mode a stage gets `‹ ›` on its start and `− +` on
    /// its days; done stages and the sub-tasks (whose days are the reports' places) are locked.
    private func phonePlanTable(_ p: InstallPlan) -> some View {
        let rows: [(InstallPlan.Row, Bool)] = p.stages.flatMap { s in [(s.row, true)] + s.subs.map { ($0, false) } }
        let date = planEditing ? PCol.date + 52 : PCol.date, days = planEditing ? PCol.days + 50 : PCol.days
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                tableHead("WBS | งาน", width: nil, leading: true)
                ForEach(rows, id: \.0.id) { r, stage in
                    HStack(spacing: 6) {
                        Text(r.code).font(.sarabunFixed(12, stage ? .bold : .regular)).foregroundStyle(Theme.inkMuted).frame(width: 30, alignment: .leading)
                        Text(r.title).font(.sarabunFixed(13, stage ? .bold : .regular)).foregroundStyle(Theme.navy).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, stage ? 10 : 18).padding(.trailing, 4)
                    .frame(height: 52)
                    .background(stage ? Theme.phonePage : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(width: PCol.name)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSubtle).frame(width: 1) }
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tableHead("เริ่ม", width: date)
                        tableHead("เสร็จ", width: PCol.date)
                        tableHead("วัน", width: days)
                        if showsCrewPhone(p) { tableHead("คน", width: PCol.crew) }
                        if showsLinksPhone(p) { tableHead("ต่อจาก", width: PCol.after) }
                        if showsBaselinePhone(p) { tableHead("Baseline", width: PCol.slip) }
                        tableHead("สถานะ", width: PCol.status)
                    }
                    ForEach(rows, id: \.0.id) { r, stage in
                        tableCells(r, stage: stage, p, dateWidth: date, daysWidth: days)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("plan-table")
    }

    private func tableHead(_ title: String, width: CGFloat?, leading: Bool = false) -> some View {
        Text(title).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
            .padding(.leading, leading ? 10 : 8)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: 44, maxHeight: 44, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
            .accessibilityHidden(true)
    }

    private func tableCells(_ r: InstallPlan.Row, stage: Bool, _ p: InstallPlan, dateWidth: CGFloat, daysWidth: CGFloat) -> some View {
        let canEdit = planEditing && stage && editable(r)
        let d = stage ? editedDates(r) : (start: r.start, end: r.end)
        let changed = stage && planDraft[r.id] != nil
        let lock = planEditing && !canEdit
        return HStack(spacing: 0) {
            Group {
                if canEdit {
                    HStack(spacing: 0) {
                        stepButton("chevron.left", "เลื่อนวันเริ่มก่อน \(r.code)") { setDraft(r) { $0.shift -= 1 } }
                        Text(ThaiFormat.dayMonth.string(from: d.start)).frame(maxWidth: .infinity)
                        stepButton("chevron.right", "เลื่อนวันเริ่มหลัง \(r.code)") { setDraft(r) { $0.shift += 1 } }
                    }
                } else {
                    HStack(spacing: 3) {
                        if lock { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.pending) }
                        Text(ThaiFormat.dayMonth.string(from: d.start))
                    }
                    .padding(.leading, 8)
                }
            }
            .frame(width: dateWidth, alignment: .leading)
            .background(changed && draft(r).shift != 0 ? Theme.warningSoft : .clear)
            Text(ThaiFormat.dayMonth.string(from: d.end)).padding(.leading, 8).frame(width: PCol.date, alignment: .leading)
            Group {
                if canEdit {
                    HStack(spacing: 0) {
                        stepButton("minus", "ลดวัน \(r.code)") { setDraft(r) { $0.days -= 1 } }
                        Text("\(draft(r).days)").frame(maxWidth: .infinity)
                        stepButton("plus", "เพิ่มวัน \(r.code)") { setDraft(r) { $0.days += 1 } }
                    }
                } else {
                    Text("\(stage ? draft(r).days : r.days)").padding(.leading, 8)
                }
            }
            .frame(width: daysWidth, alignment: .leading)
            .background(changed && draft(r).days != r.days ? Theme.warningSoft : .clear)
            if showsCrewPhone(p) { Text(r.crew.map(String.init) ?? "–").padding(.leading, 8).frame(width: PCol.crew, alignment: .leading) }
            if showsLinksPhone(p) { Text(r.after ?? "–").padding(.leading, 8).frame(width: PCol.after, alignment: .leading) }
            if showsBaselinePhone(p) { slipLabel(r.slip).padding(.leading, 8).frame(width: PCol.slip, alignment: .leading) }
            planStatus(r.status).padding(.leading, 8).frame(width: PCol.status, alignment: .leading)
        }
        .font(.sarabunFixed(14, stage ? .bold : .regular)).foregroundStyle(Theme.navy).monospacedDigit()
        .frame(height: 52)
        .background(stage ? Theme.phonePage : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: 32, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func planStatus(_ s: InstallGantt.Status) -> some View {
        let (title, tone): (String, InstallPageData.Tone) = switch s {
        case .done: ("เสร็จ", .ok)
        case .current: ("กำลังทำ", .info)
        case .waiting: ("ตามแผน", .idle)
        }
        return toneChip(title, tone)
    }

    // MARK: under the plan

    private func phoneCrewCard(_ p: InstallPlan) -> some View {
        let days = p.crewDays, cap = p.teamSize, chart: CGFloat = 100
        let top = CGFloat(max(days.map(\.count).max() ?? 1, (cap ?? 0) + 2, 1))
        let over = p.overTeam
        return phoneCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("กำลังคนตามแผน").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 6)
                    Text(cap.map { "เส้นประ = ทีม \($0) คน" } ?? "จากคำขอรายสัปดาห์").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(days, id: \.date) { d in
                        VStack(spacing: 2) {
                            Text(d.count > 0 ? "\(d.count)" : "").font(.sarabunFixed(11)).foregroundStyle(Theme.inkMuted).frame(height: 13)
                            RoundedRectangle(cornerRadius: 2).fill(crewColor(d.date, d.count, p)).frame(height: chart * CGFloat(d.count) / top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: chart + 15, alignment: .bottom)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let cap {
                        Path { q in q.move(to: .zero); q.addLine(to: CGPoint(x: 600, y: 0)) }
                            .stroke(Theme.danger, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1).clipped()
                            .offset(y: -chart * CGFloat(cap) / top)
                    }
                }
                if days.count <= 31 {
                    HStack(spacing: 3) {
                        ForEach(days, id: \.date) { d in
                            Text("\(MasterSchedule.calendar.component(.day, from: d.date))").font(.sarabunFixed(11))
                                .foregroundStyle(d.date == p.today ? Theme.dangerText : InstallPlan.isSunday(d.date) ? Theme.survey : Theme.inkMuted)
                                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity)
                        }
                    }
                }
                if cap != nil {
                    Text(over.isEmpty ? "ไม่มีวันที่เกินกำลังทีม" : "เกินกำลัง " + over.map(ThaiFormat.dayMonth.string(from:)).joined(separator: ", "))
                        .font(.sarabunFixed(13, .bold)).foregroundStyle(over.isEmpty ? Theme.successInk : Theme.dangerText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("กำลังคนตามแผนรายวัน " + days.map { "\($0.count)" }.joined(separator: ", ") + " คน")
    }

    private func crewColor(_ d: Date, _ n: Int, _ p: InstallPlan) -> Color {
        if let cap = p.teamSize, n > cap { return Theme.danger }
        return d < p.today ? Theme.success.opacity(0.45) : d == p.today ? Theme.primary : Theme.installPlanned
    }

    private func phoneMilestones(_ p: InstallPlan) -> some View {
        phoneCard {
            VStack(alignment: .leading, spacing: 6) {
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
                        toneChip(left < 0 ? "ผ่านแล้ว" : left == 0 ? "วันนี้" : "อีก \(left) วัน", left < 0 ? .ok : .info)
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func phoneReady(_ r: InstallPlan.Ready) -> some View {
        phoneCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("ความพร้อมขั้นถัดไป").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 6)
                    Text(r.stage).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
                ForEach(r.items, id: \.label) { item in checkRow(item.label, ok: item.ok, note: item.note) }
            }
        }
    }
}
