#if canImport(UIKit) && DEBUG
import SwiftUI

/// Section 8 of the board (sections/08-tokens.png): colour swatches, type scale, spacing.
struct GalleryTokens: View {
    let swatches: [(String, String, Color, Bool)] = [
        ("#16325C", "navy · ข้อความหลัก", Theme.navy, true),
        ("#1F6FB5", "primary", Theme.primary, true),
        ("#2E8FDB", "primary-light", Theme.primaryLight, true),
        ("#E3EEF8", "primary-soft", Theme.primarySoft, false),
        ("#27A99A", "teal", Theme.teal, true),
        ("#9EE6D6", "mint · ค่าคำนวณ", Theme.mint, false),
        ("#3B7420", "ok / tick", Theme.okTick, true),
        ("#B45309", "pending", Theme.pending, true),
        ("#D9453B", "danger", Theme.danger, true),
        ("#5B6B82", "ink-muted", Theme.inkMuted, true),
        ("#DDE4ED", "border-subtle", Theme.borderSubtle, false),
        ("#F3F6FA", "background", Theme.background, false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GalleryGrid(columns: 6, phone: 2) {
                ForEach(swatches, id: \.1) { hex, name, color, dark in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(hex).font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(dark ? .white : Theme.navy)
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .bottomLeading)
                            .background(color, in: RoundedRectangle(cornerRadius: Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.borderSubtle))
                        Text(name).font(.sarabun(14)).foregroundStyle(Theme.inkMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            GalleryGrid(columns: 4, phone: 1) {
                Text("หัวหน้า \(Int(TypeScale.header))").font(.sarabun(TypeScale.header, .bold, relativeTo: .largeTitle))
                Text("ชื่อหน้า \(Int(TypeScale.pageTitle))").font(.sarabun(TypeScale.pageTitle, .bold, relativeTo: .title))
                Text("ป้ายช่อง \(Int(TypeScale.label))").font(.sarabun(TypeScale.label, .bold, relativeTo: .headline))
                Text("คำอธิบาย \(Int(TypeScale.caption)) · ระยะ 4/8/12/16/24 · มุม 8/10/12/16 · แตะได้ ≥ \(Int(touchMin)) pt")
                    .font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.navy)
        }
    }
}

#Preview("Tokens · iPad", traits: .landscapeLeft) {
    ScrollView { GallerySection(number: 8, title: "สีและตัวอักษร", subtitle: "Tokens") { GalleryTokens() }.padding() }
}

#Preview("Tokens · dark", traits: .landscapeLeft) {
    ScrollView { GallerySection(number: 8, title: "สีและตัวอักษร", subtitle: "Tokens") { GalleryTokens() }.padding() }
        .preferredColorScheme(.dark)
}
#endif
