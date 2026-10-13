#if canImport(UIKit)
import SwiftUI

/// Parts of the PWA project home's overviews on iPhone (docs/ui/pwa-solar-survey-iphone-v2). No shadows.

/// A 44 pt capsule with a count: the stage pills (`counted`, equal widths, the count in a chip) and the
/// overviews' row filters (`plain`, 40 pt high in a 44 pt hit area, the count after the title).
public struct TCCountPill: View {
    public enum Style: Sendable { case counted, plain }

    let title: String
    let count: Int
    let selected: Bool
    let style: Style
    let action: () -> Void

    public init(_ title: String, count: Int, selected: Bool, style: Style = .counted, action: @escaping () -> Void) {
        self.title = title; self.count = count; self.selected = selected; self.style = style; self.action = action
    }

    public var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) \(count)")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var label: some View {
        switch style {
        case .counted:
            HStack(spacing: 5) {
                Text(title).font(.sarabunFixed(13, selected ? .bold : .semibold))
                Text("\(count)").font(.sarabunFixed(12, .bold)).monospacedDigit()
                    .foregroundStyle(selected ? Theme.onPrimary : Theme.navySolid)
                    .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                    .background(selected ? Theme.onPrimary.opacity(0.22) : Theme.hairline, in: Capsule())
            }
            .lineLimit(1).fixedSize()
            .foregroundStyle(selected ? Theme.onPrimary : Theme.navySolid)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Theme.navySolid : Theme.surface, in: Capsule())
            .overlay { if !selected { Capsule().strokeBorder(Theme.borderSubtle) } }
            .contentShape(Capsule())
        case .plain:
            Text("\(title) \(count)").font(.sarabunFixed(13, .bold)).monospacedDigit()
                .lineLimit(1).fixedSize()
                .foregroundStyle(selected ? Theme.onPrimary : Theme.navySolid)
                .padding(.horizontal, 12).frame(height: 40)
                .background(selected ? Theme.navySolid : Theme.surface, in: Capsule())
                .overlay { if !selected { Capsule().strokeBorder(Theme.borderSubtle) } }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}

/// A 64 pt progress ring with its percent in the middle, and a navy tick where the plan stands.
public struct TCPlanRing: View {
    let actual: Double
    let plan: Double?
    let tint: Color

    /// - Parameters:
    ///   - actual: 0…1, the arc and the centre text.
    ///   - plan: 0…1, the tick; nil for no tick.
    public init(actual: Double, plan: Double? = nil, tint: Color = Theme.primary) {
        self.actual = min(max(actual, 0), 1); self.plan = plan.map { min(max($0, 0), 1) }; self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Theme.borderSubtle, lineWidth: 7)
            Circle().trim(from: 0, to: actual).stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
            if let plan {
                Capsule().fill(Theme.navySolid).frame(width: 2.5, height: 11).offset(y: -26).rotationEffect(.degrees(plan * 360))
            }
            Text("\(Int((actual * 100).rounded()))%").font(.sarabunFixed(15, .bold)).monospacedDigit().foregroundStyle(Theme.navy)
        }
        .padding(3.5)
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }
}

/// An 8 pt progress bar with a 2 × 14 navy tick where the plan stands.
public struct TCPlanBar: View {
    let actual: Double
    let plan: Double?
    let tint: Color

    public init(actual: Double, plan: Double? = nil, tint: Color = Theme.primary) {
        self.actual = min(max(actual, 0), 1); self.plan = plan.map { min(max($0, 0), 1) }; self.tint = tint
    }

    public var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 8)
                Capsule().fill(tint).frame(width: max(g.size.width * actual, actual > 0 ? 8 : 0), height: 8)
                if let plan {
                    Rectangle().fill(Theme.navySolid).frame(width: 2, height: 14).offset(x: g.size.width * plan - 1)
                }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

/// A count over its label on a tint; nil tone is grey (`ออฟไลน์`).
public struct TCStatTile: View {
    let value: String
    let label: String
    let tone: TCFeedTone?

    public init(_ value: String, _ label: String, tone: TCFeedTone?) {
        self.value = value; self.label = label; self.tone = tone
    }

    public var body: some View {
        let c = tone?.tile ?? (Theme.hairline, Theme.inkMuted)
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.sarabunFixed(18, .bold)).monospacedDigit()
            Text(label).font(.sarabunFixed(11)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(c.1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(c.0, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// A small status capsule on a tint (`ช้ากว่า 12%`, `รายงานวันนี้ ✓`); nil tone is grey.
public struct TCToneChip: View {
    let text: String
    let tone: TCFeedTone?

    public init(_ text: String, tone: TCFeedTone?) { self.text = text; self.tone = tone }

    public var body: some View {
        let c = tone?.tile ?? (Theme.hairline, Theme.inkMuted)
        Text(text).font(.sarabunFixed(11, .bold)).lineLimit(1).fixedSize()
            .foregroundStyle(c.1)
            .padding(.horizontal, 8).frame(height: 18)
            .background(c.0, in: Capsule())
    }
}

/// A grouped card of a settings page: a 12 pt title over `TCSettingsRow`s, with hairlines between them.
public struct TCSettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted).padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            // each row draws a hairline on its top edge; the first one's is pushed out under the clip
            VStack(spacing: 0) { content }
                .padding(.top, -1)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
        }
    }
}

/// One row of `TCSettingsGroup`: a title over a detail line, then a chevron, a pill or a switch.
public struct TCSettingsRow<Trailing: View>: View {
    let title: String
    let detail: String
    let trailing: Trailing

    public init(_ title: String, detail: String = "", @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.detail = detail; self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sarabunFixed(15)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.85)
                if !detail.isEmpty {
                    Text(detail).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .padding(.top, 1)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

public extension TCSettingsRow where Trailing == TCSettingsChevron {
    /// A row that opens something: a chevron at the end.
    init(_ title: String, detail: String = "") { self.init(title, detail: detail) { TCSettingsChevron() } }
}

public struct TCSettingsChevron: View {
    public init() {}
    public var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chevron)
            .accessibilityHidden(true)
    }
}
#endif
