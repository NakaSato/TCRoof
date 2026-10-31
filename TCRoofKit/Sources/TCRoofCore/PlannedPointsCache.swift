import Foundation

/// Weekly weights are shared by the home timeline, plan charts and notification scheduler.
/// Exact value keys keep edits and calendar changes from reusing an older result.
final class PlannedPointsCache: @unchecked Sendable {
    static let shared = PlannedPointsCache()
    private let lock = NSLock()
    private var entries: [(plan: [MasterSchedule.PlannedTask], calendar: Calendar, points: [MasterSchedule.Task: [Date: Double]])] = []
    private let capacity = 64

    func points(for plan: [MasterSchedule.PlannedTask], calendar: Calendar,
                build: () -> [MasterSchedule.Task: [Date: Double]]) -> [MasterSchedule.Task: [Date: Double]] {
        lock.lock()
        if let index = entries.firstIndex(where: { $0.plan == plan && $0.calendar == calendar }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            lock.unlock()
            return entry.points
        }
        lock.unlock()
        // Do not block another caller's UI while a worker expands a long schedule.
        let points = build()
        lock.lock()
        entries.removeAll { $0.plan == plan && $0.calendar == calendar }
        entries.append((plan, calendar, points))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        lock.unlock()
        return points
    }
}
