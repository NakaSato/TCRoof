import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

// MARK: - Reports

/// The workbook's Weekly Update: cumulative plan vs actual to the chosen week, by part and by construction item.
struct MPWeeklyReport: View {
    let model: MPModel

    var body: some View {
        let st = model.status
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Update | ถึงสัปดาห์ \(model.week.thaiShort)").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
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
            Text("Monthly Update | \(monday.thaiMonthYear)").font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
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
/// Each task also takes its วันเริ่มจริง / วันเสร็จจริง (`Actual.setDates`), which the install page's Gantt and the
/// plan file's actual columns use; reaching 100% offers the end of this week (today at most) as the finish.
struct MPProgressSheet: View {
    @Bindable var job: Job
    let week: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.permissions) private var permissions
    @State private var percent: [MasterSchedule.Task: Double] = [:]
    /// Construction tasks this save brings to 100 % without their install photos, asked about before saving.
    @State private var missingPhotos: [MPMissingPhotos] = []
    @State private var started: [MasterSchedule.Task: Date] = [:]
    @State private var finished: [MasterSchedule.Task: Date] = [:]
    /// Finishes this sheet filled in at 100%, taken off again if the task drops below it.
    @State private var autoFinished: Set<MasterSchedule.Task> = []
    private let tasks: [MasterSchedule.PlannedTask]
    private let start: [MasterSchedule.Task: Double]
    private let startDates: [MasterSchedule.Task: Date]
    private let finishDates: [MasterSchedule.Task: Date]

    init(job: Job, week: Date) {
        self.job = job; self.week = week
        let input = job.scheduleInput, actual = job.scheduleActual, cal = MasterSchedule.calendar
        let plan = input.map { MasterSchedule.plan($0) } ?? []
        let weekEnd = cal.date(byAdding: .day, value: 6, to: week) ?? week
        func total(_ t: MasterSchedule.PlannedTask) -> Double {
            (actual.points[t.task.rawValue] ?? [:]).values.reduce(0, +) / t.weight * 100
        }
        let tasks = plan.filter { t in
            guard t.weight > 0 else { return false }
            let planned = t.start.map { $0 <= weekEnd } == true && t.end.map { $0 >= week } == true
            // a task with a typed start and nothing booked yet is open too
            let open = (total(t) > 0 || actual.started[t.task.rawValue] != nil) && total(t) < 99.95
            return planned || open
        }
        self.tasks = tasks
        start = Dictionary(uniqueKeysWithValues: tasks.map { ($0.task, total($0)) })
        startDates = Dictionary(uniqueKeysWithValues: tasks.compactMap { t in actual.started[t.task.rawValue].map { (t.task, $0) } })
        finishDates = Dictionary(uniqueKeysWithValues: tasks.compactMap { t in actual.finished[t.task.rawValue].map { (t.task, $0) } })
        _percent = State(initialValue: start)
        _started = State(initialValue: startDates)
        _finished = State(initialValue: finishDates)
    }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                PadSection("สัปดาห์ \(week.thaiShort) | % สะสมของแต่ละงาน") {
                    if tasks.isEmpty { Text("ไม่มีงานตามแผนหรืองานค้างในสัปดาห์นี้").foregroundStyle(Theme.muted) }
                    ForEach(tasks) { t in row(t) }
                } footer: {
                    Text("ส่วนที่เพิ่มหรือลดจะบันทึกลงสัปดาห์นี้ | วันเริ่มจริงและวันเสร็จจริงใส่หรือไม่ใส่ก็ได้")
                }
            }
            .navigationTitle("บันทึกความก้าวหน้า")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก", action: trySave).disabled(!permissions.can(.mpProgress, on: job.access))
                }
            }
            .mpMissingPhotos($missingPhotos, onSave: save)
        }
    }

    private func row(_ t: MasterSchedule.PlannedTask) -> some View {
        let p = Binding(get: { percent[t.task] ?? 0 }, set: { setPercent(($0 / 5).rounded() * 5, t) })
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
            if let c = job.scheduleActual.lastConfirmation(t.task) { MPAssistantMark(confirmation: c) }
            if let day = job.scheduleActual.fromDocuments[t.task.rawValue] { MPDocumentsMark(day: day) }
            dates(t)
        }
        .padding(.vertical, 4)
    }

    /// วันเริ่มจริง and วันเสร็จจริง side by side, each a button until it has a date.
    private func dates(_ t: MasterSchedule.PlannedTask) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { startField(t); finishField(t) }
            VStack(alignment: .leading, spacing: 4) { startField(t); finishField(t) }
        }
    }

    private func startField(_ t: MasterSchedule.PlannedTask) -> some View {
        let latest = min(finished[t.task] ?? .now, .now)
        return MPActualDateField(title: "วันเริ่มจริง", date: Binding(get: { started[t.task] }, set: { started[t.task] = $0 }),
                                 range: Date.distantPast...max(latest, Date.distantPast),
                                 suggested: { min(max(week, t.start ?? week), latest) })
    }

    private func finishField(_ t: MasterSchedule.PlannedTask) -> some View {
        let earliest = started[t.task] ?? .distantPast
        return MPActualDateField(title: "วันเสร็จจริง",
                                 date: Binding(get: { finished[t.task] }, set: { finished[t.task] = $0; autoFinished.remove(t.task) }),
                                 range: earliest...max(Date.now, earliest),
                                 suggested: { suggestedFinish(t) })
    }

    /// The end of this week, today at most, never before the start.
    private func suggestedFinish(_ t: MasterSchedule.PlannedTask) -> Date {
        let weekEnd = MasterSchedule.calendar.date(byAdding: .day, value: 6, to: week) ?? week
        return max(min(weekEnd, .now), started[t.task] ?? .distantPast)
    }

    private func setPercent(_ value: Double, _ t: MasterSchedule.PlannedTask) {
        percent[t.task] = value
        if value >= 100, finished[t.task] == nil {
            finished[t.task] = suggestedFinish(t); autoFinished.insert(t.task)
        } else if value < 100, autoFinished.contains(t.task) {
            finished[t.task] = nil; autoFinished.remove(t.task)
        }
    }

    /// Saves, unless a construction task reaches 100 % here while its install photos are missing: then the warning asks
    /// first (`บันทึกทั้งที่ยังไม่มีรูป` saves anyway).
    private func trySave() {
        let raised = tasks.filter { (percent[$0.task] ?? 0) >= 99.95 && (start[$0.task] ?? 0) < 99.95 }.map(\.task)
        missingPhotos = MPMissingPhotos.list(raised, job: job)
        if missingPhotos.isEmpty { save() }
    }

    private func save() {
        guard permissions.can(.mpProgress, on: job.access) else { return }
        var a = job.scheduleActual
        let cal = MasterSchedule.calendar
        func same(_ x: Date?, _ y: Date?) -> Bool { x.map { cal.startOfDay(for: $0) } == y.map { cal.startOfDay(for: $0) } }
        for t in tasks {
            if let p = percent[t.task], abs(p - (start[t.task] ?? 0)) > 0.01 {
                a.setPercent(p, task: t.task, week: week, weight: t.weight)
            }
            if !same(started[t.task], startDates[t.task]) || !same(finished[t.task], finishDates[t.task]) {
                a.setDates(t.task, started: started[t.task], finished: finished[t.task])
            }
        }
        job.scheduleActual = a
        // saved now, not at the next autosave: a booking made just before the app closes stays
        try? context.save()
        dismiss()
    }
}

/// One optional actual date: `+ title` until it has one, then a compact picker and a button that clears it.
struct MPActualDateField: View {
    let title: String
    @Binding var date: Date?
    let range: ClosedRange<Date>
    let suggested: () -> Date

    var body: some View {
        if let d = date {
            HStack(spacing: 4) {
                DatePicker(title, selection: Binding(get: { d }, set: { date = $0 }), in: range, displayedComponents: .date)
                    .font(.sarabun(14, relativeTo: .subheadline)).fixedSize()
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.groupFooter)
                        .frame(width: touchMin, height: touchMin)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ล้าง\(title)")
            }
        } else {
            Button { date = suggested() } label: {
                Label(title, systemImage: "plus.circle").font(.sarabun(14, .semibold, relativeTo: .subheadline))
                    .frame(minHeight: touchMin)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.primary)
            .accessibilityIdentifier("mpDate-\(title)")
        }
    }
}
