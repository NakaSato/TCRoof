import SwiftUI
import TCRoofUI
import TCRoofCore
import PDFReport
import ExcelExport

/// แผนงาน MP full screen (docs/specs/master-schedule-swift.md §3.3): a week picker with plan / actual / variance, the
/// Gantt of the 18 tasks, and the workbook's Weekly or Monthly Update for the chosen week. iPad wide: Gantt left,
/// report right; otherwise the report first and the Gantt under it.
struct MPScheduleScreen: View {
    @Bindable var job: Job
    /// Only the team sets up the plan (`mp.setup`) and books progress by hand (`mp.progress`).
    @Environment(\.permissions) private var permissions
    @Environment(\.modelContext) private var context
    @State private var week: Date
    @State private var monthly = false
    @State private var showProgress = false
    @State private var showSetup = false
    /// The weekly-meeting PDF being shared.
    @State private var pdf: SharedFile?
    struct SharedFile: Identifiable { let id = UUID(); let url: URL }
    @State private var exportError: String?
    @State private var workbook = MPWorkbookFlow()

    var body: some View {
        GeometryReader { g in
            if let input = job.scheduleInput {
                let model = MPModel(input: input, actual: job.scheduleActual, week: week)
                content(model, wide: !isPhone && g.size.width >= 1000)
            } else {
                VStack(spacing: 16) {
                    TCEmptyState("ยังไม่มีแผน MP", systemImage: "calendar", description: Text("สร้างแผนจากการ์ดแผนงาน MP หรือนำเข้าไฟล์แผนของสถานี"))
                    if permissions.can(.mpSetup) {
                        Button { workbook.startImport() } label: { Label("นำเข้าไฟล์แผน (Excel)", systemImage: "square.and.arrow.down") }
                            .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .navigationTitle("แผนงาน MP" + (job.mpNumber.map { " · MP \($0)" } ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: exportPDF) { Label("PDF ประชุม", systemImage: "square.and.arrow.up") }
                    .disabled(job.scheduleInput == nil)
                    .accessibilityHint("แผนภูมิแกนต์และ Weekly Update ของสัปดาห์ที่เลือก หนึ่งหน้า A3")
            }
            if permissions.can(.mpSetup) {
                ToolbarItem(placement: .primaryAction) { Button("ตั้งค่าแผน") { showSetup = true } }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu { MPWorkbookMenuItems(flow: workbook, job: job, canImport: permissions.can(.mpSetup)) } label: {
                    Label("ไฟล์ Excel", systemImage: "tablecells")
                }
            }
        }
        .tcPadNavBar("แผนงาน MP" + (job.mpNumber.map { " · MP \($0)" } ?? ""), trail: ["หน้าหลัก", job.code], current: "แผนงาน MP") {
            HStack(spacing: 12) {
                if permissions.can(.mpSetup) { TCButton("ตั้งค่าแผน", kind: .secondary) { showSetup = true } }
                Menu { MPWorkbookMenuItems(flow: workbook, job: job, canImport: permissions.can(.mpSetup)) } label: {
                    Label("ไฟล์ Excel", systemImage: "tablecells").font(.sarabun(17, .semibold, relativeTo: .body)).frame(minHeight: touchMin)
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                TCButton("PDF ประชุม", systemImage: "square.and.arrow.up", kind: .secondary, action: exportPDF)
                    .disabled(job.scheduleInput == nil)
                    .accessibilityHint("แผนภูมิแกนต์และ Weekly Update ของสัปดาห์ที่เลือก หนึ่งหน้า A3")
            }
        }
        // a plan made or imported here opens on its own weeks
        .onChange(of: job.scheduleInputJSON) { _, _ in openOnPlan() }
        .sheet(isPresented: $showProgress) { MPProgressSheet(job: job, week: week) }
        .sheet(isPresented: $showSetup) { MPSetupSheet(job: job) }
        .mpWorkbook(workbook, job: job)
        .sheet(item: $pdf) { f in ActivitySheet(items: [f.url]).presentationDetents([.medium, .large]) }
        .alert("สร้าง PDF ไม่สำเร็จ", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("ตกลง", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        #if DEBUG
        // `-mpDemo screen|progress` (with `-screen mp`) opens this screen, or its progress sheet
        .task {
            // `-mpWeek yyyy-MM-dd` opens on that week
            if let s = UserDefaults.standard.string(forKey: "mpWeek"), let d = ISODate.date(s) { week = MasterSchedule.weekStart(d) }
            switch UserDefaults.standard.string(forKey: "mpDemo") {
            case "progress"?: showProgress = true
            // `-mpDemo pdf` also writes the weekly-meeting page to Documents/mp.pdf
            case "pdf"?:
                if let input = job.scheduleInput, let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let s = MasterScheduleSheet.page(input: input, actual: job.scheduleActual, week: week, title: "MP \(job.mpNumber ?? 0) " + job.projectName)
                    try? PDFRenderer.pdf(s, title: "MP").write(to: docs.appendingPathComponent("mp.pdf"))
                }
            default: break
            }
            // `-mpWorkbook import` takes Documents/mp-import.xlsx as the plan; `-mpWorkbook export` writes the kept file
            // with the plan and progress to Documents/mp-export.xlsx
            guard let mode = UserDefaults.standard.string(forKey: "mpWorkbook"),
                  let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            if mode == "import", let data = try? Data(contentsOf: docs.appendingPathComponent("mp-import.xlsx")),
               let imported = try? MPWorkbook.read(data) {
                workbook.apply(.init(data: data, name: "mp-import.xlsx", imported: imported), to: job, context: context)
            }
            if mode == "export", let original = job.scheduleWorkbook, let input = job.scheduleInput,
               let out = try? MPWorkbook.export(original, input: input, actual: job.scheduleActual) {
                try? out.data.write(to: docs.appendingPathComponent("mp-export.xlsx"))
            }
        }
        #endif
    }

    @ViewBuilder private func content(_ m: MPModel, wide: Bool) -> some View {
        if wide {
            VStack(spacing: 16) {
                topBar(m)
                HStack(alignment: .top, spacing: 16) {
                    MPGantt(model: m, onRow: { showProgress = true }).cardStyle(padding: 0)
                    ScrollView { report(m) }.frame(width: 380)
                }
            }
            .padding(24)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    topBar(m)
                    report(m)
                    MPGantt(model: m, onRow: { showProgress = true }).frame(height: 760).cardStyle(padding: 0)
                }
                .padding(16)
            }
        }
    }

    private func topBar(_ m: MPModel) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button { shift(-7) } label: { Image(systemName: "chevron.left").frame(width: touchMin, height: touchMin) }
                    .accessibilityLabel("สัปดาห์ก่อน")
                VStack(spacing: 2) {
                    Text("สัปดาห์ \(week.thaiShort)").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    if let i = m.weekIndex(week) { Text("W\(i)").font(.sarabun(12, relativeTo: .caption).monospacedDigit()).foregroundStyle(Theme.muted) }
                }
                .frame(minWidth: isPhone ? 0 : 150).layoutPriority(1)
                Button { shift(7) } label: { Image(systemName: "chevron.right").frame(width: touchMin, height: touchMin) }
                    .accessibilityLabel("สัปดาห์ถัดไป")
                Button("สัปดาห์นี้") { week = MasterSchedule.weekStart(.now) }.font(.sarabun(15, .semibold, relativeTo: .subheadline)).fixedSize()
                Spacer(minLength: 8)
                if !isPhone { figures(m) }
            }
            if isPhone { HStack { figures(m); Spacer() } }
            HStack {
                TCSegmented(["Weekly", "Monthly"], selection: Binding(get: { monthly ? "Monthly" : "Weekly" }, set: { monthly = $0 == "Monthly" }))
                    .frame(maxWidth: 260).accessibilityLabel("รายงาน")
                Spacer()
                if permissions.can(.mpProgress) {
                    Button { showProgress = true } label: {
                        Label(isPhone ? "อัปเดต" : isThisWeek ? "อัปเดตสัปดาห์นี้" : "อัปเดตสัปดาห์ที่เลือก", systemImage: "square.and.pencil").font(.sarabun(17, .semibold, relativeTo: .body))
                            .lineLimit(1).frame(minHeight: touchMin)
                    }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
                }
            }
        }
        .cardStyle()
    }

    private func figures(_ m: MPModel) -> some View {
        HStack(spacing: 12) {
            Text("แผน \(MPFormat.percent(m.status.planned))").font(.sarabun(15, relativeTo: .subheadline).monospacedDigit())
            Text("ทำได้ \(MPFormat.percent(m.status.actual))").font(.sarabun(15, .semibold, relativeTo: .subheadline).monospacedDigit())
            MPVarianceChip(variance: m.status.variance)
        }
        .foregroundStyle(Theme.navy)
    }

    /// The Gantt and the Weekly / Monthly Update of the chosen week as one A3 page, named `MP<no>_<yyyy-MM-dd>.pdf`.
    private func exportPDF() {
        guard let input = job.scheduleInput else { return }
        let title = [job.mpNumber.map { "MP \($0)" }, job.projectName.isEmpty ? nil : job.projectName].compactMap { $0 }.joined(separator: " ")
        let sketch = MasterScheduleSheet.page(input: input, actual: job.scheduleActual, week: week, title: title.isEmpty ? job.code : title)
        let name = (job.mpNumber.map { "MP\($0)" } ?? job.code) + "_" + ISODate.string(week) + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try PDFRenderer.pdf(sketch, title: "แผนงาน MP " + title).write(to: url, options: .atomic)
            pdf = SharedFile(url: url)
        } catch { exportError = error.localizedDescription }
    }

    init(job: Job) {
        self.job = job
        _week = State(initialValue: job.scheduleInput.map { MPModel.openingWeek(input: $0, actual: job.scheduleActual) }
                      ?? MasterSchedule.weekStart(.now))
    }

    private func openOnPlan() {
        guard let input = job.scheduleInput else { return }
        #if DEBUG
        if UserDefaults.standard.string(forKey: "mpWeek") != nil { return }
        #endif
        week = MPModel.openingWeek(input: input, actual: job.scheduleActual)
    }

    private var isThisWeek: Bool { week == MasterSchedule.weekStart(.now) }

    private func shift(_ days: Int) {
        week = MasterSchedule.calendar.date(byAdding: .day, value: days, to: week) ?? week
    }

    @ViewBuilder private func report(_ m: MPModel) -> some View {
        if monthly { MPMonthlyReport(model: m) } else { MPWeeklyReport(model: m) }
    }
}

/// The plan, the actual and the chosen week, worked out once per render.
struct MPModel {
    let input: MasterSchedule.Input
    let actual: MasterSchedule.Actual
    let week: Date
    let plan: [MasterSchedule.PlannedTask]
    let status: MasterSchedule.Status
    /// Every week from the earliest planned start (or booked point) to the latest end, and the chosen week.
    let weeks: [Date]

    init(input: MasterSchedule.Input, actual: MasterSchedule.Actual, week: Date) {
        self.input = input; self.actual = actual; self.week = week
        plan = MasterSchedule.plan(input)
        status = MasterSchedule.status(plan: plan, actual: actual, through: week)
        let booked = actual.points.values.flatMap(\.keys).compactMap(MPModel.date(fromKey:))
        let dates = plan.compactMap(\.start) + plan.compactMap(\.end) + booked + [week]
        weeks = MasterSchedule.weeks(from: dates.min() ?? week, to: dates.max() ?? week)
    }

    /// The week the screen opens on: this week while the plan runs; before it, its first week; after it, its last week
    /// or the last week with booked progress, so an old plan (an imported 2567 workbook) opens on its own weeks.
    static func openingWeek(input: MasterSchedule.Input, actual: MasterSchedule.Actual, today: Date = .now) -> Date {
        let plan = MasterSchedule.plan(input)
        let booked = actual.points.filter { !$0.value.isEmpty }.values.flatMap(\.keys).compactMap(date(fromKey:))
        let now = MasterSchedule.weekStart(today)
        guard let first = (plan.compactMap(\.start) + booked).min(),
              let last = (plan.compactMap(\.end) + booked).max() else { return now }
        if now < MasterSchedule.weekStart(first) { return MasterSchedule.weekStart(first) }
        if now > MasterSchedule.weekStart(last) { return MasterSchedule.weekStart(last) }
        return now
    }

    func weekIndex(_ w: Date) -> Int? { weeks.firstIndex(of: MasterSchedule.weekStart(w)) }

    static func date(fromKey k: String) -> Date? {
        let n = k.split(separator: "-").compactMap { Int($0) }
        guard n.count == 3 else { return nil }
        return MasterSchedule.calendar.date(from: DateComponents(year: n[0], month: n[1], day: n[2]))
    }
}

// MARK: - Gantt

/// Rows = parts and tasks; columns = weeks. Planned bar from start to end; actual as the weeks with points, shaded by
/// the share of the task's weight; the chosen week highlighted and today as a red line. Tapping a row opens the
/// progress sheet.
struct MPGantt: View {
    let model: MPModel
    let onRow: () -> Void

    static let rowH: CGFloat = 44, headerH: CGFloat = 40, labelW: CGFloat = isPhone ? 150 : 230, cellW: CGFloat = 34

    enum Row: Identifiable {
        case part(MasterSchedule.Part), task(MasterSchedule.PlannedTask)
        var id: String { switch self { case let .part(p): "p\(p.rawValue)"; case let .task(t): t.id } }
    }
    var rows: [Row] {
        MasterSchedule.Part.allCases.flatMap { part in
            [Row.part(part)] + model.plan.filter { $0.task.part == part }.map(Row.task)
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                labels
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            grid
                        }
                        .overlay(alignment: .topLeading) { anchors }
                    }
                    .onAppear { proxy.scrollTo(model.weekIndex(model.week) ?? 0, anchor: .center) }
                    .onChange(of: model.week) { _, w in withAnimation { proxy.scrollTo(model.weekIndex(w) ?? 0, anchor: .center) } }
                }
            }
        }
    }

    /// Invisible markers per week, for scrolling to the chosen one.
    private var anchors: some View {
        HStack(spacing: 0) {
            ForEach(model.weeks.indices, id: \.self) { i in Color.clear.frame(width: Self.cellW, height: 1).id(i) }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("งาน").font(.sarabun(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted)
                .frame(width: Self.labelW, height: Self.headerH, alignment: .leading).padding(.leading, 12)
            ForEach(rows) { row in label(row) }
        }
        .background(Theme.surface)
    }

    @ViewBuilder private func label(_ row: Row) -> some View {
        switch row {
        case let .part(p):
            Text(p.reportTitle).font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                .frame(width: Self.labelW, height: Self.rowH, alignment: .leading).padding(.leading, 12)
                .background(Theme.primarySoft)
        case let .task(t):
            Button(action: onRow) {
                HStack(spacing: 6) {
                    Text(t.task.code).font(.sarabun(12, .semibold, relativeTo: .caption).monospacedDigit()).foregroundStyle(Theme.primary)
                        .frame(width: 26, alignment: .leading)
                    Text(t.task.title).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.navy).lineLimit(2)
                    Spacer(minLength: 4)
                    Text(t.weight > 0 ? MPFormat.percent(t.weight) : "ไม่ใช้").font(.sarabun(11, relativeTo: .caption2).monospacedDigit()).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 12)
                .frame(width: Self.labelW + 12, height: Self.rowH)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(t.weight > 0 ? 1 : 0.5)
            .accessibilityHint("บันทึกความก้าวหน้า")
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.weeks.enumerated()), id: \.offset) { i, w in
                VStack(spacing: 1) {
                    Text(MPGantt.dayMonth(w)).font(.system(size: 9).monospacedDigit())
                    Text("W\(i)").font(.system(size: 9, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(w == model.week ? Theme.primary : Theme.muted)
                .frame(width: Self.cellW, height: Self.headerH)
            }
        }
    }

    static func dayMonth(_ d: Date) -> String {
        let c = MasterSchedule.calendar.dateComponents([.day, .month], from: d)
        return "\(c.day ?? 0)/\(c.month ?? 0)"
    }

    private var grid: some View {
        let rows = self.rows, weeks = model.weeks, chosen = model.weekIndex(model.week)
        let w = CGFloat(weeks.count) * Self.cellW, h = CGFloat(rows.count) * Self.rowH
        let first = weeks.first ?? model.week, cal = MasterSchedule.calendar
        let primary = Theme.primary, navy = Theme.navy, line = Theme.borderSubtle, soft = Theme.primarySoft, danger = Theme.danger
        let actual = model.actual
        func x(_ d: Date) -> CGFloat {
            CGFloat(cal.dateComponents([.day], from: first, to: cal.startOfDay(for: d)).day ?? 0) / 7 * Self.cellW
        }
        return Canvas { ctx, _ in
            if let chosen {
                ctx.fill(Path(CGRect(x: CGFloat(chosen) * Self.cellW, y: 0, width: Self.cellW, height: h)), with: .color(soft.opacity(0.7)))
            }
            for i in 0...weeks.count {
                ctx.stroke(Path { $0.move(to: CGPoint(x: CGFloat(i) * Self.cellW, y: 0)); $0.addLine(to: CGPoint(x: CGFloat(i) * Self.cellW, y: h)) },
                           with: .color(line), lineWidth: 0.5)
            }
            for (r, row) in rows.enumerated() {
                let y = CGFloat(r) * Self.rowH
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y + Self.rowH)); $0.addLine(to: CGPoint(x: w, y: y + Self.rowH)) },
                           with: .color(line), lineWidth: 0.5)
                guard case let .task(t) = row else {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: Self.rowH)), with: .color(soft.opacity(0.5)))
                    continue
                }
                if let s = t.start, let e = t.end {
                    let x0 = x(s), x1 = max(x(e) + Self.cellW / 7, x0 + 4)
                    ctx.fill(Path(roundedRect: CGRect(x: x0, y: y + 8, width: x1 - x0, height: 12), cornerRadius: 3),
                             with: .color(t.weight > 0 ? navy.opacity(0.75) : navy.opacity(0.25)))
                }
                guard t.weight > 0 else { continue }
                for (k, pts) in actual.points[t.task.rawValue] ?? [:] where pts > 0 {
                    guard let wd = MPModel.date(fromKey: k), let i = weeks.firstIndex(of: wd) else { continue }
                    let share = min(1, pts / t.weight)
                    ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * Self.cellW + 2, y: y + 24, width: Self.cellW - 4, height: 12), cornerRadius: 3),
                             with: .color(primary.opacity(0.3 + 0.7 * share)))
                }
            }
            let tx = x(.now)
            if tx >= 0 && tx <= w {
                ctx.stroke(Path { $0.move(to: CGPoint(x: tx, y: 0)); $0.addLine(to: CGPoint(x: tx, y: h)) }, with: .color(danger), lineWidth: 1.5)
            }
        }
        .frame(width: w, height: h)
        .accessibilityLabel("แผนภูมิแกนต์ \(rows.count) แถว \(weeks.count) สัปดาห์")
    }
}

// MARK: - Reports

/// The workbook's Weekly Update: cumulative plan vs actual to the chosen week, by part and by construction item.
struct MPWeeklyReport: View {
    let model: MPModel

    var body: some View {
        let st = model.status
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Update · ถึงสัปดาห์ \(model.week.thaiShort)").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            MPReportRow(title: "รวมทั้งสถานี", planned: st.planned, actual: st.actual, bold: true)
            ForEach(MasterSchedule.Part.allCases, id: \.self) { p in
                MPReportRow(title: p.reportTitle, planned: st.plannedByPart[p] ?? 0, actual: st.actualByPart[p] ?? 0)
            }
            Divider()
            Text("งานติดตั้ง (% ของแต่ละงาน)").font(.sarabun(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
            ForEach(model.plan.filter { $0.task.part == .construction && $0.weight > 0 }) { t in
                MPReportRow(title: "\(t.task.code) \(t.task.title)", planned: st.plannedByTask[t.task] ?? 0, actual: st.actualByTask[t.task] ?? 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// The workbook's Monthly Update: points planned and done inside the chosen week's month (filed by its Monday).
struct MPMonthlyReport: View {
    let model: MPModel

    var body: some View {
        let cal = MasterSchedule.calendar
        let monday = cal.date(byAdding: .day, value: 1, to: model.week) ?? model.week
        let c = cal.dateComponents([.year, .month], from: monday)
        let m = MasterSchedule.month(plan: model.plan, actual: model.actual, year: c.year ?? 0, month: c.month ?? 0)
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Update · \(monday.thaiMonthYear)").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            MPReportRow(title: "รวมเดือนนี้", planned: m.planned.values.reduce(0, +), actual: m.actual.values.reduce(0, +), bold: true)
            ForEach(MasterSchedule.Part.allCases, id: \.self) { p in
                MPReportRow(title: p.reportTitle, planned: m.planned[p] ?? 0, actual: m.actual[p] ?? 0)
            }
            Text("% เดือนนี้ของทั้งสถานี").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// "title    แผน 45%   จริง 23%   −22.3"
struct MPReportRow: View {
    let title: String
    let planned: Double, actual: Double
    var bold = false

    var body: some View {
        let v = actual - planned
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(bold ? .sarabun(15, .bold, relativeTo: .subheadline) : .sarabun(15, relativeTo: .subheadline)).lineLimit(2)
            Spacer(minLength: 8)
            Text(MPFormat.percent(planned)).frame(width: 56, alignment: .trailing).foregroundStyle(Theme.inkMuted)
            Text(MPFormat.percent(actual)).frame(width: 56, alignment: .trailing).fontWeight(.semibold)
            Text(abs(v) < 0.05 ? "–" : (v > 0 ? "+" : "−") + MPFormat.percent(abs(v)).dropLast())
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(v < -0.05 ? Theme.dangerText : v > 0.05 ? Theme.okText : Theme.muted)
        }
        .font(.sarabun(15, relativeTo: .subheadline).monospacedDigit())
        .foregroundStyle(Theme.navy)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Progress

/// บันทึกความก้าวหน้า (§3.4): for the chosen week, each task planned in it or started and unfinished, as % done of the
/// task. The change from what is booked is written into that week (`Actual.setPercent`), capped at the task's weight.
struct MPProgressSheet: View {
    @Bindable var job: Job
    let week: Date
    @Environment(\.dismiss) private var dismiss
    @State private var percent: [MasterSchedule.Task: Double] = [:]
    private let tasks: [MasterSchedule.PlannedTask]
    private let start: [MasterSchedule.Task: Double]

    init(job: Job, week: Date) {
        self.job = job; self.week = week
        let input = job.scheduleInput, actual = job.scheduleActual, cal = MasterSchedule.calendar
        let plan = input.map { MasterSchedule.plan($0) } ?? []
        let weekEnd = cal.date(byAdding: .day, value: 6, to: week)!
        func total(_ t: MasterSchedule.PlannedTask) -> Double {
            (actual.points[t.task.rawValue] ?? [:]).values.reduce(0, +) / t.weight * 100
        }
        let tasks = plan.filter { t in
            guard t.weight > 0 else { return false }
            let planned = t.start.map { $0 <= weekEnd } == true && t.end.map { $0 >= week } == true
            let open = total(t) > 0 && total(t) < 99.95
            return planned || open
        }
        self.tasks = tasks
        start = Dictionary(uniqueKeysWithValues: tasks.map { ($0.task, total($0)) })
        _percent = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                PadSection("สัปดาห์ \(week.thaiShort) · % สะสมของแต่ละงาน") {
                    if tasks.isEmpty { Text("ไม่มีงานตามแผนหรืองานค้างในสัปดาห์นี้").foregroundStyle(Theme.muted) }
                    ForEach(tasks) { t in row(t) }
                } footer: {
                    Text("ส่วนที่เพิ่มหรือลดจะบันทึกลงสัปดาห์นี้")
                }
            }
            .navigationTitle("บันทึกความก้าวหน้า")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("บันทึก", action: save) }
            }
        }
    }

    private func row(_ t: MasterSchedule.PlannedTask) -> some View {
        let p = Binding(get: { percent[t.task] ?? 0 }, set: { percent[t.task] = ($0 / 5).rounded() * 5 })
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(t.task.code).font(.sarabun(15, .semibold, relativeTo: .subheadline).monospacedDigit()).foregroundStyle(Theme.primary)
                Text(t.task.title).font(.sarabun(15, relativeTo: .subheadline))
            }
            HStack(spacing: 12) {
                Slider(value: p, in: 0...100, step: 5).tint(Theme.primary)
                Stepper("\(Int((percent[t.task] ?? 0).rounded()))%", value: p, in: 0...100, step: 5)
                    .font(.sarabun(17, .semibold, relativeTo: .body).monospacedDigit()).fixedSize()
            }
            if let s = t.start, let e = t.end {
                Text("แผน \(s.thaiShort) – \(e.thaiShort)").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        var a = job.scheduleActual
        for t in tasks {
            guard let p = percent[t.task], abs(p - (start[t.task] ?? 0)) > 0.01 else { continue }
            a.setPercent(p, task: t.task, week: week, weight: t.weight)
        }
        job.scheduleActual = a
        dismiss()
    }
}
