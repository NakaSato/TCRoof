import Foundation

/// A page's heavy calculation (layout search, the year's shade, the hourly yield) off the main thread, tied to the
/// calling task: when the page's `.task(id:)` restarts or the page closes, the run is cancelled with it, and a short
/// wait first lets a burst of edits (typing "12.5", tapping ± quickly) start one run instead of one per edit.
///
/// The engines don't stop part way yet, so a cancelled run still finishes in the background; the wait is what saves
/// the work. Callers check `Task.isCancelled` after it and drop a stale result.
enum BackgroundRun {
    static func run<T: Sendable>(debounce: Duration = .zero, priority: TaskPriority = .userInitiated,
                                 _ work: @escaping @Sendable () -> T) async -> T? {
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return nil }
        }
        let worker = Task.detached(priority: priority) { work() }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
