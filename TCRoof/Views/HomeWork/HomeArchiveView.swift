import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import TCRoofUI
import TCRoofCore

/// Keeps files of a home job in the job's project documents (เอกสารโครงการ, SwiftData on this device), the same
/// list the job screen shows and uploads to Google Drive.
@MainActor
enum HomeArchive {
    /// Adds the file, or replaces the one with the same name when its bytes changed (then it uploads again).
    @discardableResult
    static func keep(_ data: Data, name: String, job: Job) -> DocumentAsset? {
        let clean = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        guard !data.isEmpty, !clean.isEmpty else { return nil }
        if let existing = job.documents.first(where: { $0.name == clean }) {
            if existing.data != data {
                existing.data = data
                existing.addedAt = .now
                existing.driveFileID = nil
            }
            return existing
        }
        let doc = DocumentAsset(name: clean, data: data)
        job.modelContext?.insert(doc)
        doc.job = job
        return doc
    }

    /// Ensures the name ends with the extension.
    static func name(_ base: String, ext: String) -> String {
        base.lowercased().hasSuffix("." + ext) ? base : base + "." + ext
    }
}

/// แฟ้มเอกสาร of a home job: every paper the app made (forms, BOQ, PPIM files, installer papers) and anything the
/// team adds, kept in the app and uploaded to the job's Google Drive folder.
struct HomeArchiveView: View {
    @Bindable var job: Job
    @Environment(\.modelContext) private var context
    @Environment(GoogleSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var picks: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var preview: URL?
    @State private var progress: String?
    @State private var error: String?
    @State private var query = ""

    private var docs: [DocumentAsset] {
        let all = job.documents.sorted { $0.addedAt > $1.addedAt }
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    driveCard
                    addCard
                    if job.documents.count > 6 { TCTextField("ค้นหาชื่อไฟล์", text: $query) }
                    if docs.isEmpty {
                        Text(job.documents.isEmpty ? "ยังไม่มีเอกสาร · ไฟล์ที่ส่งออกจากแบบฟอร์ม BOQ ชุดไฟล์ PPIM และเอกสารผู้รับเหมาจะเข้ามาที่นี่เอง"
                                                   : "ไม่พบไฟล์ที่ตรงกับคำค้น")
                            .font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.inkMuted)
                    }
                    ForEach(docs) { row($0) }
                }
                .padding(Space.l)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("แฟ้มเอกสาร")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } }
            .quickLookPreview($preview)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .spreadsheet, .data], allowsMultipleSelection: true) { r in
                guard case .success(let urls) = r else { return }
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) { HomeArchive.keep(data, name: url.lastPathComponent, job: job) }
                }
            }
            .onChange(of: picks) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for (i, item) in items.enumerated() {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            HomeArchive.keep(ImageUtil.compressed(data), name: "รูป \(job.code) \(Self.stamp()) \(i + 1).jpg", job: job)
                        }
                    }
                    picks = []
                }
            }
            .alert("อัปโหลดไม่สำเร็จ", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("ตกลง", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    static func stamp(_ d: Date = .now) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        return String(format: "%04d%02d%02d-%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    // MARK: Cards

    private var driveCard: some View {
        let pending = ProjectDriveUpload.pendingCount(job)
        return PermitSection(title: "Google Drive", subtitle: pending > 0 ? "รออัปโหลด \(pending) ไฟล์" : "อัปโหลดครบแล้ว") {
            if let progress { ProgressView(progress).font(.sarabun(14, relativeTo: .body)) }
            HStack(spacing: Space.s) {
                TCButton(pending > 0 ? "อัปโหลด (\(pending))" : "อัปโหลดครบแล้ว", systemImage: "icloud.and.arrow.up", kind: .primary, size: .card) {
                    upload()
                }
                .disabled(pending == 0 || progress != nil)
                if let link = job.driveFolderURL, let url = URL(string: link) {
                    Link(destination: url) {
                        Label("เปิดโฟลเดอร์", systemImage: "arrow.up.right.square").font(.sarabun(14, .semibold, relativeTo: .body))
                            .padding(.horizontal, Space.m).frame(minHeight: touchMin)
                    }
                }
            }
            Text("เก็บในเครื่องนี้และขึ้น Drive ของบัญชีที่ล็อกอิน · บางไฟล์มีเลขบัตรประชาชน แชร์โฟลเดอร์เฉพาะคนในทีม")
                .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
        }
    }

    private var addCard: some View {
        HStack(spacing: Space.s) {
            PhotosPicker(selection: $picks, maxSelectionCount: 20, matching: .images) {
                Label("เพิ่มรูป", systemImage: "photo").font(.sarabun(14, .semibold, relativeTo: .body))
                    .padding(.horizontal, Space.m).frame(minHeight: touchMin)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.45)))
            }
            .buttonStyle(.plain)
            TCButton("เพิ่มไฟล์", systemImage: "doc.badge.plus", kind: .secondary, size: .card) { importing = true }
        }
    }

    private func row(_ doc: DocumentAsset) -> some View {
        HStack(spacing: Space.m) {
            Button { open(doc) } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: icon(doc.name)).font(.system(size: 20)).foregroundStyle(Theme.primary).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.name).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text(PermitDate.long(doc.addedAt) + " · " + ByteCountFormatter.string(fromByteCount: Int64(doc.data.count), countStyle: .file))
                            .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: Space.s)
            Image(systemName: doc.driveFileID == nil ? "icloud.slash" : "checkmark.icloud.fill")
                .foregroundStyle(doc.driveFileID == nil ? Theme.inkMuted : Theme.okTick)
                .accessibilityLabel(doc.driveFileID == nil ? "ยังไม่ขึ้น Drive" : "อยู่บน Drive แล้ว")
            Menu {
                Button { open(doc) } label: { Label("ดู", systemImage: "eye") }
                ShareLink(item: tempURL(doc)) { Label("แชร์", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { context.delete(doc) } label: { Label("ลบจากแอป", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 20)).frame(width: touchMin, height: touchMin)
            }
            .accessibilityLabel("ตัวเลือกของ \(doc.name)")
        }
        .padding(Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private func icon(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "xlsx", "xls", "csv": "tablecells"
        case "jpg", "jpeg", "png", "heic": "photo"
        case "zip": "doc.zipper"
        default: "doc"
        }
    }

    private func tempURL(_ doc: DocumentAsset) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(doc.name)
        try? doc.data.write(to: url, options: .atomic)
        return url
    }

    private func open(_ doc: DocumentAsset) { preview = tempURL(doc) }

    private func upload() {
        Task {
            do {
                try await ProjectDriveUpload.run(job, session: session) { done, total in progress = "กำลังอัปโหลด \(done)/\(total)" }
            } catch {
                self.error = error.localizedDescription
            }
            progress = nil
        }
    }
}
