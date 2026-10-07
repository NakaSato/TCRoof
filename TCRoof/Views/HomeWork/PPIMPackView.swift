import SwiftUI
import PDFKit
import TCRoofUI
import TCRoofCore

/// Files ready for PPIM part 4 (self-use request): one PDF per slot, named as PPIM shows them and kept under
/// each slot's size limit, zipped for the share sheet.
enum PPIMPack {
    struct Slot: Identifiable {
        let spec: HomeDocSpec
        var url: URL?
        var bytes: Int = 0
        var id: String { spec.id }
        var limit: Int { (spec.maxMB ?? 5) * 1_000_000 }
        var ok: Bool { url != nil && bytes <= limit }
    }

    /// Image files become A4-width pages; PDFs are appended page by page. Images are re-encoded smaller until the
    /// PDF fits the slot's limit (or the smallest step is reached).
    static func pdf(for files: [URL], limit: Int) -> Data? {
        for (dim, quality) in [(2000.0, 0.8), (1600, 0.7), (1200, 0.6), (900, 0.5)] {
            let doc = PDFDocument()
            for url in files {
                if url.pathExtension.lowercased() == "pdf", let src = PDFDocument(url: url) {
                    for i in 0..<src.pageCount {
                        if let p = src.page(at: i) { doc.insert((p.copy() as? PDFPage) ?? p, at: doc.pageCount) }
                    }
                } else if let data = try? Data(contentsOf: url), let image = UIImage(data: data),
                          let small = UIImage(data: jpeg(image, dim, quality)),
                          let page = PDFPage(image: small) {
                    doc.insert(page, at: doc.pageCount)
                }
            }
            guard doc.pageCount > 0, let data = doc.dataRepresentation() else { return nil }
            if data.count <= limit || dim == 900 { return data }
        }
        return nil
    }

    private static func jpeg(_ image: UIImage, _ maxDimension: CGFloat, _ quality: CGFloat) -> Data {
        let s = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * s, height: image.size.height * s)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: quality) ?? Data()
    }

    /// Builds every slot's PDF in a fresh folder; returns the slots and the folder.
    static func build(job: Job, home: HomeJob) -> (slots: [Slot], folder: URL) {
        let store = PermitStore(job: job)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PPIM-\(job.code)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let slots = home.ppimSlots.map { spec -> Slot in
            var slot = Slot(spec: spec)
            let files = home.document(spec.id).files.map(store.url)
            guard !files.isEmpty, let name = spec.ppimFile, let data = pdf(for: files, limit: slot.limit) else { return slot }
            let url = folder.appendingPathComponent(name)
            if (try? data.write(to: url)) != nil { slot.url = url; slot.bytes = data.count }
            return slot
        }
        return (slots, folder)
    }

    /// The folder as one zip, through the system's own archiver.
    static func zip(_ folder: URL) -> URL? {
        var out: URL?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &error) { zipURL in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(folder.lastPathComponent + ".zip")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: zipURL, to: dest)) != nil { out = dest }
        }
        return out
    }
}

struct PPIMPackView: View {
    let job: Job
    let home: HomeJob
    @Environment(\.dismiss) private var dismiss

    @State private var slots: [PPIMPack.Slot] = []
    @State private var folder: URL?
    @State private var share: URL?
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text(home.mode == .selfUse
                         ? "ส่วนที่ 4 ของคำขอเชื่อมต่อ (ไม่ขายไฟ) ใน PPIM · ช่องละ 1 ไฟล์ PDF · ชื่อไฟล์และขนาดตามหน้าจอ PPIM"
                         : "สายขายไฟ: ใช้ไฟล์ชุดเดียวกันแนบในคำขอขายไฟ/ขอเชื่อมต่อ · ช่องของหน้าจอขายไฟยังไม่ยืนยัน")
                        .font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.inkMuted)
                    ForEach(slots) { slotRow($0) }
                    if slots.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding(Space.l)
            }
            .background(Theme.background)
            .navigationTitle("ชุดไฟล์ PPIM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ส่งออก ZIP") { if let folder { share = PPIMPack.zip(folder) } }
                        .disabled(working || !slots.contains { $0.url != nil })
                }
            }
            .task {
                working = true
                let built = PPIMPack.build(job: job, home: home)
                slots = built.slots
                folder = built.folder
                working = false
            }
            .sheet(item: Binding(get: { share.map(ShareURL.init) }, set: { share = $0?.url })) { ActivitySheet(items: [$0.url]) }
        }
    }

    private struct ShareURL: Identifiable { let url: URL; var id: URL { url } }

    private func slotRow(_ s: PPIMPack.Slot) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Text("\(s.spec.ppimSlot ?? 0)").font(.sarabun(18, .bold, relativeTo: .headline)).foregroundStyle(Theme.primary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.spec.ppimFile ?? s.spec.title).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                Text(s.spec.title).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if s.url == nil {
                TCStatusChip("ยังไม่มีไฟล์", kind: .pending)
            } else {
                TCStatusChip(String(format: "%.2f MB", Double(s.bytes) / 1_000_000) + (s.ok ? "" : " · เกิน \(s.spec.maxMB ?? 5) MB"),
                             kind: s.ok ? .done : .overdue)
            }
        }
        .padding(Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}
