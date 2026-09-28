#if canImport(UIKit)
import SwiftUI
import SurveyCore
import DriveSync

/// One place to export a survey: readiness check, pick the files, then share them or save them to Google Drive.
struct ExportSheet: View {
    let jobID: UUID
    /// Closes the sheet and jumps to the section with the missing transformer photos.
    let fixGaps: () -> Void

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
        var tint: Color { ["report": Color.red, "summary": Color.orange, "excel": Paper.tick, "data": Color.indigo, "photos": Color.teal][rawValue]! }
        var isPDF: Bool { self == .report || self == .summary }
        /// Drive keeps the full report, the workbook and the job data; the one-page summary is share-only.
        var driveKind: DriveSync.Kind? { ["report": .pdf, "excel": .xlsx, "data": .json][rawValue] }
        /// Photos go to Drive only — dozens of pictures don't belong in a share sheet.
        var shareable: Bool { self != .photos }
    }

    struct Shared: Identifiable { let id = UUID(); let urls: [URL] }

    @Environment(SurveyModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Key bumped when photos became a default, so choices saved before that start from the new default.
    @AppStorage("solarSurvey.exportFormats.v2") private var stored = "report,excel,photos"
    @State private var busy: String?
    @State private var log: [String] = []
    @State private var error: String?
    @State private var shared: Shared?
    @State private var preview: PDFPreviewItem?
    /// GoogleAuth reads the keychain and isn't observable — mirror its state here.
    @State private var signedIn = false

    private var selected: [Format] {
        let set = Set(stored.split(separator: ",").map(String.init))
        return Format.allCases.filter { set.contains($0.rawValue) }
    }
    private func toggle(_ f: Format) {
        var s = Set(selected)
        if s.contains(f) { s.remove(f) } else { s.insert(f) }
        stored = Format.allCases.filter { s.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
    private var driveKinds: [DriveSync.Kind] { selected.compactMap(\.driveKind) }
    private var canShare: Bool { selected.contains(where: \.shareable) }
    private var canDrive: Bool { !driveKinds.isEmpty || selected.contains(.photos) }

    var body: some View {
        NavigationStack {
            List {
                if let job = model.job(jobID) {
                    statusSection(job)
                    if !job.transformerGaps.isEmpty { gapsSection(job.transformerGaps) }
                }
                formatsSection
                if let job = model.job(jobID) { driveSection(job) }
                if !log.isEmpty {
                    Section("ความคืบหน้า") { ForEach(Array(log.enumerated()), id: \.offset) { Text($0.element).font(.callout) } }
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle("ส่งออกงาน").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() }.disabled(busy != nil) } }
            .interactiveDismissDisabled(busy != nil)
        }
        .onAppear { signedIn = model.google.isSignedIn }
        .sheet(item: $shared) { s in ShareSheet(items: s.urls).presentationDetents([.medium, .large]) }
        .sheet(item: $preview) { p in PDFPreview(item: p) }
    }

    // MARK: sections

    func statusSection(_ job: Job) -> some View {
        Section {
            HStack(spacing: 14) {
                ProgressRing(value: job.completion.fraction, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.projectName.isEmpty ? "แบบสำรวจใหม่" : job.projectName).font(.headline).lineLimit(2)
                    Text("NO.\(job.docNo.isEmpty ? "—" : job.docNo) · กรอกแล้ว \(job.completion.filled)/\(job.completion.total) · รูป \(job.photoCount)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    func gapsSection(_ gaps: [String]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("ภาพหม้อแปลงยังไม่ครบ", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.orange)
                ForEach(gaps, id: \.self) { Text($0).font(.callout) }
                Button { dismiss(); fixGaps() } label: { Label("ไปถ่ายให้ครบ", systemImage: "camera") }
                    .buttonStyle(.bordered).tint(.orange).padding(.top, 2)
            }
            .padding(.vertical, 4)
        } footer: { Text("ส่งออกต่อได้ แต่รายงานจะขาดภาพเหล่านี้") }
    }

    var formatsSection: some View {
        Section {
            ForEach(Format.allCases) { f in formatRow(f) }
        } header: { Text("ไฟล์ที่จะส่งออก") } footer: {
            let notes = [selected.contains(.summary) ? "PDF สรุป 1 หน้า แชร์ได้อย่างเดียว ไม่บันทึกลง Google Drive" : nil,
                         selected.contains(.photos) ? "รูปภาพบันทึกลง Google Drive เท่านั้น" : nil].compactMap { $0 }
            if !notes.isEmpty { Text(notes.joined(separator: "\n")) }
        }
    }

    func formatRow(_ f: Format) -> some View {
        let on = selected.contains(f)
        return HStack(spacing: 12) {
            Image(systemName: f.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(f.tint, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(.body.weight(.semibold))
                Text(f == .photos ? photoDetail : f.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if f.isPDF {
                Button { previewPDF(f) } label: { Image(systemName: "eye").frame(width: 32, height: 32) }
                    .buttonStyle(.borderless).disabled(busy != nil).accessibilityLabel("ดูตัวอย่าง " + f.title)
            }
            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2)
                .foregroundStyle(on ? Paper.tick : Color.secondary.opacity(0.5))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { if busy == nil { toggle(f) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// "46 รูป · รูปใหม่ 12 รูป" — how much the next Drive save will send.
    var photoDetail: String {
        guard let job = model.job(jobID) else { return Format.photos.detail }
        let all = job.allPhotos.count
        guard all > 0 else { return "ยังไม่มีรูปในงานนี้" }
        let sent = Set((job.drive?.photoFiles ?? [:]).keys)
        let new = job.photoFolders.flatMap(\.photos).filter { !sent.contains($0.photo.id.uuidString) }.count
        if sent.isEmpty { return "\(all) รูป · แยกโฟลเดอร์ตามหัวข้อใน Drive" }
        return "\(all) รูป · " + (new == 0 ? "อยู่ใน Drive ครบแล้ว" : "รูปใหม่ \(new) รูป")
    }

    func driveSection(_ job: Job) -> some View {
        Section("Google Drive") {
            if signedIn {
                LabeledContent("บัญชี", value: model.google.email ?? "ลงชื่อเข้าใช้แล้ว")
            } else {
                Button { signIn() } label: { Label("ลงชื่อเข้าใช้ Google", systemImage: "person.crop.circle.badge.plus") }
                    .disabled(busy != nil)
            }
            LabeledContent("โฟลเดอร์", value: "\(model.settings.driveRoot) / \(DriveSync.folderName(job))")
            if let t = job.drive?.lastSaved { LabeledContent("บันทึกล่าสุด", value: t.formatted(date: .abbreviated, time: .shortened)) }
            if let url = job.drive?.folderURL, let u = URL(string: url) { Link("เปิดโฟลเดอร์ใน Google Drive", destination: u) }
            if let id = job.drive?.photosFolderID, let u = URL(string: "https://drive.google.com/drive/folders/\(id)") { Link("เปิดโฟลเดอร์รูปภาพ", destination: u) }
        }
    }

    var actionBar: some View {
        VStack(spacing: 8) {
            if let busy {
                HStack(spacing: 8) { ProgressView(); Text(busy).font(.callout).foregroundStyle(.secondary) }
            }
            HStack(spacing: 12) {
                Button { share() } label: {
                    Label("แชร์ไฟล์", systemImage: "square.and.arrow.up").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).disabled(!canShare)
                Button { saveToDrive() } label: {
                    Label("Google Drive", systemImage: "icloud.and.arrow.up").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).disabled(!canDrive)
            }
            .controlSize(.large)
            .disabled(busy != nil)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: actions

    func file(_ f: Format, _ job: Job) throws -> SurveyModel.ExportFile {
        switch f {
        case .report: return try model.exportPDF(job)
        case .summary: return try model.exportSummaryPDF(job)
        case .excel: return try model.exportExcel(job)
        case .data: return try model.exportBackup([job.id])
        case .photos: throw DriveFailure(message: "รูปภาพบันทึกลง Google Drive เท่านั้น")
        }
    }

    /// Builds on the next run-loop turn so the progress line shows first.
    func run(_ message: String, _ work: @escaping () async throws -> Void) {
        busy = message; error = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            do { try await work() } catch { self.error = error.localizedDescription }
            busy = nil
        }
    }

    func previewPDF(_ f: Format) {
        guard let job = model.job(jobID) else { return }
        run("กำลังสร้าง \(f.title)…") {
            let out = try file(f, job)
            preview = PDFPreviewItem(url: out.url, title: (f == .summary ? "สรุป " : "") + job.projectName)
        }
    }

    func share() {
        guard let job = model.job(jobID) else { return }
        let formats = selected.filter(\.shareable)
        log = []
        run("กำลังสร้างไฟล์…") {
            var urls: [URL] = []
            for f in formats {
                busy = "กำลังสร้าง \(f.title)…"
                await Task.yield()
                let out = try file(f, job)
                urls.append(out.url)
                log.append("✓ " + out.summary)
            }
            shared = Shared(urls: urls)
        }
    }

    func signIn() {
        run("กำลังลงชื่อเข้าใช้ Google…") {
            try await model.google.signIn()
            signedIn = true
        }
    }

    func saveToDrive() {
        guard let job = model.job(jobID) else { return }
        let kinds = driveKinds, photos = selected.contains(.photos)
        log = []
        run("กำลังบันทึกลง Google Drive…") {
            do {
                if !model.google.isSignedIn { try await model.google.signIn() }
                signedIn = true
                _ = try await model.saveToDrive(job, kinds: kinds, photos: photos) { step in
                    Task { @MainActor in
                        switch step {
                        case .folder(let n): log.append("✓ โฟลเดอร์ \(n)")
                        case .building(let k): log.append("… กำลังสร้าง \(k.label)")
                        case .uploading(let k, let bytes): log.append("… อัปโหลด \(k.rawValue.uppercased()) \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
                        case .uploaded(_, let f): log.append("✓ \(f.name)")
                        case .photos(let done, let total):
                            // one line that counts up instead of a line per photo
                            let line = total == 0 ? "✓ รูปภาพอยู่ใน Drive ครบแล้ว" : done < total ? "… อัปโหลดรูป \(done)/\(total)" : "✓ รูปภาพ \(total) รูป"
                            if log.last?.hasPrefix("… อัปโหลดรูป") == true { log[log.count - 1] = line } else { log.append(line) }
                        }
                    }
                }
                log.append("บันทึกลง Google Drive เรียบร้อย")
            } catch let e as DriveSync.Interrupted {
                throw DriveFailure(message: e.localizedDescription + "\nรูปที่อัปโหลดแล้วถูกบันทึกไว้ — กดบันทึกอีกครั้งเพื่อส่งรูปที่เหลือ")
            } catch {
                throw DriveFailure(message: error.localizedDescription + "\nไฟล์อาจอัปโหลดไปแล้วบางส่วน — ตรวจสอบในโฟลเดอร์ก่อนบันทึกซ้ำ")
            }
        }
    }

    struct DriveFailure: LocalizedError { let message: String; var errorDescription: String? { message } }
}
#endif
