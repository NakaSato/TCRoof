import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import TCRoofUI
import TCRoofCore

/// State 11: a drawing's revisions, newest first, each opened from this device or Drive.
struct DrawingHistorySheet: View {
    let drawing: StationDrawing
    let canUpload: Bool
    let url: (StationDrawing.Revision) -> URL?
    let upload: () -> Void
    @State private var preview: URL?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(drawing.revisions.reversed().enumerated()), id: \.element.rev) { i, r in
                        revisionRow(r, latest: i == 0)
                    }
                }
                .padding(24)
            }
            .background(Theme.groupedPage.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if canUpload {
                    Button { upload() } label: { Text("อัปโหลด REV \(drawing.nextRev)").frame(maxWidth: .infinity) }
                        .buttonStyle(TCButtonStyle(.primary, size: .page))
                        .padding(.horizontal, 24).padding(.vertical, 14)
                        .background(Theme.surface)
                        .accessibilityIdentifier("padSheet.uploadNext")
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(drawing.id).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                        Text(drawing.title).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() }.bold() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .quickLookPreview($preview)
        }
    }

    private func revisionRow(_ r: StationDrawing.Revision, latest: Bool) -> some View {
        let link = url(r)
        return HStack(alignment: .top, spacing: 14) {
            InstallTrackingPage.revChip(r.rev, latest: latest).frame(width: 72, alignment: .leading)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.reason.isEmpty ? "ออกแบบครั้งแรก" : r.reason).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                    Text([ThaiFormat.numericDate.string(from: r.date), TeamDirectory.shared.person(r.by)?.name ?? r.by, r.file]
                        .filter { !$0.isEmpty }.joined(separator: " | "))
                        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(latest ? "ล่าสุด | ใช้งาน" : "แทนที่แล้ว").font(.sarabunFixed(13, .bold))
                    .foregroundStyle(latest ? Theme.successInk : Theme.inkMuted)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(latest ? Theme.successSoft : Theme.segmentTrack, in: Capsule())
                    .fixedSize()
                Button("เปิด") {
                    guard let link else { return }
                    if link.isFileURL { preview = link } else { openURL(link) }
                }
                .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                .disabled(link == nil)
                .accessibilityHint(link == nil ? "ไฟล์ยังไม่อยู่ในเครื่องนี้และยังไม่ขึ้น Drive" : "")
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
        }
    }
}

/// State 12: a drawing (or a new one), its file from Files or the document camera, the REV it becomes, and the reason
/// from REV 01. `อัปโหลด REV nn` stays off until it can go (`StationDrawings.problem`).
struct DrawingUploadSheet: View {
    let drawings: [StationDrawing]
    let onUpload: (StationDrawings.Upload, Data) -> Void
    @State private var upload: StationDrawings.Upload
    @State private var file: (data: Data, name: String)?
    @State private var importing = false
    @State private var scanning = false
    @Environment(\.dismiss) private var dismiss

    /// DWG has no system type; the Files picker matches it by its extension.
    private static let types: [UTType] = [.pdf, .jpeg, .png, UTType(filenameExtension: "dwg", conformingTo: .data) ?? .data]

    init(drawings: [StationDrawing], picked: String?, prefill: Bool, onUpload: @escaping (StationDrawings.Upload, Data) -> Void) {
        self.drawings = drawings
        self.onUpload = onUpload
        var u = StationDrawings.Upload(drawing: picked ?? drawings.first?.id)
        var f: (Data, String)?
        #if DEBUG
        if prefill {
            f = (DocumentCamera.stubPDF(), "แบบตัวอย่าง.pdf")
            u.ext = "pdf"
            u.reason = "ย้ายแนวราง (ตัวอย่าง)"
        }
        #endif
        _upload = State(initialValue: u)
        _file = State(initialValue: f)
    }

    private var rev: String { StationDrawings.rev(of: upload, in: drawings) }
    private var problem: String? { StationDrawings.problem(upload, in: drawings) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    picker
                    if upload.drawing == nil { newFields }
                    revInfo
                    fileZone
                    reasonField
                    if let problem { Text(problem).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).accessibilityIdentifier("padSheet.problem") }
                }
                .padding(24)
            }
            .background(Theme.groupedPage.ignoresSafeArea())
            .navigationTitle("อัปโหลดแบบ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("อัปโหลด REV \(rev)") {
                        guard let file else { return }
                        onUpload(upload, file.data)
                        dismiss()
                    }
                    .bold().disabled(problem != nil || file == nil)
                    .accessibilityIdentifier("padSheet.uploadConfirm")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: Self.types) { imported($0) }
            .fullScreenCover(isPresented: $scanning) {
                DocumentCamera { pdf in
                    if let pdf { set(pdf, name: "สแกนแบบ \(Date.now.formatted(date: .omitted, time: .shortened)).pdf") }
                    scanning = false
                }
                .ignoresSafeArea()
            }
        }
    }

    private func heading(_ text: String, required: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(text).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
            if required { Text("*").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.danger) }
        }
    }

    private func chip(_ title: String, on: Bool, dashed: Bool = false, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button(action: action) {
            Text(title).font(.sarabunFixed(15, on ? .bold : .regular)).foregroundStyle(on || dashed ? Theme.primary : Theme.navy)
                .lineLimit(1).padding(.horizontal, 14).frame(minHeight: 44)
                .background(on ? Theme.optionSelected : Theme.surface, in: shape)
                .overlay(shape.strokeBorder(on ? Theme.primary : Theme.borderControl,
                                            style: StrokeStyle(lineWidth: on ? 2 : 1, dash: dashed ? [4, 3] : [])))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("แบบที่จะอัปโหลด")
            FlowLayout(spacing: 10, lineSpacing: 10) {
                ForEach(drawings) { d in
                    // the title without its bracketed English, as the board's chips
                    chip(d.id + " " + (d.title.components(separatedBy: " (").first ?? d.title), on: upload.drawing == d.id) { upload.drawing = d.id }
                        .accessibilityIdentifier("padSheet.pick.\(d.id)")
                }
                chip("+ แบบใหม่", on: upload.drawing == nil, dashed: true) { upload.drawing = nil }
                    .accessibilityIdentifier("padSheet.pick.new")
            }
        }
    }

    private var newFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("ชื่อแบบ", required: true)
            TCTextField("เช่น ผังแผงบนหลังคา", text: $upload.newTitle).accessibilityIdentifier("padSheet.newTitle")
            heading("รหัสแบบ")
            TCTextField("เช่น A-03 (ว่างไว้ แอปตั้งให้)", text: $upload.newID)
        }
    }

    private var revInfo: some View {
        let from = upload.drawing.flatMap { id in drawings.first { $0.id == id } }?.latest
        return HStack(spacing: 10) {
            Text("จะบันทึกเป็น").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
            InstallTrackingPage.revChip(rev)
            Text(from.map { "ต่อจาก REV \($0.rev) (\(ThaiFormat.numericDate.string(from: $0.date))) | REV เดิมย้ายไปประวัติ" } ?? "แบบใหม่เริ่มที่ REV 00")
                .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var fileZone: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 12) {
            if let file {
                Label(file.name, systemImage: "doc").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                    .accessibilityIdentifier("padSheet.fileName")
            } else {
                Text("PDF | DWG | JPG / PNG | ถ่ายรูปแบบ").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
            }
            HStack(spacing: 12) {
                Button { importing = true } label: { Label(file == nil ? "เลือกไฟล์" : "เปลี่ยนไฟล์", systemImage: "folder") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                Button { scan() } label: { Label("ถ่ายรูปแบบ", systemImage: "doc.viewfinder") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
                    .disabled(!DocumentCamera.isAvailable)
                    .accessibilityIdentifier("padSheet.scan")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(file == nil ? Theme.surface : Theme.successSoft, in: shape)
        .overlay(shape.strokeBorder(file == nil ? Theme.borderControl : Theme.successInk, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("เหตุผลการแก้ไข", required: StationDrawing.needsReason(rev))
            TCTextField(StationDrawing.needsReason(rev) ? "เช่น ย้ายแนวราง" : "ไม่บังคับสำหรับ REV 00", text: $upload.reason)
                .accessibilityIdentifier("padSheet.reason")
        }
    }

    private func scan() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "pwaDocsCameraStub") {
            set(DocumentCamera.stubPDF(), name: "สแกนตัวอย่าง.pdf")
            return
        }
        #endif
        scanning = true
    }

    private func set(_ data: Data, name: String) {
        file = (data, name)
        upload.ext = (name as NSString).pathExtension.lowercased()
    }

    private func imported(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        set(data, name: url.lastPathComponent)
    }
}
