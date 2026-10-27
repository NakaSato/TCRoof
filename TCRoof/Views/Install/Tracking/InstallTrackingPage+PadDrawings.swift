import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

extension Job {
    /// The station's construction drawings (`drawingsJSON`), each with its revisions.
    var drawings: [StationDrawing] {
        get { StationDrawings.decode(drawingsJSON) }
        set { drawingsJSON = StationDrawings.encode(newValue) }
    }

    /// Takes the Drive ids of the drawings' files once the job's documents are uploaded, so the other devices can open
    /// them. True when one was recorded.
    @discardableResult
    func recordDrawingDriveIDs() -> Bool {
        let list = drawings
        guard list.contains(where: { $0.revisions.contains { $0.driveID == nil } }) else { return false }
        var uploaded: [String: String] = [:]
        for d in documents where d.folderPath == StationDrawings.folder {
            if let id = d.driveFileID { uploaded[d.name] = id }
        }
        let next = StationDrawings.recordingDriveIDs(list, uploaded: uploaded)
        guard next != list else { return false }
        drawings = next
        return true
    }
}

/// `แบบก่อสร้าง` (states 03, 11, 12): the drawings, their revision history and the upload.
extension InstallTrackingPage {
    var padDrawings: [StationDrawing] { padDemoOn ? padDemo.drawings : job.drawings }

    /// Uploads are the team's and managers' (`stationdocs.drafts`, as station papers); contractors view and open.
    var uploadsDrawings: Bool { editsStation }

    static func fileTint(_ ext: String) -> Color {
        switch ext.lowercased() {
        case "pdf": PadSettingsTint.pdf
        case "dwg": PadSettingsTint.dwg
        default: PadSettingsTint.image
        }
    }

    static func fileTile(_ ext: String, size: CGFloat = 44) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: size * 0.3,
                                           style: .continuous)
        return Text(ext.uppercased().prefix(4)).font(.sarabunFixed(size * 0.24, .bold)).foregroundStyle(Theme.onPrimary)
            .frame(width: size, height: size * 1.1, alignment: .bottom).padding(.bottom, size * 0.1)
            .background(fileTint(ext), in: shape)
            .accessibilityHidden(true)
    }

    static func revChip(_ rev: String, latest: Bool = true) -> some View {
        Text("REV " + rev).font(.sarabunFixed(13, .bold)).foregroundStyle(latest ? Theme.onPrimary : Theme.inkMuted)
            .padding(.horizontal, 8).frame(height: 24)
            .background(latest ? Theme.navySolid : Theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay { if !latest { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.borderSubtle) } }
            .fixedSize()
    }

    var padDrawingsPage: some View {
        let list = padDrawings
        return padSection(nil) {
            if list.isEmpty { padNoteRow("ยังไม่มีแบบก่อสร้าง", first: true) }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, d in drawingRow(d, first: i == 0) }
            drawingUploadRow
        }
        .task(id: job.documents.count) {
            guard !padDemoOn, job.recordDrawingDriveIDs() else { return }
            try? context.save()
        }
    }

    private func drawingRow(_ d: StationDrawing, first: Bool) -> some View {
        VStack(spacing: 0) {
            rowDivider(first)
            Button { padSheet = .history(d.id) } label: {
                HStack(spacing: 16) {
                    Self.fileTile(d.ext)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.id).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                        Text(d.title).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                        if let r = d.latest {
                            Text("แก้ล่าสุด " + ThaiFormat.numericDate.string(from: r.date) + (r.reason.isEmpty ? "" : " | " + r.reason))
                                .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        if let r = d.latest { Self.revChip(r.rev) }
                        Text("\(d.revisions.count) revision").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
                }
                .padding(.horizontal, 20).frame(minHeight: 76)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("padSettings.drawing.\(d.id)")
        }
    }

    private var drawingUploadRow: some View {
        VStack(spacing: 0) {
            rowDivider(false)
            HStack(spacing: 14) {
                if uploadsDrawings {
                    Button { padSheet = .upload(nil) } label: {
                        Label("อัปโหลดแบบ / Revision ใหม่", systemImage: "arrow.up.to.line").font(.sarabunFixed(16, .bold))
                    }
                    .buttonStyle(TCButtonStyle(.primary, size: .card)).fixedSize()
                    .accessibilityIdentifier("padSettings.upload")
                }
                Text(uploadsDrawings ? "PDF | DWG | รูป | แบบเดิมเก็บไว้ในประวัติทุก REV" : "ทีมงานเป็นผู้อัปโหลดแบบ | เปิดดูได้ทุก REV")
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
    }

    /// Appends the upload as a new revision and keeps its file with the job's documents under `แบบก่อสร้าง`, so the
    /// job's Drive upload carries it (`2. เอกสารระหว่างก่อสร้าง/แบบก่อสร้าง/` on the center Drive). The demo keeps the
    /// revision in memory and no file.
    func uploadDrawing(_ upload: StationDrawings.Upload, data: Data) {
        guard uploadsDrawings,
              let out = StationDrawings.appending(upload, to: padDrawings, by: permissions.email, date: .now) else { return }
        if padDemoOn { padDemo.drawings = out.list; return }
        for old in job.documents where old.name == out.revision.file && old.folderPath == StationDrawings.folder { context.delete(old) }
        let doc = DocumentAsset(name: out.revision.file, data: data)
        doc.folderPath = StationDrawings.folder
        context.insert(doc)
        doc.job = job
        job.drawings = out.list
        try? context.save()
    }

    /// The revision's file to open: on this device (a temporary copy for Quick Look), else on Drive.
    func drawingURL(_ r: StationDrawing.Revision) -> URL? {
        if let doc = job.documents.first(where: { $0.name == r.file && $0.folderPath == StationDrawings.folder }), !doc.data.isEmpty {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(r.file)
            if (try? doc.data.write(to: url, options: .atomic)) != nil { return url }
        }
        return r.driveID.flatMap { URL(string: "https://drive.google.com/file/d/\($0)/view") }
    }
}
