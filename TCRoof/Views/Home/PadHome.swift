import SwiftUI
import TCRoofUI
import TCRoofCore

/// iPad home (regular width, docs/ui/tcroof-home-ipad and its v2, v3): brand header; `แผนงานวันนี้`, `วันนี้` and
/// `งานสำรวจค้างอยู่` on the left; the project feed on the right, on one screen, above the floating dock of `PadTabs`.
/// `วันนี้` takes the column's free height and scrolls inside; `งานสำรวจค้างอยู่` is two rows high.
/// Under ~1000 pt wide the columns stack in one scroll view.
struct PadHome<Popover: View>: View {
    let appointments: [TodayAppointment]
    let timeline: [TimelineItem]
    let pending: [PendingSurvey]
    let unread: Int
    let surveyToday: Int
    /// The minute this was drawn at, for the feed's ages.
    let now: Date
    @Binding var notificationsShown: Bool
    let open: (TodayAppointment, MissingGroup.Target?) -> Void
    let openInstall: (Job) -> Void
    let openReport: (PendingSurvey) -> Void
    let openFeed: (FeedLink) -> Void
    /// `ดูทั้งหมด ›` of `งานสำรวจค้างอยู่`: the survey home, the dock's `สำรวจ` tab.
    let showSurveys: () -> Void
    /// The bar's search field.
    let openSearch: () -> Void
    let newSurvey: () -> Void
    @ViewBuilder let notifications: () -> Popover

    @State private var page = 0

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 1000 {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) {
                        hero
                        TodayTimelineCard(items: timeline, fill: true, select: select, open: open, openInstall: openInstall, openLink: openFeed)
                        if !pending.isEmpty { PendingSurveysCard(items: pending, capped: true, open: openReport, showAll: showSurveys) }
                    }
                    .frame(width: 520)
                    feed(scrolls: true)
                }
                .padding(.horizontal, 32).padding(.top, 20)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        hero
                        TodayTimelineCard(items: timeline, fill: false, select: select, open: open, openInstall: openInstall, openLink: openFeed)
                        if !pending.isEmpty { PendingSurveysCard(items: pending, capped: false, open: openReport, showAll: showSurveys) }
                        feed(scrolls: false).padding(.top, 4)
                    }
                    .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
                }
                .refreshable { await CloudSync.shared.refresh() }
                .feedNewPostsPill()
            }
        }
        // a tap on the page outside the panel closes it; the bar's and the dock's buttons stay live, so `ตั้งค่า`
        // closes it and opens settings in one tap (a system popover would swallow that tap)
        .overlay { if notificationsShown { Color.clear.contentShape(Rectangle()).onTapGesture { notificationsShown = false } } }
        .safeAreaInset(edge: .top, spacing: 0) {
            HomeBrandHeader(size: .pad, unread: unread, notificationsShown: $notificationsShown, openSearch: openSearch)
        }
        .background(Theme.phonePage.ignoresSafeArea())
        .overlay {
            // the board dims the page lightly behind the bell's panel
            if notificationsShown { Theme.popoverDim.ignoresSafeArea().allowsHitTesting(false) }
        }
        .overlayPreferenceValue(BellAnchorKey.self) { anchor in
            GeometryReader { g in
                if notificationsShown, let anchor { bellPanel(under: g[anchor], in: g.size) }
            }
        }
    }

    /// The notifications under the bell (board: 440 wide, r18, its arrow on the bell), kept on screen.
    private func bellPanel(under bell: CGRect, in area: CGSize) -> some View {
        let width: CGFloat = 440
        let right = min(area.width - 16, bell.midX + 27)
        return VStack(alignment: .leading, spacing: 0) {
            BellArrow().fill(Theme.surface).frame(width: 20, height: 9)
                .offset(x: bell.midX - (right - width) - 10)
            notifications()
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .compositingGroup()
        .shadow(color: Theme.navy.opacity(0.28), radius: 20, y: 16)
        .frame(width: width, alignment: .leading)
        .offset(x: right - width, y: bell.maxY + 11)
        .transition(.opacity)
    }

    /// `แผนงานวันนี้`: today's work still to come, the nearest first, then the install days already under way.
    /// The inspections, document deadlines and tests of the PWA plan are rows of `วันนี้` only
    /// (docs/ui/tcroof-home-ipad-v3, open question 1).
    private var plan: [TimelineItem] {
        let paged = timeline.filter(\.inHero)
        let ahead = paged.filter { $0.date > .now }
        return ahead + paged.filter { $0.isInstall && $0.date <= .now }
    }

    private var hero: some View {
        AppointmentHero(size: .pad, title: "แผนงานวันนี้", emptyTitle: "ไม่มีแผนงานวันนี้", appointments: plan.map(heroItem), page: $page,
                        open: open, newSurvey: newSurvey)
    }

    private func heroItem(_ item: TimelineItem) -> HeroItem {
        let a = item.appointment
        return HeroItem(id: item.id, time: item.time, kind: item.isInstall ? "\(item.tag) · \(item.right)" : "นัดสำรวจ · \(item.right)",
                        name: item.name, place: item.place, fraction: item.progress, percent: Int((item.progress * 100).rounded()),
                        actionTitle: item.action, appointment: a) {
            if let link = item.link { openFeed(link) } else if item.isInstall { openInstall(a.job) } else { open(a, a.nextStep?.page) }
        }
    }

    /// A row of the timeline moves the hero to its page, when it has one.
    private func select(_ item: TimelineItem) {
        guard let i = plan.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { page = i }
    }

    /// `ฟีดโครงการ`, the iPhone home's feed at the column's sizes.
    private func feed(scrolls: Bool) -> some View {
        HomeFeed(now: now, todayTeams: Set(appointments.map(\.job.teamRaw)), layout: .column(scrolls: scrolls), open: openFeed)
    }
}

// MARK: - Timeline data

/// One entry of the `วันนี้` timeline: an install day or a survey appointment of today, or a row of the PWA plan's
/// agenda for today (an MP install task, an inspection appointment, a document deadline, an IEC 62446 test day).
struct TimelineItem: Identifiable {
    enum Kind { case live, next, later }
    let kind: Kind
    /// Today at the row's time; the start of today for a plan row with no time.
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
    /// A plan row: its agenda id, the plan page's clock text (`ทั้งวัน` with no time), and the screen its button opens.
    var planID: String? = nil
    var clock: String? = nil
    var link: FeedLink? = nil
    /// Pages in the `แผนงานวันนี้` hero.
    var inHero = true
    /// Rows at the same time stand in the plan's type order: install, survey, inspection, document, test.
    var order = 0

    var id: String { planID.map { "plan-" + $0 } ?? (isInstall ? "install-" : "survey-") + appointment.id }
    var time: String { clock ?? ThaiFormat.time.string(from: date) }

    /// Every plan item of today in time order: the install days of the jobs the MP plan doesn't cover, the survey
    /// appointments, and the PWA plan's rows. An install day or task is "live"; the first survey still ahead is
    /// "next"; the rest are "later". `jobs` is every job.
    @MainActor static func list(jobs: [Job], survey: SurveyModel) -> [TimelineItem] {
        func report(_ job: Job) -> TCRoofCore.Job? { job.syncID.flatMap { survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } } }
        let cal = Calendar.current
        var out: [TimelineItem] = []
        // a PWA job with an MP plan gets its install rows from the plan's agenda, as on the plan page
        for job in jobs where job.kind != .pwa || job.scheduleInput == nil {
            guard let day = job.installDay(on: .now) else { continue }
            let hour = cal.component(.hour, from: job.installStart), minute = cal.component(.minute, from: job.installStart)
            // a start date picked with no time (00:00) is the whole day, as a plan row with no time: ทั้งวัน, first
            let allDay = hour == 0 && minute == 0
            let start = allDay ? Date.now.startOfDay : cal.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
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
                                    action: "เปิดบันทึกประจำวัน ›", clock: allDay ? "ทั้งวัน" : nil))
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
                                    progress: a.fraction, action: a.actionTitle, order: 1))
        }
        out += planRows(jobs: jobs, survey: survey, report: report)
        // by the minute: an appointment keeps its seconds, a plan row has none
        func minute(_ d: Date) -> Int { Int((d.timeIntervalSinceReferenceDate / 60).rounded(.down)) }
        return out.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            if minute(x.date) != minute(y.date) { return x.date < y.date }
            return x.order != y.order ? x.order < y.order : a.offset < b.offset
        }.map(\.element)
    }

    /// Today's rows of the PWA plan page's `ตารางงาน` (`PWAPlan.agenda`), without its survey appointments (they are
    /// rows already) and its daily-report reminder. A row with no time in the plan (a document deadline, a test day,
    /// an install day of a station with no working hours) shows `ทั้งวัน` and stands first.
    @MainActor private static func planRows(jobs: [Job], survey: SurveyModel, report: (Job) -> TCRoofCore.Job?) -> [TimelineItem] {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "homeTimeline") == "demo" { return demoRows(jobs: jobs, report: report) }
        #endif
        let now = Date.now
        let pwa = jobs.pwaStations
        let stations = pwa.map(\.planStation)
        let threshold = survey.settings.behindThreshold
        let deadlines = PWAPlan.deadlines(stations, library: StationDocsStore.loadLibrary(), today: now, threshold: threshold)
        let bars = Dictionary(PWAPlan.bars(stations, today: now, threshold: threshold).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let byID = Dictionary(zip(pwa, stations).map { ($1.id, ($0, $1)) }, uniquingKeysWith: { a, _ in a })
        return PWAPlan.agenda(stations, deadlines: deadlines, days: [now], today: now, threshold: threshold).compactMap { item in
            guard let (job, s) = byID[item.station] else { return nil }
            let done = (bars[item.station]?.actual ?? 0) / 100
            // `ทุ่งน้อย · ผู้รับเหมา A · TCR01 · ช้ากว่าแผน 12%` without the station, which an install row has in its name
            let party = item.subtitle.components(separatedBy: " · ").filter { $0 != s.shortName }.joined(separator: " · ")
            switch item.type {
            case .install:
                return row(item, job: job, report: report(job), name: "\(item.title) · \(s.shortName)", place: party, progress: done)
            case .test, .inspection, .document:
                return row(item, job: job, report: report(job), name: item.title, place: item.subtitle, progress: item.type == .test ? done : 0)
            case .survey, .notice: return nil
            }
        }
    }

    /// One agenda row. The button follows the type: the station's daily report of today, its ICL check list, its
    /// papers, and for a test the station itself, since the app has no IEC 62446 form (as the plan page's test rows).
    @MainActor private static func row(_ item: PWAPlan.AgendaItem, job: Job, report: TCRoofCore.Job?, name: String, place: String,
                                       progress: Double) -> TimelineItem {
        let now = Date.now, key = job.feedKey
        let a = TodayAppointment(job: job, report: report)
        let at = item.start.flatMap { Calendar.current.date(byAdding: .minute, value: $0, to: now.startOfDay) }
        let ahead = at.map { $0 > now } ?? false
        let (action, link, order): (String, FeedLink, Int) = switch item.type {
        case .inspection: ("เปิดงานตรวจรับ ›", .inspection(job: key), 2)
        case .document: ("ดูเอกสาร ›", .stationDocs(job: key), 3)
        case .test: ("เปิดฟอร์มทดสอบ ›", .job(key), 4)
        default: ("เปิดบันทึกประจำวัน ›", .daily(job: key, day: now), 0)
        }
        let working = item.status == .doing
        let right = item.type == .document ? item.status.title
            : ahead ? a.countdown(to: at ?? now) : working ? item.status.title : "ผ่านแล้ว"
        return TimelineItem(kind: working ? .live : .later, date: at ?? now.startOfDay, isInstall: item.type == .install, appointment: a,
                            tag: [item.type.title, item.ref].filter { !$0.isEmpty }.joined(separator: " · "), right: right,
                            name: name, place: place, progress: progress, action: action,
                            planID: item.id, clock: item.start.map(PWAPlan.clock) ?? "ทั้งวัน", link: link,
                            inHero: item.type == .install, order: order)
    }

    #if DEBUG
    /// `-homeTimeline demo`: the board's five PWA rows (docs/ui/tcroof-home-ipad-v3 §1) in place of the plan's, on the
    /// first jobs. The inspection and the test stand at the survey appointments of `-homeDemo YES`. Nothing is saved.
    @MainActor private static func demoRows(jobs: [Job], report: (Job) -> TCRoofCore.Job?) -> [TimelineItem] {
        let cal = Calendar.current, now = Date.now
        func minutes(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
        let surveys = jobs.map(\.surveyDate).filter { $0.isToday && $0 > now }.sorted().map(minutes)
        let first = surveys.first ?? 10 * 60 + 30, second = surveys.dropFirst().first ?? 14 * 60
        let rows: [(Int?, PWAPlan.JobType, String, String, String, PWAPlan.AgendaStatus, Double)] = [
            (8 * 60, .install, "MP 189", "2.3 ติดตั้งแผงเซลล์ · ทุ่งน้อย", "ผู้รับเหมา A · TCR01 · ช้ากว่าแผน 12%", .doing, 0.38),
            (8 * 60 + 30, .install, "MP 120", "2.1 โครงสร้างรองรับ + Walkway · วัดชัย", "ผู้รับเหมา B · TCR03 · ช้ากว่าแผน 6%", .doing, 0.22),
            (first, .inspection, "MP 154", "ผู้แทน กปภ. ตรวจ 2.5 Inverter", "แพรกหนามแดง · ผู้รับเหมา C", .waiting, 0),
            ((first + second) / 2, .document, "MP 189", "ยื่นแจ้งเทศบาล (กฎกระทรวงยกเว้น)", "ทุ่งน้อย · ครบกำหนดวันนี้", .mustSubmit, 0),
            (second, .test, "MP 77", "3.1 Pre-Commissioning (IEC 62446)", "โชคชัย · TCR05", .onPlan, 0),
        ]
        guard !jobs.isEmpty else { return [] }
        return rows.enumerated().map { i, r in
            let job = jobs[i % jobs.count]
            let item = PWAPlan.AgendaItem(id: "demo-\(i)", day: now.startOfDay, start: r.0, type: r.1, ref: r.2, title: r.3, subtitle: r.4, status: r.5)
            return row(item, job: job, report: report(job), name: r.3, place: r.4, progress: r.6)
        }
    }
    #endif
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
    let openLink: (FeedLink) -> Void

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
                Text("\(items.count) รายการ · ทุกแผนงาน").font(.sarabun(13, relativeTo: .footnote)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 4)
            if items.isEmpty {
                Text("ไม่มีแผนงานในวันนี้").font(.sarabun(15, relativeTo: .subheadline)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 16)
            } else if fill {
                ScrollView { rows }.scrollBounceBehavior(.basedOnSize).scrollIndicators(.hidden)
                    .defaultScrollAnchor(Self.startsAtEnd ? .bottom : .top)
            } else {
                rows
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.borderSubtle))
        .callDialog($calling, open: open)
    }

    /// `-homeTimelineEnd YES`: the rows open scrolled to their end, for simulator checks.
    private static var startsAtEnd: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "homeTimelineEnd")
        #else
        false
        #endif
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
                    select(item)
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
                if let link = item.link { openLink(link) } else if item.isInstall { openInstall(a.job) } else { open(a, a.nextStep?.page) }
            } label: {
                Text(item.action).font(.sarabun(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.onPrimary)
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
    /// Beside the feed: the header and at most two rows, 166 pt; rows past two are cut off.
    let capped: Bool
    let open: (PendingSurvey) -> Void
    let showAll: () -> Void

    private static let headerHeight: CGFloat = 46
    private var rowHeight: CGFloat { capped ? 60 : 64 }

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
        .frame(height: capped ? Self.headerHeight + rowHeight * CGFloat(min(items.count, 2)) : nil, alignment: .top)
        .clipped()
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
            .frame(maxWidth: .infinity, minHeight: rowHeight)
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

/// The panel's arrow pointing up at the bell.
private struct BellArrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
