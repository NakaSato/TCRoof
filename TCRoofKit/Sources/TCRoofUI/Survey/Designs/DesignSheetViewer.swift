#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import TCRoofCore

/// A design's scanned sheet (docs/specs/standard-designs.md §3.4): its pages, swiped and pinched, to read the original
/// drawing's notes while checking. Pages not yet received from the other device say so.
struct DesignSheetViewer: View {
    let design: TankDesign
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(Array(design.sheet.enumerated()), id: \.offset) { i, p in
                    Group {
                        if let u = DesignLibrary.shared.sheetURL(p), let img = UIImage(contentsOfFile: u.path) {
                            ScrollView([.horizontal, .vertical]) {
                                Image(uiImage: img).resizable().scaledToFit()
                                    .frame(width: 900 * scale)
                            }
                            .gesture(MagnifyGesture().onChanged { scale = min(4, max(1, $0.magnification)) })
                        } else {
                            Text("หน้านี้ยังไม่ได้ดาวน์โหลด").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: design.sheet.count > 1 ? .always : .never))
            .background(Theme.paper)
            .navigationTitle(design.name + (design.sheet.count > 1 ? " · หน้า \(page + 1)/\(design.sheet.count)" : ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ปิด") { dismiss() } } }
        }
    }

    /// The pages of a PDF or one image, as JPEGs under ~700 KB (one Firestore document each).
    static func pages(from url: URL) -> [(Data, Int, Int)] {
        var images: [UIImage] = []
        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            for i in 0..<min(doc.pageCount, 12) {
                guard let p = doc.page(at: i) else { continue }
                let b = p.bounds(for: .mediaBox), k = 2000 / max(b.width, b.height)
                images.append(p.thumbnail(of: CGSize(width: b.width * k, height: b.height * k), for: .mediaBox))
            }
        } else if let img = UIImage(contentsOfFile: url.path) {
            images.append(img)
        }
        return images.compactMap { img in
            var side: CGFloat = 2000, q: CGFloat = 0.7
            while side >= 800 {
                let k = min(1, side / max(img.size.width, img.size.height))
                let size = CGSize(width: (img.size.width * k).rounded(), height: (img.size.height * k).rounded())
                let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
                if let d = small.jpegData(compressionQuality: q), d.count <= 700_000 { return (d, Int(size.width), Int(size.height)) }
                if q > 0.45 { q -= 0.1 } else { side -= 300 }
            }
            return nil
        }
    }
}
#endif
