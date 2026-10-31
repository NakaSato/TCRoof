import Foundation
import SwiftData
import TCRoofCore

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
    @Transient let jsonCache = ModelJSONCache()

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

    /// The day's photos, oldest first; the signatures, stored beside them, are not among them.
    var sortedPhotos: [PhotoAsset] { photos.filter { !Self.isSignature($0.tag) }.sorted { $0.createdAt < $1.createdAt } }

    // The daily report's drawn signatures (page 3 of the DAILY REPORT form): kept as photos of the log, so `PhotoSync`
    // carries them to the other devices through Drive like the day's photos.
    static let engineerSignatureTag = "signature.engineer", inspectorSignatureTag = "signature.inspector"
    static func isSignature(_ tag: String) -> Bool { tag.hasPrefix("signature.") }

    func signature(_ tag: String) -> PhotoAsset? { photos.first { $0.tag == tag } }

    /// Replaces the signature under `tag` with `png`, or removes it when nil.
    func setSignature(_ png: Data?, tag: String, context: ModelContext) {
        for old in photos where old.tag == tag { context.delete(old) }
        guard let png, !png.isEmpty else { return }
        let asset = PhotoAsset(data: png, tag: tag)
        context.insert(asset)
        asset.log = self
    }

    /// The structured daily report; setting it also rewrites `details` as its readable summary.
    var report: RoutineReport.Daily? {
        get { jsonCache.decode(RoutineReport.Daily.self, for: "report", raw: reportJSON) }
        set {
            let encoded = newValue.flatMap { ModelJSONCache.encode($0) }
            reportJSON = encoded
            jsonCache.set(for: "report", raw: encoded, value: newValue)
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
    /// The site ICL sheet of a photo (`SiteICL`), tagged `sheet#item`.
    var iclSheet: ICLSheet?
    /// The job of an IEC 62446 test photo, or of the station's uploaded key plan (tag `Job.keyPlanTag`).
    var iecJob: Job?
    /// Google Drive file id once uploaded (daily-report photos, docs/specs/routine-reports-swift.md §4.6).
    var driveFileID: String?
    /// Firestore document id once synced (`photos`, `CloudRecords`): a photo on Drive reaches every device that way.
    var syncID: String?
    /// Received from another device and not downloaded from Drive yet; `data` is empty until `PhotoSync` brings it.
    var needsDownload = false

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

extension Sequence where Element == Job {
    /// The stations of the PWA module: the jobs set to งาน PWA.
    var pwaStations: [Job] { filter { $0.kind == .pwa } }
}

extension Array where Element == Job {
    /// `งานของฉัน`: the sync ids of the jobs that name the signed-in member (`Permissions.isNamed`); nil before sign-in.
    func mine(_ permissions: Permissions) -> Set<String>? {
        guard !permissions.email.isEmpty else { return nil }
        return Set(filter { permissions.isNamed($0.access) }.compactMap(\.syncID))
    }
}
