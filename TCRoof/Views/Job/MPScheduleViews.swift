import SwiftUI
import TCRoofUI
import TCRoofCore

// MARK: - Card

#if DEBUG
extension Job {
    /// A plan around today with some progress booked behind it, unless the job has one already. `shift` moves the
    /// plan by that many days and `pace` scales the progress, so several jobs differ on the overview.
    func seedMPDemo(mp: Int = 189, shift: Int = 0, pace: Double = 1) {
        guard scheduleInput == nil else { return }
        let cal = MasterSchedule.calendar, today = cal.startOfDay(for: .now)
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n + shift, to: today)! }
        mpNumber = mp; inverterKW = 80; kind = .pwa
        scheduleInput = MasterSchedule.Input(installStart: day(-20), installEnd: day(26), kickoff: day(-70),
                                             engineeringStart: day(-70), siteHandover: day(-60), over200kVA: false)
        var a = MasterSchedule.Actual()
        for (t, pct, back) in [(MasterSchedule.Task.kickoff, 100.0, -70), (.engineering, 100, -63), (.siteHandover, 100, -56),
                               (.buildingPermit, 100, -42), (.structure, 60, -14), (.inverter, 40, -7), (.controlCabinet, 30, 0)] {
            a.setPercent(min(100, pct * pace), task: t, week: day(back), over200kVA: false)
        }
        scheduleActual = a
    }

    /// `-installLate YES`: the install window moved back (40 days ago to 6 days on), so 2.2 (DC) has passed its end
    /// with nothing done. Its late cause is kept. It changes the job for good.
    func seedLatePlan() {
        seedMPDemo()
        guard var input = scheduleInput else { return }
        let cal = MasterSchedule.calendar, today = cal.startOfDay(for: .now)
        input.installStart = cal.date(byAdding: .day, value: -40, to: today)!
        input.installEnd = cal.date(byAdding: .day, value: 6, to: today)!
        // a plan imported from a workbook keeps its own dates; the formulas place 2.2 in the moved window
        input.fixed = nil
        scheduleInput = input
        var a = scheduleActual
        a.points[MasterSchedule.Task.dcSide.rawValue] = nil
        a.started[MasterSchedule.Task.dcSide.rawValue] = nil
        a.finished[MasterSchedule.Task.dcSide.rawValue] = nil
        scheduleActual = a
    }
}
#endif

/// Job detail's "แผนงาน MP" card (docs/specs/master-schedule-swift.md §3.1): plan vs actual up to this week, the three
/// parts, and the tasks planned this week. Without a plan it offers to make one.
struct MPScheduleCard: View {
    @Bindable var job: Job
    @State private var showSetup = false
    @State private var workbook = MPWorkbookFlow()
    @Environment(\.permissions) private var permissions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("แผนงาน MP" + (job.mpNumber.map { " · MP \($0)" } ?? "")).font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                Spacer()
                if job.scheduleInput != nil, permissions.can(.mpSetup) {
                    Button("แก้ไข") { showSetup = true }.font(.sarabun(15, .semibold, relativeTo: .subheadline)).frame(minHeight: touchMin)
                }
            }
            if let input = job.scheduleInput {
                summary(input)
            } else {
                Text("สร้างแผนจากวันติดตั้งและวันยื่นขออนุญาต ระบบจัดวัน 18 งานตามไฟล์ MP ให้")
                    .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                if permissions.can(.mpSetup) {
                    Button { showSetup = true } label: {
                        Label("สร้างแผน MP", systemImage: "calendar.badge.plus")
                            .font(.sarabun(17, .semibold, relativeTo: .body)).frame(maxWidth: .infinity, minHeight: touchMin)
                    }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
                    Button { workbook.startImport() } label: {
                        Label("นำเข้าไฟล์แผน (Excel)", systemImage: "square.and.arrow.down")
                            .font(.sarabun(17, .semibold, relativeTo: .body)).frame(maxWidth: .infinity, minHeight: touchMin)
                    }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .sheet(isPresented: $showSetup) { MPSetupSheet(job: job) }
        .mpWorkbook(workbook, job: job)
        #if DEBUG
        .task { debugSeed() }
        #endif
    }

    #if DEBUG
    /// `-mpDemo plan` gives the job a sample plan (`seedMPDemo`); `-mpDemo setup` also opens ตั้งค่าแผน, and
    /// `-mpDemo new` opens it on the job with its plan cleared.
    private func debugSeed() {
        guard let mode = UserDefaults.standard.string(forKey: "mpDemo") else { return }
        if mode == "new" { job.scheduleInputJSON = nil; job.scheduleActualJSON = nil; showSetup = true; return }
        job.seedMPDemo()
        if mode == "setup" { showSetup = true }
    }
    #endif

    private func summary(_ input: MasterSchedule.Input) -> some View {
        let plan = MasterSchedule.plan(input)
        let st = MasterSchedule.status(plan: plan, actual: job.scheduleActual, through: .now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                MPRing(actual: st.actual, planned: st.planned)
                VStack(alignment: .leading, spacing: 6) {
                    MPVarianceChip(variance: st.variance)
                    Text("แผน \(MPFormat.percent(st.planned)) · ทำได้ \(MPFormat.percent(st.actual))")
                        .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    Text("ถึงสัปดาห์ \(MasterSchedule.weekStart(.now).thaiShort)").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                }
            }
            ForEach(MasterSchedule.Part.allCases, id: \.self) { part in
                MPPartBar(part: part, total: plan.filter { $0.task.part == part }.reduce(0) { $0 + $1.weight },
                          planned: st.plannedByPart[part] ?? 0, actual: st.actualByPart[part] ?? 0)
            }
            thisWeek(plan)
            NavigationLink { MPScheduleScreen(job: job) } label: {
                Label("เปิดแผนงาน MP", systemImage: "chart.bar.xaxis")
                    .font(.sarabun(17, .semibold, relativeTo: .body)).frame(maxWidth: .infinity, minHeight: touchMin)
            }
            .buttonStyle(TCButtonStyle(.secondary, size: .card))
        }
    }

    @ViewBuilder private func thisWeek(_ plan: [MasterSchedule.PlannedTask]) -> some View {
        let cal = MasterSchedule.calendar, week = MasterSchedule.weekStart(.now)
        let weekEnd = cal.date(byAdding: .day, value: 6, to: week)!
        let now = plan.filter { p in
            guard p.weight > 0, let s = p.start, let e = p.end else { return false }
            return s <= weekEnd && e >= week
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("งานสัปดาห์นี้").font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
            if now.isEmpty {
                Text("ไม่มีงานตามแผน").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
            ForEach(now) { p in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(p.task.code).font(.sarabun(15, .semibold, relativeTo: .subheadline).monospacedDigit()).foregroundStyle(Theme.primary)
                    Text(p.task.title).font(.sarabun(15, relativeTo: .subheadline)).lineLimit(1)
                }
            }
        }
    }
}

enum MPFormat {
    /// "96%" or "52.75%" → "52.8%".
    static func percent(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        return (r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) + "%"
    }
}

/// Actual % as a ring, the planned % as a tick on it.
struct MPRing: View {
    let actual: Double, planned: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.segmentTrack, lineWidth: 8)
            Circle().trim(from: 0, to: min(actual, 100) / 100)
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Capsule().fill(Theme.navy).frame(width: 3, height: 14)
                .offset(y: -32)
                .rotationEffect(.degrees(min(planned, 100) / 100 * 360))
            Text(MPFormat.percent(actual)).font(.sarabun(17, .semibold, relativeTo: .headline).monospacedDigit()).foregroundStyle(Theme.navy)
                .minimumScaleFactor(0.6).padding(10)
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ทำได้ \(MPFormat.percent(actual)) แผน \(MPFormat.percent(planned))")
    }
}

/// ช้ากว่า (red) / เร็วกว่า (green) / ตามแผน, by the variance in percentage points.
struct MPVarianceChip: View {
    let variance: Double

    var body: some View {
        let behind = variance < -0.05, ahead = variance > 0.05
        let text = behind ? "ช้ากว่า \(MPFormat.percent(-variance))" : ahead ? "เร็วกว่า \(MPFormat.percent(variance))" : "ตามแผน"
        Text(text)
            .font(.sarabun(15, .bold, relativeTo: .subheadline))
            .foregroundStyle(behind ? Theme.dangerText : ahead ? Theme.okText : Theme.navy)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(behind ? Theme.dangerSoft : ahead ? Theme.okSoft : Theme.primarySoft, in: Capsule())
            .lineLimit(1).fixedSize()
    }
}

/// One part's points done out of its weight, the plan as a tick.
struct MPPartBar: View {
    let part: MasterSchedule.Part
    let total: Double, planned: Double, actual: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(part.reportTitle).font(.sarabun(15, relativeTo: .subheadline))
                Spacer()
                Text("\(MPFormat.percent(actual)) / \(MPFormat.percent(total))").font(.sarabun(15, relativeTo: .subheadline).monospacedDigit()).foregroundStyle(Theme.inkMuted)
            }
            GeometryReader { g in
                let w = g.size.width, k = total > 0 ? w / total : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.segmentTrack)
                    Capsule().fill(Theme.primary).frame(width: min(actual, total) * k)
                    Rectangle().fill(Theme.navy).frame(width: 2, height: 12).offset(x: min(planned, total) * k - 1)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Setup

/// ตั้งค่าแผน (§3.2): the install window, the three permit dates and the over-200 kVA flag; the 18 tasks preview live.
/// Saving regenerates the plan and keeps the actual points.
struct MPSetupSheet: View {
    @Bindable var job: Job
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var input: MasterSchedule.Input
    @State private var mpNumber: Int?
    @State private var inverterKW: Double?
    /// The imported task being edited.
    @State private var editing: MasterSchedule.Task?

    init(job: Job) {
        self.job = job
        let cal = MasterSchedule.calendar
        let start = cal.startOfDay(for: job.installStart)
        let kickoff = cal.date(byAdding: .day, value: -60, to: start)!
        _input = State(initialValue: job.scheduleInput ?? MasterSchedule.Input(
            installStart: start, installEnd: cal.startOfDay(for: job.installEnd), kickoff: kickoff,
            engineeringStart: cal.date(byAdding: .day, value: 7, to: kickoff)!,
            siteHandover: cal.date(byAdding: .day, value: -30, to: start)!,
            over200kVA: MasterSchedule.Input.isOver200kVA(inverterKW: job.inverterKW ?? 0)))
        _mpNumber = State(initialValue: job.mpNumber)
        _inverterKW = State(initialValue: job.inverterKW)
    }

    private var plan: [MasterSchedule.PlannedTask] { MasterSchedule.plan(input) }
    private var isValid: Bool { input.installEnd >= input.installStart }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                PadSection("สถานี") {
                    LabeledContent("MP เลขที่") {
                        TextField("เช่น 189", value: $mpNumber, format: .number.grouping(.never))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Inverter รวม (kW)") {
                        TextField("0", value: $inverterKW, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Toggle(isOn: $input.over200kVA) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("inverter เกิน 200 kVA (ต้องยื่น พค.2)")
                            if let kw = inverterKW, kw > 0 {
                                Text("สถานีนี้ \(kw.formatted()) kW").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .onChange(of: inverterKW) { _, kw in if let kw { input.over200kVA = MasterSchedule.Input.isOver200kVA(inverterKW: kw) } }
                }
                if input.fixed != nil {
                    PadSection("แผนจากไฟล์ Excel") {
                        Text("วันและน้ำหนักของแต่ละงานมาจากไฟล์" + (job.scheduleWorkbookName.map { " \($0)" } ?? "")
                             + " ช่วงติดตั้งและวันขออนุญาตด้านล่างไม่เปลี่ยนแผนจนกว่าจะคำนวณใหม่")
                            .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                        Button("คำนวณวันใหม่ตามสูตร MP", role: .destructive) { input.fixed = nil }
                    } footer: {
                        Text("ส่งออกไฟล์แผนหลังคำนวณใหม่ จะลงวันและน้ำหนักใหม่ทุกงานในไฟล์เดิม")
                    }
                }
                PadSection("ช่วงติดตั้ง") {
                    DatePicker("วันเริ่มติดตั้ง", selection: $input.installStart, displayedComponents: .date)
                    DatePicker("วันจบติดตั้ง", selection: $input.installEnd, in: input.installStart..., displayedComponents: .date)
                } footer: {
                    Text("วันติดตั้งในปฏิทินแผนงานจะเปลี่ยนตามช่วงนี้")
                }
                PadSection("ขออนุญาต") {
                    DatePicker("Kick off", selection: $input.kickoff, displayedComponents: .date)
                    DatePicker("Engineering เริ่ม", selection: $input.engineeringStart, displayedComponents: .date)
                    DatePicker("ส่งมอบพื้นที่", selection: $input.siteHandover, displayedComponents: .date)
                    DisclosureGroup("ปรับจำนวนวัน") {
                        Stepper("Engineering \(input.engineeringDays) วัน", value: $input.engineeringDays, in: 1...90)
                        Stepper("อ.1 \(input.buildingPermitDays) วัน", value: $input.buildingPermitDays, in: 1...120)
                        Stepper("พค.2 \(input.pk2Days) วัน", value: $input.pk2Days, in: 1...120)
                        Stepper("ขนานไฟ \(input.gridConnectionDays) วัน", value: $input.gridConnectionDays, in: 1...60)
                    }
                }
                PadSection(input.fixed == nil ? "ตัวอย่างแผน 18 งาน" : "แผน 18 งานตามไฟล์") {
                    ForEach(plan) { p in
                        if input.fixed != nil {
                            Button { editing = p.task } label: {
                                HStack { MPPlanRow(task: p); Image(systemName: "chevron.right").foregroundStyle(Theme.chevron) }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("แก้วันและน้ำหนักของงานนี้")
                            .accessibilityIdentifier("mpSetup.task.\(p.task.code)")
                        } else {
                            MPPlanRow(task: p)
                        }
                    }
                } footer: {
                    if input.fixed != nil {
                        let total = plan.reduce(0) { $0 + $1.weight }
                        Text("แตะงานเพื่อแก้วันหรือน้ำหนัก ส่งออกไฟล์แผนจะลงเฉพาะงานที่แก้ · รวมน้ำหนัก \(MPFormat.percent(total))"
                             + (abs(total - 100) > 0.01 ? " (ควรเป็น 100%)" : ""))
                    }
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .sheet(item: $editing) { task in
                MPTaskEditSheet(task: task, value: input.fixed?[task.rawValue] ?? .init(start: nil, end: nil, weight: 0)) {
                    input.fixed?[task.rawValue] = $0
                }
            }
            .navigationTitle(job.scheduleInput == nil ? "สร้างแผน MP" : "ตั้งค่าแผน MP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("บันทึก", action: save).disabled(!isValid) }
            }
        }
    }

    private func save() {
        job.mpNumber = mpNumber
        job.inverterKW = inverterKW
        var input = input
        input.fitInstallWindow()
        job.scheduleInput = input
        try? context.save()
        dismiss()
    }
}

/// One task of an imported plan: its dates (or none, as COP has) and its weight.
struct MPTaskEditSheet: View {
    let task: MasterSchedule.Task
    let done: (MasterSchedule.FixedTask) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var dated: Bool
    @State private var start: Date
    @State private var end: Date
    /// Typed text, read on ตกลง: a number field only takes its value when editing ends.
    @State private var weight: String

    init(task: MasterSchedule.Task, value: MasterSchedule.FixedTask, done: @escaping (MasterSchedule.FixedTask) -> Void) {
        self.task = task; self.done = done
        let cal = MasterSchedule.calendar, s = value.start ?? cal.startOfDay(for: .now)
        _dated = State(initialValue: value.start != nil && value.end != nil)
        _start = State(initialValue: s)
        _end = State(initialValue: max(value.end ?? s, s))
        _weight = State(initialValue: value.weight == value.weight.rounded() ? String(Int(value.weight)) : String(value.weight))
    }

    private var days: Int { (MasterSchedule.calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 560) {
                PadSection("\(task.code) \(task.title)") {
                    Toggle("มีกำหนดวัน", isOn: $dated)
                    if dated {
                        DatePicker("เริ่ม", selection: $start, displayedComponents: .date)
                            .onChange(of: start) { _, s in if end < s { end = s } }
                        DatePicker("เสร็จ", selection: $end, in: start..., displayedComponents: .date)
                    }
                    LabeledContent("น้ำหนัก (%)") {
                        TextField("0", text: $weight)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("mpTask.weight")
                    }
                } footer: {
                    Text(dated ? "\(days) วัน · ส่งออกไฟล์แผนจะลงวันและน้ำหนักนี้ในแถวของงาน" : "งานที่ไม่มีกำหนดวันไม่อยู่ในแกนต์")
                }
            }
            .environment(\.locale, ThaiFormat.locale)
            .navigationTitle("แก้งาน \(task.code)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ตกลง") {
                        let cal = MasterSchedule.calendar
                        done(.init(start: dated ? cal.startOfDay(for: start) : nil, end: dated ? cal.startOfDay(for: end) : nil,
                                   weight: max(Double(weight.replacingOccurrences(of: ",", with: ".")) ?? 0, 0)))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// "2.1  ติดตั้งโครงสร้าง…  20  3 ส.ค. – 7 ก.ย." ; weight 0 shows "ไม่ใช้".
struct MPPlanRow: View {
    let task: MasterSchedule.PlannedTask

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(task.task.code).font(.sarabun(15, .semibold, relativeTo: .subheadline).monospacedDigit()).foregroundStyle(Theme.primary)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.task.title).font(.sarabun(15, relativeTo: .subheadline))
                if let s = task.start, let e = task.end {
                    Text(s == e ? s.thaiShort : "\(s.thaiShort) – \(e.thaiShort) · \(task.days() ?? 0) วัน")
                        .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 8)
            Text(task.weight > 0 ? MPFormat.percent(task.weight) : "ไม่ใช้").font(.sarabun(12, relativeTo: .caption).monospacedDigit()).foregroundStyle(Theme.muted)
        }
        .opacity(task.weight > 0 ? 1 : 0.5)
    }
}

/// `ผ่านผู้ช่วย · 60% · สมชาย · 19/10/69`: the latest change to a task confirmed on the project assistant's card, and who
/// confirmed it (`MasterSchedule.Actual.confirmations`), named from the team directory when listed there.
struct MPAssistantMark: View {
    let confirmation: MasterSchedule.Actual.Confirmation

    var body: some View {
        let who = TeamDirectory.shared.person(confirmation.by)?.label ?? confirmation.by
        let what = confirmation.replan ? "ปรับแผน" : confirmation.after
        Label {
            Text(["ผ่านผู้ช่วย", what, who, ThaiFormat.numericDate.string(from: confirmation.at)].filter { !$0.isEmpty }.joined(separator: " · "))
                .lineLimit(2)
        } icon: {
            Image(systemName: "sparkles")
        }
        .font(.sarabun(12, relativeTo: .caption))
        .foregroundStyle(Theme.inkMuted)
        .accessibilityIdentifier("mpAssistantMark")
    }
}
