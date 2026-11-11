import Foundation
import TCRoofCore

extension Job {
    /// The station's leading indicators today (CHA-85, `LeadingIndicators`): its ERC flow's waits, the site ICL's
    /// failed items, the daily reports' crew against the crew the plan needs, open problems and this week's request R1.
    /// The install tracking page, the MP plan notifications and the assistant all read this.
    func leadingIndicators(today: Date = .now) -> [LeadingIndicator] {
        let dailies = dailyReports
        let waits = stationDocs.erc.map { ERCFlow.waits($0, ercContext, today: today) } ?? []
        let failed = iclSheets.flatMap { model -> [LeadingIndicators.FailedItem] in
            let sheet = model.sheet
            return sheet.failed(model.items).map { item in
                .init(name: "\(item.id) \(item.title)", checkedAt: sheet.result(item).checkedAt)
            }
        }
        let need = scheduleInput.flatMap {
            Assistant.Strategy.crewNeed(input: $0, actual: scheduleActual, dailies: dailies,
                                        workingWeekdays: routineSettings.workingWeekdays, today: today)
        }
        let input = LeadingIndicators.Input(waits: waits, failedICL: failed, dailies: dailies, crewNeed: need,
                                            requests: weeklyRequests, installStart: installStart, installEnd: installEnd,
                                            completed: status == .completed)
        return LeadingIndicators.compute(input, today: today)
    }
}
