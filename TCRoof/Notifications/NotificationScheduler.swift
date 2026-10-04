import SwiftUI
import SwiftData
import TCRoofCore
import SurveyUI

extension View {
    /// Keeps the system notifications in step with the jobs and survey reports while signed in.
    func systemNotifications(survey: SurveyModel) -> some View { modifier(NotificationScheduler(survey: survey)) }
}

/// Survey reminders 30 min before today's and tomorrow's appointments, the one `รอซิงก์`, and
/// `บันทึกขึ้น Drive แล้ว`; rescheduled when jobs, reports, the toggles or the day change.
private struct NotificationScheduler: ViewModifier {
    let survey: SurveyModel
    @Query private var jobs: [Job]
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NotificationGroup.survey.defaultsKey) private var surveyOn = true
    @AppStorage(NotificationGroup.syncExport.defaultsKey) private var syncOn = true
    /// Bumped when the app comes back, so a new day reschedules.
    @State private var tick = 0

    func body(content: Content) -> some View {
        content
            .task {
                let service = NotificationService.shared
                #if DEBUG
                // the component gallery's screenshots run on a fresh install; no permission prompt over them
                if UserDefaults.standard.string(forKey: "screen") != "components" { await service.requestAuthorization() }
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

    #if DEBUG
    /// `-notifDemo survey|all`, `-notifAction <type>.<action>` (see `NotificationService.demo`).
    private func debugDemo(_ service: NotificationService) async {
        try? await Task.sleep(for: .seconds(1))   // sample data is seeded by RootView meanwhile
        if NotificationService.demo == "survey", let job = jobs.sorted(by: { $0.code < $1.code }).first {
            job.surveyDate = Date.now.addingTimeInterval(31 * 60)
            UserDefaults.standard.set(job.syncID ?? job.code, forKey: "notifJob")
        }
        if NotificationService.demo == "all" { service.postBoardExamples() }
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
