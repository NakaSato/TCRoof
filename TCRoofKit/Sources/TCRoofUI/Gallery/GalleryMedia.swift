#if canImport(UIKit) && DEBUG
import SwiftUI

/// Section 6 of the board (sections/06-media.png).
struct GalleryMedia: View {
    @State var hasPhoto = true
    @State var layer = 1
    @State var playing = false
    @State var view = 0
    @State var heading = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GalleryGrid(columns: 3, phone: 1) {
                GalleryItem("ช่องภาพ | ว่าง") {
                    TCPhotoSlot(hint: "ถ่ายหน้าเบรกเกอร์ให้เห็นตัวเลข AT ชัด", filled: false,
                                onUpload: { hasPhoto = true }, onCamera: { hasPhoto = true }, onDelete: {}) { EmptyView() }
                }
                GalleryItem("ช่องภาพ | มีภาพ + overlay") {
                    TCPhotoSlot(hint: "ถ่ายหน้าเบรกเกอร์ให้เห็นตัวเลข AT ชัด", filled: hasPhoto, caption: "ตัวเครื่อง | 30/9 10:22",
                                mark: .init(title: "จุดเชื่อมต่อ PV", rect: CGRect(x: 0.52, y: 0.58, width: 0.4, height: 0.37)),
                                onUpload: { hasPhoto = true }, onCamera: { hasPhoto = true }, onDelete: { hasPhoto = false }) {
                        Rectangle().fill(Theme.photoPlaceholder)
                    }
                }
                GalleryItem("แผนที่ + ระดับ + ซูม") {
                    SampleMap()
                        .frame(height: 150)
                        .overlay { TCMapControls(layer: $layer, scale: "50 ม.", onZoomIn: {}, onZoomOut: {}) }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.borderSubtle))
                }
            }
            GalleryGrid(columns: 4, phone: 2) {
                GalleryItem("เข็มทิศ", note: "แตะเพื่อหมุน 30°") {
                    TCCompass(heading: heading).onTapGesture { withAnimation { heading += 30 } }
                }
                GalleryItem("เล่นแอนิเมชันเงา") {
                    HStack(spacing: Space.l) {
                        TCPlayPauseButton(playing: .constant(false))
                        TCPlayPauseButton(playing: .constant(true))
                    }
                }
                GalleryItem("เต็มจอ") { TCFullscreenButton {} }
                GalleryItem("Segmented ขนาดเล็ก") { TCSmallSegmented(selection: $view) }
            }
        }
    }
}

/// A drawn stand-in for a map: land, two roads, a building and a red pin.
struct SampleMap: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.mapLand))
            var road = Path()
            road.move(to: CGPoint(x: size.width * 0.38, y: 0))
            road.addLine(to: CGPoint(x: size.width * 0.52, y: size.height))
            road.move(to: CGPoint(x: 0, y: size.height * 0.62))
            road.addLine(to: CGPoint(x: size.width, y: size.height * 0.52))
            ctx.stroke(road, with: .color(.white), lineWidth: 10)
            let b = CGRect(x: size.width * 0.5, y: size.height * 0.33, width: size.width * 0.22, height: size.height * 0.22)
            ctx.fill(Path(b), with: .color(Theme.borderSubtle))
            ctx.stroke(Path(b), with: .color(Theme.muted.opacity(0.6)), lineWidth: 1)
            let p = CGPoint(x: b.midX, y: b.midY + 8)
            var pin = Path()
            pin.move(to: p)
            pin.addCurve(to: CGPoint(x: p.x, y: p.y - 26), control1: CGPoint(x: p.x - 12, y: p.y - 12), control2: CGPoint(x: p.x - 12, y: p.y - 26))
            pin.addCurve(to: p, control1: CGPoint(x: p.x + 12, y: p.y - 26), control2: CGPoint(x: p.x + 12, y: p.y - 12))
            ctx.fill(pin, with: .color(Theme.danger))
        }
        .accessibilityHidden(true)
    }
}

#Preview("Media | iPad", traits: .landscapeLeft) {
    ScrollView { GallerySection(number: 6, title: "ภาพ แผนที่ และแบบ", subtitle: "Media") { GalleryMedia() }.padding() }
}

#Preview("Media | iPhone") {
    ScrollView { GallerySection(number: 6, title: "ภาพ แผนที่ และแบบ", subtitle: "Media") { GalleryMedia() }.padding() }
        .environment(\.horizontalSizeClass, .compact)
}
#endif
