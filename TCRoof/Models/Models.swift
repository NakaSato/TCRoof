import Foundation
import SwiftData
import SwiftUI
import TCRoofUI
import TCRoofCore

// MARK: - Enums

enum Team: String, CaseIterable, Identifiable, Codable {
    case t1 = "TCR01", t2 = "TCR02", t3 = "TCR03", t4 = "TCR04"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .t1: Color(hex: 0x2E9E5B)
        case .t2: Color(hex: 0x8B3FD9)
        case .t3: Color(hex: 0x2F6FDB)
        case .t4: Color(hex: 0xF08A24)
        }
    }
}

enum JobStatus: String, CaseIterable, Identifiable, Codable {
    case interested, confirmed, installing, completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interested: "ลูกค้าสนใจติดตั้ง"
        case .confirmed: "ลูกค้ายืนยันติดตั้ง"
        case .installing: "กำลังติดตั้ง"
        case .completed: "ติดตั้งเสร็จสิ้น"
        }
    }

    var color: Color {
        switch self {
        case .interested: Color(hex: 0x4DA3E0)
        case .confirmed: Theme.teal
        case .installing: Color(hex: 0xF08A24)
        case .completed: Color(hex: 0x2E9E5B)
        }
    }
}

enum DeviceKind: String, CaseIterable, Identifiable, Codable {
    case panel, inverter, optimizer, battery, meter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .panel: "แผงโซลาร์เซลล์"
        case .inverter: "อินเวอร์เตอร์"
        case .optimizer: "ออปติไมเซอร์"
        case .battery: "แบตเตอรี่"
        case .meter: "สมาร์ทมิเตอร์"
        }
    }

    var symbol: String {
        switch self {
        case .panel: "square.grid.3x3.fill"
        case .inverter: "bolt.horizontal.fill"
        case .optimizer: "cpu"
        case .battery: "battery.100.bolt"
        case .meter: "gauge.with.dots.needle.33percent"
        }
    }
}

// MARK: - Job

@Model
final class Job {
    var code: String
    var projectName: String
    var customerName: String
    var phone: String
    var address: String
    var province: String
    var capacityKW: Double
    var teamRaw: String
    var statusRaw: String
    var surveyDate: Date
    var installStart: Date
    var installDays: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SurveyForm.job) var surveys: [SurveyForm] = []
    @Relationship(deleteRule: .cascade, inverse: \ScannedDevice.job) var devices: [ScannedDevice] = []
    @Relationship(deleteRule: .cascade, inverse: \InstallLog.job) var logs: [InstallLog] = []
    @Relationship(deleteRule: .cascade, inverse: \Inspection.job) var inspections: [Inspection] = []
    @Relationship(deleteRule: .cascade, inverse: \DocumentAsset.job) var documents: [DocumentAsset] = []
    /// Project folder on Google Drive, set after the first upload.
    var driveFolderURL: String?
    /// Firestore document id shared by every device; nil only on records made before cloud sync.
    var syncID: String?
    // MP schedule (docs/specs/master-schedule-swift.md §2); optional so older stores open without a migration.
    /// MP number in the PWA project list (e.g. 189).
    var mpNumber: Int?
    /// Inverter total in kW; sets the default of the MP plan's "เกิน 200 kVA".
    var inverterKW: Double?
    /// Encoded `MasterSchedule.Input` and `MasterSchedule.Actual`.
    var scheduleInputJSON: String?
    var scheduleActualJSON: String?
    // Routine reports (docs/specs/routine-reports-swift.md §2.2–2.3); optional for the same reason.
    /// Encoded `RoutineReport.Settings`.
    var routineSettingsJSON: String?
    /// Encoded `[RoutineReport.WeeklyRequest]`, one per week.
    var weeklyRequestsJSON: String?
    /// Encoded `StationDocs.Station`: the station's papers for a PWA job (เอกสารสถานี กปภ.); optional for the same reason.
    var stationDocsJSON: String?

    init(code: String, projectName: String, customerName: String, phone: String = "", address: String = "",
         province: String, capacityKW: Double, team: Team, status: JobStatus,
         surveyDate: Date, installStart: Date, installDays: Int) {
        self.code = code
        self.projectName = projectName
        self.customerName = customerName
        self.phone = phone
        self.address = address
        self.province = province
        self.capacityKW = capacityKW
        self.teamRaw = team.rawValue
        self.statusRaw = status.rawValue
        self.surveyDate = surveyDate
        self.installStart = installStart
        self.installDays = installDays
        self.createdAt = .now
        self.syncID = UUID().uuidString
    }

    var team: Team {
        get { Team(rawValue: teamRaw) ?? .t1 }
        set { teamRaw = newValue.rawValue }
    }

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .interested }
        set { statusRaw = newValue.rawValue }
    }

    var installEnd: Date { installStart.startOfDay.adding(days: max(installDays, 1) - 1) }
    var installInterval: ClosedRange<Date> { installStart.startOfDay...installEnd.endOfDay }
    var surveyInterval: ClosedRange<Date> { surveyDate.startOfDay...surveyDate.endOfDay }

    /// 1-based day number of the installation on `date`, or nil when not scheduled that day.
    func installDay(on date: Date) -> Int? {
        let diff = Calendar.current.dateComponents([.day], from: installStart.startOfDay, to: date.startOfDay).day ?? -1
        return (0..<max(installDays, 1)).contains(diff) ? diff + 1 : nil
    }

    /// The MP plan's dates and flag; setting it also moves the install window so the Plan calendar agrees.
    var scheduleInput: MasterSchedule.Input? {
        get { scheduleInputJSON.flatMap { try? JSONDecoder().decode(MasterSchedule.Input.self, from: Data($0.utf8)) } }
        set {
            scheduleInputJSON = newValue.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            if let i = newValue {
                let cal = MasterSchedule.calendar
                installStart = cal.startOfDay(for: i.installStart)
                installDays = max(1, (cal.dateComponents([.day], from: installStart, to: cal.startOfDay(for: i.installEnd)).day ?? 0) + 1)
            }
        }
    }
    var scheduleActual: MasterSchedule.Actual {
        get { scheduleActualJSON.flatMap { try? JSONDecoder().decode(MasterSchedule.Actual.self, from: Data($0.utf8)) } ?? .init() }
        set { scheduleActualJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } }
    }

    var routineSettings: RoutineReport.Settings {
        get { routineSettingsJSON.flatMap { try? JSONDecoder().decode(RoutineReport.Settings.self, from: Data($0.utf8)) } ?? .init() }
        set { routineSettingsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } }
    }
    var stationDocs: StationDocs.Station {
        get { StationDocs.Station.decode(stationDocsJSON) }
        set { stationDocsJSON = newValue.json }
    }
    var stationContext: StationDocs.Context {
        StationDocs.Context(stationDocs, inverterKW: inverterKW ?? (scheduleInput?.over200kVA == true ? 200 : nil))
    }
    var weeklyRequests: [RoutineReport.WeeklyRequest] {
        get { weeklyRequestsJSON.flatMap { try? JSONDecoder().decode([RoutineReport.WeeklyRequest].self, from: Data($0.utf8)) } ?? [] }
        set {
            let sorted = newValue.sorted { $0.weekStart < $1.weekStart }
            weeklyRequestsJSON = sorted.isEmpty ? nil : (try? JSONEncoder().encode(sorted)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    var estimatedPanels: Int { Int((capacityKW * 1000 / 550).rounded(.up)) }
    var inspection: Inspection? { inspections.first }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [code, projectName, customerName, province].contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

// MARK: - Survey

@Model
final class SurveyForm {
    var createdAt: Date
    var surveyor: String
    var roofType: String
    var roofAreaSqm: Double
    var orientation: String
    var tiltDegree: Int
    var shading: String
    var structureOK: Bool
    var meterPhase: String
    var mainBreakerAmp: Int
    var monthlyBill: Double
    var recommendedKW: Double
    var notes: String
    var job: Job?
    var syncID: String?

    // Added 2026-09: defaults let older records open without a migration step.
    /// A form still being filled in; hidden from lists until it is saved.
    var isDraft: Bool = false
    var utility: String = ""        // กฟภ. / กฟน.
    var caNumber: String = ""       // เลขผู้ใช้ไฟฟ้า (CA)
    var meterSize: String = ""      // e.g. 15(45) A
    var tariff: String = ""         // อัตราปกติ / TOU
    var monthlyKWh: Double = 0      // หน่วยต่อเดือนจากบิล, 0 = ไม่ได้กรอก
    var grounding: String = ""      // มี / ไม่มี / ไม่แน่ใจ
    var latitude: Double? = nil
    var longitude: Double? = nil

    @Relationship(deleteRule: .cascade, inverse: \PhotoAsset.survey) var photos: [PhotoAsset] = []

    init(surveyor: String, roofType: String, roofAreaSqm: Double, orientation: String, tiltDegree: Int,
         shading: String, structureOK: Bool, meterPhase: String, mainBreakerAmp: Int,
         monthlyBill: Double, recommendedKW: Double, notes: String) {
        self.createdAt = .now
        self.surveyor = surveyor
        self.roofType = roofType
        self.roofAreaSqm = roofAreaSqm
        self.orientation = orientation
        self.tiltDegree = tiltDegree
        self.shading = shading
        self.structureOK = structureOK
        self.meterPhase = meterPhase
        self.mainBreakerAmp = mainBreakerAmp
        self.monthlyBill = monthlyBill
        self.recommendedKW = recommendedKW
        self.notes = notes
        self.syncID = UUID().uuidString
    }

    /// An empty draft: nothing pre-filled, so a skipped field can't pass for a measured one.
    static func blankDraft(surveyor: String) -> SurveyForm {
        let form = SurveyForm(surveyor: surveyor, roofType: "", roofAreaSqm: 0, orientation: "", tiltDegree: 0,
                              shading: "", structureOK: true, meterPhase: "", mainBreakerAmp: 0,
                              monthlyBill: 0, recommendedKW: 0, notes: "")
        form.isDraft = true
        return form
    }
}

extension Job {
    /// Saved survey forms, newest first (drafts left out).
    var savedSurveys: [SurveyForm] { surveys.filter { !$0.isDraft }.sorted { $0.createdAt > $1.createdAt } }
    var surveyDraft: SurveyForm? { surveys.first { $0.isDraft } }
}

// MARK: - Devices

@Model
final class ScannedDevice {
    var kindRaw: String
    var serial: String
    var scannedAt: Date
    var scannedBy: String
    var job: Job?
    var syncID: String?

    init(kind: DeviceKind, serial: String, scannedBy: String) {
        self.kindRaw = kind.rawValue
        self.serial = serial
        self.scannedAt = .now
        self.scannedBy = scannedBy
        self.syncID = UUID().uuidString
    }

    var kind: DeviceKind { DeviceKind(rawValue: kindRaw) ?? .panel }
}

// MARK: - Install log

@Model
final class InstallLog {
    var date: Date
    var recorder: String
    var details: String
    var createdAt: Date
    var job: Job?
    var syncID: String?
    // Daily report R2 (docs/specs/routine-reports-swift.md §2.1); nil on free-text logs.
    /// Encoded `RoutineReport.Daily`.
    var reportJSON: String?
    var engineerSignedAt: Date?
    /// When the Inspector acknowledged it (typed in after the paper or LINE reply).
    var inspectorAckAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \PhotoAsset.log) var photos: [PhotoAsset] = []

    init(date: Date, recorder: String, details: String) {
        self.date = date
        self.recorder = recorder
        self.details = details
        self.createdAt = .now
        self.syncID = UUID().uuidString
    }

    var detailLines: [String] {
        details.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var sortedPhotos: [PhotoAsset] { photos.sorted { $0.createdAt < $1.createdAt } }

    /// The structured daily report; setting it also rewrites `details` as its readable summary.
    var report: RoutineReport.Daily? {
        get { reportJSON.flatMap { try? JSONDecoder().decode(RoutineReport.Daily.self, from: Data($0.utf8)) } }
        set {
            reportJSON = newValue.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            if let r = newValue { details = r.summary }
        }
    }
}

// MARK: - Inspection checklist (ICL)

struct InspectionStep: Identifiable {
    let id: String
    let title: String
    let short: String
    var unit: String? = nil
    var needsInstrument = false
    var hint: String

    var needsValue: Bool { unit != nil }

    static let all: [InspectionStep] = [
        .init(id: "structure", title: "ตรวจสอบโครงสร้างและการยึดราง", short: "โครงสร้าง",
              hint: "ตรวจการยึดขาจับ ราง และน็อตทุกจุด ไม่มีรอยรั่วซึมบนหลังคา"),
        .init(id: "panels", title: "ตรวจสอบการติดตั้งแผงโซลาร์เซลล์", short: "แผงโซลาร์",
              hint: "แผงไม่แตกร้าว ติดตั้งตรงแนว แคลมป์ยึดแน่น"),
        .init(id: "dc", title: "ตรวจสอบสาย DC และคอนเนคเตอร์ MC4", short: "สาย DC",
              hint: "สายเดินในท่อ/รางเรียบร้อย คอนเนคเตอร์เข้าล็อกสนิท ติดป้ายสตริง"),
        .init(id: "voc", title: "วัดแรงดันวงจรเปิด (Voc) ของสตริง", short: "แรงดัน Voc", unit: "V",
              needsInstrument: true, hint: "วัดค่า Voc ทุกสตริงก่อนเชื่อมต่ออินเวอร์เตอร์"),
        .init(id: "inverter", title: "ตรวจสอบการติดตั้งอินเวอร์เตอร์", short: "อินเวอร์เตอร์",
              hint: "ติดตั้งในที่อากาศถ่ายเท ระยะห่างตามคู่มือ ตั้งค่าและเชื่อมต่อระบบมอนิเตอร์แล้ว"),
        .init(id: "acdb", title: "ตรวจสอบตู้ AC/DC และอุปกรณ์ป้องกัน", short: "ตู้ควบคุม",
              hint: "เบรกเกอร์ ฟิวส์ และ Surge Protection ถูกขนาด ติดป้ายเตือนครบถ้วน"),
        .init(id: "ground", title: "วัดค่าความต้านทานระหว่างหลักดินกับดิน", short: "ค่าความต้านทาน", unit: "Ω",
              needsInstrument: true, hint: "ค่าความต้านทานดินต้องไม่เกิน 5 Ω"),
    ]
}

struct InspectionResult: Codable, Hashable {
    var stepID: String
    var instrumentSerial: String = ""
    var value: String = ""
    var passed: Bool? = nil
    var note: String = ""
}

@Model
final class Inspection {
    var createdAt: Date
    var updatedAt: Date
    var inspector: String
    var currentStep: Int
    var results: [InspectionResult]
    var customerName: String
    var submittedAt: Date?
    /// Google Drive file of the signed report PDF, once uploaded.
    var driveFileID: String?
    @Attribute(.externalStorage) var signature: Data?
    var job: Job?
    var syncID: String?

    @Relationship(deleteRule: .cascade, inverse: \PhotoAsset.inspection) var photos: [PhotoAsset] = []

    init(inspector: String, customerName: String) {
        self.createdAt = .now
        self.updatedAt = .now
        self.inspector = inspector
        self.currentStep = 0
        self.results = InspectionStep.all.map { InspectionResult(stepID: $0.id) }
        self.customerName = customerName
        self.syncID = UUID().uuidString
    }

    func photos(for stepID: String) -> [PhotoAsset] {
        photos.filter { $0.tag == stepID }.sorted { $0.createdAt < $1.createdAt }
    }

    func isComplete(_ index: Int) -> Bool {
        let step = InspectionStep.all[index]
        let r = results[index]
        return r.passed != nil
            && (!step.needsValue || !r.value.trimmingCharacters(in: .whitespaces).isEmpty)
            && (!step.needsInstrument || !r.instrumentSerial.trimmingCharacters(in: .whitespaces).isEmpty)
            && !photos(for: step.id).isEmpty
    }

    var completedCount: Int { InspectionStep.all.indices.filter(isComplete).count }
    var allComplete: Bool { completedCount == InspectionStep.all.count }
    var allPassed: Bool { results.allSatisfy { $0.passed == true } }
}

// MARK: - Assets

@Model
final class PhotoAsset {
    @Attribute(.externalStorage) var data: Data
    var tag: String
    var createdAt: Date
    var survey: SurveyForm?
    var log: InstallLog?
    var inspection: Inspection?
    /// Google Drive file id once uploaded (daily-report photos, docs/specs/routine-reports-swift.md §4.6).
    var driveFileID: String?

    init(data: Data, tag: String = "") {
        self.data = data
        self.tag = tag
        self.createdAt = .now
    }
}

@Model
final class DocumentAsset {
    var name: String
    @Attribute(.externalStorage) var data: Data
    var addedAt: Date
    /// Google Drive file id, once uploaded.
    var driveFileID: String?
    var job: Job?
    /// Subfolders under the job's Drive folder, "/"-separated (routine reports file by kind and month); nil = the job folder.
    var folderPath: String?

    init(name: String, data: Data) {
        self.name = name
        self.data = data
        self.addedAt = .now
    }
}
