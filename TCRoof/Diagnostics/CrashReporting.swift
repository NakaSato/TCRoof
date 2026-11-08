import FirebaseCrashlytics
import UIKit

/// Coarse startup breadcrumbs, without project contents or account details.
@MainActor
enum CrashReporting {
    static func configure() {
        let reporter = Crashlytics.crashlytics()
        reporter.setCustomValue(UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone",
                                forKey: "device_family")
        reporter.log("App startup")
    }

    /// The SwiftData store didn't open (`AppStore`): the error goes to Crashlytics as a non-fatal, since the app no
    /// longer stops on it.
    static func storeFailed(_ error: Error) {
        let reporter = Crashlytics.crashlytics()
        reporter.log("Store failed to open")
        reporter.record(error: error)
    }

    static func startupStage(_ stage: String, state: String, elapsedMilliseconds: Int? = nil) {
        let reporter = Crashlytics.crashlytics()
        reporter.setCustomValue(stage, forKey: "startup_stage")
        reporter.setCustomValue(state, forKey: "startup_stage_state")
        let duration = elapsedMilliseconds.map { " (\($0) ms)" } ?? ""
        reporter.log("Startup \(stage): \(state)\(duration)")
    }
}
