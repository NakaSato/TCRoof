import SwiftUI
import UIKit
import Vision
import VisionKit
import TCRoofCore

/// Reads the text on a receipt or odometer photo on the device (Thai and English when the system has them).
enum TextReader {
    static func read(_ data: Data) async -> String {
        guard let image = UIImage(data: data)?.cgImage else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            request.recognitionLanguages = ["th-TH", "en-US"].filter { supported.contains($0) }
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            // top to bottom, so the vendor's name comes first
            let lines = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            return lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

/// The system document camera: crops and flattens each receipt, several in one go (§B4). Each page comes back as a
/// JPEG at most 1600 px on its long side.
struct ReceiptScanner: UIViewControllerRepresentable {
    let onScan: ([Data]) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: ReceiptScanner
        init(_ parent: ReceiptScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).compactMap { ReceiptImage.jpeg(scan.imageOfPage(at: $0)) }
            parent.onScan(pages)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.dismiss() }
    }
}

enum ReceiptImage {
    static let maxSide: CGFloat = 1600

    static func jpeg(_ image: UIImage) -> Data? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.75)
    }

    static func jpeg(_ data: Data) -> Data { UIImage(data: data).flatMap(jpeg) ?? data }

    #if DEBUG
    /// A drawn receipt for the simulator (`-travelReceiptStub YES`), which has no camera: the text reader reads it.
    static func stub(_ n: Int = 0) -> Data {
        let samples = [
            ["สถานีบริการน้ำมัน PTT สาขาโคราช", "เลขประจำตัวผู้เสียภาษี 0107561000013", "15/10/2569 09:42", "ดีเซล B7 32.50 ลิตร",
             "รวมเงิน 1,038.05", "เงินสด 1,100.00"],
            ["การทางพิเศษแห่งประเทศไทย", "ด่านเก็บเงินบางนา", "15/10/2569", "จำนวนเงิน 50.00 บาท"],
        ]
        let lines = samples[n % samples.count]
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for (i, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 60, y: 80 + CGFloat(i) * 110),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: 46, weight: i == 0 ? .bold : .regular),
                                                         .foregroundColor: UIColor.black])
            }
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }
    #endif
}
