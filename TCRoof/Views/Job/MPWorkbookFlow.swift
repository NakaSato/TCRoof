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
    /// The confirmation is the iPhone install page's sheet (`MPImportSheet`) rather than the alert. A file that names
    /// another station says so there, and its `เลือกสถานีอื่น…` hands over to the alert, which offers that station.
    var confirmsInSheet = false

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
    /// job keeps what it has booked (as the confirmation says), each task keeping its % done under the file's weight,
    /// and takes the file's actual start and finish dates where it has them. The file is kept on the job and goes up to
    /// Drive on the next save (`PhotoSync`).
    static func install(_ imported: MPWorkbook.Imported, data: Data, name: String, on job: Job) {
        let old = job.scheduleInput, new = imported.input
        job.scheduleInput = new
        let fileActual = imported.actual
        if !fileActual.points.isEmpty {
            var a = fileActual
            a.lateCauses = job.scheduleActual.lateCauses
            a.confirmations = job.scheduleActual.confirmations
            job.scheduleActual = a
        } else {
            var a = job.scheduleActual
            if let old {
                for task in MasterSchedule.Task.allCases {
                    guard let byWeek = a.points[task.rawValue] else { continue }
                    let from = old.weight(task), to = new.weight(task)
                    let k = from > 0 ? to / from : 0
                    let scaled = byWeek.mapValues { $0 * k }.filter { $0.value > 0 }
                    a.points[task.rawValue] = scaled.isEmpty ? nil : scaled
                }
            }
            // a file with dates and no points (actual starts typed, nothing booked yet) still gives its dates
            for (task, d) in fileActual.started { a.started[task] = d }
            for (task, d) in fileActual.finished { a.finished[task] = d }
            if a != job.scheduleActual { job.scheduleActual = a }
        }
        // the file's progress replaced the job's, `fromDocuments` with it: the papers book their permits again (only
        // where the file has them below 100 %), as they would for a plan made after the approval
        job.bookPermitsFromDocs()
        job.scheduleWorkbook = data
        job.scheduleWorkbookName = name
        job.scheduleWorkbookDriveID = nil
    }

    /// The job's progress with a file's taken in (`Actual.merging`): only what was changed in the file since the app
    /// exported it (the record the export keeps in the file), else since the app imported the file it keeps; a file with
    /// neither adds its bookings. No task ends above its weight in the job's plan.
    static func merged(_ imported: MPWorkbook.Imported, into job: Job) -> (actual: MasterSchedule.Actual, changed: Int) {
        let base = imported.base ?? job.scheduleWorkbook.flatMap { try? MPWorkbook.read($0).actual }
        var weights: [String: Double] = [:]
        if let input = job.scheduleInput {
            for task in MasterSchedule.Task.allCases { weights[task.rawValue] = input.weight(task) }
        }
        return job.scheduleActual.merging(imported.actual, base: base, covering: base == nil ? nil : imported.coverage,
                                          weights: weights)
    }

    /// รับเฉพาะความก้าวหน้า: a file updated in Excel gives only its progress (`merged`); the job keeps its plan, and the
    /// file becomes the kept original. Returns how many task-weeks and dates changed.
    @discardableResult
    static func takeProgress(_ imported: MPWorkbook.Imported, data: Data, name: String, on job: Job) -> Int {
        let (a, changed) = merged(imported, into: job)
        if a != job.scheduleActual { job.scheduleActual = a }
        job.scheduleWorkbook = data
        job.scheduleWorkbookName = name
        job.scheduleWorkbookDriveID = nil
        return changed
    }

    func takeProgress(_ p: Pending, on job: Job, context: ModelContext) {
        let n = Self.takeProgress(p.imported, data: p.data, name: p.name, on: job)
        try? context.save()
        message = Message(title: "รับความก้าวหน้าแล้ว",
                          text: n == 0 ? "ไม่มีช่องที่เปลี่ยนตามไฟล์ ความก้าวหน้าและแผนของสถานีคงเดิม"
                                       : "ใช้ตามไฟล์ \(n) ช่อง แผนของสถานีคงเดิม")
    }

    /// What a file's formula check means for its previews; nil when the app works out every formula as Excel did.
    static func formulaNote(_ c: MPWorkbook.FormulaCheck) -> String? {
        if !c.differs.isEmpty {
            return "สูตร \(c.differs.count) ช่องในไฟล์ แอปคำนวณได้ไม่ตรงกับ Excel ไฟล์ที่ส่งออกจะไม่ลงผลคำนวณจากแอป ตัวเลขจะอัปเดตเมื่อเปิดใน Excel"
        }
        if !c.unknown.isEmpty {
            return "สูตร \(c.unknown.count) ช่องในไฟล์ แอปคำนวณไม่ได้ ตัวเลขเหล่านั้นในตัวอย่างไฟล์จะอัปเดตเมื่อเปิดใน Excel"
        }
        return nil
    }

    /// What the import will do, for its confirmation.
    func summary(_ p: Pending, job: Job) -> String {
        let r = p.imported
        var lines: [String] = []
        if let project = r.project { lines.append(project) }
        lines.append("\(r.tasks.count) งาน | ติดตั้ง \(r.input.installStart.thaiShort) – \(r.input.installEnd.thaiShort)")
        let weeks = Set(r.actual.points.values.flatMap(\.keys)).count
        if weeks > 0 {
            lines.append("ความก้าวหน้าตามไฟล์ \(weeks) สัปดาห์" + (job.scheduleActual.points.isEmpty ? "" : " แทนที่บันทึกไว้"))
        } else if !job.scheduleActual.points.isEmpty {
            lines.append("เก็บความก้าวหน้าที่บันทึกไว้")
        }
        if job.scheduleInput != nil {
            lines.append("นำเข้า: แทนแผน MP เดิมของสถานีนี้")
            let n = Self.merged(r, into: job).changed
            // only cells changed in the file since the app wrote or took it in; bookings made in the app since stay
            lines.append("รับเฉพาะความก้าวหน้า: " + (n == 0 ? "ไม่มีช่องที่เปลี่ยนตามไฟล์" : "ใช้ตามไฟล์ \(n) ช่อง") + " แผนคงเดิม")
        }
        if let note = Self.formulaNote(r.formulas) { lines.append("⚠︎ " + note) }
        return lines.joined(separator: "\n")
    }

    /// The file names a station that isn't `job` (`MPWorkbook.match`): the file's station, and the PWA station it does
    /// fit when one does. Nil when it fits, or the file names no station to compare.
    func mismatch(_ p: Pending, job: Job, stations: [Job]) -> (file: String, fits: Job?)? {
        let f = MPWorkbook.station(project: p.imported.project, fileName: p.name)
        guard let name = f.name else { return nil }
        func candidates(_ jobs: [Job]) -> [MPWorkbook.Candidate] {
            jobs.enumerated().map { .init(id: String($0.offset), name: $0.element.stationName, mpNumber: $0.element.mpNumber, kWp: $0.element.capacityKW) }
        }
        guard MPWorkbook.match(f, among: candidates([job])).pick == nil else { return nil }
        let others = stations.filter { $0 !== job }
        let fits = MPWorkbook.match(f, among: candidates(others)).pick.flatMap(Int.init).map { others[$0] }
        return (name, fits)
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
    @Query private var jobs: [Job]
    /// The file goes to the station it fits, which has a plan already: asked again, with that station's summary.
    @State private var retarget: Retarget?

    struct Retarget: Identifiable {
        let id = UUID()
        let pending: MPWorkbookFlow.Pending
        let job: Job
    }

    private var mismatch: (file: String, fits: Job?)? {
        flow.pending.flatMap { flow.mismatch($0, job: job, stations: jobs.pwaStations) }
    }

    private var inSheet: Bool { flow.confirmsInSheet }

    private func label(_ j: Job) -> String { [j.mpNumber.map { "MP \($0)" }, j.stationName].compactMap { $0 }.joined(separator: " | ") }

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $flow.importing, allowedContentTypes: MPWorkbookFlow.types) { flow.read($0) }
            .sheet(item: Binding(get: { inSheet ? flow.pending : nil }, set: { if $0 == nil { flow.pending = nil } })) { p in
                MPImportSheet(flow: flow, pending: p, job: job, otherStation: mismatch.map { m in (m.file, m.fits.map(label)) })
            }
            .alert(mismatch == nil ? "นำเข้าแผนจากไฟล์ Excel" : "ไฟล์นี้อาจเป็นของสถานีอื่น",
                   isPresented: Binding(get: { flow.pending != nil && !inSheet }, set: { if !$0 { flow.pending = nil } }),
                   presenting: flow.pending) { p in
                let other = mismatch
                if let fits = other?.fits {
                    Button("นำเข้าที่ \(label(fits))") {
                        flow.pending = nil
                        // that station's own plan and progress would be replaced: ask again, about it
                        if fits.scheduleInput != nil { retarget = Retarget(pending: p, job: fits); return }
                        flow.apply(p, to: fits, context: context)
                        flow.message = .init(title: "นำเข้าแล้ว", text: "แผนจากไฟล์อยู่ที่ \(label(fits)) ไม่ใช่สถานีที่เปิดอยู่")
                    }
                }
                Button(other == nil ? "นำเข้า" : "นำเข้าที่สถานีนี้") {
                    flow.apply(p, to: job, context: context)
                    flow.pending = nil
                }
                if job.scheduleInput != nil {
                    Button("รับเฉพาะความก้าวหน้า") {
                        flow.pending = nil
                        flow.takeProgress(p, on: job, context: context)
                    }
                }
                Button("ยกเลิก", role: .cancel) { flow.pending = nil }
            } message: { p in
                if let other = mismatch {
                    Text("ไฟล์: \(other.file)\nสถานีนี้: \(label(job))"
                         + (other.fits.map { "\nไฟล์ตรงกับ \(label($0))" } ?? "") + "\n\n" + flow.summary(p, job: job))
                } else {
                    Text(flow.summary(p, job: job))
                }
            }
            .alert(retarget.map { "นำเข้าที่ \(label($0.job))" } ?? "", isPresented: Binding(get: { retarget != nil }, set: { if !$0 { retarget = nil } }),
                   presenting: retarget) { r in
                Button("นำเข้า") {
                    flow.apply(r.pending, to: r.job, context: context)
                    retarget = nil
                    flow.message = .init(title: "นำเข้าแล้ว", text: "แผนจากไฟล์อยู่ที่ \(label(r.job)) ไม่ใช่สถานีที่เปิดอยู่")
                }
                Button("รับเฉพาะความก้าวหน้า") {
                    retarget = nil
                    flow.takeProgress(r.pending, on: r.job, context: context)
                }
                Button("ยกเลิก", role: .cancel) { retarget = nil }
            } message: { r in
                Text("สถานีนี้มีแผน MP อยู่แล้ว\n\n" + flow.summary(r.pending, job: r.job))
            }
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
