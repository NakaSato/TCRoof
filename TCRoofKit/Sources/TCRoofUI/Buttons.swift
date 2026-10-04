#if canImport(UIKit)
import SwiftUI
import UIKit

/// Section 2 · Buttons (docs/ui/components/sections/02-buttons.png).
public enum TCButtonKind: CaseIterable, Sendable {
    /// Solid #1F6FB5.
    case primary
    /// #1F6FB5 → #2E8FDB.
    case primaryGradient
    /// #27A99A → #4DB6E0, the survey module.
    case tealGradient
    /// White, navy outline.
    case secondary
    /// Outline, danger text.
    case destructive
    /// Blue text, no frame.
    case text
    /// Dashed outline, `+ เพิ่ม…`.
    case dashedAdd
    /// Solid danger, only inside confirm dialogs.
    case danger
}

public enum TCButtonSize: Sendable {
    /// Primary in a page: iPad 52 · r12 · 16 pt, hugs content; iPhone 48 · r10 · 15 pt, full width.
    case page
    /// Inside a card: 44 · r10 · 14 pt.
    case card
    /// Bottom bar: 53 · r10 · 16 pt.
    case bar

    func height(compact: Bool) -> CGFloat {
        switch self {
        case .page: compact ? 48 : 52
        case .card: 44
        case .bar: 53
        }
    }
    func radius(compact: Bool) -> CGFloat {
        switch self {
        case .page: compact ? Radius.md : Radius.lg
        case .card, .bar: Radius.md
        }
    }
    func fontSize(compact: Bool) -> CGFloat {
        switch self {
        case .page: compact ? 15 : 16
        case .card: 14
        case .bar: 16
        }
    }
}

/// The look of every `TCButton`: fill, border and text per kind; pressed = darker and 2 % smaller;
/// disabled = grey; working = a spinner and no taps.
public struct TCButtonStyle: ButtonStyle {
    public var kind: TCButtonKind
    public var size: TCButtonSize
    /// Stretch to the width offered (iPhone page buttons and bars do).
    public var fullWidth: Bool?
    public var working: Bool

    public init(_ kind: TCButtonKind = .primary, size: TCButtonSize = .page, fullWidth: Bool? = nil, working: Bool = false) {
        self.kind = kind; self.size = size; self.fullWidth = fullWidth; self.working = working
    }

    // The environment is read in `TCButtonBody`, not here: a style with its own `@Environment` blanks the whole page
    // when it styles a `NavigationLink`.
    public func makeBody(configuration: Configuration) -> some View {
        TCButtonBody(label: configuration.label, isPressed: configuration.isPressed, style: self)
    }
}

/// The drawn button of `TCButtonStyle`.
struct TCButtonBody: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let style: TCButtonStyle
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.horizontalSizeClass) private var sizeClass

    var kind: TCButtonKind { style.kind }
    var size: TCButtonSize { style.size }
    var working: Bool { style.working }
    var compact: Bool { sizeClass == .compact }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.radius(compact: compact), style: .continuous)
        let wide = style.fullWidth ?? (size == .page && compact)
        let pressed = isPressed && isEnabled && !working
        return HStack(spacing: Space.s) {
            if working { ProgressView().tint(foreground) }
            label
        }
        .font(.sarabun(size.fontSize(compact: compact), .bold))
        .foregroundStyle(foreground)
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, kind == .text ? Space.s : 18)
        .frame(maxWidth: wide ? .infinity : nil)
        .frame(minWidth: touchMin, minHeight: size.height(compact: compact))
        .background(fill, in: shape)
        .overlay { border(shape) }
        .overlay { if pressed && kind != .text { shape.fill(Color.black.opacity(0.18)) } }
        .opacity(pressed && kind == .text ? 0.6 : 1)
        .contentShape(shape)
        .scaleEffect(pressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .allowsHitTesting(!working)
    }

    var off: Bool { !isEnabled }

    var foreground: Color {
        if off { return kind == .text ? Theme.disabledText : (kind == .secondary || kind == .destructive || kind == .dashedAdd ? Theme.disabledText : .white) }
        switch kind {
        case .primary, .primaryGradient, .tealGradient, .danger: return Theme.onPrimary
        case .secondary: return Theme.navy
        case .destructive: return Theme.dangerText
        case .text, .dashedAdd: return Theme.primary
        }
    }

    var fill: AnyShapeStyle {
        if off {
            switch kind {
            case .text, .dashedAdd: return AnyShapeStyle(Color.clear)
            case .secondary, .destructive: return AnyShapeStyle(Theme.surface)
            default: return AnyShapeStyle(Theme.disabledFill)
            }
        }
        switch kind {
        case .primary: return AnyShapeStyle(Theme.primary)
        case .primaryGradient: return AnyShapeStyle(Theme.headerGradient)
        case .tealGradient: return AnyShapeStyle(Theme.tealGradient)
        case .secondary, .destructive: return AnyShapeStyle(Theme.surface)
        case .text, .dashedAdd: return AnyShapeStyle(Color.clear)
        case .danger: return AnyShapeStyle(Theme.danger)
        }
    }

    @ViewBuilder func border(_ shape: RoundedRectangle) -> some View {
        switch kind {
        case .secondary: shape.strokeBorder(off ? Theme.borderSubtle : Theme.navy.opacity(0.6))
        case .destructive: shape.strokeBorder(off ? Theme.borderSubtle : Theme.danger.opacity(0.5))
        case .dashedAdd: shape.strokeBorder(off ? Theme.borderSubtle : Theme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        default: EmptyView()
        }
    }
}

/// A labelled button of the design system.
///
/// - `working`: spinner, and no second tap until it's done.
/// - `disabledReason`: the button is disabled and the reason shows under it (the board's rule: always say why).
public struct TCButton: View {
    let title: String
    var systemImage: String?
    var kind: TCButtonKind
    var size: TCButtonSize
    var fullWidth: Bool?
    var working: Bool
    var disabledReason: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, kind: TCButtonKind = .primary, size: TCButtonSize = .page,
                fullWidth: Bool? = nil, working: Bool = false, disabledReason: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.kind = kind; self.size = size
        self.fullWidth = fullWidth; self.working = working; self.disabledReason = disabledReason; self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button(action: action) {
                if let systemImage {
                    Label(title, systemImage: systemImage).labelStyle(TCIconTitleLabel())
                } else {
                    Text(title)
                }
            }
            .buttonStyle(TCButtonStyle(kind, size: size, fullWidth: fullWidth, working: working))
            .disabled(disabledReason != nil)
            .accessibilityValue(working ? "กำลังทำงาน" : "")
            if let disabledReason {
                Text(disabledReason).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
            }
        }
    }
}

/// Icon then title, 8 pt apart, icon 20 pt.
public struct TCIconTitleLabel: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s) {
            configuration.icon.font(.system(size: 18, weight: .semibold))
            configuration.title
        }
    }
}

/// 44 × 44 icon button with an optional red count badge (bell, gear, ✕, back).
/// `bordered: false` is the iPhone header version.
public struct TCIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var badge: Int?
    var bordered: Bool
    let action: () -> Void

    public init(_ systemImage: String, accessibilityLabel: String, badge: Int? = nil, bordered: Bool = true, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.accessibilityLabel = accessibilityLabel
        self.badge = badge; self.bordered = bordered; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(bordered ? Theme.navy : Theme.primary)
                .frame(width: touchMin, height: touchMin)
                .background(bordered ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay { if bordered { RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Theme.borderControl) } }
                .overlay(alignment: .topTrailing) {
                    if let badge, badge > 0 {
                        Text("\(badge)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20).padding(.horizontal, badge > 9 ? 4 : 0)
                            .background(Theme.danger, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.surface, lineWidth: 2))
                            .offset(x: 7, y: -8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(TCPressStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(badge.map { $0 > 0 ? "\($0) รายการใหม่" : "" } ?? "")
    }
}

/// Pressed: a little darker and 2 % smaller, for buttons that draw their own frame.
public struct TCPressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Floating action button: a circle (icon) or a capsule (icon + title).
/// iPad 68 pt, 24 from the edge; iPhone 60 pt, 20 from the right and 12 from the bottom. Place it with `.tcFabPlacement()`.
public struct TCFab: View {
    let systemImage: String
    var title: String?
    let accessibilityLabel: String
    var gradient: LinearGradient
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(_ systemImage: String = "plus", title: String? = nil, accessibilityLabel: String,
                gradient: LinearGradient = Theme.headerGradient, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.title = title; self.accessibilityLabel = accessibilityLabel
        self.gradient = gradient; self.action = action
    }

    public var body: some View {
        let side: CGFloat = sizeClass == .compact ? 60 : 68
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 26, weight: .semibold))
                if let title { Text(title).font(.sarabun(20, .bold)).lineLimit(1) }
            }
            .foregroundStyle(Theme.onPrimary)
            .padding(.horizontal, title == nil ? 0 : 28)
            .frame(minWidth: side, minHeight: side)
            .background(gradient, in: Capsule())
            .shadow(color: Theme.fabShadow, radius: 10, y: 4)
        }
        .buttonStyle(TCPressStyle())
        .accessibilityLabel(title ?? accessibilityLabel)
    }
}

public extension View {
    /// FAB margin: iPad 24 all round; iPhone 20 right, 12 bottom.
    func tcFabPlacement(compact: Bool) -> some View {
        padding(.trailing, compact ? 20 : 24).padding(.bottom, compact ? 12 : 24)
    }
}

/// A blue text link inside a card (`เปิด A2 →`, `แก้ ▾`), 44 pt target.
public struct TCLinkButton: View {
    let title: String
    var trailingSymbol: String?
    let action: () -> Void

    public init(_ title: String, trailingSymbol: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.trailingSymbol = trailingSymbol; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let trailingSymbol { Image(systemName: trailingSymbol).font(.system(size: 13, weight: .bold)) }
            }
            .font(.sarabun(16, .bold))
            .foregroundStyle(Theme.primary)
            .frame(minHeight: touchMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
