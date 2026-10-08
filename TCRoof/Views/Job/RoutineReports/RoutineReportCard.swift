import SwiftUI
import TCRoofUI
import TCRoofCore

/// Job detail's "รายงานประจำ" card under the MP card (§4.1): today's status, this week's count of reported working days,
/// next week's request, and the four reports.
struct RoutineReportCard: View {
    @Bindable var job: Job
    @State private var showSettings = false

    var body: some View {
        let today = RoutineReport.calendar.startOfDay(for: .now)
        let settings = job.routineSettings
        let week = RoutineReport.week(of: today)
        let worked = RoutineReport.workingDays(settings: settings, from: week.lowerBound, to: week.upperBound)
        let reported = worked.filter { job.dailyLog(on: $0) != nil }.count
        let next = job.weeklyRequest(for: RoutineReport.calendar.date(byAdding: .day, value: 7, to: week.lowerBound)!)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("รายงานประจำ").font(.headline).foregroundStyle(Theme.navy)
                Spacer()
                Button { showSettings = true } label: { Label("ตั้งค่า", systemImage: "gearshape").labelStyle(.iconOnly).frame(width: touchMin, height: touchMin) }
                    .accessibilityLabel("ตั้งค่ารายงานประจำ")
            }
            HStack(spacing: 10) {
                Text("วันนี้").font(.subheadline).foregroundStyle(Theme.inkMuted)
                todayChip(today, working: RoutineReport.isWorkingDay(today, settings: settings))
                Spacer()
            }
            facts(reported: reported, of: worked.count, next: next)
            buttons(today)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .sheet(isPresented: $showSettings) { RoutineSettingsSheet(job: job) }
    }

    @ViewBuilder private func todayChip(_ today: Date, working: Bool) -> some View {
        switch job.dailyState(on: today) {
        case .signed: TCStatusChip("ส่งแล้ว", fill: Theme.okSoft, text: Theme.okText)
        case .draft: TCStatusChip("ร่าง", fill: Theme.warningSoft, text: Theme.pending)
        case .none:
            let late = RoutineReport.calendar.component(.hour, from: .now) >= 17
            if !working { TCStatusChip("วันหยุด", fill: Theme.segmentTrack, text: Theme.inkMuted) }
            else if late { TCStatusChip("ยังไม่ส่งรายงานวันนี้", fill: Theme.dangerSoft, text: Theme.dangerText) }
            else { TCStatusChip("ยังไม่ทำ", fill: Theme.segmentTrack, text: Theme.navy) }
        }
    }

    private func facts(reported: Int, of total: Int, next: RoutineReport.WeeklyRequest?) -> some View {
        let layout = isPhone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 20))
        let request = switch next?.status {
        case .approved?: "อนุมัติแล้ว"
        case .sent?: "รออนุมัติ"
        case .draft?: "ร่าง"
        case nil: "ยังไม่มี"
        }
        return layout {
            Label("สัปดาห์นี้รายงาน \(reported)/\(total) วันทำงาน", systemImage: "calendar")
            Label("คำขอสัปดาห์หน้า: \(request)", systemImage: "doc.badge.clock")
            Label("รายงานทั้งหมด \(job.dailyLogs.count) วัน", systemImage: "doc.text")
        }
        .font(.subheadline).foregroundStyle(Theme.navy)
    }

    private func buttons(_ today: Date) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: isPhone ? 2 : 5), spacing: 10) {
            link("รายงานวันนี้", "square.and.pencil", prominent: true) { DailyReportScreen(job: job, date: today) }
            link("รายงานย้อนหลัง", "list.bullet.rectangle") { DailyReportListView(job: job) }
            link("คำขอสัปดาห์หน้า", "doc.badge.clock") { WeeklyRequestScreen(job: job) }
            link("รายงานสัปดาห์", "calendar.badge.checkmark") { RoutineSummaryScreen(job: job, period: .week) }
            link("รายงานเดือน", "chart.bar.doc.horizontal") { RoutineSummaryScreen(job: job, period: .month) }
        }
    }

    @ViewBuilder
    private func link<D: View>(_ title: String, _ symbol: String, prominent: Bool = false, @ViewBuilder _ destination: @escaping () -> D) -> some View {
        let label = Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: touchMin)
        if prominent {
            NavigationLink(destination: destination) { label }.buttonStyle(.borderedProminent).tint(Theme.primary)
        } else {
            NavigationLink(destination: destination) { label }.buttonStyle(.bordered).tint(Theme.primary)
        }
    }
}

/// Every working day from the install start to today with its report state, missing days included, newest first.
struct DailyReportListView: View {
    let job: Job

    private var days: [Date] {
        let cal = RoutineReport.calendar
        let today = cal.startOfDay(for: .now)
        let start = cal.startOfDay(for: min(job.dailyLogs.first?.date ?? job.installStart, job.installStart))
        let end = min(today, max(cal.startOfDay(for: job.installEnd), job.dailyLogs.last.map { cal.startOfDay(for: $0.date) } ?? start))
        let worked = start <= end ? RoutineReport.workingDays(settings: job.routineSettings, from: start, to: end) : []
        let reported = job.dailyLogs.map { cal.startOfDay(for: $0.date) }
        return Array(Set(worked + reported)).sorted(by: >)
    }

    var body: some View {
        List {
            if days.isEmpty {
                ContentUnavailableView("ยังไม่ถึงช่วงติดตั้ง", systemImage: "calendar",
                                       description: Text("เริ่มติดตั้ง \(job.installStart.thaiLong)"))
            }
            ForEach(days, id: \.self) { d in
                NavigationLink { DailyReportScreen(job: job, date: d) } label: { row(d) }
            }
        }
        .navigationTitle("รายงานประจำวัน")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ d: Date) -> some View {
        let log = job.dailyLog(on: d)
        let r = log?.report
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RoutineReport.thaiDate(d)).font(.headline).foregroundStyle(Theme.navy)
                if let r {
                    Text("\(r.crewTotal) คน · \(r.progress.count) งาน" + (r.rainHours > 0 ? " · ฝน \(r.rainHours) ชม." : ""))
                        .font(.caption).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer()
            switch job.dailyState(on: d) {
            case .signed: TCStatusChip(log?.inspectorAckAt != nil ? "Inspector รับทราบ" : "ส่งแล้ว", fill: Theme.okSoft, text: Theme.okText)
            case .draft: TCStatusChip("ร่าง", fill: Theme.warningSoft, text: Theme.pending)
            case .none:
                if RoutineReport.dayKey(d) == RoutineReport.dayKey(.now), RoutineReport.calendar.component(.hour, from: .now) < 17 {
                    TCStatusChip("ยังไม่ทำ", fill: Theme.segmentTrack, text: Theme.navy)
                } else {
                    TCStatusChip("ไม่มีรายงาน", fill: Theme.dangerSoft, text: Theme.dangerText)
                }
            }
        }
        .frame(minHeight: touchMin)
    }
}
