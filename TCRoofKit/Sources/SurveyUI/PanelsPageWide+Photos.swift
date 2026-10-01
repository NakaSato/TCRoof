#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// B1's two photos: the wide one with the PV connection point dragged out on it, and the main breaker.
extension PanelsPageWide {
    func addPhoto(_ img: UIImage, to field: PhotoField) {
        guard let p = model.addPhoto(img, to: job.id) else { return }
        set(field.rawValue, .photo(p))
    }

    var pvPoint: SiteShape? { values.shapes(BuildingPanels.Key.pvPoint).first }

    var widePhotoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("ภาพมุมกว้างของตู้ไฟฟ้า", required: true, aside: "ใช้พิจารณาจุดเชื่อมต่อระบบโซลาร์")
            if values.photo(PhotoField.wide.rawValue) == nil {
                PhotoSlot(photo: nil, jobID: job.id, hint: "ถ่ายมุมกว้างให้เห็นทั้งตู้และช่องว่าง", required: true,
                          onPick: { addPhoto($0, to: .wide) }, onClear: {})
                    .frame(height: 330)
            } else {
                GeometryReader { geo in wideStage(geo.size) }
                    .frame(height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.15)))
            }
        }
    }

    var breakerPhotoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("ภาพเบรกเกอร์เมนของตู้", required: true, aside: "เห็นป้าย AT / รุ่น ชัด")
            PhotoSlot(photo: values.photo(PhotoField.breaker.rawValue), jobID: job.id, hint: "ถ่ายหน้าเบรกเกอร์ให้เห็นตัวเลขชัด",
                      required: true, onPick: { addPhoto($0, to: .breaker) },
                      onClear: { set(PhotoField.breaker.rawValue, nil) }, onOpen: { viewing = $0 })
                .frame(height: 250)
        }
    }

    func imageRect(_ img: UIImage, in size: CGSize) -> CGRect {
        guard img.size.width > 0, img.size.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let k = min(size.width / img.size.width, size.height / img.size.height)
        let w = img.size.width * k, h = img.size.height * k
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
    func fraction(_ p: CGPoint, in r: CGRect) -> ShapePoint { ShapePoint(Double((p.x - r.minX) / r.width), Double((p.y - r.minY) / r.height)) }

    @ViewBuilder func wideStage(_ size: CGSize) -> some View {
        let photo = values.photo(PhotoField.wide.rawValue)
        ZStack(alignment: .topLeading) {
            PhotoSlot.stageColor
            if let p = photo, let img = model.image(p, in: job.id) {
                let r = imageRect(img, in: size)
                Image(uiImage: img).resizable().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                pointDrawing(r).allowsHitTesting(false)
                Color.white.opacity(0.001).frame(width: size.width, height: size.height)
                    .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .local)
                        .onChanged { g in dragRect = (fraction(g.startLocation, in: r), fraction(g.location, in: r)) }
                        .onEnded { _ in savePoint() })
                    .accessibilityLabel("ภาพมุมกว้างของตู้ไฟฟ้า ลากเพื่อวงจุดเชื่อมต่อ PV")
            } else {
                PhotoSlot.notDownloaded
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) { if photo != nil { PhotoDoneBadge() } }
        .overlay(alignment: .topTrailing) { if photo != nil { PhotoClearButton(label: pvPoint != nil ? "ล้างจุดเชื่อมต่อ" : "ลบภาพ") { clearWide() } } }
        .overlay(alignment: .bottomLeading) {
            if photo != nil {
                Text(pvPoint == nil ? "แตะภาพเพื่อวงจุดเชื่อมต่อ" : "ลากใหม่เพื่อย้ายจุดเชื่อมต่อ")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Home.navy)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.95), in: Capsule()).padding(10).allowsHitTesting(false)
            }
        }
    }

    /// The saved point, or the one being dragged, drawn like the PDF.
    func pointDrawing(_ r: CGRect) -> some View {
        let box = Box(Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        var shape = pvPoint
        if let d = dragRect { shape = SiteShape(kind: .pvPoint, points: [d.0, d.1]) }
        shape?.label = BuildingPanels.pointLabel(values)
        let ops = shape.map { SiteShapes.ops([$0], in: box, metersAcross: nil) } ?? []
        return Canvas { ctx, _ in ctx.withCGContext { cg in PDFRenderer.draw(ops, in: cg, photo: { _ in nil }) } }
    }

    func savePoint() {
        defer { dragRect = nil }
        // too small to be a deliberate rectangle
        guard let d = dragRect, abs(d.0.x - d.1.x) > 0.02, abs(d.0.y - d.1.y) > 0.02 else { return }
        set(BuildingPanels.Key.pvPoint, .shapes([SiteShape(kind: .pvPoint, points: [d.0, d.1])]))
    }

    func clearWide() {
        if pvPoint != nil { set(BuildingPanels.Key.pvPoint, nil) } else { set(PhotoField.wide.rawValue, nil) }
    }
}
#endif
