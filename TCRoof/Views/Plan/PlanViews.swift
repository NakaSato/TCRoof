import SwiftUI
import SwiftData
import SurveyCore
import SurveyUI

struct PlanCalendarView: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var month = Date().startOfMonth
    @State private var selected = Date().startOfDay
    @State private var surveyModel = SurveyModel.shared

    private static let weekdays = ["อา.", "จ.", "อ.", "พ.", "พฤ.", "ศ.", "ส."]

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(title: "แผนก่อสร้าง", symbol: AppModule.plan.symbol) {
                        HeaderLink(title: "ดูรายการแผนก่อสร้าง", systemImage: "list.bullet") { PlanListView() }
                    }
                    if geo.size.width > 900 {
                        HStack(alignment: .top, spacing: 20) {
                            calendarCard
                            dayList.frame(width: 380)
                        }
                    } else {
                        calendarCard
                        dayList
                    }
                }
                .padding(24)
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Calendar

    private var gridDays: [Date] {
        let calendar = Calendar.current
        let leading = (calendar.component(.weekday, from: month) - 1)
        let start = month.adding(days: -leading)
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let cells = Int((Double(leading + count) / 7).rounded(.up)) * 7
        return (0..<cells).map { start.adding(days: $0) }
    }

    private func jobs(on date: Date) -> [Job] {
        jobs.filter { $0.installDay(on: date) != nil }
    }

    /// Survey appointments (TCRoof jobs) and NO.224 reports dated that day. A report whose job already has
    /// its appointment on the same day is shown on that job's row rather than twice.
    private func surveys(on date: Date) -> (appointments: [Job], reports: [SurveyCore.Job]) {
        let cal = Calendar.current
        let appointments = jobs.filter { cal.isDate($0.surveyDate, inSameDayAs: date) }
        let covered = Set(appointments.compactMap(\.syncID))
        let reports = surveyModel.jobs.filter { r in
            guard let d = ISODate.date(r.values.text("date")), cal.isDate(d, inSameDayAs: date) else { return false }
            return r.jobSyncID.map { !covered.contains($0) } ?? true
        }
        return (appointments, reports)
    }

    private var calendarCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text(month.thaiMonthYear).font(.title2.bold()).foregroundStyle(Theme.navy)
                Spacer()
                Button("วันนี้") {
                    month = Date().startOfMonth
                    selected = Date().startOfDay
                }
                .buttonStyle(.bordered)
                navButton("chevron.left", label: "เดือนก่อนหน้า") { month = month.adding(months: -1) }
                navButton("chevron.right", label: "เดือนถัดไป") { month = month.adding(months: 1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 10) {
                ForEach(Self.weekdays, id: \.self) { Text($0).font(.caption.bold()).foregroundStyle(Theme.navy) }
                ForEach(gridDays, id: \.self) { day in
                    DayCell(date: day,
                            inMonth: Calendar.current.isDate(day, equalTo: month, toGranularity: .month),
                            isSelected: Calendar.current.isDate(day, inSameDayAs: selected),
                            teams: Array(Set(jobs(on: day).map(\.team))).sorted { $0.rawValue < $1.rawValue },
                            hasSurvey: { let s = surveys(on: day); return !s.appointments.isEmpty || !s.reports.isEmpty }())
                        .onTapGesture { selected = day.startOfDay }
                }
            }
            HStack(spacing: 16) {
                ForEach(Team.allCases) { team in
                    HStack(spacing: 6) {
                        Circle().fill(team.color).frame(width: 10, height: 10)
                        Text("ทีม \(team.rawValue)").font(.caption).foregroundStyle(Theme.navy)
                    }
                }
                HStack(spacing: 6) {
                    SurveyDot()
                    Text("นัดสำรวจ").font(.caption).foregroundStyle(Theme.navy)
                }
                Spacer()
            }
        }
        .cardStyle(padding: 24)
    }

    private func navButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.navy, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(label)
    }

    // MARK: Day list

    private var dayList: some View {
        let dayJobs = jobs(on: selected)
        let daySurveys = surveys(on: selected)
        return VStack(alignment: .leading, spacing: 12) {
            Text(selected.isToday ? "วันนี้ · \(selected.thaiLong)" : selected.thaiLong)
                .font(.title3.bold())
                .foregroundStyle(Theme.navy)
            if !daySurveys.appointments.isEmpty || !daySurveys.reports.isEmpty {
                Text("งานสำรวจ").font(.subheadline.bold()).foregroundStyle(Theme.muted)
                ForEach(daySurveys.appointments) { job in
                    NavigationLink { JobDetailView(job: job) } label: {
                        PlanSurveyRow(title: job.linkLabel, detail: "นัดสำรวจ \(job.surveyDate.formatted(date: .omitted, time: .shortened)) · \(job.customerName)",
                                      reports: job.syncID.map { surveyModel.jobs(linkedTo: $0).count } ?? 0)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(daySurveys.reports) { report in
                    NavigationLink { SurveyReportEditor(jobID: report.id) } label: {
                        PlanSurveyRow(title: report.projectName.isEmpty ? "แบบสำรวจ กปภ." : report.projectName,
                                      detail: (report.jobSyncID.flatMap { surveyModel.linkedJobLabel?($0) } ?? "ยังไม่ผูกกับงาน") + " · " + surveyReportSummary(report),
                                      reports: 1)
                    }
                    .buttonStyle(.plain)
                }
                Text("งานติดตั้ง").font(.subheadline.bold()).foregroundStyle(Theme.muted)
            }
            if dayJobs.isEmpty {
                Text("ไม่มีงานติดตั้งในวันนี้")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            }
            ForEach(dayJobs) { job in
                NavigationLink { JobDetailView(job: job) } label: { PlanJobRow(job: job, date: selected) }
                    .buttonStyle(.plain)
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let inMonth: Bool
    let isSelected: Bool
    let teams: [Team]
    var hasSurvey = false

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.headline)
                .foregroundStyle(inMonth ? (date.isToday ? Theme.primary : Theme.navy) : Theme.muted.opacity(0.6))
                .frame(width: 40, height: 40)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(date.isWeekend && inMonth ? Color.gray.opacity(0.12) : .clear)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8).stroke(Theme.primary, lineWidth: 2)
                    }
                }
            HStack(spacing: 3) {
                ForEach(teams) { Circle().fill($0.color).frame(width: 7, height: 7) }
                if hasSurvey { SurveyDot() }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.thaiLong), \(teams.count) งาน" + (hasSurvey ? ", มีนัดสำรวจ" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Hollow dot marking a survey day, next to the filled team dots of install days.
private struct SurveyDot: View {
    var body: some View { Circle().strokeBorder(Theme.navy, lineWidth: 1.5).frame(width: 7, height: 7) }
}

/// A survey appointment or NO.224 report in the day list.
private struct PlanSurveyRow: View {
    let title: String
    let detail: String
    /// NO.224 reports behind this row; shown as a badge.
    let reports: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.clipboard").foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold()).lineLimit(1)
                Text(detail).font(.caption).lineLimit(2)
            }
            Spacer()
            if reports > 0 {
                Text("แบบ กปภ.").font(.caption2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.primary, in: Capsule())
            }
        }
        .foregroundStyle(Theme.navy)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.navy.opacity(0.12)))
    }
}

struct PlanJobRow: View {
    let job: Job
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TeamTag(team: job.team)
                Text(job.code).font(.subheadline.bold())
                Spacer()
                if let day = job.installDay(on: date) {
                    Text("Day \(day)/\(job.installDays)").font(.caption.bold())
                }
            }
            Text("\(job.capacityKW.kw) | \(job.province)").font(.caption)
            Label(job.customerName, systemImage: "person").font(.caption)
            Text("โครงการ : \(job.projectName)").font(.caption)
        }
        .foregroundStyle(Theme.navy)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.mint.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(job.team.color)
                .frame(width: 5)
        }
    }
}

struct PlanListView: View {
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var search = ""

    private var grouped: [(month: Date, jobs: [Job])] {
        let filtered = jobs.filter { $0.matches(search) }
        let dict = Dictionary(grouping: filtered) { $0.installStart.startOfMonth }
        return dict.keys.sorted().map { ($0, dict[$0]!) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.month) { group in
                Section(group.month.thaiMonthYear) {
                    ForEach(group.jobs) { job in
                        NavigationLink { JobDetailView(job: job) } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2).fill(job.team.color).frame(width: 4)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(job.code).bold()
                                        TeamTag(team: job.team)
                                    }
                                    Text(job.projectName).font(.subheadline)
                                    Text("\(job.installStart.thaiShort) – \(job.installEnd.thaiShort) · \(job.installDays) วัน · \(job.capacityKW.kw)")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                StatusBadge(title: job.status.title, color: job.status.color)
                            }
                            .foregroundStyle(Theme.navy)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "ค้นหาด้วยชื่อลูกค้าหรือรหัสโครงการ")
        .navigationTitle("รายการแผนก่อสร้าง")
    }
}
