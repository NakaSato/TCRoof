import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// ภาพรวมทุกสถานี (docs/specs/master-schedule-swift.md §3.5): one row per PWA job with an MP plan, most behind first,
/// with how many stations are behind and the progress averaged over the stations' kWp. Under them, the PWA
/// representative's inspection appointments and the deadlines of two weeks, as on the iPhone `แผนงาน` page.
struct MPOverviewView: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]

    /// One station's figures to this week.
    struct Row: Identifiable {
        let job: Job
        let status: MasterSchedule.Status
        /// The first task with weight planned this week and not yet done.
        let current: MasterSchedule.PlannedTask?
        var id: PersistentIdentifier { job.persistentModelID }
    }

    private var rows: [Row] {
        let cal = MasterSchedule.calendar, week = MasterSchedule.weekStart(.now)
        let weekEnd = cal.date(byAdding: .day, value: 6, to: week)!
        return jobs.pwaStations.compactMap { job -> Row? in
            guard let input = job.scheduleInput else { return nil }
            let plan = MasterSchedule.plan(input), st = MasterSchedule.status(plan: plan, actual: job.scheduleActual, through: .now)
            let current = plan.first { p in
                guard p.weight > 0, let s = p.start, let e = p.end, s <= weekEnd, e >= week else { return false }
                return (st.actualByTask[p.task] ?? 0) < 99.95
            }
            return Row(job: job, status: st, current: current)
        }
        .sorted { $0.status.variance < $1.status.variance }
    }

    /// The inspection appointments from today to the end of next week, and the deadlines of the two weeks.
    private var upcoming: (inspections: [PWAPlan.AgendaItem], due: PWAPlan.DeadlineGroups) {
        let cal = PWAPlan.calendar, today = Date.now
        let board = PWAPlanBoard(stations: jobs.pwaStations.map(\.planStation), library: StationDocsStore.loadLibrary(), today: today,
                                 threshold: SurveyModel.shared.settings.behindThreshold)
        let due = PWAPlan.groups(board.deadlines, today: today)
        let last = cal.date(byAdding: .day, value: 6, to: due.nextStart) ?? today
        let span = max(cal.dateComponents([.day], from: cal.startOfDay(for: today), to: last).day ?? 0, 0)
        let days = (0...span).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        return (board.agenda(days).filter { $0.type == .inspection }, due)
    }

    var body: some View {
        let rows = self.rows, upcoming = self.upcoming
        ScrollView {
            VStack(spacing: 16) {
                if rows.isEmpty {
                    TCEmptyState("ยังไม่มีสถานีที่มีแผน MP", systemImage: "chart.bar.xaxis",
                                           description: Text("สร้างแผนจากการ์ดแผนงาน MP ในหน้างาน"))
                } else {
                    totals(rows)
                    VStack(spacing: 0) {
                        ForEach(rows) { r in
                            NavigationLink { MPScheduleScreen(job: r.job) } label: { MPOverviewRow(row: r) }
                                .buttonStyle(.plain)
                            if r.id != rows.last?.id { Divider().padding(.leading, 16) }
                        }
                    }
                    .cardStyle(padding: 0)
                }
                if !upcoming.inspections.isEmpty { inspectionCard(upcoming.inspections) }
                if !upcoming.due.all.isEmpty { dueCard(upcoming.due) }
            }
            .padding(isPhone ? 16 : 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .navigationTitle("แผน MP ทุกสถานี")
        .navigationBarTitleDisplayMode(.inline)
        .tcPadNavBar("แผน MP ทุกสถานี", trail: ["หน้าหลัก", "แผนก่อสร้างและเอกสาร"])
    }

    // MARK: inspections and deadlines

    private func job(_ station: String) -> Job? { jobs.first { $0.overviewID == station } }

    private func heading(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.sarabun(17, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            Text(detail).font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Date, title over subtitle, and a chip: one line of the two cards.
    private func line(_ date: String, _ title: String, _ subtitle: String, chip: String, fill: Color, ink: Color) -> some View {
        HStack(spacing: 12) {
            Text(date).font(.sarabun(15, .semibold, relativeTo: .subheadline).monospacedDigit()).foregroundStyle(Theme.primary)
                .frame(width: isPhone ? 92 : 130, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabun(17, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                Text(subtitle).font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            TCStatusChip(chip, fill: fill, text: ink)
            Image(systemName: "chevron.right").font(.sarabun(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.chevron)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(minHeight: touchMin)
        .contentShape(Rectangle())
    }

    private func inspectionCard(_ items: [PWAPlan.AgendaItem]) -> some View {
        VStack(spacing: 0) {
            heading("นัดตรวจรับ", "ผู้แทน กปภ. · ถึงสิ้นสัปดาห์หน้า")
            ForEach(items) { item in
                let when = PWAPlanFormat.dayMonth.string(from: item.day) + (item.start.map { " " + PWAPlan.clock($0) } ?? "")
                NavigationLink {
                    if let job = job(item.station) { JobDetailView(job: job) }
                } label: {
                    line(when, item.title, [item.ref, item.subtitle].filter { !$0.isEmpty }.joined(separator: " · "),
                         chip: item.status.title, fill: Theme.planInspectSoft, ink: Theme.planInspect)
                }
                .buttonStyle(.plain)
                if item.id != items.last?.id { Divider().padding(.leading, 16) }
            }
        }
        .cardStyle(padding: 0)
    }

    private func toneColors(_ tone: PWAPlan.Tone) -> (fill: Color, ink: Color) {
        switch tone {
        case .late: (Theme.dangerSoft, Theme.dangerText)
        case .risk: (Theme.warningTint, Theme.warningText)
        case .ok: (Theme.okSoft, Theme.okText)
        }
    }

    /// The handovers, submissions and trainings of this week (with everything overdue) and the next.
    private func dueCard(_ due: PWAPlan.DeadlineGroups) -> some View {
        let rows = due.thisWeek + due.nextWeek
        return VStack(spacing: 0) {
            heading("กำหนดส่ง", "สัปดาห์นี้และสัปดาห์หน้า · รวมที่เลยกำหนด")
            ForEach(rows) { d in
                let colors = toneColors(d.tone)
                NavigationLink {
                    if let job = job(d.station) {
                        if d.opens == .docs { StationDocsScreen(job: job) } else { JobDetailView(job: job) }
                    }
                } label: {
                    line(PWAPlanFormat.dayMonth.string(from: d.date), d.title, d.subtitle, chip: d.chip, fill: colors.fill, ink: colors.ink)
                }
                .buttonStyle(.plain)
                if d.id != rows.last?.id { Divider().padding(.leading, 16) }
            }
        }
        .cardStyle(padding: 0)
    }

    /// Stations, how many are behind, and plan / actual averaged by kWp (equally when no station has a kWp).
    private func totals(_ rows: [Row]) -> some View {
        let w = rows.map { max($0.job.capacityKW, 0) }, sum = w.reduce(0, +)
        let weights = sum > 0 ? w : rows.map { _ in 1.0 }, total = sum > 0 ? sum : Double(rows.count)
        let plan = zip(rows, weights).reduce(0) { $0 + $1.0.status.planned * $1.1 } / total
        let actual = zip(rows, weights).reduce(0) { $0 + $1.0.status.actual * $1.1 } / total
        let behind = rows.filter { $0.status.variance < -0.05 }.count
        let cols = isPhone ? [GridItem(.flexible()), GridItem(.flexible())] : Array(repeating: GridItem(.flexible()), count: 4)
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
            figure("สถานีที่มีแผน", "\(rows.count)")
            figure("ช้ากว่าแผน", "\(behind)", color: behind > 0 ? Theme.dangerText : Theme.navy)
            figure("แผนเฉลี่ย", MPFormat.percent(plan))
            figure("ทำได้เฉลี่ย", MPFormat.percent(actual))
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func figure(_ title: String, _ value: String, color: Color = Theme.navy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabun(22, .bold, relativeTo: .title2).monospacedDigit()).foregroundStyle(color)
        }
    }
}

/// "MP 189  สถานี…   แผน 45%  ทำได้ 23%  [ช้ากว่า 22%]   2.1 ติดตั้งโครงสร้าง…"
struct MPOverviewRow: View {
    let row: MPOverviewView.Row

    var body: some View {
        let st = row.status, job = row.job
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(job.mpNumber.map { "MP \($0)" } ?? job.code).font(.sarabun(15, .semibold, relativeTo: .subheadline).monospacedDigit())
                        .foregroundStyle(Theme.primary)
                    Text(job.projectName).font(.sarabun(17, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy).lineLimit(1)
                }
                let contractor = job.routineSettings.subcontractor.trimmingCharacters(in: .whitespaces)
                Text([row.current.map { "\($0.task.code) \($0.task.title)" } ?? "ไม่มีงานตามแผนสัปดาห์นี้",
                      contractor.isEmpty ? "" : PWAPlan.contractorTitle(contractor)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                if isPhone {
                    HStack(spacing: 10) { numbers(st); MPVarianceChip(variance: st.variance) }
                }
            }
            Spacer(minLength: 8)
            if !isPhone {
                numbers(st)
                MPVarianceChip(variance: st.variance).frame(width: 150, alignment: .trailing)
            }
            Image(systemName: "chevron.right").font(.sarabun(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.chevron)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: touchMin)
        .contentShape(Rectangle())
    }

    private func numbers(_ st: MasterSchedule.Status) -> some View {
        HStack(spacing: 10) {
            Text("แผน \(MPFormat.percent(st.planned))").foregroundStyle(Theme.inkMuted)
            Text("ทำได้ \(MPFormat.percent(st.actual))").fontWeight(.semibold).foregroundStyle(Theme.navy)
        }
        .font(.sarabun(15, relativeTo: .subheadline).monospacedDigit())
        .lineLimit(1).minimumScaleFactor(0.75)
    }
}
