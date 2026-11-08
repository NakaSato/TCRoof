import Foundation
import Observation

/// A value worked out from observable models (SwiftData jobs and reports, the survey model), built once and kept until
/// something it read changes. For values a screen's body would otherwise rebuild on every pass: a tab switch, a sheet, a
/// row toggled or a scroll position re-runs the body but changes none of the data.
///
/// What `build` reads is tracked (`withObservationTracking`), so the first change to any of it drops the value and
/// bumps `version`, which the caller's body has read, so it runs again and rebuilds. What isn't observable (a `@Query`'s
/// list of rows, the day, a file on disk, a setting) goes into `key`, which is compared on every pass.
@MainActor @Observable
final class ObservedCache<Value> {
    private(set) var version = 0
    @ObservationIgnored private var value: Value?
    @ObservationIgnored private var key: AnyHashable?
    /// Set while building: a change seen then is the build's own reading (a fault filling in), not an edit.
    @ObservationIgnored nonisolated(unsafe) private var building = false

    func value(key: AnyHashable, build: () -> Value) -> Value {
        _ = version
        if let value, self.key == key { return value }
        building = true
        let made = withObservationTracking(build) { [weak self] in
            guard let self, !self.building else { return }
            Task { @MainActor [weak self] in self?.invalidate() }
        }
        building = false
        value = made
        self.key = key
        return made
    }

    private func invalidate() {
        guard value != nil else { return }
        value = nil
        version += 1
    }
}
