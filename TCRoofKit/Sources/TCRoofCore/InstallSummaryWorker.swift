import Foundation

/// Decodes and calculates station summaries away from the UI actor, retaining only the current stations.
public actor InstallSummaryWorker {
    private struct Entry {
        let input: InstallSummaryInput
        let day: Date
        let summary: InstallStationSummary
    }
    private var entries: [String: Entry] = [:]
    private(set) var calculationCount = 0

    public init() {}

    public func summaries(_ inputs: [InstallSummaryInput], at now: Date) -> [InstallStationSummary] {
        let day = MasterSchedule.calendar.startOfDay(for: now)
        var kept: [String: Entry] = [:]
        var result: [InstallStationSummary] = []
        for input in inputs {
            guard !Task.isCancelled else { return [] }
            let id = input.base.id
            let entry: Entry
            if let existing = entries[id], existing.input == input, existing.day == day {
                entry = existing
            } else {
                entry = Entry(input: input, day: day, summary: input.summary(at: now))
                calculationCount += 1
            }
            kept[id] = entry
            result.append(entry.summary)
        }
        entries = kept
        return result
    }
}
