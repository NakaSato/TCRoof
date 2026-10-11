#if canImport(UIKit)
import SwiftUI

/// A `Form` on iPhone; on iPad, board cards on the page gradient (`PadSection` becomes a `tcCard()`).
/// Screens keep one body for both: swap `Form` for `PadForm` and `Section` for `PadSection`.
public struct PadForm<Content: View>: View {
    var maxWidth: CGFloat
    var content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(maxWidth: CGFloat = 900, @ViewBuilder content: () -> Content) { self.maxWidth = maxWidth; self.content = content() }

    public var body: some View {
        if sizeClass == .compact {
            Form { content }
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

/// A `Section` on iPhone; on iPad a white card with the title above its rows and a hairline between them.
public struct PadSection<Content: View, Footer: View>: View {
    var title: String?
    var content: Content
    var footer: Footer
    @Environment(\.horizontalSizeClass) private var sizeClass

    public var body: some View {
        if sizeClass == .compact {
            if let title { Section { content } header: { Text(title) } footer: { footer } }
            else { Section { content } footer: { footer } }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    if let title {
                        Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.navy).padding(.top, 8).padding(.bottom, 2)
                    }
                    if #available(iOS 18, *) {
                        Group(subviews: content) { rows in
                            ForEach(rows.indices, id: \.self) { i in
                                if i > 0 { Divider().overlay(Theme.borderSubtle) }
                                rows[i].padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                            }
                        }
                    } else {
                        content.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .tcCard()
                footer.font(.footnote).foregroundStyle(Theme.inkMuted).padding(.horizontal, 4)
            }
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

/// A `NavigationLink` row: the list's own disclosure on iPhone; on iPad a plain row with a chevron, for `PadSection`.
public struct PadLink<Destination: View, Label: View>: View {
    var destination: () -> Destination
    var label: Label
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination; self.label = label()
    }

    public var body: some View {
        if sizeClass == .compact {
            NavigationLink(destination: destination) { label }
        } else {
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

public extension View {
    /// A system `Form` / `List` on the page gradient with white rows (`TCFormStyle`).
    func tcFormStyle() -> some View { modifier(TCFormStyle()) }
}
#endif
