import SwiftUI
import TCRoofUI
import TCRoofCore

/// iPad home (regular width, docs/ui/tcroof-home-ipad and its v2, v3): brand header; `แผนงานวันนี้`, `วันนี้` and
/// `งานสำรวจค้างอยู่` on the left; the project feed on the right, on one screen, above the floating dock of `PadTabs`.
/// `วันนี้` takes the column's free height and scrolls inside; `งานสำรวจค้างอยู่` is two rows high.
/// Under ~1000 pt wide the columns stack in one scroll view.
struct PadHome<Popover: View>: View {
    let jobs: [Job]
    let appointments: [TodayAppointment]
    let jobsLoading: Bool
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
    let newSurvey: (() -> Void)?
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

    @ViewBuilder private var hero: some View {
        if jobsLoading && jobs.isEmpty {
            DataLoadingSkeleton(lines: 3)
        } else {
            AppointmentHero(size: .pad, title: "แผนงานวันนี้", emptyTitle: "ไม่มีแผนงานวันนี้", appointments: plan.map(heroItem), page: $page,
                            open: open, newSurvey: newSurvey)
        }
    }

    private func heroItem(_ item: TimelineItem) -> HeroItem {
        let a = item.appointment
        return HeroItem(id: item.id, time: item.time, kind: item.isInstall ? "\(item.tag) | \(item.right)" : "นัดสำรวจ | \(item.right)",
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
        HomeFeed(now: now, todayTeams: Set(appointments.map(\.job.teamRaw)), jobs: jobs,
                 layout: .column(scrolls: scrolls), open: openFeed)
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
                                    tag: "ติดตั้ง | Day \(day)/\(job.installDays)",
                                    right: started ? "กำลังทำ" : a.countdown(to: start),
                                    name: "\(job.code) | ทีม \(job.team.rawValue)",
                                    place: [job.province.isEmpty ? nil : "จ.\(job.province)",
                                            job.capacityKW > 0 ? "\(job.capacityKW.plain) kWp" : nil,
                                            started ? "ทีมเข้างานแล้ว" : nil].compactMap { $0 }.joined(separator: " | "),
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
                                    tag: isNext ? "นัดสำรวจ | ถัดไป" : "นัดสำรวจ",
                                    right: ahead ? a.countdown : "ผ่านแล้ว",
                                    name: a.name,
                                    place: [a.place, steps].filter { !$0.isEmpty }.joined(separator: " | "),
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
            // `ทุ่งน้อย | ผู้รับเหมา A | TCR01 | ช้ากว่าแผน 12%` without the station, which an install row has in its name
            let party = item.subtitle.components(separatedBy: " | ").filter { $0 != s.shortName }.joined(separator: " | ")
            switch item.type {
            case .install:
                return row(item, job: job, report: report(job), name: "\(item.title) | \(s.shortName)", place: party, progress: done)
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
                            tag: [item.type.title, item.ref].filter { !$0.isEmpty }.joined(separator: " | "), right: right,
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
            (8 * 60, .install, "MP 189", "2.3 ติดตั้งแผงเซลล์ | ทุ่งน้อย", "ผู้รับเหมา A | TCR01 | ช้ากว่าแผน 12%", .doing, 0.38),
            (8 * 60 + 30, .install, "MP 120", "2.1 โครงสร้างรองรับ + Walkway | วัดชัย", "ผู้รับเหมา B | TCR03 | ช้ากว่าแผน 6%", .doing, 0.22),
            (first, .inspection, "MP 154", "ผู้แทน กปภ. ตรวจ 2.5 Inverter", "แพรกหนามแดง | ผู้รับเหมา C", .waiting, 0),
            ((first + second) / 2, .document, "MP 189", "ยื่นแจ้งเทศบาล (กฎกระทรวงยกเว้น)", "ทุ่งน้อย | ครบกำหนดวันนี้", .mustSubmit, 0),
            (second, .test, "MP 77", "3.1 Pre-Commissioning (IEC 62446)", "โชคชัย | TCR05", .onPlan, 0),
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
