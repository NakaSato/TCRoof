import SwiftUI
import PDFKit
import VisionKit
import UniformTypeIdentifiers
import TCRoofUI
import TCRoofCore

/// `อัปโหลดเอกสาร` on iPad (docs/ui/pwa-docs-ipad §5, `states/04`, `11`): which slot the file goes into, where it comes
/// from (the document camera or a file), and for an ID card the three masking checks. One upload covers every package
/// sharing the paper, since they share its `DocState`. Files are kept locally first, so offline only adds a note.
struct PWADocsUploadSheet: View {
    let page: PWADocsPadView
    let data: PWADocsPadView.PageData
    /// Nil: a library paper, with `preselected` its only slot.
    let stationID: String?
    let package: StationDocs.Package?
    let preselected: String?

    enum Source { case camera, file }

    @Environment(\.dismiss) private var dismiss
    @State private var slot: String?
    @State private var showAll = false
    @State private var source: Source?
    @State private var file: (data: Data, ext: String, name: String)?
    @State private var scanning = false
    @State private var importing = false
    @State private var masked: Set<String> = []

    private static let maskChecks = ["ปิดศาสนา", "ปิดกรุ๊ปเลือด", "ปิดวันเกิด"]

    private var station: PWAPlan.Station? { data.station(stationID) }
    private var kind: StationDocs.Kind? { slot.flatMap(StationDocs.kind) }
    private var isID: Bool { kind.map(PWADocs.isIDCard) ?? false }

    /// The station's open papers (of the drilled package), with the paper it was opened from first when that one is
    /// ready already (`เปลี่ยนไฟล์`).
    private var slots: [StationDocs.Kind] {
        var out: [StationDocs.Kind]
        if let st = station {
            out = PWADocs.open(st, library: data.library)
            if let package { out = out.filter { $0.packages.contains(package) } }
        } else {
            out = []
        }
        if let id = preselected, let k = StationDocs.kind(id), !out.contains(k) { out.insert(k, at: 0) }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    slotSection
                    if let k = kind, k.packages.count > 1 { sharedNote(k) }
                    sourceSection
                    if isID { maskSection }
                    if page.isOffline { offlineNote }
                }
                .padding(20)
            }
            footer
        }
        .frame(width: 640)
        // the slots scroll on a station with many open papers, so the sheet stays on a landscape screen
        .frame(minHeight: 520, maxHeight: 700)
        .background(Theme.surface)
        .onAppear { if slot == nil { slot = preselected ?? slots.first?.id } }
        .onChange(of: slot) { masked = [] }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .spreadsheet, .data], onCompletion: imported)
        .fullScreenCover(isPresented: $scanning) {
            DocumentCamera { pdf in
                if let pdf { file = (pdf, "pdf", "สแกน \(Date.now.formatted(date: .omitted, time: .shortened))"); source = .camera }
                scanning = false
            }
            .ignoresSafeArea()
        }
    }

    // MARK: parts

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("อัปโหลดเอกสาร | " + (station.map { $0.ref + " " + $0.shortName } ?? "คลังกลาง"))
                    .font(.sarabunFixed(19, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                Text(station == nil ? "ใช้กับทุกสถานี" : package?.padTitle ?? "ทุกชุดของสถานีนี้")
                    .font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.navy)
                    .frame(width: 44, height: 44).background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิด")
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func sectionTitle(_ text: String, ink: Color = Theme.navy) -> some View {
        Text(text).font(.sarabunFixed(14, .bold)).foregroundStyle(ink)
    }

    private var slotSection: some View {
        let all = slots
        let shown = showAll ? all : Array(all.prefix(12))
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("1 | ใส่ในช่องไหน")
            if all.isEmpty {
                Text("เอกสารของสถานีนี้ครบแล้ว | เปลี่ยนไฟล์ได้จากหน้าเอกสาร").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            FlowLayout(spacing: 8) {
                ForEach(shown) { k in slotChip(k) }
                if !showAll, all.count > 12 {
                    Button("อีก \(all.count - 12) ช่อง") { showAll = true }
                        .font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary).frame(minHeight: touchMin)
                }
            }
        }
    }

    private func slotChip(_ k: StationDocs.Kind) -> some View {
        let on = slot == k.id
        return Button { slot = k.id } label: {
            Text(k.name).font(.sarabunFixed(14, on ? .bold : .semibold)).foregroundStyle(on ? Theme.primary : Theme.navy).lineLimit(1)
                .padding(.horizontal, 14).frame(height: 40)
                .background(on ? Theme.primarySoft : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
                .frame(minHeight: touchMin).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("pwaDocs.slot.\(k.id)")
    }

    private func sharedNote(_ k: StationDocs.Kind) -> some View {
        let others = k.packages.filter { $0 != package }.map { PWADocs.stepTitle($0) }
        return Text("⇄ ไฟล์นี้จะเข้า " + others.joined(separator: " | ") + " ด้วย | อัปโหลดครั้งเดียว")
            .font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.dockTeal)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.tealSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("2 | จากไหน")
            HStack(spacing: 10) {
                sourceCard(.camera, "ถ่ายรูปเอกสาร", "ตัดขอบ ปรับให้ตรง รวมหลายหน้า", enabled: DocumentCamera.isAvailable) {
                    #if DEBUG
                    if UserDefaults.standard.bool(forKey: "pwaDocsCameraStub") {
                        file = (DocumentCamera.stubPDF(), "pdf", "สแกนตัวอย่าง")
                        source = .camera
                        return
                    }
                    #endif
                    scanning = true
                }
                sourceCard(.file, "เลือกไฟล์", "PDF | รูป | Word", enabled: true) { importing = true }
            }
            if let file {
                Label(file.name, systemImage: "doc.fill").font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.primary)
            }
        }
    }

    private func sourceCard(_ s: Source, _ title: String, _ sub: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        let on = source == s && file != nil
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.sarabunFixed(15, .bold)).foregroundStyle(enabled ? Theme.navy : Theme.inkFaint)
                    Spacer()
                    if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary) }
                }
                Text(enabled ? sub : "เครื่องนี้ไม่มีกล้องสแกนเอกสาร").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(on ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(s == .camera ? "pwaDocs.source.camera" : "pwaDocs.source.file")
    }

    private var maskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("3 | ยืนยันว่าปิดข้อมูลบนบัตรทุกใบแล้ว", ink: Theme.dangerText)
            HStack(spacing: 16) {
                ForEach(Self.maskChecks, id: \.self) { c in
                    let on = masked.contains(c)
                    Button { if on { masked.remove(c) } else { masked.insert(c) } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 22))
                                .foregroundStyle(on ? Theme.danger : Theme.inkFaint)
                            Text(c).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.dangerText)
                        }
                        .frame(minHeight: touchMin).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("pwaDocs.mask.\(c)")
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var offlineNote: some View {
        Label("ออฟไลน์ | ไฟล์จะเข้าคิวและส่งเมื่อออนไลน์", systemImage: "wifi.slash")
            .font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.warningText)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: footer

    private var hint: String {
        if slot == nil { return "เลือกช่องเอกสาร" }
        if file == nil { return "เลือกที่มาของไฟล์" }
        if isID && masked.count < Self.maskChecks.count { return "ยืนยันการปิดข้อมูลบนบัตรให้ครบ 3 ข้อ" }
        return "พร้อมอัปโหลด"
    }

    private var ready: Bool { hint == "พร้อมอัปโหลด" }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(hint).font(.sarabunFixed(13)).foregroundStyle(ready ? Theme.successText : Theme.inkMuted)
                .accessibilityIdentifier("pwaDocs.upload.hint")
            Spacer()
            Button("ยกเลิก") { dismiss() }.buttonStyle(TCButtonStyle(.secondary, size: .bar))
            Button("อัปโหลด") { upload() }
                .buttonStyle(TCButtonStyle(.primary, size: .bar))
                .disabled(!ready)
                .accessibilityIdentifier("pwaDocs.upload.go")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func imported(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bytes = try? Data(contentsOf: url) else { return }
        file = (bytes, url.pathExtension, url.lastPathComponent)
        source = .file
    }

    private func upload() {
        guard let kind, let file else { return }
        page.attach(file.data, ext: file.ext, kind: kind, stationID: kind.scope.isShared ? nil : stationID)
        dismiss()
    }
}

/// VisionKit's document camera: edges found and straightened, several pages, handed back as one PDF (nil when
/// cancelled or failed).
struct DocumentCamera: UIViewControllerRepresentable {
    let done: (Data?) -> Void

    static var isAvailable: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "pwaDocsCameraStub") { return true }
        #endif
        return VNDocumentCameraViewController.isSupported
    }

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: (Data?) -> Void
        init(done: @escaping (Data?) -> Void) { self.done = done }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pdf = PDFDocument()
            for i in 0..<scan.pageCount {
                if let page = PDFPage(image: scan.imageOfPage(at: i)) { pdf.insert(page, at: pdf.pageCount) }
            }
            done(pdf.dataRepresentation())
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { done(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { done(nil) }
    }

    #if DEBUG
    /// `-pwaDocsCameraStub YES`: a drawn one-page paper in place of a scan, for the simulator.
    static func stubPDF() -> Data {
        let size = CGSize(width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { ctx in
            ctx.beginPage()
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.lightGray.setFill()
            for i in 0..<12 { ctx.fill(CGRect(x: 60, y: 120 + i * 40, width: i % 3 == 0 ? 300 : 470, height: 10)) }
        }
    }
    #endif
}

/// A library paper (docs/ui/pwa-docs-ipad §8, `states/07`): its badge and pill, the stations using it, and the
/// download and the new file. Earlier versions and a zone choice have no model, so they are not shown.
struct PWALibrarySheet: View {
    let page: PWADocsPadView
    let data: PWADocsPadView.PageData
    let kind: StationDocs.Kind

    @Environment(\.dismiss) private var dismiss
    @State private var uploading = false
    @State private var shareFile: SharedLink?

    private var state: StationDocs.DocState { StationDocs.state(kind, station: .init(), library: data.library) }
    private var row: PWADocs.LibraryRow? { data.libraryRows.first { $0.kind.id == kind.id } }
    private var url: URL? { page.fileURL(kind, stationID: nil, name: state.fileName) }

    var body: some View {
        let used = PWADocs.usedIn(kind, data.stations)
        return VStack(spacing: 0) {
            head
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let note = kind.note { Text(note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted) }
                    if PWADocs.isIDCard(kind) {
                        Text("🔒 ก่อนแนบ ปิดศาสนา กรุ๊ปเลือด และวันเกิดบนบัตรทุกใบ | แอปไม่เก็บเลขบัตรเป็นข้อความ")
                            .font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.dangerText)
                    }
                    Text("ใช้ใน \(used.count) สถานี").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                    FlowLayout(spacing: 8) {
                        ForEach(used.prefix(6)) { st in
                            Text(st.ref + " " + st.shortName).font(.sarabunFixed(13, .semibold)).foregroundStyle(Theme.primary)
                                .padding(.horizontal, 10).frame(height: 30).background(Theme.primarySoft, in: Capsule())
                        }
                    }
                    if used.count > 6 {
                        Text("และอีก \(used.count - 6) สถานี").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Spacer()
                Button("ดาวน์โหลด") { if let url { shareFile = SharedLink(url: url) } }
                    .buttonStyle(TCButtonStyle(.secondary, size: .bar))
                    .disabled(url == nil)
                Button("อัปโหลดฉบับใหม่") { uploading = true }
                    .buttonStyle(TCButtonStyle(.primary, size: .bar))
                    .accessibilityIdentifier("pwaDocs.lib.upload")
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
        .frame(width: 600)
        .frame(minHeight: 420)
        .background(Theme.surface)
        .sheet(isPresented: $uploading) {
            PWADocsUploadSheet(page: page, data: data, stationID: nil, package: nil, preselected: kind.id).presentationSizing(.fitted)
        }
        .sheet(item: $shareFile) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
    }

    private var head: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(kind.scope.padBadge).font(.sarabunFixed(12, .heavy)).foregroundStyle(kind.scope.padBadgeInk)
                .frame(width: 46, height: 46).background(kind.scope.padBadgeFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.name).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy).lineLimit(2)
                if let row { Text(page.librarySub(row)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted).lineLimit(1) }
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let row {
                Text(row.pill.padTitle).font(.sarabunFixed(11.5, .bold)).foregroundStyle(row.pill.ink)
                    .padding(.horizontal, 8).frame(height: 22).background(row.pill.fill, in: Capsule())
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.navy)
                    .frame(width: 44, height: 44).background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ปิด")
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
