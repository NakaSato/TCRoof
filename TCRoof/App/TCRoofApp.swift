import SwiftUI
import TCRoofUI
import SwiftData
import FirebaseCore

/// Sets the notification delegate at launch, so a quick action that starts the app is still handled.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { NotificationService.shared.configure() }
        return true
    }
}

@main
struct TCRoofApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer = {
        let schema = Schema([
            Job.self, SurveyForm.self, ScannedDevice.self, InstallLog.self,
            Inspection.self, PhotoAsset.self, DocumentAsset.self,
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
        AppFont.register()
        _session = State(initialValue: GoogleSession())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isSignedIn {
                    RootView()
                        .transition(.opacity)
                } else {
                    LoginView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: session.isSignedIn)
            .environment(session)
            // dark only on the login gradient so the status bar turns white; signed in, always light
            .preferredColorScheme(session.isSignedIn ? .light : .dark)
            .tint(Theme.primary)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(GoogleSession.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            #if DEBUG
            // `-screen <name>` opens that screen as the stack's root. Pushed over the home at launch
            // (`.navigationDestination(isPresented: .constant(true))`), iOS 27 never draws a frame: a blank
            // screen and "Observation tracking feedback loop detected".
            if DebugScreen.isKnown {
                NavigationStack { DebugScreen() }
            } else if sizeClass == .compact {
                PhoneTabs { home }
            } else {
                NavigationStack { home }
            }
            #else
            // iPhone: tabs under the floating bar; iPad: one stack from the home
            if sizeClass == .compact {
                PhoneTabs { home }
            } else {
                NavigationStack { home }
            }
            #endif
        }
        .systemNotifications(survey: session.survey)
        .task {
            // report cards name the TCRoof job they belong to
            let context = context
            session.survey.linkedJobLabel = { id in
                (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.syncID == id })))?.first?.linkLabel
            }
            #if DEBUG
            // Simulator checks run on sample data, offline.
            if DebugScreen.requested != nil {
                SampleData.seedIfNeeded(context)
                if UserDefaults.standard.bool(forKey: "planDemo") { SampleData.redate(context, today: PlanCalendarView.today) }
                return
            }
            #endif
            SampleData.removeSamples(context)
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
    static let requested = UserDefaults.standard.string(forKey: "screen")
    static let screens: Set = ["survey", "plan", "scan", "install", "job", "surveyForm", "devices", "logs", "log", "icl", "pwa", "components", "mp", "mpall", "permits", "poa", "selfcert", "homework",
                              "daily", "dailies", "request", "weekly", "monthly", "routine"]
    static var isKnown: Bool { requested.map(screens.contains) ?? false }

    @Query(sort: \Job.installStart) private var jobs: [Job]

    var body: some View {
        let job = jobs.first { $0.status == .installing } ?? jobs.first
        switch Self.requested {
        case "survey": SurveyListView()
        case "plan": PlanCalendarView()
        case "scan": ScanJobListView()
        case "install": InstallRecordsView()
        case "job": if let job { JobDetailView(job: job) }
        case "surveyForm": if let job { SurveyFormView(job: job) }
        case "devices": if let job { JobDevicesView(job: job) }
        case "logs": if let job { JobInstallLogsView(job: job) }
        case "log": if let log = job?.logs.first { InstallLogDetailView(log: log) }
        case "icl": if let job { InspectionView(job: job) }
        case "mp": if let job { MPScheduleScreen(job: job).onAppear { job.seedMPDemo() } }
        case "mpall":
            MPOverviewView().onAppear {
                for (i, j) in jobs.prefix(4).enumerated() { j.seedMPDemo(mp: 189 + i, shift: [0, -14, 10, -30][i], pace: [1, 1.6, 0.6, 2.2][i]) }
            }
        case "pwa": SolarSurveyEntryView()
        case "permits": if let job { PermitFormsView(job: job) }
        case "poa": if let job { PowerOfAttorneyView(job: job) }
        case "selfcert": if let job { SelfCertificationView(job: job) }
        case "homework": if let job { HomeWorkView(job: job) }
        case "daily", "dailies", "request", "weekly", "monthly", "routine":
            if let job { RoutineDebugScreen(job: job, screen: Self.requested ?? "") }
        case "components": ComponentGallery(only: Optional(UserDefaults.standard.integer(forKey: "gallerySection")).flatMap { $0 == 0 ? nil : $0 })
        default: EmptyView()
        }
    }
}
#endif
