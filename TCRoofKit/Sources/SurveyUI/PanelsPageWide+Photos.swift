#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import PDFReport

/// B1's two photos: the wide one with the PV connection point dragged out on it, and the main breaker.
extension PanelsPageWide {
    func addPhoto(_ img: UIImage) {
        guard let p = model.addPhoto(img, to: job.id) else { return }
        set(pickTarget.rawValue, .photo(p))
    }

    var pvPoint: SiteShape? { values.shapes(BuildingPanels.Key.pvPoint).first }

    var widePhotoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("ภาพมุมกว้างของตู้ไฟฟ้า", required: true, aside: "ใช้พิจารณาจุดเชื่อมต่อระบบโซลาร์")
            GeometryReader { geo in wideStage(geo.size) }
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.15)))
        }
    }

    var breakerPhotoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("ภาพเบรกเกอร์เมนของตู้", required: true, aside: "เห็นป้าย AT / รุ่น ชัด")
            breakerStage
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
            Color(red: 0.91, green: 0.933, blue: 0.961)
            if let p = photo, let img = model.image(p, in: job.id) {
                let r = imageRect(img, in: size)
                Image(uiImage: img).resizable().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                pointDrawing(r).allowsHitTesting(false)
                Color.white.opacity(0.001).frame(width: size.width, height: size.height)
                    .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .local)
                        .onChanged { g in dragRect = (fraction(g.startLocation, in: r), fraction(g.location, in: r)) }
                        .onEnded { _ in savePoint() })
                    .accessibilityLabel("ภาพมุมกว้างของตู้ไฟฟ้า ลากเพื่อวงจุดเชื่อมต่อ PV")
            } else if photo != nil {
                Label("ภาพนี้อยู่ในอีกเครื่อง ยังไม่ได้ดาวน์โหลด", systemImage: "icloud.and.arrow.down")
                    .font(.callout).foregroundStyle(Home.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyPhoto(.wide, text: "ถ่ายมุมกว้างให้เห็นทั้งตู้และช่องว่าง").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) { if photo != nil { doneBadge } }
        .overlay(alignment: .topTrailing) { if photo != nil { clearButton(pvPoint != nil ? "ล้างจุดเชื่อมต่อ" : "ลบภาพ") { clearWide() } } }
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

    @ViewBuilder var breakerStage: some View {
        let photo = values.photo(PhotoField.breaker.rawValue)
        if let p = photo {
            ZStack {
                Color(red: 0.91, green: 0.933, blue: 0.961)
                if let img = model.image(p, in: job.id) {
                    Button { viewing = p } label: { Image(uiImage: img).resizable().scaledToFit() }
                        .buttonStyle(.plain).accessibilityLabel("ภาพเบรกเกอร์เมน แตะเพื่อดูเต็มจอ")
                } else {
                    Label("ภาพนี้อยู่ในอีกเครื่อง ยังไม่ได้ดาวน์โหลด", systemImage: "icloud.and.arrow.down").font(.callout).foregroundStyle(Home.muted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.navy.opacity(0.15)))
            .overlay(alignment: .topLeading) { doneBadge }
            .overlay(alignment: .topTrailing) { clearButton("ลบภาพ") { set(PhotoField.breaker.rawValue, nil) } }
        } else {
            emptyPhoto(.breaker, text: "ถ่ายหน้าเบรกเกอร์ให้เห็นตัวเลขชัด")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Home.danger, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        }
    }

    func emptyPhoto(_ field: PhotoField, text: String) -> some View {
        VStack(spacing: 14) {
            Text(text).font(.system(size: 15)).foregroundStyle(Home.muted)
            HStack(spacing: 10) {
                photoButton("อัปโหลด", icon: "ui-upload-photo", fallback: "photo") { pickTarget = field; showPicker = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    photoButton("กล้อง", icon: "ui-camera", fallback: "camera") { pickTarget = field; showCamera = true }
                }
            }
        }
        .padding()
    }

    func photoButton(_ title: String, icon: String, fallback: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                A2Icon(name: icon, fallback: fallback, size: 18)
                Text(title).font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Home.navy)
            .frame(width: 150, height: 46)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Home.navy.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }

    var doneBadge: some View {
        A2Icon(name: "b1-photo-done", fallback: "checkmark.circle.fill", size: 28).foregroundStyle(Home.ok)
            .padding(10).allowsHitTesting(false).accessibilityHidden(true)
    }

    func clearButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            A2Icon(name: "b1-photo-clear", fallback: "xmark.circle.fill", size: 28)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(4)
        .accessibilityLabel(label)
    }
}
#endif
