import SwiftUI
import SwiftData
import TCRoofCore
import TCRoofUI

extension View {
    /// Keeps the system notifications in step with the jobs and survey reports while signed in.
    func systemNotifications(survey: SurveyModel) -> some View { modifier(NotificationScheduler(survey: survey)) }
}

/// The feed's posts as the scheduler last built them, for the bell, and which of them were already announced.
@MainActor
@Observable final class LiveFeed {
    static let shared = LiveFeed()
    private(set) var posts: [FeedPost] = []
    private static let seenKey = "notifications.feed.seen"

    /// Keeps `posts` and returns the ones to announce. The first run announces nothing: every post is old news then.
    func update(_ posts: [FeedPost], me: String, now: Date) -> [NotificationPlan] {
        self.posts = posts
        let d = UserDefaults.standard
        let saved = d.string(forKey: Self.seenKey).map { Set($0.split(separator: "\n").map(String.init)) }
        let fresh = saved.map { FeedNotification.fresh(posts, seen: $0, me: me, now: now) } ?? []
        d.set(posts.map(\.id).sorted().joined(separator: "\n"), forKey: Self.seenKey)
        return fresh
    }
}

/// Survey reminders 30 min before today's and tomorrow's appointments, the one `รอซิงก์`, `บันทึกขึ้น Drive แล้ว`, the
/// routine-report and calibration reminders, install days, the MP plan and the project feed's events; rescheduled when
/// jobs, reports, tools, the toggles or the minute change.
private struct NotificationScheduler: ViewModifier {
    let survey: SurveyModel
    @Query private var jobs: [Job]
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NotificationGroup.survey.defaultsKey) private var surveyOn = true
    @AppStorage(NotificationGroup.syncExport.defaultsKey) private var syncOn = true
    @AppStorage(NotificationGroup.report.defaultsKey) private var reportOn = true
    @AppStorage(NotificationGroup.calibration.defaultsKey) private var calibrationOn = true
    @AppStorage(NotificationGroup.plan.defaultsKey) private var planOn = true
    @AppStorage(NotificationGroup.feed.defaultsKey) private var feedOn = true
    @AppStorage("userName") private var userName = ""
    @Environment(\.permissions) private var permissions
    @State private var instruments = InstrumentStore.shared
    /// Bumped each minute and when the app comes back, so a new day reschedules and a synced record is announced.
    @State private var tick = 0

    func body(content: Content) -> some View {
        content
            .task {
                let service = NotificationService.shared
                #if DEBUG
                // the component gallery's screenshots run on a fresh install; no permission prompt over them,
                // nor with `-noNotificationPrompt YES` (simulator screenshots of other screens)
                if UserDefaults.standard.string(forKey: "screen") != "components", !UserDefaults.standard.bool(forKey: "noNotificationPrompt") {
                    await service.requestAuthorization()
                }
                #else
                await service.requestAuthorization()
                #endif
                survey.onDriveSaved = { job, kinds, photos in
                    service.driveSaved(job, kinds: kinds.map(\.rawValue), photos: photos, root: survey.settings.driveRoot)
                }
                #if DEBUG
                await debugDemo(service)
                #endif
            }
            .task(id: surveyPlans(tick)) { await NotificationService.shared.scheduleSurveys(surveyPlans(tick)) }
            .task(id: reportPlans(tick)) { await NotificationService.shared.schedule(reportPlans(tick), type: .report) }
            .task(id: calibrationPlans(tick)) { await NotificationService.shared.schedule(calibrationPlans(tick), type: .cal) }
            .task(id: installPlans(tick)) { await NotificationService.shared.schedule(installPlans(tick), type: .install) }
            .task(id: mpPlans(tick)) { await NotificationService.shared.schedule(mpPlans(tick), type: .mp) }
            .task(id: FeedState(tick: tick, jobs: jobs.count, on: feedOn)) { await refreshFeed() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    tick += 1
                }
            }
            .task(id: SyncState(survey: survey, on: syncOn)) {
                let pending = survey.jobsToSync
                await NotificationService.shared.updateSync(names: pending.map(Self.label), oldest: pending.map(\.updated).min())
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                tick += 1
                Task { await NotificationService.shared.refreshAuthorization() }
            }
    }

    /// Appointments from now to the end of tomorrow whose reminder is still ahead and whose report isn't finished.
    private func surveyPlans(_: Int) -> [NotificationPlan] {
        guard surveyOn else { return [] }
        let end = Calendar.current.startOfDay(for: .now.adding(days: 2))
        return jobs.compactMap { job in
            guard job.surveyDate.addingTimeInterval(-NotificationPlan.surveyLead) > .now, job.surveyDate < end else { return nil }
            let report = job.syncID.flatMap { survey.jobs(linkedTo: $0).max { $0.updated < $1.updated } }
            if report?.completion.isComplete == true { return nil }
            let a = TodayAppointment(job: job, report: report)
            return .survey(jobKey: job.syncID ?? job.code, name: a.name, area: a.area, appointment: job.surveyDate)
        }
        .sorted { $0.id < $1.id }
    }

    /// The jobs whose reminders this member hears (`Permissions.hearsNews`): the ones naming them on the team, as
    /// supervisor or as an assigned external, those naming none of ours, and every job for a manager. Install days, the
    /// MP plan, the ERC flow and the routine reports follow the job's people, as the feed does.
    private var heard: [Job] { jobs.filter { permissions.hearsNews($0.access) } }

    /// Routine-report reminders of the stations being installed (docs/specs/routine-reports-swift.md §5): 17:00 when today's
    /// daily report isn't signed, Friday 15:00 when next week has no request.
    private func reportPlans(_: Int) -> [NotificationPlan] {
        guard reportOn else { return [] }
        let now = Date.now, cal = RoutineReport.calendar
        return heard.filter { $0.status == .installing || $0.installInterval.contains(now) }.flatMap { job -> [NotificationPlan] in
            let key = job.syncID ?? job.code
            let settings = job.routineSettings
            let daily = RoutineReportNotification.daily(jobKey: key, station: job.stationName, now: now,
                                                        isWorkingDay: RoutineReport.isWorkingDay(now, settings: settings),
                                                        signed: job.dailyState(on: now) == .signed)
            let nextWeek = cal.date(byAdding: .day, value: 7, to: MasterSchedule.weekStart(now))!
            let request = job.installEnd >= nextWeek
                ? RoutineReportNotification.request(jobKey: key, station: job.stationName, now: now, hasNextWeek: job.weeklyRequest(for: nextWeek) != nil)
                : nil
            return [daily, request].compactMap { $0 }
        }
        .sorted { $0.id < $1.id }
    }

    /// 30 and 7 days before each tool's calibration runs out (the tools register: the iPad `เครื่องมือ` tab, on iPhone the settings sheet's `เครื่องมือวัด` row).
    private func calibrationPlans(_: Int) -> [NotificationPlan] {
        guard calibrationOn else { return [] }
        return instruments.all.flatMap { tool -> [NotificationPlan] in
            guard let due = tool.calibrationDue else { return [] }
            return ToolNotification.scheduleCalibration(toolID: tool.id, tool: tool.name, kind: tool.kind, due: due, now: .now)
        }
        .sorted { $0.id < $1.id }
    }

    /// `เริ่มติดตั้งพรุ่งนี้` on the eve, then `ติดตั้ง Day n/m` 30 min before each install day starts.
    private func installPlans(_: Int) -> [NotificationPlan] {
        guard planOn else { return [] }
        let now = Date.now
        return heard.filter { $0.status != .completed && $0.installEnd.endOfDay > now }.flatMap { job in
            InstallNotification.plans(jobKey: job.syncID ?? job.code, name: [job.code, job.projectName].filter { !$0.isEmpty }.joined(separator: " "),
                                      team: job.teamRaw, start: job.installStart, days: job.installDays, now: now)
        }
        .sorted { $0.id < $1.id }
    }

    /// Tasks of a PWA station's MP plan that start tomorrow, a station behind its plan, and a step of the ERC flow
    /// whose time limit is about to end or has passed.
    private func mpPlans(_: Int) -> [NotificationPlan] {
        guard planOn else { return [] }
        let now = Date.now
        return heard.pwaStations.filter { $0.status != .completed }.flatMap { job -> [NotificationPlan] in
            let key = job.syncID ?? job.code
            let erc = job.stationContext.over200kVA ? job.stationDocs.erc.map {
                ERCNotification.plans(jobKey: key, station: job.stationName, record: $0, context: job.ercContext, now: now)
            } ?? [] : []
            guard let input = job.scheduleInput else { return erc }
            return erc + MPNotification.plans(jobKey: key, station: job.stationName, plan: MasterSchedule.plan(input),
                                              actual: job.scheduleActual, now: now)
        }
        .sorted { $0.id < $1.id }
    }

    /// Rebuilds the project feed: a post not seen before is announced at once, today's summary waits for 18:00, and
    /// an open issue reminds on its due day. Records made on another device show up here once sync has brought them in.
    /// A job's posts are announced only to who hears its news (`Permissions.hearsNews`): its team members and supervisor
    /// when it names any, a manager always, everyone when it names none. The bell's list keeps every post.
    private func refreshFeed() async {
        let now = Date.now
        let stations = jobs.map(\.feedStation)
        let posts = FeedBuilder.posts(stations, now: now)
        let fresh = LiveFeed.shared.update(posts, me: userName, now: now)
        let access = Dictionary(jobs.map { ($0.feedKey, $0.access) }) { a, _ in a }
        let permissions = permissions
        let heard = { (p: NotificationPlan) in p.info[NotificationInfo.job].map { permissions.hearsNews(access[$0]) } ?? true }
        let service = NotificationService.shared
        await service.schedule([FeedNotification.summary(stations, now: now)].compactMap { $0 }, type: .feed)
        await service.schedule(FeedNotification.due(posts, now: now).filter(heard), type: .issue)
        fresh.filter(heard).forEach(service.post)
    }

    private struct FeedState: Equatable { let tick: Int; let jobs: Int; let on: Bool }

    #if DEBUG
    /// `-notifDemo survey|all`, `-notifAction <type>.<action>` (see `NotificationService.demo`).
    private func debugDemo(_ service: NotificationService) async {
        try? await Task.sleep(for: .seconds(1))   // sample data is seeded by RootView meanwhile
        if NotificationService.demo == "survey", let job = jobs.sorted(by: { $0.code < $1.code }).first {
            job.surveyDate = Date.now.addingTimeInterval(31 * 60)
            UserDefaults.standard.set(job.syncID ?? job.code, forKey: "notifJob")
        }
        if NotificationService.demo == "all" { service.postBoardExamples() }
        if NotificationService.demo == "live" {
            let first = jobs.sorted { $0.code < $1.code }.first
            service.postLiveExamples(job: first.map { $0.syncID ?? $0.code } ?? "demo",
                                     only: UserDefaults.standard.object(forKey: "notifOnly") as? Int ?? UserDefaults.standard.string(forKey: "notifOnly").flatMap(Int.init))
        }
        if let action = UserDefaults.standard.string(forKey: "notifAction") {
            if UserDefaults.standard.string(forKey: "notifJob") == nil, let job = jobs.first {
                UserDefaults.standard.set(job.syncID ?? job.code, forKey: "notifJob")
            }
            try? await Task.sleep(for: .seconds(1))
            service.replay(action)
        }
    }
    #endif

    static func label(_ j: TCRoofCore.Job) -> String {
        j.docNo.isEmpty ? (j.projectName.isEmpty ? "งานสำรวจ" : j.projectName) : "NO.\(j.docNo)"
    }

    private struct SyncState: Equatable {
        let ids: [UUID]
        let on: Bool
        @MainActor init(survey: SurveyModel, on: Bool) { ids = survey.jobsToSync.map(\.id); self.on = on }
    }
}
