#if canImport(UIKit)
import SwiftUI

/// Grouped white cards instead of a system `Form`: on iPad on the page gradient, on iPhone on `Theme.phonePage`
/// (docs/ui/tcroof-home-iphone states/06). Screens keep one body for both: swap `Form` for `PadForm` and `Section` for `PadSection`.
public struct PadForm<Content: View>: View {
    var maxWidth: CGFloat
    var content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(maxWidth: CGFloat = 900, @ViewBuilder content: () -> Content) { self.maxWidth = maxWidth; self.content = content() }

    public var body: some View {
        if sizeClass == .compact {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .font(.sarabun(16))
            .foregroundStyle(Theme.navy)
            .background(Theme.phonePage.ignoresSafeArea())
            .tint(Theme.primary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(24)
                    .frame(maxWidth: maxWidth)
                    .frame(maxWidth: .infinity)
            }
            .background(Theme.pageGradient.ignoresSafeArea())
        }
    }
}

/// A white card with the title above its rows and a hairline between them; on iPhone the title is the settings screen's small caption.
public struct PadSection<Content: View, Footer: View>: View {
    var title: String?
    var content: Content
    var footer: Footer
    @Environment(\.horizontalSizeClass) private var sizeClass

    public var body: some View {
        let compact = sizeClass == .compact
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            if let title, compact {
                Text(title).font(.sarabun(12.5, .bold, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    .padding(.leading, 4).accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let title, !compact {
                    Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.navy).padding(.top, 8).padding(.bottom, 2)
                }
                if #available(iOS 18, *) {
                    Group(subviews: content) { rows in
                        ForEach(rows.indices, id: \.self) { i in
                            if i > 0 { Divider().overlay(compact ? Theme.hairline : Theme.borderSubtle) }
                            rows[i].padding(.vertical, compact ? 6 : 10).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                        }
                    }
                } else {
                    content.padding(.vertical, compact ? 6 : 10).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, compact ? 14 : 16).padding(.vertical, compact ? 2 : 6)
            .tcCard()
            footer.font(.footnote).foregroundStyle(Theme.inkMuted).padding(.horizontal, 4)
        }
    }
}

public extension PadSection where Footer == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content(); self.footer = EmptyView()
    }
}

public extension PadSection {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title; self.content = content(); self.footer = footer()
    }
}

/// A `NavigationLink` row for `PadSection`: a plain row with a chevron.
public struct PadLink<Destination: View, Label: View>: View {
    var destination: () -> Destination
    var label: Label

    public init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination; self.label = label()
    }

    public var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                label
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.chevron)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A picker row for `PadSection`: the title on the left, the choice as a menu on the right (a bare `Picker` outside a `Form` hides its title).
public struct PadPicker<Value: Hashable, Options: View>: View {
    var title: String
    @Binding var selection: Value
    var options: Options

    public init(_ title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.title = title; _selection = selection; self.options = options()
    }

    public var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) { options }.pickerStyle(.menu).labelsHidden()
        }
    }
}

/// A 44 pt icon button at the end of a `PadSection` row, standing in for a list's swipe actions (delete, move up).
public struct PadRowButton: View {
    var systemImage: String
    var label: String
    var destructive: Bool
    var action: () -> Void

    public init(_ label: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.label = label; self.systemImage = systemImage; self.destructive = destructive; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(destructive ? Theme.danger : Theme.primary)
                .frame(width: touchMin, height: touchMin).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The board's look for a system `Form` or `List` that stays one (sheets with text fields, pickers and toggles):
/// the page gradient behind white rows, controls in `Theme.primary`.
private struct TCFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.pageGradient.ignoresSafeArea())
            .tint(Theme.primary)
            .foregroundStyle(Theme.navy)
    }
}

/// The page behind a screen or sheet that lays out its own cards: `Theme.phonePage` on iPhone, as `PadForm`, and the page gradient on iPad.
/// A view, not a `ViewModifier`: the modifier crashed in Debug inside D1's full-screen plans.
private struct TCPageFill: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact { Theme.phonePage } else { Theme.pageGradient }
    }
}

public extension View {
    /// A system `Form` / `List` on the page gradient with white rows (`TCFormStyle`).
    func tcFormStyle() -> some View { modifier(TCFormStyle()) }

    /// The page behind a screen of its own cards (`TCPageFill`): `Theme.phonePage` on iPhone, the page gradient on iPad.
    func tcPageBackground() -> some View { background(TCPageFill().ignoresSafeArea()) }
}
#endif
