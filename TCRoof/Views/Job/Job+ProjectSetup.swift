import Foundation
import TCRoofCore

/// A job's facts a plan file can set (`ProjectSetup.Target`): read from the job, and written back only where they
/// changed, so a take that changes nothing leaves the job's records (and their sync) untouched.
extension Job {
    var setupTarget: ProjectSetup.Target {
        get {
            .init(stationName: projectName, kWp: capacityKW, customerName: customerName, inverterKW: inverterKW,
                  station: stationDocs, routine: routineSettings)
        }
        set {
            if newValue.stationName != projectName { projectName = newValue.stationName }
            if newValue.kWp != capacityKW { capacityKW = newValue.kWp }
            if newValue.customerName != customerName { customerName = newValue.customerName }
            if newValue.inverterKW != inverterKW { inverterKW = newValue.inverterKW }
            if newValue.station != stationDocs { stationDocs = newValue.station }
            if newValue.routine != routineSettings { routineSettings = newValue.routine }
        }
    }

    /// The facts the file has that this job doesn't hold yet (`ตั้งค่าโครงการจากไฟล์`).
    func setupChanges(_ setup: ProjectSetup) -> [ProjectSetup.Change] { setup.changes(for: setupTarget) }

    /// Takes the chosen facts from a plan file. Returns how many it took.
    @discardableResult
    func takeSetup(_ setup: ProjectSetup, fields: Set<ProjectSetup.Field>) -> Int {
        let wanted = Set(setupChanges(setup).map(\.field)).intersection(fields)
        guard !wanted.isEmpty else { return 0 }
        var t = setupTarget
        setup.apply(wanted, to: &t)
        setupTarget = t
        return wanted.count
    }

    /// The gaps only: every fact the file has for a field this job leaves empty.
    @discardableResult
    func fillSetup(_ setup: ProjectSetup) -> Int {
        takeSetup(setup, fields: ProjectSetup.defaultFields(setupChanges(setup)))
    }
}
