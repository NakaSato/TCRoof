#if canImport(UIKit) && DEBUG
import SwiftUI

/// One board section: white card, radius 16, title `n · ชื่อ` over a rule.
struct GallerySection<Content: View>: View {
    let number: Int
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number) · \(title)").font(.sarabun(20, .bold)).foregroundStyle(Theme.navy)
                Text(subtitle).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSubtle).frame(height: 1) }
            content
        }
        .padding(.horizontal, 22).padding(.vertical, 20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Theme.borderSubtle))
    }
}

/// A labelled cell of the board: mono caps caption over the sample, optional note under it.
struct GalleryItem<Content: View>: View {
    let label: String
    var note: String?
    @ViewBuilder var content: Content

    init(_ label: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label; self.note = note; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)
            content
            if let note {
                Text(note).font(.sarabun(13)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A sub-heading inside a section (`สถานะของปุ่ม`).
struct GallerySubhead: View {
    let title: String
    var body: some View {
        Text(title).font(.sarabun(17, .bold)).foregroundStyle(Theme.navy)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Theme.borderSubtle).frame(height: 1).offset(y: -6) }
    }
}

/// Columns of the board: 4 on iPad, 1 on iPhone (or `phone` when given).
struct GalleryGrid<Content: View>: View {
    var columns = 4
    var phone = 1
    /// Fewer columns when the page is narrower than the board (iPad portrait): each needs this much.
    var minItem: CGFloat = 200
    @ViewBuilder var content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat = 0

    var body: some View {
        let fit = max(1, Int((width + 16) / (minItem + 16)))
        let n = sizeClass == .compact ? phone : min(columns, fit)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16, alignment: .topLeading), count: n),
                  alignment: .leading, spacing: 16) { content }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
#endif
