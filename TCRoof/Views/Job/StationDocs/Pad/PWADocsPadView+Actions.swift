import SwiftUI
import PDFKit
import TCRoofUI
import TCRoofCore

// What the iPad page's sheets change: a paper's state and file, its reminders, and the station's merged PDF. Site
// papers live on the job (`Job.stationDocs`, the file in its documents, so it goes to Drive with the job); shared
// papers in the device library (`StationDocsStore`). With `-pwaDocsDemo YES` the example changes in memory only.

extension PWADocsPadView {

    func kind(_ ref: PaperRef) -> StationDocs.Kind? { StationDocs.kind(ref.kindID) }

    func state(_ kind: StationDocs.Kind, stationID: String?, _ data: PageData) -> StationDocs.DocState {
        StationDocs.state(kind, station: data.station(stationID)?.docs ?? .init(), library: data.library)
    }

    /// Changes one paper and stamps it updated. Never for a contractor (`readOnly`).
    func update(_ kind: StationDocs.Kind, stationID: String?, _ change: (inout StationDocs.DocState) -> Void) {
        guard !readOnly else { return }
        let data = self.data
        var s = state(kind, stationID: stationID, data)
        change(&s)
        s.updatedAt = .now
        if kind.scope.isShared {
            if isDemo {
                var lib = data.library
                lib.docs[kind.id] = s
                demoLibrary = lib
            } else {
                library.docs[kind.id] = s
                StationDocsStore.save(library)
            }
        } else if let id = stationID {
            if isDemo {
                guard var st = data.station(id)?.docs else { return }
                st.docs[kind.id] = s
                demoEdits[id] = st
            } else if let job = job(id) {
                var st = job.stationDocs
                st.docs[kind.id] = s
                job.stationDocs = st
            }
        }
    }

    /// Keeps an uploaded file as the paper's, in place of the one before, and moves the paper on
    /// (`PWADocs.statusAfterUpload`). Nothing is kept for the example.
    func attach(_ file: Data, ext: String, kind: StationDocs.Kind, stationID: String?) {
        guard !readOnly else { return }
        let data = self.data
        let old = state(kind, stationID: stationID, data).fileName
        let ext = ext.isEmpty ? "pdf" : ext.lowercased()
        var name: String?
        if isDemo {
            name = kind.id + "." + ext
        } else if kind.scope.isShared {
            name = StationDocsStore.keepFile(file, kindID: kind.id, ext: ext)
        } else if let job = job(stationID) {
            if let old, let doc = job.documents.first(where: { $0.name == old }) { job.modelContext?.delete(doc) }
            name = HomeArchive.keep(file, name: HomeArchive.name("\(job.code) \(kind.name)", ext: ext), job: job)?.name
        }
        guard let name else { notice = "เก็บไฟล์ไม่สำเร็จ"; return }
        update(kind, stationID: stationID) {
            $0.fileName = name
            $0.status = PWADocs.statusAfterUpload(kind, $0.status)
        }
    }

    /// A drafted paper (the outage letter) becomes the paper's file, as `StationDocSheet.keepDraft`.
    func keepDraft(_ file: Data, kind: StationDocs.Kind, stationID: String?) {
        guard !readOnly else { return }
        let old = state(kind, stationID: stationID, data).fileName
        guard let job = job(stationID) else { return }
        let name = HomeArchive.name("\(job.code) \(kind.name)", ext: "pdf")
        guard let kept = HomeArchive.keep(file, name: name, job: job)?.name else { return }
        if let old, old != kept, let doc = job.documents.first(where: { $0.name == old }) { job.modelContext?.delete(doc) }
        update(kind, stationID: stationID) {
            $0.fileName = kept
            $0.status = .draft
        }
    }

    /// The paper's file as a local URL, for the preview and the share sheet.
    func fileURL(_ kind: StationDocs.Kind, stationID: String?, name: String?) -> URL? {
        guard let name else { return nil }
        if kind.scope.isShared { return StationDocsStore.fileURL(name) }
        guard let doc = job(stationID)?.documents.first(where: { $0.name == name }) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(doc.name)
        try? doc.data.write(to: url)
        return url
    }

    /// `ทวง`: counts one more reminder and returns the message for the share sheet. The app sends nothing itself.
    func remind(_ kind: StationDocs.Kind, stationID: String?) -> String {
        update(kind, stationID: stationID) { $0.reminders.append(.now) }
        let data = self.data
        let st = data.station(stationID)
        var lines = ["ขอติดตามเอกสาร: " + kind.name]
        if let st { lines.append("สถานี: " + st.ref + " " + st.name) }
        if let st, let due = due(kind, st) { lines.append("ครบกำหนด " + PWAPlanFormat.numeric.string(from: due)) }
        lines.append("ขอบคุณครับ")
        return lines.joined(separator: "\n")
    }

    /// The earliest due day of the packages the paper is in, for this station.
    func due(_ kind: StationDocs.Kind, _ st: PWAPlan.Station) -> Date? {
        let packages = StationDocs.packages(st.docsContext)
        return kind.packages.filter(packages.contains).compactMap { PWADocs.due($0, st) }.min()
    }

    /// `รวมชุดเอกสาร PDF`: every approved file of the station in catalog order, PDFs page by page and pictures a page
    /// each, then the share sheet.
    func mergePDF(_ st: PWAPlan.Station, data: PageData) {
        let merged = PDFDocument()
        for kind in PWADocs.stationPapers(st.docsContext) {
            let s = StationDocs.state(kind, station: st.docs, library: data.library)
            guard s.status == .approved, let url = fileURL(kind, stationID: st.id, name: s.fileName) else { continue }
            if let pdf = PDFDocument(url: url) {
                for i in 0..<pdf.pageCount { if let p = pdf.page(at: i) { merged.insert(p, at: merged.pageCount) } }
            } else if let image = UIImage(contentsOfFile: url.path), let page = PDFPage(image: image) {
                merged.insert(page, at: merged.pageCount)
            }
        }
        guard merged.pageCount > 0 else { notice = "ยังไม่มีไฟล์ที่อนุมัติแล้วของสถานีนี้"; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(st.ref) ชุดเอกสาร.pdf")
        guard merged.write(to: url) else { notice = "รวมไฟล์ไม่สำเร็จ"; return }
        share = SharedLink(url: url)
    }
}

/// The page's sheets, kept out of its body (the Debug type-check limit).
struct PWADocsPadSheets: ViewModifier {
    let page: PWADocsPadView
    let data: PWADocsPadView.PageData

    func body(content: Content) -> some View {
        content
            .sheet(item: page.$paper) { ref in
                if let kind = page.kind(ref) {
                    PWADocSheetPad(page: page, data: data, kind: kind, stationID: ref.stationID)
                        .presentationSizing(.fitted)
                }
            }
            .sheet(item: page.$upload) { ref in
                PWADocsUploadSheet(page: page, data: data, stationID: ref.stationID, package: ref.package, preselected: ref.kindID)
                    .presentationSizing(.fitted)
            }
            .sheet(item: page.$libraryPaper) { ref in
                if let kind = page.kind(ref) {
                    PWALibrarySheet(page: page, data: data, kind: kind).presentationSizing(.fitted)
                }
            }
            .sheet(item: page.$share) { ActivitySheet(items: [$0.url]).presentationDetents([.medium, .large]) }
            .alert(page.notice ?? "", isPresented: Binding(get: { page.notice != nil }, set: { if !$0 { page.notice = nil } })) {
                Button("ตกลง", role: .cancel) {}
            }
    }
}

/// `ลำดับ กกพ.` of one station, pushed from the พค.2 drill-down.
struct PWADocsERCScreen: View {
    @Bindable var job: Job
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PadForm {
            ERCFlowRows(job: job, library: StationDocsStore.loadLibrary()) { _ in dismiss() }
        }
        .navigationTitle("ลำดับ กกพ.")
        .navigationBarTitleDisplayMode(.inline)
    }
}
