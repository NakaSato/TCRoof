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
