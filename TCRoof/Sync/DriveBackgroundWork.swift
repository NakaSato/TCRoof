import Foundation
import BackgroundTasks
import SwiftData
import TCRoofUI
import TCRoofCore

/// Starts Drive uploads while the app is closed (the user, 2026-10-22): a job upload the person started that didn't
/// finish, and photos not on Drive yet, for instance taken offline. When the app goes to the background with such work
/// left (`scheduleIfNeeded`), it asks iOS for two background tasks: an app refresh (a short run, when iOS sees fit) and
/// a processing task that waits for a network connection. Either one looks up the folders and hands the files to the
/// background transfer (`DriveBackground`), which iOS then sends on its own, records what landed, and asks again if
/// something is still left.
///
/// iOS decides when they run (often while the device charges or is used little) and runs none after the person
/// force-quits the app, until it is opened again. Try one from Xcode while the app is in the background:
/// `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.tcroof.internal.drive-refresh"]`.
@MainActor
enum DriveBackgroundWork {
    static let refreshID = "com.tcroof.internal.drive-refresh"
    static let processingID = "com.tcroof.internal.drive-processing"

    /// At launch, before `didFinishLaunching` returns (iOS needs the handlers by then).
    static func register() {
        for id in [refreshID, processingID] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { task in
                MainActor.assumeIsolated { handle(task) }
            }
        }
    }

    /// Asks iOS for the two tasks when there is Drive work left; the app going to the background calls it.
    static func scheduleIfNeeded(_ context: ModelContext) {
        guard hasWork(context) else { return }
        let refresh = BGAppRefreshTaskRequest(identifier: refreshID)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        let processing = BGProcessingTaskRequest(identifier: processingID)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = false
        for request in [refresh, processing] as [BGTaskRequest] {
            do { try BGTaskScheduler.shared.submit(request) } catch {
                // the simulator refuses them; a device without background refresh too
                print("Drive: background task \(request.identifier): \(error.localizedDescription)")
            }
        }
    }

    /// A job upload the person started and didn't finish, photos waiting for Drive, or a plan workbook not sent.
    static func hasWork(_ context: ModelContext) -> Bool {
        let survey = SurveyModel.shared
        guard survey.google.isSignedIn else { return false }
        if ProjectDriveUpload.hasRequested { return true }
        guard survey.settings.autoUploadPhotos else { return false }
        let photos = (try? context.fetchCount(FetchDescriptor<PhotoAsset>(predicate: #Predicate { $0.driveFileID == nil && !$0.needsDownload }))) ?? 0
        if photos > 0 { return true }
        let jobs = (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.scheduleWorkbookName != nil }))) ?? []
        return jobs.contains { $0.scheduleWorkbookUnsent }
    }

    private static func handle(_ task: BGTask) {
        let context = TCRoofApp.sharedContainer.mainContext
        let done = Completion(task)
        let work = Task { @MainActor in
            let ok = await pass(context)
            try? context.save()
            scheduleIfNeeded(context)
            done.finish(ok)
        }
        task.expirationHandler = {
            // what was handed to the background transfer goes on; the rest waits for the next run
            work.cancel()
            done.finish(false)
        }
    }

    /// One pass: the started job uploads, then the photos and plan workbooks, as the open app would.
    static func pass(_ context: ModelContext) async -> Bool {
        let survey = SurveyModel.shared
        guard survey.google.isSignedIn, let email = survey.google.email else { return true }
        // launched for this task, the app hasn't loaded the account's role yet, and where its files go depends on it
        // (`DriveRoute`: a contractor's own Drive, the team's center folder)
        if MemberRole.shared.permissions.email != Permissions.normalized(email) { MemberRole.shared.signedIn(email) }
        let docs = await ProjectDriveUpload.resumeNow(context: context, survey: survey)
        let photos = await PhotoSync.shared.uploadNow(context: context, survey: survey)
        return docs && photos
    }

    /// `setTaskCompleted` once, whichever of the pass and the expiry comes first.
    private final class Completion: @unchecked Sendable {
        private let task: BGTask
        private let lock = NSLock()
        private var done = false
        init(_ task: BGTask) { self.task = task }

        func finish(_ success: Bool) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { task.setTaskCompleted(success: success) }
        }
    }
}
