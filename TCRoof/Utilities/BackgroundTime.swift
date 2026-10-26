import UIKit

/// A little time after the person leaves the app (about 30 s) to finish what a Drive pass is doing: looking up the
/// folders and handing the files to the background transfer, which iOS then sends on its own (`DriveBackground`).
@MainActor
final class BackgroundTime {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
