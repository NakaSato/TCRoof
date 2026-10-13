import SwiftUI
import TCRoofUI
import SwiftData
import TCRoofCore

enum AppModule: String, CaseIterable, Identifiable {
    case survey, plan, scan, install, pwa, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .survey: "สำรวจหน้างาน"
        case .plan: "แผนก่อสร้าง\nและเอกสาร"
        case .scan: "สแกนอุปกรณ์"
        case .install: "บันทึกงานติดตั้ง\nและใบตรวจรับงาน"
        case .pwa: "การประปา\nส่วนภูมิภาค"
        case .tools: "เครื่องมือวัด"
        }
    }

    var subtitle: String {
        switch self {
        case .survey: "นัดหมาย เก็บข้อมูลหลังคาและระบบไฟฟ้า"
        case .plan: "ปฏิทินทีมติดตั้งและเอกสารโครงการ"
        case .scan: "สแกนซีเรียลแผงและอินเวอร์เตอร์"
        case .install: "บันทึกประจำวันและใบตรวจรับ (ICL)"
        case .pwa: "Excel / PDF / Drive"
        case .tools: "โดรน กล้องถ่ายภาพความร้อน แคลมป์มิเตอร์"
        }
    }

    /// One-line subtitle of the iPhone module rows.
    var shortSubtitle: String {
        switch self {
        case .survey: "นัดหมาย · หลังคา · ระบบไฟฟ้า"
        case .install: "บันทึกประจำวัน · ใบตรวจรับ ICL"
        default: subtitle
        }
    }

    /// Status chip of the home row: `2 นัดวันนี้` on the survey row, `Day 2/5` on the install row.
    func chip(surveyToday: Int, installDay: String?) -> String? {
        switch self {
        case .survey: surveyToday > 0 ? "\(surveyToday) นัดวันนี้" : nil
        case .install: installDay
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .survey: "list.clipboard.fill"
        case .plan: "calendar"
        case .scan: "barcode.viewfinder"
        case .install: "folder.fill"
        case .pwa: "drop.fill"
        case .tools: "briefcase.fill"
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .survey: SurveyListView()
        case .plan: PlanCalendarView()
        case .scan: ScanJobListView()
        case .install: InstallRecordsView()
        case .pwa: SolarSurveyEntryView()
        case .tools: ToolsView()
        }
    }
}

struct HomeView: View {
    @AppStorage("notifications.read") private var readRaw = ""
    @Environment(GoogleSession.self) private var session
    @Query(sort: \Job.installStart) private var jobs: [Job]
    @State private var showSettings = false
    @State private var showNotifications = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPad: the dock over this home (`PadTabs`).
    @Environment(PadDock.self) private var dock: PadDock?
    @State private var openReport: OpenReportPage?
    /// Appointment whose job has no report yet: pick a template, then open the new report at A1.
    @State private var startReport: Job?
    @State private var showNewJob = false
    @State private var openedJob: Job?
    /// The iPad bar's search field: the survey list over every date, its search field focused.
    @State private var showSearch = false
    @State private var installLogs: Job?
    @AppStorage("userName") private var engineerName = ""
    @State private var notificationService = NotificationService.shared
    @State private var liveFeed = LiveFeed.shared
    @State private var instruments = InstrumentStore.shared
    /// A screen opened from a system notification.
    @State private var linked: LinkedScreen?
    @State private var shareURL: SharedLink?
    /// A record opened from a post of the project feed.
    @State private var feedLink: FeedLink?
    @Environment(\.openURL) private var openURL

    private var todaysJobs: [Job] {
        jobs.filter { $0.installDay(on: .now) != nil || $0.surveyDate.isToday }
    }

    var body: some View {
        // each minute, so appointments drop off and "อีก n นาที" counts down
        TimelineView(.everyMinute) { timeline in
            if sizeClass == .compact { phoneHome(now: timeline.date) } else { padHome(now: timeline.date) }
        }
        .font(.sarabun(17))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView().presentationDetents([.large]).formSheetSizing().environment(\.homeInk, sizeClass == .compact ? .outdoor : .standard)
        }
        .sheet(isPresented: $showNewJob) { NewJobView { openedJob = $0 } }
        .navigationDestination(item: $openedJob) { JobDetailView(job: $0) }
        // iPad shows them in a panel under the bell (PadHome)
        .fullScreenCover(isPresented: Binding(get: { sizeClass == .compact && showNotifications }, set: { showNotifications = $0 })) {
            notificationsView(large: false).environment(\.homeInk, .outdoor)
        }
        .navigationDestination(item: $openReport) { SurveyReportEditor(jobID: $0.id, start: $0.start) }
        .navigationDestination(item: $installLogs) { JobInstallLogsView(job: $0) }
        .navigationDestination(item: $feedLink) { feedScreen($0) }
        .navigationDestination(isPresented: $showSearch) { SurveyListView(startSearching: true) }
        .navigationDestination(item: $linked) { screen in
            switch screen {
            case .pending: SolarSurveyReportView(unsyncedOnly: true)
            case .tools(let action): ToolsView(request: action)
            case .dailyReport(let key):
                if let job = jobs.first(where: { ($0.syncID ?? $0.code) == key }) { DailyReportScreen(job: job, date: .now) }
            case .weeklyRequest(let key):
                if let job = jobs.first(where: { ($0.syncID ?? $0.code) == key }) { WeeklyRequestScreen(job: job) }
            }
        }
        .sheet(item: $shareURL) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
        .onChange(of: notificationService.link, initial: true) { _, link in
            guard let link else { return }
            notificationService.link = nil
            open(link)
        }
        .onChange(of: unreadCount, initial: true) { _, n in notificationService.setBadge(n) }
        // the dock closes the bell's panel
        .onChange(of: dock?.tab) { showNotifications = false }
        .onChange(of: dock?.showSettings) { showNotifications = false }
        .sheet(item: $startReport) { job in
            SurveyTemplatePicker { t in
                let survey = session.survey
                let engineer = survey.settings.engineer.isEmpty ? engineerName : survey.settings.engineer
                let r = survey.create(t, engineer: engineer, linkedTo: job.ensureSyncID(), prefill: job.surveyPrefill)
                startReport = nil
                openReport = OpenReportPage(id: r.id)
            }
        }
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "homeDemo") { seedDemo() }
            // `-homeNotifications YES` opens the notifications for simulator checks
            if UserDefaults.standard.bool(forKey: "homeNotifications") { try? await Task.sleep(for: .seconds(1)); showNotifications = true }
            // `-homeSettings YES` opens the settings sheet
            if UserDefaults.standard.bool(forKey: "homeSettings") { try? await Task.sleep(for: .seconds(1)); showSettings = true }
        }
        #endif
    }

    private func notificationsView(large: Bool, close: (() -> Void)? = nil) -> PhoneNotificationsView {
        PhoneNotificationsView(items: notifications, read: readIDs, markRead: markRead, sync: sync,
                               surveyHint: surveyHint, openSurvey: openSurvey, openLink: openLater, large: large, close: close)
    }

    // MARK: iPhone

    private func phoneHome(now: Date) -> some View {
        let survey = session.survey
        let items = notifications, read = readIDs
        let appointments = TodayAppointment.list(jobs: jobs, survey: survey)
        return PhoneHome(appointments: appointments,
                         unread: items.filter { !read.contains($0.id) }.count,
                         now: now,
                         notificationsShown: $showNotifications,
                         open: openAppointment,
                         openFeed: { feedLink = $0 })
    }

    /// The record a feed post opens.
    @ViewBuilder private func feedScreen(_ link: FeedLink) -> some View {
        switch link {
        case .daily(let key, let day): if let job = job(key) { DailyReportScreen(job: job, date: day) }
        case .inspection(let key): if let job = job(key) { InspectionView(job: job) }
        case .job(let key): if let job = job(key) { JobDetailView(job: job) }
        case .homework(let key): if let job = job(key) { HomeWorkView(job: job) }
        case .records: InstallRecordsView()
        }
    }

    private func job(_ key: String) -> Job? { jobs.first { $0.feedKey == key } }

    // MARK: iPad

    private func padHome(now: Date) -> some View {
        let survey = session.survey
        let items = notifications, read = readIDs
        let appointments = TodayAppointment.list(jobs: jobs, survey: survey)
        return PadHome(appointments: appointments,
                       timeline: TimelineItem.list(jobs: todaysJobs, survey: survey),
                       pending: PendingSurvey.list(survey: survey, todayJobs: todaysJobs),
                       unread: items.filter { !read.contains($0.id) }.count,
                       surveyToday: jobs.filter { $0.surveyDate.isToday }.count,
                       now: now,
                       notificationsShown: $showNotifications,
                       open: openAppointment,
                       openInstall: { installLogs = $0 },
                       openReport: { openReport = OpenReportPage(id: $0.report.id, start: $0.target) },
                       openFeed: { feedLink = $0 },
                       showSurveys: { dock?.select(.survey) },
                       openSearch: { showNotifications = false; showSearch = true },
                       newSurvey: { showNewJob = true }) {
            notificationsView(large: true) { showNotifications = false }
        }
    }

    #if DEBUG
    /// `-screen home -homeDemo YES`: two sample jobs get survey appointments later today and the first a linked
    /// report with GPS and a phone, so the hero shows the pager, ring, navigate and call; a third is on install day 2/5.
    private func seedDemo() {
        guard DebugScreen.requested != nil else { return }
        let sorted = jobs.sorted { abs($0.surveyDate.timeIntervalSinceNow) < abs($1.surveyDate.timeIntervalSinceNow) }
        let picks = sorted.prefix(2)
        for (i, job) in picks.enumerated() {
            job.surveyDate = Date.now.addingTimeInterval(i == 0 ? 49 * 60 + 30 : 3 * 3600)
        }
        if sorted.count > 2, !jobs.contains(where: { $0.installDay(on: .now) != nil }) {
            let install = sorted[2]
            install.installStart = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now.adding(days: -1)) ?? .now
            install.installDays = 5
        }
        // an open report off today's schedule, for `งานสำรวจค้างอยู่`
        if PendingSurvey.list(survey: session.survey, todayJobs: todaysJobs).isEmpty, let template = JobTemplate.all.first {
            var r = session.survey.create(template, engineer: "สมชาย")
            r.values["docNo"] = .text("198")
            session.survey.update(r)
        }
        guard let first = picks.first, session.survey.jobs(linkedTo: first.ensureSyncID()).isEmpty,
              let template = JobTemplate.all.first else { return }
        var r = session.survey.create(template, engineer: "สมชาย", linkedTo: first.ensureSyncID(), prefill: first.surveyPrefill)
        r.values["docNo"] = .text("224")
        r.values["gps"] = .text("17.0062, 99.8235")
        r.values["coordinator"] = .text("คุณสมชาย")
        session.survey.update(r)
    }
    #endif

    /// Opens the appointment's report at `start`, or starts one when the job has none.
    private func openAppointment(_ a: TodayAppointment, at start: MissingGroup.Target?) {
        if let r = a.report { openReport = OpenReportPage(id: r.id, start: start) } else { startReport = a.job }
    }

    private func appointment(for n: AppNotification) -> TodayAppointment? {
        guard let job = n.job else { return nil }
        let report = job.syncID.flatMap { session.survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
        return TodayAppointment(job: job, report: report)
    }

    private func surveyHint(_ n: AppNotification) -> String {
        guard let a = appointment(for: n) else { return "" }
        guard a.report != nil else { return "แตะเพื่อเริ่มสำรวจ A1" }
        return a.nextStepLabel.map { "แตะเพื่อทำต่อ \($0)" } ?? "แตะเพื่อเปิดแบบสำรวจ"
    }

    private func openSurvey(_ n: AppNotification) {
        guard let a = appointment(for: n) else { return }
        // after the cover has gone, so the push lands on the home stack
        Task { try? await Task.sleep(for: .milliseconds(350)); openAppointment(a, at: a.nextStep?.page) }
    }

    // MARK: notifications

    private var notifications: [AppNotification] {
        AppNotification.list(jobs: todaysJobs, survey: session.survey, posts: liveFeed.posts, tools: instruments.all)
    }

    /// Opens a bell row's screen after the cover has gone, so the push lands on the home stack.
    private func openLater(_ link: DeepLink) {
        Task { try? await Task.sleep(for: .milliseconds(350)); open(link) }
    }

    /// A job's record, when the job is on this device.
    private func openRecord(_ link: FeedLink, job key: String) {
        if job(key) != nil { feedLink = link }
    }
    private var readIDs: Set<String> { Set(readRaw.split(separator: "\n").map(String.init)) }

    /// Marks these read; ids no longer shown are dropped so the stored list stays small.
    private func markRead(_ list: [AppNotification]) {
        let shown = Set(notifications.map(\.id))
        readRaw = readIDs.intersection(shown).union(list.map(\.id)).sorted().joined(separator: "\n")
        notificationService.bellRead(Set(list.map(\.id)))
    }

    private func sync() { session.survey.cloudPush?() }

    private var unreadCount: Int {
        let read = readIDs
        return notifications.filter { !read.contains($0.id) }.count
    }

    // MARK: system notification links

    /// Opens the screen a notification tap or quick action points to.
    private func open(_ link: DeepLink) {
        showNotifications = false
        showSettings = false
        switch link {
        case .survey(let key):
            guard let a = appointment(key: key) else { return }
            openAppointment(a, at: a.nextStep?.page)
        case .navigate(let key):
            guard let a = appointment(key: key) else { return }
            if let c = a.coordinate { openURL(mapsURL(c)) }
            else if let q = a.job.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), !q.isEmpty,
                    let url = URL(string: "http://maps.apple.com/?daddr=\(q)&dirflg=d") { openURL(url) }
        case .toolCamera, .toolQueue, .leaveQueue, .extendLoan, .toolRecord:
            linked = .tools(action: notificationService.linkAction ?? "")
        case .call(let phone):
            let digits = phone.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(digits)") { openURL(url) }
        case .syncNow: sync()
        case .pendingList: linked = .pending
        case .dailyReport(let key): linked = .dailyReport(job: key)
        case .weeklyRequest(let key): linked = .weeklyRequest(job: key)
        case .job(let key): openRecord(.job(key), job: key)
        case .daily(let key, let day): openRecord(.daily(job: key, day: day), job: key)
        case .inspection(let key): openRecord(.inspection(job: key), job: key)
        case .homework(let key): openRecord(.homework(job: key), job: key)
        case .records: feedLink = .records
        case .driveFolder(let url): openURL(url)
        case .share(let url): shareURL = SharedLink(url: url)
        case .remindLater, .home: break
        }
    }

    /// The appointment of a job by the key its notification carries (`syncID`, else the job code).
    private func appointment(key: String) -> TodayAppointment? {
        guard let job = jobs.first(where: { ($0.syncID ?? $0.code) == key }) else { return nil }
        let report = job.syncID.flatMap { session.survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
        return TodayAppointment(job: job, report: report)
    }
}

/// Screens only a notification opens: the survey home on รอซิงก์ (`ดูรายการ`), and the tools screen
/// with the quick action's title.
enum LinkedScreen: Hashable {
    case pending
    case tools(action: String)
    /// A routine-report reminder: today's daily report, or next week's request, of the job with this key.
    case dailyReport(job: String)
    case weeklyRequest(job: String)
}

struct SharedLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

extension View {
    /// `-homeBoard YES`: lays the iPad tabs out at the board's 1366 × 1024 (landscape) and scales them to fit,
    /// since the simulator here can't be rotated by hand.
    @ViewBuilder func debugBoard() -> some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "homeBoard") {
            GeometryReader { g in
                self.frame(width: 1366, height: 1024).scaleEffect(g.size.width / 1366, anchor: .topLeading)
            }
            .ignoresSafeArea()
        } else { self }
        #else
        self
        #endif
    }

    /// iPad settings as a centred form sheet (about 560 × 820).
    @ViewBuilder func formSheetSizing() -> some View {
        if #available(iOS 18, *) { presentationSizing(.form) } else { self }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GoogleSession.self) private var session
    @State private var confirmLogout = false

    /// The same grouped cards on iPhone (large sheet) and iPad (form sheet).
    var body: some View {
        NavigationStack {
            PhoneSettingsList(confirmLogout: $confirmLogout)
                .navigationTitle("ตั้งค่า")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } }
                .confirmationDialog("ต้องการออกจากระบบหรือไม่?", isPresented: $confirmLogout, titleVisibility: .visible) {
                    Button("ออกจากระบบ", role: .destructive) {
                        dismiss()
                        session.signOut()
                    }
                    Button("ยกเลิก", role: .cancel) {}
                } message: {
                    Text("งานที่ยังไม่ได้ซิงค์จะยังอยู่ในเครื่องนี้")
                }
        }
    }
}
