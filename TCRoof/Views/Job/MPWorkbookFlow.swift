import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import TCRoofUI
import TCRoofCore
import ExcelExport

/// Import and export of a station's own plan workbook (`MPWorkbook`): the file's dates, weights and actual points become
/// the job's MP plan, the file itself is kept on the job, and export writes the app's plan and progress back into that
/// same file, leaving everything else in it as it came. A screen holds one as `@State`, applies `.mpWorkbook(_:job:)`
/// and calls `startImport()` / `export(_:)` from its buttons.
@MainActor @Observable
final class MPWorkbookFlow {
    struct Pending: Identifiable {
        let id = UUID()
        let data: Data
        let name: String
        let imported: MPWorkbook.Imported
    }
    struct Message: Identifiable {
        let id = UUID()
        let title: String
        let text: String
        /// Shared once the message is closed.
        var then: URL?
    }
    struct SharedFile: Identifiable { let id = UUID(); let url: URL }

    var importing = false
    var pending: Pending?
    var message: Message?
    var shared: SharedFile?

    static let types: [UTType] = [UTType(filenameExtension: "xlsx"), .spreadsheet].compactMap { $0 }

    func startImport() {
        #if DEBUG
        // `-mpImportFile <path>` reads that file instead of opening the picker, for UI tests
        if let path = UserDefaults.standard.string(forKey: "mpImportFile") { read(.success(URL(fileURLWithPath: path))); return }
        #endif
        importing = true
    }

    func read(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pending = Pending(data: data, name: url.lastPathComponent, imported: try MPWorkbook.read(data))
        } catch {
            message = Message(title: "นำเข้าไม่ได้", text: (error as? MPWorkbook.Failure)?.message ?? error.localizedDescription)
        }
    }

    func apply(_ p: Pending, to job: Job, context: ModelContext) {
        Self.install(p.imported, data: p.data, name: p.name, on: job)
        try? context.save()
    }

    /// The plan from the file replaces the job's; the file's actual replaces the job's when it has any points, else the
    /// job keeps what it has booked, each task keeping its % done under the file's weight. The file is kept on the job
    /// and goes up to Drive on the next save (`PhotoSync`).
    static func install(_ imported: MPWorkbook.Imported, data: Data, name: String, on job: Job) {
        let old = job.scheduleInput, new = imported.input
        job.scheduleInput = new
        let fileActual = imported.actual
        if !fileActual.points.isEmpty || !fileActual.started.isEmpty || !fileActual.finished.isEmpty {
            var a = fileActual
            a.lateCauses = job.scheduleActual.lateCauses
            job.scheduleActual = a
        } else if let old, !job.scheduleActual.points.isEmpty {
            var a = job.scheduleActual
            for task in MasterSchedule.Task.allCases {
                guard let byWeek = a.points[task.rawValue] else { continue }
                let from = old.weight(task), to = new.weight(task)
                let k = from > 0 ? to / from : 0
                let scaled = byWeek.mapValues { $0 * k }.filter { $0.value > 0 }
                a.points[task.rawValue] = scaled.isEmpty ? nil : scaled
            }
            job.scheduleActual = a
        }
        job.scheduleWorkbook = data
        job.scheduleWorkbookName = name
        job.scheduleWorkbookDriveID = nil
    }

    /// What the import will do, for its confirmation.
    func summary(_ p: Pending, job: Job) -> String {
        let r = p.imported
        var lines: [String] = []
        if let project = r.project { lines.append(project) }
        lines.append("\(r.tasks.count) งาน · ติดตั้ง \(r.input.installStart.thaiShort) – \(r.input.installEnd.thaiShort)")
        let weeks = Set(r.actual.points.values.flatMap(\.keys)).count
        if weeks > 0 {
            lines.append("ความก้าวหน้าตามไฟล์ \(weeks) สัปดาห์" + (job.scheduleActual.points.isEmpty ? "" : " แทนที่บันทึกไว้"))
        } else if !job.scheduleActual.points.isEmpty {
            lines.append("เก็บความก้าวหน้าที่บันทึกไว้")
        }
        if job.scheduleInput != nil { lines.append("แทนแผน MP เดิมของสถานีนี้") }
        return lines.joined(separator: "\n")
    }

    /// The kept file with the job's plan and progress written in, under its own name.
    func export(_ job: Job) {
        guard let original = job.scheduleWorkbook, let input = job.scheduleInput else { return }
        do {
            let out = try MPWorkbook.export(original, input: input, actual: job.scheduleActual)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MP-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(MPWorkbook.fileName(original: job.scheduleWorkbookName, fallback: "แผนงาน MP " + job.stationName))
            try out.data.write(to: url, options: .atomic)
            #if DEBUG
            // `-mpExportFile <path>` also writes the export there, for UI tests to read
            if let path = UserDefaults.standard.string(forKey: "mpExportFile") { try? out.data.write(to: URL(fileURLWithPath: path)) }
            #endif
            if out.weeksOutside.isEmpty {
                shared = SharedFile(url: url)
            } else {
                let weeks = out.weeksOutside.compactMap(ISODate.date).map(\.thaiShort).joined(separator: ", ")
                message = Message(title: "บางสัปดาห์อยู่นอกตารางของไฟล์",
                                  text: "ความก้าวหน้าสัปดาห์ \(weeks) ไม่มีคอลัมน์ในไฟล์ จึงไม่ได้ลง ส่วนอื่นลงครบ", then: url)
            }
        } catch {
            message = Message(title: "ส่งออกไม่สำเร็จ", text: (error as? MPWorkbook.Failure)?.message ?? error.localizedDescription)
        }
    }
}

extension View {
    /// The file picker, the confirmation, the messages and the share sheet of an `MPWorkbookFlow`.
    func mpWorkbook(_ flow: MPWorkbookFlow, job: Job) -> some View {
        modifier(MPWorkbookModifier(flow: flow, job: job))
    }
}

private struct MPWorkbookModifier: ViewModifier {
    @Bindable var flow: MPWorkbookFlow
    @Bindable var job: Job
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $flow.importing, allowedContentTypes: MPWorkbookFlow.types) { flow.read($0) }
            .alert("นำเข้าแผนจากไฟล์ Excel", isPresented: Binding(get: { flow.pending != nil }, set: { if !$0 { flow.pending = nil } }),
                   presenting: flow.pending) { p in
                Button("นำเข้า") {
                    flow.apply(p, to: job, context: context)
                    flow.pending = nil
                }
                Button("ยกเลิก", role: .cancel) { flow.pending = nil }
            } message: { p in Text(flow.summary(p, job: job)) }
            .alert(flow.message?.title ?? "", isPresented: Binding(get: { flow.message != nil }, set: { if !$0 { flow.message = nil } }),
                   presenting: flow.message) { m in
                Button("ตกลง", role: .cancel) {
                    flow.message = nil
                    if let url = m.then { flow.shared = .init(url: url) }
                }
            } message: { m in Text(m.text) }
            .sheet(item: $flow.shared) { f in ActivitySheet(items: [f.url]).presentationDetents([.medium, .large]) }
    }
}

/// `นำเข้าไฟล์แผน…` and `ส่งออกไฟล์แผน (Excel)` as one menu's items.
struct MPWorkbookMenuItems: View {
    let flow: MPWorkbookFlow
    let job: Job
    let canImport: Bool

    var body: some View {
        if canImport {
            Button { flow.startImport() } label: { Label("นำเข้าไฟล์แผน (Excel)…", systemImage: "square.and.arrow.down") }
        }
        Button { flow.export(job) } label: {
            Label(job.scheduleWorkbookDownloading ? "ส่งออกไฟล์แผน (กำลังดาวน์โหลดจาก Drive…)"
                  : job.scheduleWorkbook == nil ? "ส่งออกไฟล์แผน (นำเข้าไฟล์ก่อน)" : "ส่งออกไฟล์แผน (Excel)", systemImage: "square.and.arrow.up")
        }
        .disabled(job.scheduleWorkbook == nil || job.scheduleInput == nil)
    }
}
