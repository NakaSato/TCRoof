import SwiftUI
import SwiftData
import PDFKit
import UIKit
import TCRoofUI
import TCRoofCore

/// The SLD of step 1: each upload is a job document under `IEC 62446/แบบ SLD` (so it goes to Drive with the rest),
/// the newest being the current one; the report keeps which and which version (`IECReport.sld`).
extension Job {
    static let sldFolder = "IEC 62446/แบบ SLD"

    /// Every uploaded SLD, oldest first.
    var iecSLDVersions: [DocumentAsset] {
        documents.filter { $0.folderPath == Self.sldFolder }.sorted { $0.addedAt < $1.addedAt }
    }

    var iecSLD: DocumentAsset? { iecSLDVersions.last }

    /// A new upload: kept beside the older ones (never replacing them).
    func storeSLD(_ data: Data, name: String, context: ModelContext) {
        let doc = DocumentAsset(name: name, data: data)
        doc.folderPath = Self.sldFolder
        context.insert(doc)
        doc.job = self
        let version = iecSLDVersions.count
        updateIEC(context) { $0.sld = .init(name: name, version: version, at: doc.addedAt) }
    }
}

enum SLDFile {
    static func isPDF(_ data: Data) -> Bool { data.prefix(4) == Data("%PDF".utf8) }

    static func pageCount(_ data: Data) -> Int { isPDF(data) ? (PDFDocument(data: data)?.pageCount ?? 1) : 1 }

    /// The first page (PDF) or the photo, scaled down for the card.
    static func preview(_ data: Data, width: CGFloat = 900) -> UIImage? {
        if isPDF(data), let page = PDFDocument(data: data)?.page(at: 0) {
            let box = page.bounds(for: .mediaBox)
            return page.thumbnail(of: CGSize(width: width, height: width * box.height / max(box.width, 1)), for: .mediaBox)
        }
        return UIImage(data: data)
    }
}

/// The SLD full screen: a PDF scrolls and zooms in PDFKit, a photo pinches.
struct SLDViewer: View {
    let doc: DocumentAsset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.mediaBackdrop.ignoresSafeArea()
            if SLDFile.isPDF(doc.data) { PDFKitView(data: doc.data).ignoresSafeArea(edges: .bottom) }
            else if let img = UIImage(data: doc.data) { IECZoomableImage(image: img) }
            HStack(spacing: 12) {
                Text(doc.name).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.onPrimary).lineLimit(1)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 44, height: 44).background(Theme.navy.opacity(0.6), in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("ปิด")
            }
            .padding(20)
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = PDFDocument(data: data)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

/// Reads a serial from a nameplate photo (`สแกนป้าย`, the instruments' `สแกน`): the camera, the photo text reader,
/// then `IECReport.serialCandidate`. With `-iecCameraStub` it reads a drawn plate.
struct IECSerialScanner: ViewModifier {
    @Binding var active: Bool
    let found: (String?) -> Void
    @State private var camera = false

    func body(content: Content) -> some View {
        content
            .onChange(of: active) { _, on in
                guard on else { return }
                active = false
                if IECCamera.stub { found(IECReport.serialCandidate(in: "S/N: TCR2026SN01")) }
                else if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true }
                else { found(nil) }
            }
            .fullScreenCover(isPresented: $camera) {
                StampedCamera { data in
                    Task {
                        guard let img = UIImage(data: data) else { found(nil); return }
                        found(IECReport.serialCandidate(in: await PlatePhotoReader.text(in: img)))
                    }
                }
            }
    }
}

#if DEBUG
extension Job {
    /// `-iecDemo praek` (with `-iecStep 1`): the sample with the board's inverter models and MPPT counts, and a drawn SLD.
    func seedIECStep1Demo(context: ModelContext) {
        guard var r = iecReport else { return }
        let models = [("Growatt MAX 125KTL3-X LV", 10), ("Growatt MAX 60KTL3 LV", 6)]
        for (i, m) in models.enumerated() where r.inverters.indices.contains(i) { r.inverters[i].model = m.0; r.inverters[i].mppt = m.1 }
        iecReport = r
        for d in iecSLDVersions { context.delete(d) }
        // saved first, or the deleted ones still count and the new one isn't made
        try? context.save()
        seedDemoSLD(context: context)
        try? context.save()
    }

    /// The demo's SLD: a drawn two-page single line diagram (inverters, strings, boards), labelled as a sample.
    func seedDemoSLD(context: ModelContext) {
        // one from an earlier run: the (replaced) test points at it again
        if let doc = iecSLD {
            let n = iecSLDVersions.count
            updateIEC(context) { $0.sld = .init(name: doc.name, version: n, at: doc.addedAt) }
            return
        }
        let size = CGRect(x: 0, y: 0, width: 842, height: 595)
        let data = UIGraphicsPDFRenderer(bounds: size).pdfData { ctx in
            for page in 1...2 {
                ctx.beginPage()
                let g = ctx.cgContext
                g.setStrokeColor(UIColor.darkGray.cgColor); g.setLineWidth(1)
                g.stroke(size.insetBy(dx: 20, dy: 20))
                for k in 0..<(page == 1 ? 16 : 8) {
                    let x = 60 + CGFloat(k) * 44
                    g.stroke(CGRect(x: x, y: 380, width: 30, height: 60))
                    g.move(to: CGPoint(x: x + 15, y: 380)); g.addLine(to: CGPoint(x: x + 15, y: 300)); g.strokePath()
                }
                g.move(to: CGPoint(x: 60, y: 300)); g.addLine(to: CGPoint(x: 760, y: 300)); g.strokePath()
                g.stroke(CGRect(x: 360, y: 160, width: 120, height: 80))
                g.move(to: CGPoint(x: 420, y: 240)); g.addLine(to: CGPoint(x: 420, y: 300)); g.strokePath()
                ("SLD Inverter \(page) (sample)" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
            }
        }
        storeSLD(data, name: "Inverter_SLD_test_IEC_report.pdf", context: context)
    }
}
#endif
