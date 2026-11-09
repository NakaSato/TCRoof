#if canImport(UIKit)
import SwiftUI

/// Loading skeletons: grey blocks in the shape of what is being fetched, with a light sweep across them, in place of a
/// spinner. With Reduce Motion they stay still. VoiceOver reads one `กำลังโหลดข้อมูล` per skeleton.

/// One grey block: a line of text (12 pt high) or, taller, a chart or a picture. Without a width it fills the row.
public struct TCSkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat

    public init(width: CGFloat? = nil, height: CGFloat = 12, radius: CGFloat = 4) {
        self.width = width; self.height = height; self.radius = radius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.borderSubtle)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// A card of skeleton lines: a title, `lines` lines of text (the last one shorter) and, with `block`, a chart-sized
/// block, on `Theme.surface`.
public struct TCSkeletonCard: View {
    var lines: Int
    var block: CGFloat?
    var padding: CGFloat

    public init(lines: Int = 2, block: CGFloat? = nil, padding: CGFloat = 14) {
        self.lines = lines; self.block = block; self.padding = padding
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TCSkeletonBlock(width: 150, height: 16, radius: 5)
            ForEach(0..<max(lines, 1), id: \.self) { i in
                TCSkeletonBlock(width: i == lines - 1 ? 180 : nil)
            }
            if let block { TCSkeletonBlock(height: block, radius: 8) }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcShimmer()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        .tcLoadingLabel()
    }
}

/// A single-line diagram in outline while it is drawn: a feed line down through three boxes to a busbar with four
/// branches, scaled to fit and centred. At least 160 pt high.
public struct TCSkeletonDiagram: View {
    public init() {}

    public var body: some View {
        SkeletonDiagramShape()
            .fill(Theme.borderSubtle)
            .tcShimmer()
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            .tcLoadingLabel()
    }
}

private struct SkeletonDiagramShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // the outline is 10 units wide and 7.3 high
        let u = min(r.width / 10, r.height / 8, 48)
        let line = max(u * 0.08, 2)
        let corner = CGSize(width: u * 0.15, height: u * 0.15)
        let cx = r.midX, top = r.midY - 3.65 * u
        for i in 0..<3 {
            let y = top + CGFloat(i) * 2 * u
            p.addRoundedRect(in: CGRect(x: cx - 0.7 * u, y: y, width: 1.4 * u, height: u), cornerSize: corner)
            p.addRect(CGRect(x: cx - line / 2, y: y + u, width: line, height: u))
        }
        let bus = top + 6 * u
        p.addRect(CGRect(x: cx - 4 * u, y: bus, width: 8 * u, height: line * 1.5))
        for i in 0..<4 {
            let x = cx - 3 * u + CGFloat(i) * 2 * u
            p.addRect(CGRect(x: x - line / 2, y: bus, width: line, height: 0.5 * u))
            p.addRoundedRect(in: CGRect(x: x - 0.5 * u, y: bus + 0.5 * u, width: u, height: 0.8 * u), cornerSize: corner)
        }
        return p
    }
}

/// A list row in outline: a round avatar (or none) and two lines, at least 44 pt high, for lists of people or records.
public struct TCSkeletonRow: View {
    var avatar: Bool

    public init(avatar: Bool = true) { self.avatar = avatar }

    public var body: some View {
        HStack(spacing: 12) {
            if avatar { Circle().fill(Theme.borderSubtle).frame(width: 36, height: 36) }
            VStack(alignment: .leading, spacing: 7) {
                TCSkeletonBlock(width: 160, height: 13)
                TCSkeletonBlock(width: 110, height: 10)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 6)
        .tcShimmer()
        .tcLoadingLabel()
    }
}

public extension View {
    /// The skeleton sweep over this view's own shapes (only where it draws), while `active`.
    func tcShimmer(_ active: Bool = true) -> some View { modifier(TCShimmer(active: active)) }

    /// One VoiceOver element, `กำลังโหลดข้อมูล`, for a skeleton made of several blocks.
    func tcLoadingLabel() -> some View {
        accessibilityElement(children: .ignore).accessibilityLabel("กำลังโหลดข้อมูล")
    }
}

/// A light band sweeping left to right every 1.3 s, masked to the content.
struct TCShimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                // the timeline drives the sweep, so no animation leaks into the page's own layout
                TimelineView(.animation) { context in
                    GeometryReader { geo in
                        let w = geo.size.width
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.3) / 1.3
                        LinearGradient(colors: [.clear, Theme.surface.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: w * 0.5)
                            .offset(x: -w * 0.5 + CGFloat(t) * w * 1.5)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}
#endif
