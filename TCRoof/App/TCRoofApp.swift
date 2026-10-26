import SwiftUI
import TCRoofUI
import TCRoofCore
import SwiftData
import ExcelExport
import FirebaseCore

/// Sets the notification delegate at launch, so a quick action that starts the app is still handled, and connects the
/// Drive uploads' background session (`DriveBackground`), so uploads go on after the person leaves the app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated {
            NotificationService.shared.configure()
            // starts Drive uploads left waiting while the app is closed (`DriveBackgroundWork`)
            DriveBackgroundWork.register()
        }
        DriveBackground.activate()
        return true
    }

    /// iOS woke the app for Drive uploads that finished while it was in the background or closed.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        if !DriveBackground.handleEvents(identifier, completion: completionHandler) { completionHandler() }
    }
}

@main
struct TCRoofApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// One container for the process: the scene's, and `DriveBackgroundWork`'s when iOS launches the app for it.
    let container = TCRoofApp.sharedContainer
    static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Job.self, SurveyForm.self, ScannedDevice.self, InstallLog.self,
            Inspection.self, ICLSheet.self, PhotoAsset.self, DocumentAsset.self,
            Trip.self, Expense.self, ClaimMonth.self,
            ToolEvent.self, CompanyVehicle.self,
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create model container: \(error)")
        }
    }()

    @State private var session: GoogleSession

    init() {
        FirebaseApp.configure()
        // before any Firestore call (sign-in's membership check is one): settings can't change once it has started
        CloudSync.configureCache()
        AppFont.register()
        _session = State(initialValue: GoogleSession())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isSignedIn {
                    RootView()
                        .overlay {
                            // `config/app.minSyncVersion` is above this build: nothing more until the update
                            if AppGate.shared.outdated { UpdateRequiredView().transition(.opacity) }
                        }
                        .transition(.opacity)
                } else {
                    LoginView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: session.isSignedIn)
            // `tcroof://job/<syncID>` (a survey appointment in Calendar) opens the job as a notification tap does; before
            // sign-in it waits for the home
            .onOpenURL { url in
                if let link = DeepLink(url: url) { NotificationService.shared.link = link }
            }
            .environment(session)
            // light everywhere, the login page included (it's on the design system's light page)
            .preferredColorScheme(.light)
            .tint(Theme.primary)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(GoogleSession.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            // `-screen <name>` opens that screen as the stack's root. Pushed over the home at launch
            // (`.navigationDestination(isPresented: .constant(true))`), iOS 27 never draws a frame: a blank
            // screen and "Observation tracking feedback loop detected".
            if DebugScreen.requested == "pwa" {
                // the PWA module is a tab of the main dock: `กปภ.` on iPhone, `โครงการ` on iPad
                if sizeClass == .compact { PhoneTabs { home } } else { PadTabs { home } }
            } else if DebugScreen.isKnown {
                NavigationStack { DebugScreen() }
            } else if sizeClass == .compact {
                PhoneTabs { home }
            } else {
                PadTabs { home }
            }
            #else
            // tabs under the floating dock, each with its own stack
            if sizeClass == .compact {
                PhoneTabs { home }
            } else {
                PadTabs { home }
            }
            #endif
        }
        .systemNotifications(survey: session.survey)
        // Drive work left when the person leaves: iOS starts it later, even after the app is closed
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { DriveBackgroundWork.scheduleIfNeeded(context) }
        }
        #if DEBUG
        // `-driveBackgroundPass YES`: the background task's pass at launch, since the simulator runs no BGTask
        .task {
            guard UserDefaults.standard.bool(forKey: "driveBackgroundPass") else { return }
            let ok = await DriveBackgroundWork.pass(context)
            print("DriveBackgroundWork: pass \(ok ? "ok" : "failed"), work left: \(DriveBackgroundWork.hasWork(context))")
        }
        #endif
        // ซิงก์นัดอัตโนมัติ, when turned on in Settings › ปฏิทิน
        .calendarSync()
        // what the signed-in member's role lets them do, for every screen
        .environment(\.permissions, MemberRole.shared.permissions)
        .task {
            // report cards name the TCRoof job they belong to
            let context = context
            session.survey.linkedJobLabel = { id in
                (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.syncID == id })))?.first?.linkLabel
            }
            session.survey.linkedJobAccess = { id in
                (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.syncID == id })))?.first?.access
            }
            // a survey's photos on Drive are read by everyone who can open it
            let surveyModel = session.survey
            session.survey.driveReaders = { job in DriveReaders.survey(surveyModel.access(job)) }
            // a survey moved to installation puts its job into construction, as its first install log does, and in the
            // PWA module, whose install overview and install tracking page list it
            session.survey.onMovedToInstall = { id in
                guard let job = (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.syncID == id })))?.first,
                      job.status == .confirmed || job.status == .interested else { return }
                job.status = .installing
                job.kind = .pwa
                try? context.save()
            }
            // moved back: the job leaves the install list, unless its installation has started (an MP plan or a log)
            session.survey.onMovedBackToSurvey = { id in
                guard let job = (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.syncID == id })))?.first,
                      job.status == .installing, job.scheduleInputJSON == nil, job.logs.isEmpty else { return }
                job.status = .confirmed
                try? context.save()
            }
            // a deleted survey takes the job made for it along (its syncID is the survey's id), unless work was recorded on it
            session.survey.onDeleted = { survey in
                let id = survey.id.uuidString
                guard survey.jobSyncID == id,
                      let job = (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.syncID == id })))?.first,
                      job.scheduleInputJSON == nil, job.iecReportJSON == nil, job.stationDocsJSON == nil,
                      job.logs.isEmpty, job.surveys.isEmpty, job.devices.isEmpty, job.inspections.isEmpty, job.documents.isEmpty
                else { return }
                context.delete(job)
                try? context.save()
            }
            // a survey moved to installation with no TCRoof job gets one, so its card opens the install tracking page. Its
            // syncID is the survey's id: two devices making it for the same survey write the same record
            session.survey.makeInstallJob = { survey in
                let id = survey.id.uuidString
                if let job = (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.syncID == id })))?.first {
                    if job.status == .confirmed || job.status == .interested { job.status = .installing }
                    job.kind = .pwa
                    try? context.save()
                    return id
                }
                let v = survey.values
                let job = Job(code: SampleData.newJobCode(),
                              projectName: survey.projectName.isEmpty ? "ยังไม่ได้ตั้งชื่อโครงการ" : survey.projectName,
                              customerName: v.text("coordinator"), phone: v.text("phone"), address: v.text("address"), province: "",
                              capacityKW: Double(v.text("capacity").trimmingCharacters(in: .whitespaces)) ?? 0, team: .t1,
                              status: .installing, surveyDate: ISODate.date(v.text("date")) ?? survey.created,
                              installStart: .now, installDays: 2)
                job.syncID = id
                job.kind = .pwa
                context.insert(job)
                try? context.save()
                return id
            }
            #if DEBUG
            // Simulator checks run on sample data, offline.
            if DebugScreen.requested != nil {
                SampleData.seedIfNeeded(context)
                Job.keepKinds(context)
                if UserDefaults.standard.bool(forKey: "planDemo") { SampleData.redate(context, today: PlanCalendarView.today) }
                return
            }
            #endif
            // another account signed in: the previous one's records go before sync brings this one's
            LocalData.wipeIfNeeded(context, survey: session.survey)
            SampleData.removeSamples(context)
            Job.keepKinds(context)
            CloudSync.shared.start(context: context, survey: session.survey)
            let survey = session.survey
            NotificationService.shared.syncNow = { survey.cloudPush?() }
            if NotificationService.shared.takePendingSyncNow() { survey.cloudPush?() }
        }
    }

    private var home: some View {
        HomeView()
    }
}

#if DEBUG
/// Opens one screen directly for simulator checks: `simctl launch <device> com.tcroof.internal -screen plan`.
struct DebugScreen: View {
    static var requested: String? { UserDefaults.standard.string(forKey: "screen") }
    static let screens: Set = ["survey", "plan", "planlist", "surveyhistory", "scanhistory", "loghistory", "scan", "install", "job", "surveyForm", "devices", "logs", "log", "icl", "pwa", "station", "components", "mp", "mpall", "permits", "poa", "selfcert", "homework",
                              "daily", "dailies", "request", "weekly", "monthly", "routine", "stationdocs", "siteicl", "members", "useradmin", "assistant", "travel", "claimreview"]
    static var isKnown: Bool { requested.map(screens.contains) ?? false }

    @Query(sort: \Job.installStart) private var jobs: [Job]
    /// The job `-screen mp` opened, kept for the launch: clearing its plan or starting it from a template moves its
    /// install dates, which would otherwise hand the screen to another job.
    @MainActor private static var mpJob: String?

    /// `-jobKind home|pwa` shows the job detail as that kind. `-mpDemo` needs the PWA cards, also on the job whose plan it clears.
    private static func applyJobKind(_ job: Job) {
        let defaults = UserDefaults.standard
        if let kind = defaults.string(forKey: "jobKind").flatMap(JobKind.init) { job.kind = kind }
        else if defaults.string(forKey: "mpDemo") != nil { job.kind = .pwa }
    }

    var body: some View {
        let job = jobs.first { $0.status == .installing } ?? jobs.first
        switch Self.requested {
        case "survey": SurveyListView()
        case "plan": PlanCalendarView()
        case "planlist": PlanListView()
        case "surveyhistory": SurveyHistoryView()
        case "scanhistory": ScanHistoryView()
        case "loghistory": InstallLogHistoryView()
        case "scan": ScanJobListView()
        case "install": InstallRecordsView()
        case "job": if let job { JobDetailView(job: job).onAppear { Self.applyJobKind(job) } }
        case "surveyForm": if let job { SurveyFormView(job: job) }
        case "devices": if let job { JobDevicesView(job: job) }
        case "logs": if let job { JobInstallLogsView(job: job) }
        case "log": if let log = job?.logs.first { InstallLogDetailView(log: log) }
        case "icl": if let job { InspectionView(job: job) }
        // `-mpClear YES` opens it on the job with no plan, no progress, no WBS and no plan file instead; then
        // `-mpTemplate P3-028` starts it from that station's plan file (moved to today) and `-mpTickWBS 2.1.1,2.1.2` ticks those WBS rows today
        case "mp": if let job = Self.mpJob.flatMap({ id in jobs.first { $0.syncID == id } }) ?? job {
            MPScheduleScreen(job: job).onAppear {
                guard Self.mpJob == nil else { return }
                Self.mpJob = job.syncID
                let d = UserDefaults.standard
                if d.bool(forKey: "mpClear") {
                    job.scheduleInputJSON = nil; job.scheduleActualJSON = nil
                    job.scheduleWBSJSON = nil; job.wbsTicksJSON = nil
                    job.scheduleWorkbook = nil; job.scheduleWorkbookName = nil; job.scheduleWorkbookDriveID = nil
                } else { job.seedMPDemo() }
                if let id = d.string(forKey: "mpTemplate"), job.scheduleInput == nil,
                   let c = MPTemplates.cases().first(where: { $0.id == id }),
                   let r = try? MPTemplates.plan(c, kickoff: MasterSchedule.calendar.startOfDay(for: .now)) {
                    MPWorkbookFlow.install(r.imported, data: r.data, name: "แผนงาน MP (แม่แบบ \(c.id)).xlsx", on: job)
                }
                if let codes = d.string(forKey: "mpTickWBS") {
                    var ticks = job.wbsTicks
                    for code in codes.split(separator: ",") {
                        ticks[String(code)] = .init(by: MemberRole.shared.permissions.email, at: MasterSchedule.calendar.startOfDay(for: .now))
                    }
                    job.wbsTicks = ticks
                }
            }
        }
        case "mpall":
            MPOverviewView().onAppear {
                for (i, j) in jobs.prefix(4).enumerated() { j.seedMPDemo(mp: 189 + i, shift: [0, -14, 10, -30][i], pace: [1, 1.6, 0.6, 2.2][i]) }
            }
        case "pwa": SolarSurveyEntryView()
        case "station":
            let tabStr = UserDefaults.standard.string(forKey: "stationTab") ?? "overview"
            let tab: PWAMaintenanceStationView.Tab = tabStr == "repairs" ? .repairs : tabStr == "pm" ? .pm : tabStr == "equipment" ? .equipment : .overview
            PWAMaintenanceStationView(
                station: MaintenanceStationSummary(
                    id: "demo-25", mpNumber: 25, name: "สถานีผลิตน้ำนครชัยศรี", kWp: 220,
                    energy: 410, expected: 790, pr: 63, status: .alarm, openRepairs: 1,
                    nextPM: Calendar.current.date(byAdding: .day, value: 21, to: .now),
                    note: "INV 2 fault | 2 วัน"
                ),
                initialTab: tab
            )
        case "permits": if let job { PermitFormsView(job: job) }
        case "poa": if let job { PowerOfAttorneyView(job: job) }
        case "selfcert": if let job { SelfCertificationView(job: job) }
        case "homework": if let job { HomeWorkView(job: job) }
        case "stationdocs": if let job { StationDocsScreen(job: job) }
        // the PWA site ICL (`SiteICL`) of the first job
        case "siteicl": if let job { SiteICLScreen(job: job) }
        case "members": MembersView()
        // `-travelDemo YES` seeds a month (for good), `-travelMonth 2026-09` opens that month, `-travelSubmit YES` the sign sheet
        case "travel": ClaimScreen()
        // `-claimReviewDemo YES` lists three team members' months and the manager's own (decisions in memory),
        // `-claimReviewFilter ส่งกลับ|อนุมัติแล้ว` picks the tab; run with `-role manager`
        case "claimreview": ClaimReviewScreen()
        case "useradmin": UserAdminView().debugBoard()
        // `-assistantDemo YES` answers from a stand-in for Qwen; `-assistantFocus YES` opens it on the first job
        case "assistant":
            AssistantChatView(focus: UserDefaults.standard.bool(forKey: "assistantFocus") ? jobs.first : nil).onAppear {
                for (i, j) in jobs.prefix(4).enumerated() { j.seedMPDemo(mp: 189 + i, shift: [0, -14, 10, -30][i], pace: [1, 1.6, 0.6, 2.2][i]) }
            }
        case "daily", "dailies", "request", "weekly", "monthly", "routine":
            if let job { RoutineDebugScreen(job: job, screen: Self.requested ?? "") }
        case "components": ComponentGallery(only: Optional(UserDefaults.standard.integer(forKey: "gallerySection")).flatMap { $0 == 0 ? nil : $0 })
        default: EmptyView()
        }
    }
}
#endif
