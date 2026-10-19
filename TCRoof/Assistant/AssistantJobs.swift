import Foundation
import SwiftData
import TCRoofCore

extension Job {
    /// The station's name for the assistant: the project name, else its MP number or code. Never the customer's name,
    /// which `stationName` falls back to.
    var assistantStation: String {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return mpNumber.map { "MP \($0)" } ?? code
    }

    /// This station as the assistant sees it: its MP plan, progress and daily reports, no customer details.
    func assistantJob(_ permissions: Permissions) -> Assistant.Job {
        Assistant.Job(id: overviewID, station: assistantStation, mpNumber: mpNumber, kWp: capacityKW > 0 ? capacityKW : nil,
                      input: scheduleInput, actual: scheduleActual, dailies: dailyReports,
                      canEdit: permissions.can(.mpProgress, on: access))
    }
}

extension ModelContext {
    /// The PWA stations with an MP plan, read fresh for each of the assistant's tool calls.
    func assistantStations() -> [Job] {
        ((try? fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\.installStart)]))) ?? []).pwaStations
            .filter { $0.scheduleInput != nil }
    }

    /// Saves a change the person confirmed on the assistant's card, as บันทึกความก้าวหน้า does. False when the station
    /// or its plan is gone.
    func applyAssistant(_ action: Assistant.PendingAction) -> Bool {
        guard let job = assistantStations().first(where: { $0.overviewID == action.jobID }), let input = job.scheduleInput else { return false }
        let a = action.apply(to: job.scheduleActual, input: input)
        if a != job.scheduleActual { job.scheduleActual = a }
        try? save()
        return true
    }
}
