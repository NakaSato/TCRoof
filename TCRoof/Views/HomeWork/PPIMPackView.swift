import SwiftUI
import PDFKit
import TCRoofUI
import TCRoofCore

/// Files ready for PPIM part 4 (self-use request): one PDF per slot, named as PPIM shows them and kept under
/// each slot's size limit, zipped for the share sheet. A slot's file joins every document that goes into it.
enum PPIMPack {
    struct Slot: Identifiable {
        let upload: PPIMUpload
        var url: URL?
        var bytes: Int = 0
        var id: Int { upload.slot.number }
        var limit: Int { upload.slot.maxMB * 1_000_000 }
        var ok: Bool { url != nil && bytes <= limit }
    }

    /// Generated pages that lead a slot's file (slot 4's photo report).
    struct Lead {
        var report: PhotoReport
        var kWp: Double?
        var store: PermitStore
    }

    /// The lead pages, then image files as A4-width pages and PDFs page by page. Images are re-encoded smaller until
    /// the PDF fits the slot's limit (or the smallest step is reached).
    static func pdf(lead: Lead?, files: [URL], limit: Int) -> Data? {
        for (dim, quality) in [(2000.0, 0.8), (1600, 0.7), (1200, 0.6), (900, 0.5)] {
            let doc = PDFDocument()
            if let lead, let data = PhotoReportRenderer.pdf(lead.report, kWp: lead.kWp, load: { name in
                lead.store.photo(name).flatMap(UIImage.init(data:)).flatMap { UIImage(data: jpeg($0, dim, quality)) }
            }), let pages = PDFDocument(data: data) {
                for i in 0..<pages.pageCount { if let p = pages.page(at: i) { doc.insert(p, at: doc.pageCount) } }
            }
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
    /// A document's files in file order: the library item's (engineer papers, datasheets), then the job's own.
    static func files(_ doc: String, home: HomeJob, library: HomeLibrary, store: PermitStore) -> [URL] {
        let shared = library.item(home.libraryPicks[doc])?.files.map(PermitStore.library.url) ?? []
        return shared + home.document(doc).files.map(store.url)
    }

    static func build(job: Job, home: HomeJob, library: HomeLibrary) -> (slots: [Slot], folder: URL) {
        let store = PermitStore(job: job)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PPIM-\(job.code)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let kWp = HomeJob.number(home.pvKWp) ?? home.ppim.panelKWp
        let slots = home.ppimSlots.map { upload -> Slot in
            var slot = Slot(upload: upload)
            // documents in file order: the drawings before the engineer's papers, the ID card before the house registration
            let files = upload.documents.flatMap { files($0.id, home: home, library: library, store: store) }
            let lead = upload.documents.contains { $0.form == .photoReport } && !home.photoReport.pages.isEmpty
                ? Lead(report: home.photoReport, kWp: kWp, store: store) : nil
            guard !files.isEmpty || lead != nil, let data = pdf(lead: lead, files: files, limit: slot.limit) else { return slot }
            let url = folder.appendingPathComponent(upload.slot.file)
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
    var library = HomeLibrary()
    @Environment(\.dismiss) private var dismiss

    @State private var slots: [PPIMPack.Slot] = []
    @State private var folder: URL?
    @State private var share: URL?
    @State private var working = false
    @State private var kept = 0

    /// Each built slot file goes into แฟ้มเอกสาร as "PPIM <file>", replacing the earlier build of the same slot.
    private func keepSlots() {
        kept = 0
        for s in slots {
            guard let url = s.url, let data = try? Data(contentsOf: url) else { continue }
            HomeArchive.keep(data, name: "PPIM " + s.upload.slot.file, job: job)
            kept += 1
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text(home.mode == .selfUse
                         ? "ส่วนที่ 4 ของคำขอเชื่อมต่อ (ไม่ขายไฟ) ใน PPIM · ช่องละ 1 ไฟล์ PDF · ชื่อไฟล์และขนาดตามหน้าจอ PPIM · ช่อง 7 ไม่มีในงานแสงอาทิตย์"
                         : "สายขายไฟ: ใช้ไฟล์ชุดเดียวกันแนบในคำขอขายไฟ/ขอเชื่อมต่อ · ช่องของหน้าจอขายไฟยังไม่ยืนยัน")
                        .font(.sarabun(14, relativeTo: .body)).foregroundStyle(Theme.inkMuted)
                    HStack(spacing: Space.s) {
                        TCButton("เก็บเข้าแฟ้มเอกสาร", systemImage: "folder.badge.plus", kind: .secondary, size: .card) { keepSlots() }
                            .disabled(working || !slots.contains { $0.url != nil })
                        if kept > 0 {
                            Text("เก็บแล้ว \(kept) ไฟล์").font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.okText)
                        }
                    }
                    ForEach(["เอกสารหลัก", "พลังงานแสงอาทิตย์"], id: \.self) { group in
                        Text(group).font(.sarabun(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(slots.filter { $0.upload.slot.group == group }) { slotRow($0) }
                    }
                    if slots.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                }
                .padding(Space.l)
            }
            .tcPageBackground()
            .navigationTitle("ชุดไฟล์ PPIM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ส่งออก ZIP") { if let folder { keepSlots(); share = PPIMPack.zip(folder) } }
                        .disabled(working || !slots.contains { $0.url != nil })
                }
            }
            .task {
                working = true
                let built = PPIMPack.build(job: job, home: home, library: library)
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
            Text("\(s.upload.slot.number)").font(.sarabun(18, .bold, relativeTo: .headline)).foregroundStyle(Theme.primary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.upload.slot.file).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                Text(s.upload.slot.title).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("ในไฟล์: " + s.upload.documents.map(\.title).joined(separator: " → "))
                    .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if s.url == nil {
                TCStatusChip("ยังไม่มีไฟล์", kind: .pending)
            } else {
                TCStatusChip(String(format: "%.2f MB", Double(s.bytes) / 1_000_000) + (s.ok ? "" : " · เกิน \(s.upload.slot.maxMB) MB"),
                             kind: s.ok ? .done : .overdue)
            }
        }
        .padding(Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}
