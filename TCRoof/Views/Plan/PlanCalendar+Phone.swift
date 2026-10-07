import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore
import SurveyUI

/// The iPhone calendar's view switch.
enum PlanPhoneMode: String, CaseIterable {
    case month = "เดือน", week = "สัปดาห์"
}

/// The team button's frame, so the menu can be drawn over the page under it.
private struct PlanTeamButtonAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

/// What the iPhone calendar draws over the visible days, worked out once per render.
struct PlanPhoneData {
    /// Visible installs (team-filtered) overlapping the days, as spans with their lane.
    var spans: [(id: PersistentIdentifier, start: Date, end: Date)] = []
    var byID: [PersistentIdentifier: Job] = [:]
    var lanes: [PersistentIdentifier: Int] = [:]
    /// Installs running on each day (start of day), earliest first.
    var installs: [Date: [Job]] = [:]
    /// Survey appointments and NO.224 reports on each day, team-filtered.
    var surveys: [Date: Int] = [:]
}

// MARK: - iPhone (docs/ui/tcroof-plan-calendar-iphone)

/// The compact layout: month or week calendar with a team filter, team-coloured range lines (one lane per
/// install job), a pink diamond for survey appointments, then the selected day's agenda.
extension PlanCalendarView {
    private static let weekdaysShort = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]

    #if DEBUG
    /// `-planToday 2026-09-30` fixes "today", to compare with the board's sample data.
    private static let debugToday: Date? = UserDefaults.standard.string(forKey: "planToday").flatMap(PlanCalendarView.isoDay)

    static func isoDay(_ raw: String) -> Date? {
        let p = raw.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        // a Gregorian date, whatever calendar the device uses
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
    #endif

    /// The real date, or `-planToday` in DEBUG builds.
    static var today: Date {
        #if DEBUG
        if let debugToday { return debugToday }
        #endif
        return Date()
    }

    private func isToday(_ d: Date) -> Bool { Calendar.current.isDate(d, inSameDayAs: Self.today) }

    var phoneBody: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    phoneTitleRow
                    phoneCounts
                }
                phoneControls
                phoneCalendarCard
                phoneAgenda
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
        .overlayPreferenceValue(PlanTeamButtonAnchor.self) { anchor in
            GeometryReader { geo in
                if teamMenuOpen, let anchor {
                    teamMenuLayer(button: geo[anchor], size: geo.size)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TCGradientHeader(title: "ปฏิทินทีมติดตั้ง", subtitle: "แผนก่อสร้างและเอกสาร") {
                HStack(spacing: 8) {
                    NavigationLink { MPOverviewView() } label: { TCHeaderIcon("chart.bar.xaxis") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("แผน MP ทุกสถานี")
                    NavigationLink { PlanListView() } label: { TCHeaderIcon("list.bullet") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("รายการแผนก่อสร้าง")
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .onAppear(perform: applyDebugState)
        #endif
    }

    #if DEBUG
    /// `-planDay 2026-10-01` selects that day (and shows its month), `-planView week`, `-planTeam TCR01` and
    /// `-planTeamMenu YES` open the board's states.
    private func applyDebugState() {
        let defaults = UserDefaults.standard
        if let day = defaults.string(forKey: "planDay").flatMap(Self.isoDay) {
            selected = day.startOfDay
            month = day.startOfMonth
        }
        if defaults.string(forKey: "planView") == "week" { phoneMode = .week }
        if let raw = defaults.string(forKey: "planTeam") { team = Team(rawValue: raw) }
        if defaults.bool(forKey: "planTeamMenu") { teamMenuOpen = true }
    }
    #endif

    // MARK: Data

    private func teamLabel(_ t: Team?) -> String { t.map { "ทีม \($0.rawValue.suffix(2))" } ?? "ทุกทีม" }

    /// The week (Sunday first) containing the selected day.
    private var selectedWeek: [Date] {
        let leading = Calendar.current.component(.weekday, from: selected) - 1
        let start = selected.startOfDay.adding(days: -leading)
        return (0..<7).map { start.adding(days: $0) }
    }

    /// The job a NO.224 report belongs to, for the team filter.
    private func reportTeam(_ r: TCRoofCore.Job) -> Team? {
        guard let id = r.jobSyncID else { return nil }
        return jobs.first { $0.syncID == id }?.team
    }

    /// `surveys(on:)` with the team filter: appointments of that team, reports linked to one of its jobs.
    private func phoneSurveys(on date: Date) -> (appointments: [Job], reports: [TCRoofCore.Job]) {
        let s = surveys(on: date)
        let appointments = s.appointments.sorted { $0.surveyDate < $1.surveyDate }
        guard let team else { return (appointments, s.reports) }
        return (appointments.filter { $0.team == team }, s.reports.filter { reportTeam($0) == team })
    }

    private func phoneData(from first: Date, to last: Date) -> PlanPhoneData {
        var data = PlanPhoneData()
        let visible = visibleJobs.filter { overlaps($0, from: first, to: last) }
        data.spans = visible.map { (id: $0.persistentModelID, start: $0.installStart, end: $0.installEnd) }
        data.byID = Dictionary(visible.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { a, _ in a })
        data.lanes = PlanLanes.assign(data.spans)
        for job in visible {
            var d = max(job.installStart.startOfDay, first)
            let end = min(job.installEnd, last)
            while d <= end {
                data.installs[d, default: []].append(job)
                d = d.adding(days: 1)
            }
        }
        var covered: [Date: Set<String>] = [:]
        for job in jobs {
            let d = job.surveyDate.startOfDay
            guard d >= first, d <= last.endOfDay else { continue }
            if let id = job.syncID { covered[d, default: []].insert(id) }
            if team == nil || job.team == team { data.surveys[d, default: 0] += 1 }
        }
        for r in surveyModel.jobs {
            guard let d = ISODate.date(r.values.text("date"))?.startOfDay, d >= first, d <= last.endOfDay else { continue }
            if let id = r.jobSyncID, covered[d]?.contains(id) == true { continue }
            if team == nil || reportTeam(r) == team { data.surveys[d, default: 0] += 1 }
        }
        return data
    }

    // MARK: Title row and controls

    /// `ติดตั้ง n งาน · สำรวจ n นัด` for the shown month, or the shown week in week view, team-filtered.
    private var phoneCounts: some View {
        let first: Date, last: Date
        if phoneMode == .week {
            let week = selectedWeek
            (first, last) = (week[0], week[6])
        } else {
            (first, last) = (month, monthEnd)
        }
        let data = phoneData(from: first, to: last)
        let surveys = data.surveys.values.reduce(0, +)
        return Text("ติดตั้ง \(data.spans.count) งาน · สำรวจ \(surveys) นัด")
            .font(.sarabun(13, relativeTo: .subheadline)).foregroundStyle(Theme.inkStrong)
            .lineLimit(1)
    }

    private var atToday: Bool {
        isToday(selected) && Calendar.current.isDate(month, equalTo: Self.today, toGranularity: .month)
    }

    @ViewBuilder private var phoneTitle: some View {
        if phoneMode == .week {
            let week = selectedWeek
            let cal = Calendar.current
            let first = week[0], last = week[6]
            let range = cal.isDate(first, equalTo: last, toGranularity: .month)
                ? "\(cal.component(.day, from: first))–\(ThaiFormat.dayMonthShort.string(from: last))"
                : "\(ThaiFormat.dayMonthShort.string(from: first)) – \(ThaiFormat.dayMonthShort.string(from: last))"
            Text(range).font(.sarabun(22, .bold, relativeTo: .title2)).foregroundStyle(Theme.navy)
        } else {
            Text(ThaiFormat.month.string(from: month)).font(.sarabun(22, .bold, relativeTo: .title2)).foregroundStyle(Theme.navy)
                + Text(" " + ThaiFormat.year.string(from: month)).font(.sarabun(22, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
        }
    }

    private var phoneTitleRow: some View {
        HStack(spacing: 2) {
            phoneTitle
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button {
                month = Self.today.startOfMonth
                selected = Self.today.startOfDay
            } label: {
                Text("วันนี้").font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 10).frame(minHeight: touchMin).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(atToday ? 0.4 : 1)
            stepButton("chevron.left", label: "ก่อนหน้า", by: -1)
            stepButton("chevron.right", label: "ถัดไป", by: 1)
        }
        .padding(.top, 12)
    }

    private func stepButton(_ symbol: String, label: String, by step: Int) -> some View {
        Button { self.step(step) } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.navy)
                .frame(width: touchMin, height: touchMin).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Month view: one month, keeping the selection. Week view: the selection moves 7 days and the month follows it.
    private func step(_ s: Int) {
        if phoneMode == .week {
            selected = selected.adding(days: 7 * s)
            month = selected.startOfMonth
        } else {
            month = month.adding(months: s)
        }
    }

    private var phoneControls: some View {
        HStack(spacing: 8) {
            TCSegmented(PlanPhoneMode.allCases.map(\.rawValue),
                        selection: Binding(get: { phoneMode.rawValue },
                                           set: { phoneMode = PlanPhoneMode(rawValue: $0) ?? .month }),
                        fontSize: 14, style: .view)
            teamButton
        }
    }

    private var teamButton: some View {
        Button { teamMenuOpen.toggle() } label: {
            HStack(spacing: 8) {
                if let team { Circle().fill(team.color).frame(width: 10, height: 10) }
                Text(teamLabel(team)).font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                    .lineLimit(1).fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.inkStrong)
            }
            .padding(.leading, 12).padding(.trailing, 10)
            .frame(height: touchMin)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Theme.borderSubtle))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .anchorPreference(key: PlanTeamButtonAnchor.self, value: .bounds) { $0 }
        .accessibilityLabel("กรองทีม \(teamLabel(team))")
        .accessibilityValue(teamMenuOpen ? "เปิดเมนูอยู่" : "")
    }

    /// The team menu under the button's right edge, over a clear layer that closes it on a tap outside.
    private func teamMenuLayer(button: CGRect, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { teamMenuOpen = false }
                .accessibilityHidden(true)
            PlanTeamMenu(selection: team) { t in
                team = t
                teamMenuOpen = false
            }
            .offset(x: max(button.maxX - PlanTeamMenu.width, 0), y: button.minY + 50)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: Calendar card

    private var phoneCalendarCard: some View {
        VStack(spacing: 0) {
            if phoneMode == .month { phoneMonth } else { phoneWeek }
            legend
        }
        .padding(.vertical, 10).padding(.horizontal, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // swipe sideways for the next or previous month (week in week view)
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) * 1.5, abs(v.translation.width) > 50 else { return }
            step(v.translation.width < 0 ? 1 : -1)
        })
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdaysShort, id: \.self) { d in
                Text(d).font(.sarabun(11.5, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var phoneMonth: some View {
        let weeks = weeks
        let data = phoneData(from: weeks.first?.first ?? month, to: weeks.last?.last ?? month)
        return VStack(spacing: 0) {
            weekdayHeader.padding(.bottom, 6)
            VStack(spacing: 6) {
                ForEach(weeks, id: \.first) { week in
                    VStack(spacing: 2) {
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in monthDay(day, data) }
                        }
                        PlanRangeLines(segments: segments(week, data), jobs: data.byID)
                    }
                }
            }
        }
    }

    private func segments(_ week: [Date], _ data: PlanPhoneData) -> [PlanLayout.Bar<PersistentIdentifier>] {
        PlanLanes.segments(data.spans, lanes: data.lanes, weekStart: week[0])
    }

    private func dayLabel(_ day: Date, _ data: PlanPhoneData) -> String {
        let key = day.startOfDay
        let installs = data.installs[key]?.count ?? 0
        let surveys = data.surveys[key] ?? 0
        return ThaiFormat.dayMonthLong.string(from: day) + (isToday(day) ? " วันนี้" : "")
            + (installs > 0 ? ", ติดตั้ง \(installs)" : "") + (surveys > 0 ? ", นัดสำรวจ \(surveys)" : "")
    }

    private func monthDay(_ day: Date, _ data: PlanPhoneData) -> some View {
        let inMonth = Calendar.current.isDate(day, equalTo: month, toGranularity: .month)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
        // a grey day of the previous or next month also turns to that month
        return Button {
            selected = day.startOfDay
            if !inMonth { month = day.startOfMonth }
        } label: {
            VStack(spacing: 3) {
                PlanPhoneDayNumber(date: day, size: 34, isSelected: isSelected, isToday: isToday(day), inMonth: inMonth)
                HStack {
                    if inMonth, (data.surveys[day.startOfDay] ?? 0) > 0 { PlanSurveyDiamond() }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: touchMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayLabel(day, data))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var phoneWeek: some View {
        let week = selectedWeek
        let data = phoneData(from: week[0], to: week[6])
        let bars = segments(week, data)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(week.enumerated()), id: \.offset) { i, day in weekDay(day, weekday: Self.weekdaysShort[i], data) }
            }
            VStack(spacing: 2) {
                ForEach(bars, id: \.id) { bar in
                    if let job = data.byID[bar.id] { PlanWeekBar(bar: bar, job: job) }
                }
            }
            .padding(.top, 2)
        }
    }

    private func weekDay(_ day: Date, weekday: String, _ data: PlanPhoneData) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
        let key = day.startOfDay
        return Button { selected = key } label: {
            VStack(spacing: 4) {
                Text(weekday).font(.sarabun(11.5, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted)
                PlanPhoneDayNumber(date: day, size: 36, isSelected: isSelected, isToday: isToday(day), inMonth: true)
                HStack(spacing: 3) {
                    ForEach(Array((data.installs[key] ?? []).prefix(2).enumerated()), id: \.offset) { _, job in
                        Circle().fill(job.team.color).frame(width: 6, height: 6)
                    }
                    if (data.surveys[key] ?? 0) > 0 { PlanSurveyDiamond() }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayLabel(day, data))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(Team.allCases.filter { team == nil || $0 == team }) { t in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(t.color).frame(width: 14, height: 5)
                    Text(t.rawValue.suffix(2))
                }
            }
            HStack(spacing: 4) {
                PlanSurveyDiamond()
                Text("สำรวจ")
            }
        }
        .font(.sarabun(11.5, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Agenda

    private var phoneAgenda: some View {
        let installs = jobs(on: selected)
        let surveys = phoneSurveys(on: selected)
        let surveyCount = surveys.appointments.count + surveys.reports.count
        let teams = Set(installs.map(\.team)).count
        let summary = [surveyCount > 0 ? "สำรวจ \(surveyCount)" : nil, installs.isEmpty ? nil : "ติดตั้ง \(installs.count)",
                       teams > 0 ? "\(teams) ทีม" : nil].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selected.thaiLong).font(.sarabun(18, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    .lineLimit(1).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(summary).font(.sarabun(13, relativeTo: .subheadline)).foregroundStyle(Theme.inkStrong).lineLimit(1)
            }
            if installs.isEmpty && surveyCount == 0 {
                Text("ไม่มีนัดในวันนี้").font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.inkStrong)
                    .padding(.vertical, 20).padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.borderSubtle, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }
            ForEach(surveys.appointments) { job in appointmentRow(job) }
            ForEach(surveys.reports) { report in reportRow(report) }
            ForEach(installs) { job in installRow(job) }
        }
        .padding(.top, 8).padding(.bottom, 4)
    }

    private func appointmentRow(_ job: Job) -> some View {
        let time = ThaiFormat.time.string(from: job.surveyDate)
        return NavigationLink { SurveyFormView(job: job) } label: {
            PlanAgendaRow(rule: Theme.survey, title: job.projectName, subtitle: "นัดสำรวจ · ทีม \(job.team.rawValue)") {
                Text("\(time) น.").font(.sarabun(15, .bold, relativeTo: .body)).monospacedDigit().foregroundStyle(Theme.navy)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("นัดสำรวจ \(job.projectName) \(time)")
        }
        .buttonStyle(.plain)
    }

    /// A NO.224 report dated that day with no appointment of its own: a survey row with the `แบบ กปภ.` badge.
    private func reportRow(_ report: TCRoofCore.Job) -> some View {
        let title = report.projectName.isEmpty ? "แบบสำรวจ กปภ." : report.projectName
        let linked = report.jobSyncID.flatMap { surveyModel.linkedJobLabel?($0) } ?? "ยังไม่ผูกกับงาน"
        return NavigationLink { SurveyReportEditor(jobID: report.id) } label: {
            PlanAgendaRow(rule: Theme.survey, title: title, subtitle: "\(linked) · \(surveyReportSummary(report))") {
                PlanInfoBadge(title: "แบบ กปภ.")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("แบบสำรวจ กปภ. \(title)")
        }
        .buttonStyle(.plain)
    }

    private func installRow(_ job: Job) -> some View {
        let day = job.installDay(on: selected) ?? 1
        let total = max(job.installDays, 1)
        return NavigationLink { JobDetailView(job: job) } label: {
            PlanAgendaRow(rule: job.team.color, title: job.projectName, subtitle: "งานติดตั้ง · ทีม \(job.team.rawValue)",
                          progress: (day, total, job.team.color)) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("วัน \(day)/\(total)").font(.sarabun(15, .bold, relativeTo: .body)).monospacedDigit().foregroundStyle(Theme.navy)
                    Text("เหลือ \(total - day) วัน").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkStrong)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("งานติดตั้ง \(job.projectName) วันที่ \(day) จาก \(total)")
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Parts

/// A day number in its circle: selected navy with light text, today primary text, other months faded.
private struct PlanPhoneDayNumber: View {
    let date: Date
    let size: CGFloat
    let isSelected: Bool
    let isToday: Bool
    let inMonth: Bool

    var body: some View {
        Text("\(Calendar.current.component(.day, from: date))")
            .font(.sarabun(15.5, isSelected || isToday ? .bold : .regular, relativeTo: .body)).monospacedDigit()
            .foregroundStyle(isSelected ? Theme.onPrimary : isToday ? Theme.primary : inMonth ? Theme.navy : Theme.dayOutside)
            .frame(width: size, height: size)
            .background { if isSelected { Circle().fill(Theme.navy) } }
    }
}

/// The survey appointment mark: a 6 pt pink square turned 45°.
struct PlanSurveyDiamond: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1).fill(Theme.survey)
            .frame(width: 6, height: 6)
            .rotationEffect(.degrees(45)).scaleEffect(0.9)
    }
}

/// Under a month row: one 5 pt line per install job on its lane, inset 5 pt where the job starts or ends and
/// square where it carries over from or into another week.
private struct PlanRangeLines: View {
    let segments: [PlanLayout.Bar<PersistentIdentifier>]
    let jobs: [PersistentIdentifier: Job]

    private static let lane: CGFloat = 5
    private static let gap: CGFloat = 3

    var body: some View {
        let lanes = (segments.map(\.lane).max() ?? -1) + 1
        GeometryReader { geo in
            let column = geo.size.width / 7
            ForEach(segments, id: \.id) { bar in
                if let job = jobs[bar.id] { line(bar, job, column: column) }
            }
        }
        .frame(height: max(CGFloat(lanes) * Self.lane + CGFloat(max(lanes - 1, 0)) * Self.gap, Self.lane))
    }

    private func line(_ bar: PlanLayout.Bar<PersistentIdentifier>, _ job: Job, column: CGFloat) -> some View {
        let leading: CGFloat = bar.continuesBefore ? 0 : 5
        let trailing: CGFloat = bar.continuesAfter ? 0 : 5
        let r: (CGFloat, CGFloat) = (bar.continuesBefore ? 0 : 3, bar.continuesAfter ? 0 : 3)
        return UnevenRoundedRectangle(topLeadingRadius: r.0, bottomLeadingRadius: r.0, bottomTrailingRadius: r.1, topTrailingRadius: r.1)
            .fill(job.team.color)
            .frame(width: max(column * CGFloat(bar.span) - leading - trailing, 0), height: Self.lane)
            .offset(x: column * CGFloat(bar.startColumn) + leading, y: CGFloat(bar.lane) * (Self.lane + Self.gap))
            .accessibilityElement()
            .accessibilityLabel("ทีม \(job.team.rawValue.suffix(2)) · \(nickname(job)) · ช่วงติดตั้ง")
    }
}

/// The project without `คุณ` / `บริษัท`, first word only: `ดารา`.
private func nickname(_ job: Job) -> String {
    let name = PlanLayout.shortName(job.projectName)
    return name.split(separator: " ").first.map(String.init) ?? name
}

/// A job's days in the week view: team tint at 20 %, a 4 pt solid leading edge, `TCR01 · <project>` or just `01`.
private struct PlanWeekBar: View {
    let bar: PlanLayout.Bar<PersistentIdentifier>
    let job: Job

    var body: some View {
        let color = job.team.color
        let label = bar.span >= 3 ? "\(job.team.rawValue) · \(job.projectName)" : String(job.team.rawValue.suffix(2))
        GeometryReader { geo in
            let column = geo.size.width / 7
            Text(label)
                .font(.sarabun(11, .bold, relativeTo: .caption)).foregroundStyle(color)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(width: max(column * CGFloat(bar.span) - 6, 0), height: 20, alignment: .leading)
                .background(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        color.opacity(0.2)
                        color.frame(width: 4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .offset(x: column * CGFloat(bar.startColumn) + 3)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ติดตั้ง ทีม \(job.team.rawValue) \(job.projectName) \(bar.span) วันในสัปดาห์นี้")
    }
}

/// The team filter's dropdown: `ทุกทีม` (a four-colour dot), then each team, the selected row tinted with a check.
private struct PlanTeamMenu: View {
    static let width: CGFloat = 170
    let selection: Team?
    let pick: (Team?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            row(nil)
            ForEach(Team.allCases) { row($0) }
        }
        .padding(6)
        .frame(width: Self.width)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
        .compositingGroup()
        .shadow(color: Theme.navy.opacity(0.18), radius: 14, y: 10)
    }

    private func row(_ t: Team?) -> some View {
        let on = t == selection
        let label = t.map { "ทีม \($0.rawValue.suffix(2))" } ?? "ทุกทีม"
        return Button { pick(t) } label: {
            HStack(spacing: 10) {
                dot(t)
                Text(label).font(.sarabun(14.5, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 0)
                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.primary) }
            }
            .padding(.horizontal, 10)
            .frame(height: touchMin)
            .background(on ? Theme.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func dot(_ t: Team?) -> some View {
        if let t {
            Circle().fill(t.color).frame(width: 10, height: 10)
        } else {
            let colors = Team.allCases.map(\.color)
            let stops = colors.enumerated().flatMap { i, c in
                [Gradient.Stop(color: c, location: Double(i) / 4), Gradient.Stop(color: c, location: Double(i + 1) / 4)]
            }
            Circle().fill(AngularGradient(stops: stops, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                .frame(width: 10, height: 10)
        }
    }
}

/// An agenda row: white, bordered, a 4 pt leading rule, title and subtitle, an optional day-by-day progress,
/// and the trailing time or day count.
private struct PlanAgendaRow<Trailing: View>: View {
    let rule: Color
    let title: String
    let subtitle: String
    var progress: (done: Int, total: Int, color: Color)?
    @ViewBuilder var trailing: Trailing

    init(rule: Color, title: String, subtitle: String, progress: (done: Int, total: Int, color: Color)? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.rule = rule; self.title = title; self.subtitle = subtitle; self.progress = progress; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabun(15.5, .bold, relativeTo: .body)).foregroundStyle(Theme.navy).lineLimit(1)
                Text(subtitle).font(.sarabun(13, relativeTo: .subheadline)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                if let progress {
                    HStack(spacing: 3) {
                        ForEach(0..<progress.total, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(i < progress.done ? progress.color : Theme.headerLine).frame(height: 4)
                        }
                    }
                    .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 10).padding(.trailing, 12).padding(.leading, 12 + 4 + 12)
        .frame(minHeight: 64)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(rule).frame(width: 4).padding(.vertical, 10).padding(.leading, 12)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
