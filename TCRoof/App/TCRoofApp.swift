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
            // dark only on the login gradient so the status bar turns white
            .preferredColorScheme(session.isSignedIn ? .light : .dark)
            .tint(Theme.primary)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(GoogleSession.self) private var session

    var body: some View {
        NavigationStack {
            HomeView()
            #if DEBUG
                .navigationDestination(isPresented: .constant(DebugScreen.isKnown)) {
                    DebugScreen()
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
            if DebugScreen.requested != nil { return SampleData.seedIfNeeded(context) }
            #endif
            SampleData.removeSamples(context)
            CloudSync.shared.start(context: context, survey: session.survey)
            let survey = session.survey
            NotificationService.shared.syncNow = { survey.cloudPush?() }
            if NotificationService.shared.takePendingSyncNow() { survey.cloudPush?() }
        }
    }
}

#if DEBUG
/// Opens one screen directly for simulator checks: `simctl launch <device> com.tcroof.internal -screen plan`.
struct DebugScreen: View {
    static let requested = UserDefaults.standard.string(forKey: "screen")
    static let screens: Set = ["survey", "plan", "scan", "install", "job", "surveyForm", "devices", "logs", "log", "icl", "pwa", "components"]
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
        case "pwa": SolarSurveyEntryView()
        case "components": ComponentGallery(only: Optional(UserDefaults.standard.integer(forKey: "gallerySection")).flatMap { $0 == 0 ? nil : $0 })
        default: EmptyView()
        }
    }
}
#endif
