import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

/// ภาพรวมทุกสถานี (docs/specs/master-schedule-swift.md §3.5): one row per job with an MP plan, most behind first,
/// with how many stations are behind and the progress averaged over the stations' kWp.
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
        return jobs.compactMap { job -> Row? in
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

    var body: some View {
        let rows = self.rows
        ScrollView {
            VStack(spacing: 16) {
                if rows.isEmpty {
                    ContentUnavailableView("ยังไม่มีสถานีที่มีแผน MP", systemImage: "chart.bar.xaxis",
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
            Text(title).font(.subheadline).foregroundStyle(Theme.inkMuted)
            Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(color)
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
                    Text(job.mpNumber.map { "MP \($0)" } ?? job.code).font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.primary)
                    Text(job.projectName).font(.body.weight(.semibold)).foregroundStyle(Theme.navy).lineLimit(1)
                }
                Text(row.current.map { "\($0.task.code) \($0.task.title)" } ?? "ไม่มีงานตามแผนสัปดาห์นี้")
                    .font(.subheadline).foregroundStyle(Theme.inkMuted).lineLimit(1)
                if isPhone {
                    HStack(spacing: 10) { numbers(st); MPVarianceChip(variance: st.variance) }
                }
            }
            Spacer(minLength: 8)
            if !isPhone {
                numbers(st)
                MPVarianceChip(variance: st.variance).frame(width: 150, alignment: .trailing)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.chevron)
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
        .font(.subheadline.monospacedDigit())
        .lineLimit(1).minimumScaleFactor(0.75)
    }
}
