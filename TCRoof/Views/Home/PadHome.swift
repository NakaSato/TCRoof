import SwiftUI
import TCRoofCore
import SurveyUI

/// iPad home (regular width, docs/ui/tcroof-home-ipad): brand header; `นัดวันนี้`, `วันนี้` and `งานสำรวจค้างอยู่`
/// on the left; six module rows on the right, on one screen. Under ~1000 pt wide the columns stack in one scroll view.
struct PadHome<Popover: View>: View {
    let appointments: [TodayAppointment]
    let timeline: [TimelineItem]
    let pending: [PendingSurvey]
    let unread: Int
    let surveyToday: Int
    let installChip: String?
    let greetingFacts: HomeGreeting.Facts
    @Binding var notificationsShown: Bool
    let openSettings: () -> Void
    let open: (TodayAppointment, MissingGroup.Target?) -> Void
    let openInstall: (Job) -> Void
    let openReport: (PendingSurvey) -> Void
    let showSurveyList: () -> Void
    let newSurvey: () -> Void
    @ViewBuilder let notifications: () -> Popover

    @AppStorage("userName") private var userName = ""
    @Environment(GoogleSession.self) private var session
    @State private var page = 0

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 1000 {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) {
                        hero
                        TodayTimelineCard(items: timeline, fill: true, select: select, open: open, openInstall: openInstall)
                        if !pending.isEmpty { PendingSurveysCard(items: pending, open: openReport, showAll: showSurveyList) }
                    }
                    .frame(width: 520)
                    moduleRows(spacing: 12)
                }
                .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 28)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        hero
                        TodayTimelineCard(items: timeline, fill: false, select: select, open: open, openInstall: openInstall)
                        if !pending.isEmpty { PendingSurveysCard(items: pending, open: openReport, showAll: showSurveyList) }
                        moduleRows(spacing: 12).frame(height: 6 * 96 + 5 * 12)
                    }
                    .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 28)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HomeBrandHeader(size: .pad, initials: userInitials(userName, email: session.email), unread: unread, facts: greetingFacts,
                            notificationsShown: $notificationsShown, openSettings: openSettings, popover: notifications)
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .overlay {
            // the board dims the page lightly behind the bell popover
            if notificationsShown { Theme.popoverDim.ignoresSafeArea().allowsHitTesting(false) }
        }
    }

    private var hero: some View {
        AppointmentHero(size: .pad, appointments: appointments, page: $page, open: open, newSurvey: newSurvey)
    }

    /// A survey row of the timeline moves the hero to its appointment.
    private func select(_ item: TimelineItem) {
        guard let i = appointments.firstIndex(where: { $0.id == item.appointment.id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { page = i }
    }

    private func moduleRows(spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(AppModule.allCases) { module in
                NavigationLink { module.destination } label: {
                    ModuleRow(size: .pad, module: module, chip: module.chip(surveyToday: surveyToday, installDay: installChip))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Timeline data

/// One entry of the `วันนี้` timeline: an install day or a survey appointment of today.
struct TimelineItem: Identifiable {
    enum Kind { case live, next, later }
    let kind: Kind
    let date: Date
    let isInstall: Bool
    /// The job with its linked report, for the ring, navigate and call.
    let appointment: TodayAppointment
    let tag: String
    let right: String
    let name: String
    let place: String
    let progress: Double
    let action: String

    var id: String { (isInstall ? "install-" : "survey-") + appointment.id }
    var time: String { ThaiFormat.time.string(from: date) }

    /// Today's install days and survey appointments in time order. An install day is "live"; the first survey
    /// still ahead is "next"; the rest are "later".
    @MainActor static func list(jobs: [Job], survey: SurveyModel) -> [TimelineItem] {
        func report(_ job: Job) -> TCRoofCore.Job? { job.syncID.flatMap { survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } } }
        let cal = Calendar.current
        var out: [TimelineItem] = []
        for job in jobs {
            guard let day = job.installDay(on: .now) else { continue }
            let start = cal.date(bySettingHour: cal.component(.hour, from: job.installStart),
                                 minute: cal.component(.minute, from: job.installStart), second: 0, of: .now) ?? .now
            let started = start <= .now
            let a = TodayAppointment(job: job, report: report(job))
            out.append(TimelineItem(kind: .live, date: start, isInstall: true, appointment: a,
                                    tag: "ติดตั้ง · Day \(day)/\(job.installDays)",
                                    right: started ? "กำลังทำ" : a.countdown(to: start),
                                    name: "\(job.code) · ทีม \(job.team.rawValue)",
                                    place: [job.province.isEmpty ? nil : "จ.\(job.province)",
                                            job.capacityKW > 0 ? "\(job.capacityKW.plain) kWp" : nil,
                                            started ? "ทีมเข้างานแล้ว" : nil].compactMap { $0 }.joined(separator: " · "),
                                    progress: Double(day) / Double(max(job.installDays, 1)),
                                    action: "เปิดบันทึกประจำวัน ›"))
        }
        let surveys = jobs.filter { $0.surveyDate.isToday }.sorted { $0.surveyDate < $1.surveyDate }
        let nextID = surveys.first { $0.surveyDate > .now }?.persistentModelID
        for job in surveys {
            let a = TodayAppointment(job: job, report: report(job))
            let ahead = job.surveyDate > .now
            let isNext = job.persistentModelID == nextID
            let steps = a.report.map { "\($0.stepsDone)/\($0.steps.count) ขั้น" } ?? "ยังไม่เริ่ม"
            out.append(TimelineItem(kind: isNext ? .next : .later, date: job.surveyDate, isInstall: false, appointment: a,
                                    tag: isNext ? "นัดสำรวจ · ถัดไป" : "นัดสำรวจ",
                                    right: ahead ? a.countdown : "ผ่านแล้ว",
                                    name: a.name,
                                    place: [a.place, steps].filter { !$0.isEmpty }.joined(separator: " · "),
                                    progress: a.fraction, action: a.actionTitle))
        }
        return out.sorted { $0.date < $1.date }
    }
}

extension TCRoofCore.Job {
    /// Steps with nothing left to fill, out of `steps.count` ("10/13 ขั้น").
    var stepsDone: Int { steps.filter { $0.completion.total == 0 || $0.completion.isComplete }.count }
}

// MARK: - Timeline card

/// `วันนี้`: time, a line with a dot per item, and a card that expands (one at a time) into a progress bar and actions.
private struct TodayTimelineCard: View {
    let items: [TimelineItem]
    /// Fill the column's remaining height and scroll inside (landscape); natural height when stacked.
    let fill: Bool
    let select: (TimelineItem) -> Void
    let open: (TodayAppointment, MissingGroup.Target?) -> Void
    let openInstall: (Job) -> Void

    /// nil until the first tap: the next survey starts expanded.
    @State private var expanded: String??
    @State private var calling: TodayAppointment?
    @Environment(\.openURL) private var openURL

    private var openID: String? { expanded ?? items.first { $0.kind == .next }?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("วันนี้").font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    .accessibilityAddTraits(.isHeader)
                Text("\(items.count) รายการ").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 4)
            if items.isEmpty {
                Text("ไม่มีงานสำรวจหรืองานติดตั้งในวันนี้").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 16)
            } else if fill {
                ScrollView { rows }.scrollBounceBehavior(.basedOnSize)
            } else {
                rows
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.borderSubtle))
        .callDialog($calling, open: open)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                row(item, first: i == 0, last: i == items.count - 1)
            }
        }
        .padding(.leading, 10).padding(.trailing, 16).padding(.bottom, 10)
    }

    private func row(_ item: TimelineItem, first: Bool, last: Bool) -> some View {
        let isOpen = openID == item.id
        return HStack(alignment: .top, spacing: 10) {
            Text(item.time).font(.sarabun(14, .bold, relativeTo: .subheadline)).monospacedDigit()
                .foregroundStyle(timeColor(item.kind))
                .frame(width: 48, alignment: .trailing).padding(.top, 12)
            rail(item.kind, first: first, last: last)
            VStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded = .some(isOpen ? nil : item.id) }
                    if !item.isInstall { select(item) }
                } label: { card(item, open: isOpen) }
                .buttonStyle(.plain)
                .accessibilityHint(isOpen ? "แตะเพื่อย่อ" : "แตะเพื่อดูการทำงาน")
                if isOpen { actions(item) }
            }
            .padding(.vertical, 4)
        }
    }

    /// The vertical line through the dots; it starts at the first dot and ends at the last.
    private func rail(_ kind: TimelineItem.Kind, first: Bool, last: Bool) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Theme.borderSubtle).frame(width: 2)
                .frame(maxHeight: last ? 18 : .infinity, alignment: .top)
                .padding(.top, first ? 18 : 0)
                .frame(maxHeight: .infinity, alignment: .top)
            dot(kind).padding(.top, 15)
        }
        .frame(width: 14)
    }

    @ViewBuilder private func dot(_ kind: TimelineItem.Kind) -> some View {
        switch kind {
        case .live: Circle().fill(Theme.success).frame(width: 13, height: 13)
        case .next:
            Circle().fill(Theme.primary).frame(width: 13, height: 13)
                .background(Circle().fill(Theme.primary.opacity(0.18)).padding(-4))
        case .later: Circle().strokeBorder(Theme.chevron, lineWidth: 2).background(Circle().fill(Theme.surface)).frame(width: 13, height: 13)
        }
    }

    private func timeColor(_ kind: TimelineItem.Kind) -> Color {
        switch kind {
        case .live: Theme.successInk
        case .next: Theme.primary
        case .later: Theme.inkMuted
        }
    }

    private func card(_ item: TimelineItem, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(item.tag).font(.sarabun(12, .bold, relativeTo: .caption)).lineLimit(1)
                    .foregroundStyle(tagColors(item.kind).ink)
                    .padding(.horizontal, 8).padding(.vertical, 1)
                    .background(tagColors(item.kind).fill, in: Capsule())
                Spacer(minLength: 4)
                Text(item.right).font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Text(item.name).font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
                .lineLimit(1).padding(.top, 3)
            Text(item.place).font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted).lineLimit(1)
            if open {
                GeometryReader { g in
                    Capsule().fill(Theme.borderSubtle)
                        .overlay(alignment: .leading) { Capsule().fill(Theme.primary).frame(width: g.size.width * min(max(item.progress, 0), 1)) }
                }
                .frame(height: 5).padding(.top, 8)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(open ? Theme.primary : Theme.borderSubtle, lineWidth: open ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func tagColors(_ kind: TimelineItem.Kind) -> (fill: Color, ink: Color) {
        switch kind {
        case .live: (Theme.paperBand, Theme.successInk)
        case .next: (Theme.primarySoft, Theme.primary)
        case .later: (Theme.hairline, Theme.inkMuted)
        }
    }

    private func actions(_ item: TimelineItem) -> some View {
        let a = item.appointment
        return HStack(spacing: 8) {
            Button {
                if item.isInstall { openInstall(a.job) } else { open(a, a.nextStep?.page) }
            } label: {
                Text(item.action).font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.actionGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            if let c = a.coordinate {
                outlinedIcon("location", label: "นำทาง") { openURL(mapsURL(c)) }
            }
            if !a.phone.isEmpty {
                outlinedIcon("phone", label: "โทรหน้างาน") { calling = a }
            }
        }
        .transition(.opacity)
    }

    private func outlinedIcon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
                .frame(width: 46, height: 46)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Pending surveys

/// A survey report still open (not complete, or not saved to Drive since its last edit) that isn't on today's schedule.
struct PendingSurvey: Identifiable {
    let report: TCRoofCore.Job
    var id: UUID { report.id }

    /// The two most recently edited open reports not linked to `todayJobs`.
    @MainActor static func list(survey: SurveyModel, todayJobs: [Job]) -> [PendingSurvey] {
        let today = Set(todayJobs.filter { $0.surveyDate.isToday }.compactMap(\.syncID))
        return survey.jobs
            .filter { $0.stage == .survey && !($0.jobSyncID.map(today.contains) ?? false) }
            .filter { !$0.completion.isComplete || $0.needsDriveSave }
            .sorted { $0.updated > $1.updated }
            .prefix(2).map(PendingSurvey.init)
    }

    var done: Int { report.stepsDone }
    var total: Int { report.steps.count }
    var isComplete: Bool { report.completion.isComplete }

    var name: String {
        [report.docNo.isEmpty ? "" : "NO.\(report.docNo)", report.projectName].filter { !$0.isEmpty }.joined(separator: " ")
            .nonEmpty ?? "งานสำรวจ"
    }

    /// `ยังขาด 3 รายการใน C1 หลังคา · แก้ไขล่าสุด 28/9`, or `ครบทุกขั้น · ยังไม่ส่งรายงานให้ กปภ.`
    var status: (text: String, missing: Bool) {
        let edited = "แก้ไขล่าสุด " + ThaiFormat.dayMonth.string(from: report.updated)
        guard !isComplete, let next = report.nextStep else { return ("ครบทุกขั้น · ยังไม่ส่งรายงานให้ กปภ.", false) }
        let n = report.missingGroups.first { $0.target == next.page }?.items.count ?? 0
        let what = n > 0 ? "ยังขาด \(n) รายการใน \(next.code) \(next.title)" : "ทำถึง \(next.code) \(next.title)"
        return (what + " · " + edited, n > 0)
    }

    /// `ทำต่อ C1 ›` at the next step, or `ส่งออก ›` (E1) when every step is done.
    var button: String { isComplete ? "ส่งออก ›" : report.nextStep.map { "ทำต่อ \($0.code) ›" } ?? "เปิด ›" }
    var target: MissingGroup.Target? { isComplete ? .final : report.nextStep?.page }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private struct PendingSurveysCard: View {
    let items: [PendingSurvey]
    let open: (PendingSurvey) -> Void
    let showAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("งานสำรวจค้างอยู่").font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                    .accessibilityAddTraits(.isHeader)
                Text("นอกนัดวันนี้").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 4)
                Button(action: showAll) {
                    Text("ดูทั้งหมด ›").font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.primary)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 18).padding(.trailing, 16).padding(.top, 2)
            ForEach(items) { row($0) }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.borderSubtle))
    }

    private func row(_ p: PendingSurvey) -> some View {
        let status = p.status
        return Button { open(p) } label: {
            HStack(spacing: 14) {
                StepsRing(done: p.done, total: p.total)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.name).font(.sarabun(15.5, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).lineLimit(1)
                    Text(status.text).font(.sarabun(13, relativeTo: .footnote))
                        .foregroundStyle(status.missing ? Theme.pending : Theme.inkMuted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(p.button).font(.sarabun(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(p.isComplete ? Theme.successInk : Theme.primary).lineLimit(1)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(p.isComplete ? Theme.paperBand : Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .fixedSize()
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 64)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Steps done out of all steps: blue, or green once every step is done.
private struct StepsRing: View {
    let done: Int
    let total: Int

    var body: some View {
        let full = total > 0 && done >= total
        ZStack {
            Circle().stroke(Theme.primarySoft, lineWidth: 4)
            Circle().trim(from: 0, to: total > 0 ? Double(done) / Double(total) : 0)
                .stroke(full ? Theme.success : Theme.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)").font(.sarabun(10, .bold, relativeTo: .caption2)).monospacedDigit().foregroundStyle(Theme.navy)
                .minimumScaleFactor(0.7).lineLimit(1).padding(.horizontal, 4)
        }
        .padding(2)
        .frame(width: 44, height: 44)
        .accessibilityLabel("ทำแล้ว \(done) จาก \(total) ขั้น")
    }
}
