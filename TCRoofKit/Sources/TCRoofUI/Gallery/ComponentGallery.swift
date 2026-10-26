#if canImport(UIKit) && DEBUG
import SwiftUI

/// Every component in every state, laid out like the board `คอมโพเนนต์ iPad` (docs/ui/components/sections).
/// DEBUG only; the visual test of the library. Open it from Settings, or launch with `-screen components`.
public struct ComponentGallery: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Opens with only this section (1–9), for screenshots.
    var only: Int?

    public init(only: Int? = nil) { self.only = only }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if show(1) { GallerySection(number: 1, title: "โครงหน้า", subtitle: "Layout") { GalleryLayout() } }
                if show(2) { GallerySection(number: 2, title: "ปุ่ม", subtitle: "Buttons | สูง ≥ 44 pt") { GalleryButtons() } }
                if show(3) { GallerySection(number: 3, title: "ช่องกรอกข้อมูล", subtitle: "Inputs") { GalleryInputs() } }
                if show(4) { GallerySection(number: 4, title: "สถานะและข้อความแจ้ง", subtitle: "Status & feedback") { GalleryStatus() } }
                if show(5) { GallerySection(number: 5, title: "การ์ดและรายการ", subtitle: "Cards & lists") { GalleryCards() } }
                if show(6) { GallerySection(number: 6, title: "ภาพ แผนที่ และแบบ", subtitle: "Media") { GalleryMedia() } }
                if show(7) { GallerySection(number: 7, title: "หน้าต่างซ้อน และการแจ้งเตือน", subtitle: "Overlays") { GalleryOverlays() } }
                if show(8) { GallerySection(number: 8, title: "สีและตัวอักษร", subtitle: "Tokens (tcroofsurvey)") { GalleryTokens() } }
                if show(9) { GallerySection(number: 9, title: "ป้อนตัวเลข", subtitle: "Number input popup | แป้นตัวเลขแบบ popover") { GalleryNumberPad() } }
            }
            .padding(sizeClass == .compact ? 16 : 24)
        }
        // `-galleryBottom YES`: open scrolled to the end, for screenshots of tall sections
        .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "galleryBottom") ? .bottom : .top)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("คอมโพเนนต์")
        .navigationBarTitleDisplayMode(.inline)
    }

    func show(_ n: Int) -> Bool { only == nil || only == n }
}

#Preview("Gallery | iPad", traits: .landscapeLeft) {
    NavigationStack { ComponentGallery() }
}

#Preview("Gallery | iPhone") {
    NavigationStack { ComponentGallery() }
}
#endif
