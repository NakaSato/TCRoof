import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore

/// Construction plan month view: install jobs as bars across the days they run, survey appointments as
/// dashed pills, and the selected day's work in a panel on the right.
struct PlanCalendarView: View {
    @Query(sort: \Job.installStart) var jobs: [Job]
    @State var month = Self.today.startOfMonth
    @State var selected = Self.today.startOfDay
    /// nil shows every team.
    @State var team: Team?
    @State var surveyModel = SurveyModel.shared
    /// iPhone: `เดือน` or `สัปดาห์`, and whether the team menu is open.
    @State var phoneMode = PlanPhoneMode.month
    @State var teamMenuOpen = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.permissions) private var permissions

    private static let weekdays = ["อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัสบดี", "ศุกร์", "เสาร์"]

    /// `day`: the day selected when it opens (the home's `ดูแผนงาน ›`).
    init(day: Date? = nil) {
        let d = day ?? Self.today
        _month = State(initialValue: d.startOfMonth)
        _selected = State(initialValue: d.startOfDay)
    }

    var body: some View {
        if sizeClass == .compact { phoneBody } else { padBody }
    }

    /// iPad (docs/ui/plan-calendar): the wall planner with install bars and the day panel.
    private var padBody: some View {
        GeometryReader { geo in
            if geo.size.width > 900 {
                HStack(alignment: .top, spacing: 16) {
                    calendarCard(rowHeight: nil)
                    dayPanel(scrolls: true).frame(width: 360)
                }
                .padding(.top, 16).padding([.horizontal, .bottom], 24)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        calendarCard(rowHeight: 112)
                        dayPanel(scrolls: false)
                    }
                    .padding(.top, 16).padding([.horizontal, .bottom], isPhone ? 16 : 24)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TCNavBar(title: "แผนก่อสร้าง", trail: ["หน้าหลัก", "แผนก่อสร้างและเอกสาร"], current: "ปฏิทิน") {
                HStack(spacing: 8) {
                    TopBarLink(title: "แผน MP ทุกสถานี", systemImage: "chart.bar.xaxis") { MPOverviewView() }
                    TopBarLink(title: "ดูรายการแผนก่อสร้าง", systemImage: "list.bullet") { PlanListView() }
                }
            }
        }
        .background(Theme.pageGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Data

    var monthEnd: Date { month.adding(months: 1).adding(days: -1) }

    func overlaps(_ job: Job, from start: Date, to end: Date) -> Bool {
        job.installStart.startOfDay <= end && job.installEnd >= start
    }

    /// Installs overlapping the visible month, every team.
    private var monthJobs: [Job] { jobs.filter { overlaps($0, from: month, to: monthEnd) } }

    var visibleJobs: [Job] { team.map { t in jobs.filter { $0.team == t } } ?? jobs }

    var weeks: [[Date]] {
        let calendar = Calendar.current
        let leading = calendar.component(.weekday, from: month) - 1
        let start = month.adding(days: -leading)
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let rows = Int((Double(leading + count) / 7).rounded(.up))
        return (0..<rows).map { w in (0..<7).map { start.adding(days: w * 7 + $0) } }
    }

    func jobs(on date: Date) -> [Job] {
        visibleJobs.filter { $0.installDay(on: date) != nil }
    }

    /// Survey appointments (TCRoof jobs) and NO.224 reports dated that day. A report whose job already has
    /// its appointment on the same day is shown on that job's row rather than twice.
    func surveys(on date: Date) -> (appointments: [Job], reports: [TCRoofCore.Job]) {
        let cal = Calendar.current
        let appointments = jobs.filter { cal.isDate($0.surveyDate, inSameDayAs: date) }
        let covered = Set(appointments.compactMap(\.syncID))
        let reports = surveyModel.jobs.filter { r in
            guard let d = ISODate.date(r.values.text("date")), cal.isDate(d, inSameDayAs: date) else { return false }
            return r.jobSyncID.map { !covered.contains($0) } ?? true
        }
        return (appointments, reports)
    }

    /// Installs and survey counts per day (start of day) and the bars' spans over the visible weeks, worked out once per render
    /// rather than by filtering every job and report again for each of the 35–42 cells.
    private struct GridData {
        var installs: [Date: Int] = [:]
        /// Teams installing that day, in `Team.allCases` order (the iPhone grid's dots).
        var teams: [Date: [Team]] = [:]
        var surveys: [Date: Int] = [:]
        /// The visible jobs as `PlanLayout` spans, and by id, for every week's bars.
        var spans: [(id: PersistentIdentifier, start: Date, end: Date)] = []
        var byID: [PersistentIdentifier: Job] = [:]
    }

    /// The same counts as `jobs(on:)` and `surveys(on:)`, for every day from `first` to `last`.
    private func gridData(from first: Date, to last: Date) -> GridData {
        var c = GridData()
        let visible = visibleJobs
        c.spans = visible.map { (id: $0.persistentModelID, start: $0.installStart, end: $0.installEnd) }
        c.byID = Dictionary(visible.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { a, _ in a })
        for job in visible {
            var d = max(job.installStart.startOfDay, first)
            let end = min(job.installEnd, last)
            while d <= end {
                c.installs[d, default: 0] += 1
                if c.teams[d]?.contains(job.team) != true { c.teams[d, default: []].append(job.team) }
                d = d.adding(days: 1)
            }
        }
        for (d, t) in c.teams { c.teams[d] = Team.allCases.filter(t.contains) }
        var covered: [Date: Set<String>] = [:]
        for job in jobs {
            let d = job.surveyDate.startOfDay
            guard d >= first, d <= last else { continue }
            c.surveys[d, default: 0] += 1
            if let id = job.syncID { covered[d, default: []].insert(id) }
        }
        for r in surveyModel.jobs {
            guard let d = ISODate.date(r.values.text("date"))?.startOfDay, d >= first, d <= last else { continue }
            if let id = r.jobSyncID, covered[d]?.contains(id) == true { continue }
            c.surveys[d, default: 0] += 1
        }
        return c
    }

    // MARK: Calendar card

    /// `rowHeight` nil: the week rows share the card's height (wide layout, no page scroll).
    private func calendarCard(rowHeight: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow
            monthGrid(rowHeight: rowHeight)
            footerRow
        }
        .padding(16)
        .frame(maxHeight: rowHeight == nil ? .infinity : nil, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardShadow()
    }

    private var titleRow: some View {
        let inMonth = monthJobs
        let appointments = jobs.filter { $0.surveyDate >= month && $0.surveyDate < month.adding(months: 1) }.count
        let teams = Set(inMonth.map(\.team)).count
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(month.thaiMonthYear).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.navy)
                Text("\(inMonth.count) งานติดตั้ง | \(appointments) นัดสำรวจ | \(teams) ทีมทำงาน")
                    .font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 12)
            PlanMonthStepper(
                previous: { month = month.adding(months: -1) },
                today: { month = Date().startOfMonth; selected = Date().startOfDay },
                next: { month = month.adding(months: 1) })
        }
    }

    private func monthGrid(rowHeight: CGFloat?) -> some View {
        let weeks = weeks
        let counts = gridData(from: weeks.first?.first ?? month, to: weeks.last?.last ?? month)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Self.weekdays.indices, id: \.self) { i in
                    Text(Self.weekdays[i])
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(i % 6 == 0 ? Theme.muted : Theme.inkMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(weeks, id: \.first) { week in
                Rectangle().fill(Theme.borderSubtle).frame(height: 1)
                weekRow(week, counts)
                    .frame(height: rowHeight)
                    .frame(maxHeight: rowHeight == nil ? .infinity : nil)
            }
        }
        .frame(maxHeight: rowHeight == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func weekRow(_ week: [Date], _ counts: GridData) -> some View {
        let cal = Calendar.current
        let bars = PlanLayout.lanes(for: counts.spans, weekStart: week[0]).compactMap { bar in
            counts.byID[bar.id].map { PlanBarItem(bar: bar, job: $0) }
        }
        let days = week.map { day in
            PlanDayInfo(date: day,
                        inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                        isSelected: cal.isDate(day, inSameDayAs: selected),
                        installs: counts.installs[day.startOfDay] ?? 0,
                        surveys: counts.surveys[day.startOfDay] ?? 0)
        }
        return PlanWeekRow(days: days, bars: bars) { selected = $0.startOfDay }
    }

    /// Team filter chips, then the survey legend when there is room for it.
    private var footerRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                teamChips
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Circle().strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 14, height: 14)
                    Text("นัดสำรวจ").font(.system(size: 13)).foregroundStyle(Theme.inkMuted).fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { teamChips } }
        }
    }

    @ViewBuilder private var teamChips: some View {
        let inMonth = monthJobs
        PlanTeamChip(title: "ทุกทีม", color: Theme.navy, count: inMonth.count, isOn: team == nil) { team = nil }
        ForEach(Team.allCases) { t in
            PlanTeamChip(title: t.rawValue, color: t.color, count: inMonth.filter { $0.team == t }.count, isOn: team == t) { team = t }
        }
    }

    // MARK: Day panel

    private func dayPanel(scrolls: Bool) -> some View {
        let dayJobs = jobs(on: selected)
        let daySurveys = surveys(on: selected)
        let surveyCount = daySurveys.appointments.count + daySurveys.reports.count
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.isToday ? "วันนี้ | \(selected.thaiLong)" : selected.thaiLong)
                    .font(.system(size: 17, weight: .bold))
                Text("\(surveyCount) งานสำรวจ | \(dayJobs.count) งานติดตั้ง").font(.system(size: 12))
            }
            .foregroundStyle(Theme.navy)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paperBand)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
            if scrolls {
                ScrollView { dayContent(dayJobs, daySurveys) }
            } else {
                dayContent(dayJobs, daySurveys)
            }
        }
        .frame(maxHeight: scrolls ? .infinity : nil, alignment: .top)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardShadow()
    }

    private func dayContent(_ dayJobs: [Job], _ daySurveys: (appointments: [Job], reports: [TCRoofCore.Job])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !daySurveys.appointments.isEmpty || !daySurveys.reports.isEmpty {
                sectionCaption("งานสำรวจ")
                ForEach(daySurveys.appointments) { job in
                    VStack(spacing: 0) {
                        NavigationLink { JobDetailView(job: job) } label: {
                            PlanSurveyRow(title: job.linkLabel, detail: appointmentDetail(job),
                                          isReport: job.syncID.map { !surveyModel.jobs(linkedTo: $0).isEmpty } ?? false)
                        }
                        .buttonStyle(.plain)
                        // นำทาง | โทร | ปฏิทิน: the customer's phone and address are the team's
                        if permissions.can(.jobEdit), job.hasSurveyAppointment { AppointmentActions(job: job) }
                    }
                }
                ForEach(daySurveys.reports) { report in
                    NavigationLink { SurveyReportEditor(jobID: report.id) } label: {
                        PlanSurveyRow(title: report.projectName.isEmpty ? "แบบสำรวจ กปภ." : report.projectName,
                                      detail: (report.jobSyncID.flatMap { surveyModel.linkedJobLabel?($0) } ?? "ยังไม่ผูกกับงาน") + " | " + surveyReportSummary(report),
                                      isReport: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            sectionCaption("งานติดตั้ง")
            if dayJobs.isEmpty {
                Label("ไม่มีงานติดตั้งในวันนี้", systemImage: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.paperPage, in: RoundedRectangle(cornerRadius: 8))
            }
            ForEach(dayJobs) { job in
                NavigationLink { JobDetailView(job: job) } label: { PlanDayJobRow(job: job, date: selected) }
                    .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func appointmentDetail(_ job: Job) -> String {
        let time = "นัดสำรวจ \(ThaiFormat.time.string(from: job.surveyDate))"
        return job.customerName == job.projectName ? time : "\(time) | \(job.customerName)"
    }

    private func sectionCaption(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkMuted)
    }
}
