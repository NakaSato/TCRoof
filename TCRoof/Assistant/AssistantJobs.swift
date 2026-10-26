import Foundation
import SwiftData
import TCRoofCore
import TCRoofUI

extension Job {
    /// The station's name for the assistant: the project name, else its MP number or code. Never the customer's name,
    /// which `stationName` falls back to.
    var assistantStation: String {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return mpNumber.map { "MP \($0)" } ?? code
    }

    /// This station as the assistant sees it: its MP plan, progress, daily reports, crew, inspections and paper
    /// deadlines; no customer details. `library` is the PWA paper library, read once for all stations.
    func assistantJob(_ permissions: Permissions, library: StationDocs.Library? = nil) -> Assistant.Job {
        let settings = routineSettings
        let deadlines = library.map { lib in
            PWAPlan.deadlines([planStation], library: lib, today: .now).map { Assistant.Deadline(date: $0.date, title: $0.title) }
        } ?? []
        return Assistant.Job(id: overviewID, station: assistantStation, mpNumber: mpNumber, kWp: capacityKW > 0 ? capacityKW : nil,
                             input: scheduleInput, actual: scheduleActual, dailies: dailyReports,
                             canEdit: permissions.can(.mpProgress, on: access), canReplan: permissions.can(.mpSetup, on: access),
                             contractor: settings.subcontractor.trimmingCharacters(in: .whitespaces), team: team.rawValue,
                             workingWeekdays: settings.workingWeekdays, inspections: settings.inspections, deadlines: deadlines)
    }
}

extension Job {
    /// The rest of this station for `get_project`: the job's basics, its NO.224 surveys, papers and ERC flow, IEC test,
    /// weekly requests, ICL, scanned devices, install logs and inspections. No customer details: the survey reports go
    /// as completion, section facts and missing items, never their A1 answers.
    @MainActor
    func assistantProject(library: StationDocs.Library, today: Date = .now) -> Assistant.ProjectFacts {
        let cal = MasterSchedule.calendar
        let day = { (d: Date) in ScheduleBrief.day(d, calendar: cal) }
        let settings = routineSettings
        let contractor = settings.subcontractor.trimmingCharacters(in: .whitespaces)
        let basics = Assistant.ProjectFacts.Basics(
            code: code, status: status.title, province: province,
            capacityKW: capacityKW > 0 ? capacityKW : nil, inverterKW: inverterKW,
            crew: contractor.isEmpty ? "ทีม \(team.rawValue)" : "ผู้รับเหมา \(contractor)",
            surveyDate: day(surveyDate), installStart: day(installStart), installEnd: day(installEnd),
            hasMPPlan: scheduleInput != nil)
        let surveys = syncID.map { SurveyModel.shared.jobs(linkedTo: $0) } ?? []
        let icl = inspection.map {
            Assistant.ProjectFacts.ICL(stepsDone: $0.completedCount, steps: InspectionStep.all.count,
                                       allPassed: $0.allPassed, submitted: $0.submittedAt.map(day))
        }
        let devices = Dictionary(grouping: self.devices, by: { $0.kind.title }).mapValues(\.count)
        let isPWA = kind == .pwa
        return Assistant.ProjectFacts(
            jobID: overviewID, station: assistantStation, mpNumber: mpNumber, basics: basics, surveys: surveys,
            stationDocs: isPWA ? stationDocs : nil, library: library, docsContext: isPWA ? stationContext : nil,
            ercContext: ercContext, iec: iecReport, weeklyRequests: weeklyRequests, icl: icl, devices: devices,
            installLogs: logs.map(\.date), inspections: settings.inspections, today: today, calendar: cal)
    }
}

extension ModelContext {
    /// Every PWA station, with or without an MP plan, for the assistant's list and `get_project`.
    func assistantProjects() -> [Job] {
        ((try? fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\.installStart)]))) ?? []).pwaStations
    }

    /// The PWA stations with an MP plan, read fresh for each of the assistant's tool calls.
    func assistantStations() -> [Job] {
        ((try? fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\.installStart)]))) ?? []).pwaStations
            .filter { $0.scheduleInput != nil }
    }

    /// Saves a change the person confirmed on the assistant's card, as บันทึกความก้าวหน้า does, and lists it as
    /// confirmed through the assistant by `email`. False when the station or its plan is gone.
    func applyAssistant(_ action: Assistant.PendingAction, by email: String) -> Bool {
        guard let job = assistantStations().first(where: { $0.overviewID == action.jobID }), let input = job.scheduleInput else { return false }
        var a = job.scheduleActual
        if let replanned = action.replanned(input) {
            job.scheduleInput = replanned
        } else {
            a = action.apply(to: a, input: input)
        }
        a.confirmations.append(action.confirmation(by: email))
        job.scheduleActual = a
        // a re-plan can give a permit task weight it had none of: book what its papers approved
        job.bookPermitsFromDocs()
        try? save()
        return true
    }
}
