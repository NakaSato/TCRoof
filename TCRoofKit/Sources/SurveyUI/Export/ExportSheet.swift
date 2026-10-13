#if canImport(UIKit)
import SwiftUI
import TCRoofCore
import DriveSync
import TCRoofUI

/// One place to export a survey: readiness check, pick the files, then share them or save them to Google Drive.
struct ExportSheet: View {
    let jobID: UUID
    /// Closes the sheet and opens the editor page that still has gaps.
    let goTo: (MissingGroup.Target) -> Void

    enum Format: String, CaseIterable, Identifiable {
        case report, summary, excel, data, photos
        var id: String { rawValue }
        var title: String { ["report": "รายงาน PDF", "summary": "PDF สรุป 1 หน้า", "excel": "Excel", "data": "ข้อมูลงาน (.json)", "photos": "รูปภาพ"][rawValue]! }
        var detail: String {
            ["report": "รายงานฉบับเต็มแบบ NO.215 พร้อมรูปภาพ",
             "summary": "ภาพรวมโครงการในหน้าเดียว",
             "excel": "กรอกลงแบบฟอร์ม NO.224 ครบทุกแผ่น พร้อมรูป",
             "data": "สำหรับเปิดต่อบน iPad เครื่องอื่น",
             "photos": "แยกโฟลเดอร์ตามหัวข้อใน Drive · ส่งเฉพาะรูปใหม่"][rawValue]!
        }
        var symbol: String { ["report": "doc.richtext", "summary": "doc.text.magnifyingglass", "excel": "tablecells", "data": "curlybraces", "photos": "photo.on.rectangle.angled"][rawValue]! }
        var tint: Color { ["report": Theme.danger, "summary": Theme.warning, "excel": Paper.tick, "data": Theme.primary, "photos": Theme.teal][rawValue]! }
        var isPDF: Bool { self == .report || self == .summary }
        /// Drive keeps the full report, the workbook and the job data; the one-page summary is share-only.
        var driveKind: DriveSync.Kind? { ["report": .pdf, "excel": .xlsx, "data": .json][rawValue] }
        /// Photos go to Drive only — dozens of pictures don't belong in a share sheet.
        var shareable: Bool { self != .photos }
    }

    struct Shared: Identifiable { let id = UUID(); let urls: [URL] }

    @Environment(SurveyModel.self) var model
    @Environment(\.dismiss) var dismiss
    /// Key bumped when photos became a default, so choices saved before that start from the new default.
    @AppStorage(Self.formatsKey) var stored = Self.defaultFormats
    static let formatsKey = "solarSurvey.exportFormats.v2", defaultFormats = "report,excel,photos"

    /// What the sheet was last set to save on Drive — "sync all" on the home screen saves the same.
    static var driveChoice: (kinds: [DriveSync.Kind], photos: Bool) {
        let set = Set((UserDefaults.standard.string(forKey: formatsKey) ?? defaultFormats).split(separator: ",").map(String.init))
        let f = Format.allCases.filter { set.contains($0.rawValue) }
        let kinds = f.compactMap(\.driveKind), photos = f.contains(.photos)
        // only the share-only summary chosen: still send the job data and photos so other iPads can open it
        return kinds.isEmpty && !photos ? ([.json], true) : (kinds, photos)
    }
    @State var busy: String?
    @State var log: [String] = []
    @State var error: String?
    @State var shared: Shared?
    @State var preview: PDFPreviewItem?
    /// GoogleAuth reads the keychain and isn't observable — mirror its state here.
    @State var signedIn = false
    /// Export held back until the user confirms it may go out without the photos this device lacks.
    @State var pendingGo: PendingGo?
    struct PendingGo: Identifiable { let id = UUID(); let gap: PhotoGap; let go: () -> Void }
    /// PDF export held back while the report still lacks a signature.
    @State var pendingUnsigned: PendingUnsigned?
    struct PendingUnsigned: Identifiable { let id = UUID(); let names: [String]; let go: () -> Void }

    var selected: [Format] {
        let set = Set(stored.split(separator: ",").map(String.init))
        return Format.allCases.filter { set.contains($0.rawValue) }
    }
    func toggle(_ f: Format) {
        var s = Set(selected)
        if s.contains(f) { s.remove(f) } else { s.insert(f) }
        stored = Format.allCases.filter { s.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
    var driveKinds: [DriveSync.Kind] { selected.compactMap(\.driveKind) }
    var canShare: Bool { selected.contains(where: \.shareable) }
    var canDrive: Bool { !driveKinds.isEmpty || selected.contains(.photos) }
    var pdfSelected: Bool { selected.contains(where: \.isPDF) }

    var body: some View {
        NavigationStack {
            PadForm(maxWidth: 720) {
                if let job = model.job(jobID) {
                    statusSection(job)
                    let gap = PhotoGap(model: model, job: job)
                    if gap.missing > 0 || model.photoFetch[jobID]?.running == true { photoSection(gap) }
                    let unsigned = job.missingSignatures
                    if pdfSelected && !unsigned.isEmpty { signatureSection(unsigned) }
                    let groups = job.missingGroups
                    if !groups.isEmpty { missingSection(groups) }
                }
                formatsSection
                if let job = model.job(jobID) { driveSection(job) }
                if !log.isEmpty {
                    PadSection("ความคืบหน้า") { ForEach(Array(log.enumerated()), id: \.offset) { Text($0.element).font(.sarabun(16, relativeTo: .callout)) } }
                }
                if let error { PadSection { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.dangerText) } }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle("ส่งออกงาน").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() }.disabled(busy != nil) } }
            .interactiveDismissDisabled(busy != nil)
        }
        .onAppear { signedIn = model.google.isSignedIn }
        .alert("รูปยังไม่ครบในเครื่องนี้", isPresented: Binding(get: { pendingGo != nil }, set: { if !$0 { pendingGo = nil } }), presenting: pendingGo) { p in
            if p.gap.onDrive > 0 { Button("ดาวน์โหลดรูปก่อน") { pendingGo = nil; fetchPhotos() } }
            Button("ส่งออกต่อ") { let go = p.go; pendingGo = nil; go() }
            Button("ยกเลิก", role: .cancel) { pendingGo = nil }
        } message: { p in Text(p.gap.message) }
        .alert("รายงานยังไม่มีลายเซ็น", isPresented: Binding(get: { pendingUnsigned != nil }, set: { if !$0 { pendingUnsigned = nil } }), presenting: pendingUnsigned) { p in
            Button("ไปลงนาม") { pendingUnsigned = nil; dismiss(); goTo(.final) }
            Button("ส่งออกเป็นฉบับร่าง") { let go = p.go; pendingUnsigned = nil; go() }
            Button("ยกเลิก", role: .cancel) { pendingUnsigned = nil }
        } message: { p in Text("ยังขาด" + p.names.joined(separator: " และ") + "\nPDF ที่ส่ง กปภ. ต้องมีลายเซ็นทั้งสองฝ่าย") }
        .sheet(item: $shared) { s in ShareSheet(items: s.urls).presentationDetents([.medium, .large]) }
        .sheet(item: $preview) { p in PDFPreview(item: p) }
    }
}
#endif
