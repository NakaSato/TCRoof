import Foundation
import SwiftData

/// A SwiftData model mirrored to one Firestore collection. Only text fields travel; photos,
/// signatures and documents stay on the device and Google Drive.
protocol CloudSynced: PersistentModel {
    associatedtype Record: Codable
    static var collection: String { get }
    var syncID: String? { get set }
    var record: Record { get }
    /// Copies a record's fields; false when the record's job isn't on this device yet.
    func apply(_ r: Record, jobs: [String: Job]) -> Bool
    /// An unlinked model to insert and then `apply` the record to; nil when its job isn't on this device yet.
    static func make(_ r: Record, jobs: [String: Job]) -> Self?
}

extension Date {
    /// Whole milliseconds, so a date reads back from Firestore exactly as it was written.
    var millis: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
    init(millis: Int64) { self.init(timeIntervalSince1970: Double(millis) / 1000) }
}

/// The job a child record points at: .some(nil) for no job, nil when that job hasn't arrived yet.
private func parent(_ id: String?, in jobs: [String: Job]) -> Job?? {
    guard let id else { return .some(nil) }
    return jobs[id].map { .some($0) }
}

// MARK: - Job

extension Job: CloudSynced {
    struct Record: Codable {
        var code, projectName, customerName, phone, address, province: String
        var capacityKW: Double
        var team, status: String
        var surveyDate, installStart, createdAt: Int64
        var installDays: Int
        var driveFolderURL: String?
        // MP schedule; optional so documents from older app versions still decode.
        var mpNumber: Int?
        var inverterKW: Double?
        var scheduleInput, scheduleActual: String?
        var routineSettings, weeklyRequests: String?
        var stationDocs: String?
        var kind: String?
        var iecReport: String?

        var hasPWAData: Bool {
            mpNumber != nil || scheduleInput != nil || routineSettings != nil || weeklyRequests != nil || stationDocs != nil
        }
    }

    static let collection = "jobs"

    var record: Record {
        Record(code: code, projectName: projectName, customerName: customerName, phone: phone, address: address,
               province: province, capacityKW: capacityKW, team: teamRaw, status: statusRaw,
               surveyDate: surveyDate.millis, installStart: installStart.millis, createdAt: createdAt.millis,
               installDays: installDays, driveFolderURL: driveFolderURL, mpNumber: mpNumber, inverterKW: inverterKW,
               scheduleInput: scheduleInputJSON, scheduleActual: scheduleActualJSON,
               routineSettings: routineSettingsJSON, weeklyRequests: weeklyRequestsJSON, stationDocs: stationDocsJSON, kind: kind.rawValue,
               iecReport: iecReportJSON)
    }

    func apply(_ r: Record, jobs: [String: Job]) -> Bool {
        code = r.code; projectName = r.projectName; customerName = r.customerName; phone = r.phone
        address = r.address; province = r.province; capacityKW = r.capacityKW
        teamRaw = r.team; statusRaw = r.status
        surveyDate = Date(millis: r.surveyDate); installStart = Date(millis: r.installStart)
        createdAt = Date(millis: r.createdAt); installDays = r.installDays; driveFolderURL = r.driveFolderURL
        // a record written by an app version without the MP plan keeps this device's
        if let v = r.mpNumber { mpNumber = v }
        if let v = r.inverterKW { inverterKW = v }
        if let v = r.scheduleInput { scheduleInputJSON = v }
        if let v = r.scheduleActual { scheduleActualJSON = v }
        if let v = r.routineSettings { routineSettingsJSON = v }
        if let v = r.weeklyRequests { weeklyRequestsJSON = v }
        if let v = r.stationDocs { stationDocsJSON = v }
        if let v = r.iecReport { iecReportJSON = v }
        // a record with no kind is from an app version that took a job with PWA data for a PWA job
        if let v = r.kind { kindRaw = v } else if kindRaw == nil, r.hasPWAData { kind = .pwa }
        return true
    }

    static func make(_ r: Record, jobs: [String: Job]) -> Job? {
        let job = Job(code: r.code, projectName: r.projectName, customerName: r.customerName, province: r.province,
                      capacityKW: r.capacityKW, team: .t1, status: .interested, surveyDate: .now, installStart: .now,
                      installDays: r.installDays)
        return job
    }
}

// MARK: - Survey

extension SurveyForm: CloudSynced {
    struct Record: Codable {
        var createdAt: Int64
        var surveyor, roofType, orientation, shading, meterPhase, notes: String
        var roofAreaSqm, monthlyBill, recommendedKW: Double
        var tiltDegree, mainBreakerAmp: Int
        var structureOK: Bool
        var jobID: String?
        // Optional so documents written by older app versions still decode.
        var isDraft: Bool?
        var utility, caNumber, meterSize, tariff, grounding: String?
        var monthlyKWh, latitude, longitude: Double?
    }

    static let collection = "surveyForms"

    var record: Record {
        Record(createdAt: createdAt.millis, surveyor: surveyor, roofType: roofType, orientation: orientation,
               shading: shading, meterPhase: meterPhase, notes: notes, roofAreaSqm: roofAreaSqm,
               monthlyBill: monthlyBill, recommendedKW: recommendedKW, tiltDegree: tiltDegree,
               mainBreakerAmp: mainBreakerAmp, structureOK: structureOK, jobID: job?.syncID,
               isDraft: isDraft, utility: utility, caNumber: caNumber, meterSize: meterSize, tariff: tariff,
               grounding: grounding, monthlyKWh: monthlyKWh, latitude: latitude, longitude: longitude)
    }

    func apply(_ r: Record, jobs: [String: Job]) -> Bool {
        guard let owner = parent(r.jobID, in: jobs) else { return false }
        createdAt = Date(millis: r.createdAt); surveyor = r.surveyor; roofType = r.roofType
        orientation = r.orientation; shading = r.shading; meterPhase = r.meterPhase; notes = r.notes
        roofAreaSqm = r.roofAreaSqm; monthlyBill = r.monthlyBill; recommendedKW = r.recommendedKW
        tiltDegree = r.tiltDegree; mainBreakerAmp = r.mainBreakerAmp; structureOK = r.structureOK
        isDraft = r.isDraft ?? false
        utility = r.utility ?? ""; caNumber = r.caNumber ?? ""; meterSize = r.meterSize ?? ""
        tariff = r.tariff ?? ""; grounding = r.grounding ?? ""; monthlyKWh = r.monthlyKWh ?? 0
        latitude = r.latitude; longitude = r.longitude
        if job !== owner { job = owner }
        return true
    }

    static func make(_ r: Record, jobs: [String: Job]) -> SurveyForm? {
        guard parent(r.jobID, in: jobs) != nil else { return nil }
        let form = SurveyForm(surveyor: r.surveyor, roofType: r.roofType, roofAreaSqm: r.roofAreaSqm,
                              orientation: r.orientation, tiltDegree: r.tiltDegree, shading: r.shading,
                              structureOK: r.structureOK, meterPhase: r.meterPhase, mainBreakerAmp: r.mainBreakerAmp,
                              monthlyBill: r.monthlyBill, recommendedKW: r.recommendedKW, notes: r.notes)
        return form
    }
}

// MARK: - Devices

extension ScannedDevice: CloudSynced {
    struct Record: Codable {
        var kind, serial, scannedBy: String
        var scannedAt: Int64
        var jobID: String?
    }

    static let collection = "devices"

    var record: Record {
        Record(kind: kindRaw, serial: serial, scannedBy: scannedBy, scannedAt: scannedAt.millis, jobID: job?.syncID)
    }

    func apply(_ r: Record, jobs: [String: Job]) -> Bool {
        guard let owner = parent(r.jobID, in: jobs) else { return false }
        kindRaw = r.kind; serial = r.serial; scannedBy = r.scannedBy; scannedAt = Date(millis: r.scannedAt)
        if job !== owner { job = owner }
        return true
    }

    static func make(_ r: Record, jobs: [String: Job]) -> ScannedDevice? {
        guard parent(r.jobID, in: jobs) != nil else { return nil }
        let device = ScannedDevice(kind: DeviceKind(rawValue: r.kind) ?? .panel, serial: r.serial, scannedBy: r.scannedBy)
        return device
    }
}

// MARK: - Install log

extension InstallLog: CloudSynced {
    struct Record: Codable {
        var date, createdAt: Int64
        var recorder, details: String
        var jobID: String?
        // daily report R2; optional so documents from older app versions still decode
        var report: String?
        var engineerSignedAt, inspectorAckAt: Int64?
    }

    static let collection = "installLogs"

    var record: Record {
        Record(date: date.millis, createdAt: createdAt.millis, recorder: recorder, details: details, jobID: job?.syncID,
               report: reportJSON, engineerSignedAt: engineerSignedAt?.millis, inspectorAckAt: inspectorAckAt?.millis)
    }

    func apply(_ r: Record, jobs: [String: Job]) -> Bool {
        guard let owner = parent(r.jobID, in: jobs) else { return false }
        date = Date(millis: r.date); createdAt = Date(millis: r.createdAt); recorder = r.recorder; details = r.details
        // a record written by an app version without daily reports keeps this device's report
        if let v = r.report {
            reportJSON = v
            engineerSignedAt = r.engineerSignedAt.map(Date.init(millis:)); inspectorAckAt = r.inspectorAckAt.map(Date.init(millis:))
        }
        if job !== owner { job = owner }
        return true
    }

    static func make(_ r: Record, jobs: [String: Job]) -> InstallLog? {
        guard parent(r.jobID, in: jobs) != nil else { return nil }
        let log = InstallLog(date: Date(millis: r.date), recorder: r.recorder, details: r.details)
        return log
    }
}

// MARK: - Inspection

extension Inspection: CloudSynced {
    struct Record: Codable {
        var createdAt, updatedAt: Int64
        var submittedAt: Int64?
        var inspector, customerName: String
        var currentStep: Int
        var results: [InspectionResult]
        var driveFileID, jobID: String?
    }

    static let collection = "inspections"

    var record: Record {
        Record(createdAt: createdAt.millis, updatedAt: updatedAt.millis, submittedAt: submittedAt?.millis,
               inspector: inspector, customerName: customerName, currentStep: currentStep, results: results,
               driveFileID: driveFileID, jobID: job?.syncID)
    }

    func apply(_ r: Record, jobs: [String: Job]) -> Bool {
        guard let owner = parent(r.jobID, in: jobs) else { return false }
        createdAt = Date(millis: r.createdAt); updatedAt = Date(millis: r.updatedAt)
        submittedAt = r.submittedAt.map(Date.init(millis:))
        inspector = r.inspector; customerName = r.customerName; currentStep = r.currentStep
        results = r.results; driveFileID = r.driveFileID
        if job !== owner { job = owner }
        return true
    }

    static func make(_ r: Record, jobs: [String: Job]) -> Inspection? {
        guard parent(r.jobID, in: jobs) != nil else { return nil }
        let inspection = Inspection(inspector: r.inspector, customerName: r.customerName)
        return inspection
    }
}
