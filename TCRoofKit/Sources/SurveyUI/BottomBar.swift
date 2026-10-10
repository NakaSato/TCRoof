#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore
import TCRoofUI

/// iPhone bottom bar of the survey steps (docs/ui/components/iphone-bottom-bar): "บันทึก" · ‹ · › on every step,
/// or two buttons on a detail page (delete + done) and on SLD (two equal actions).
struct BottomBar: View {
    struct Action {
        let title: String
        let action: () -> Void
    }
    /// ‹ or ›: icon only; `action == nil` greys it out.
    struct Nav {
        let label: String
        var hint: String? = nil
        let action: (() -> Void)?
    }
    enum Variant {
        /// `save` runs before "✓ บันทึกแล้ว" shows; it returns the save time.
        case steps(save: @MainActor () async -> Date, version: Int = 0, previous: Nav, next: Nav)
        case detail(destructive: Action, primary: Action)
        case pair(secondary: Action, primary: Action)
    }

    let variant: Variant

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.top, 8).padding(.horizontal, 24).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(Rectangle().fill(Theme.surface.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2))).ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder var content: some View {
        switch variant {
        case let .steps(save, version, previous, next):
            SaveButton(save: save, version: version)
            navButton(previous, symbol: "chevron.left")
            navButton(next, symbol: "chevron.right")
        case let .detail(destructive, primary):
            // widths 1 : 1.4
            GeometryReader { g in
                HStack(spacing: 12) {
                    outline(destructive, size: 15, weight: .bold, tint: Theme.dangerText, border: Theme.danger.opacity(0.5))
                        .frame(width: max(0, g.size.width - 12) / 2.4)
                    gradient(primary, colors: [Theme.primary, Theme.primaryLight], size: 17)
                }
            }
            .frame(height: 53)
        case let .pair(secondary, primary):
            outline(secondary, size: 16, weight: .semibold, tint: Theme.navy, border: Theme.navy.opacity(0.6))
            gradient(primary, colors: [Theme.teal, Theme.tealLight], size: 16)
        }
    }

    func navButton(_ nav: Nav, symbol: String) -> some View {
        Button { nav.action?() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 53, maxHeight: 53)
                .frame(minWidth: 72)
                .background(nav.action == nil ? AnyShapeStyle(Theme.navOff.opacity(0.4)) : AnyShapeStyle(Self.blue), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(BarPress())
        .disabled(nav.action == nil)
        .accessibilityLabel(nav.label)
        .accessibilityHint(nav.hint ?? "")
    }

    func outline(_ a: Action, size: CGFloat, weight: Font.Weight, tint: Color, border: Color) -> some View {
        Button(action: a.action) {
            Text(a.title).font(.system(size: size, weight: weight)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 8)
                .frame(maxWidth: .infinity).frame(height: 53)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border))
        }
        .buttonStyle(BarPress())
    }

    func gradient(_ a: Action, colors: [Color], size: CGFloat) -> some View {
        Button(action: a.action) {
            Text(a.title).font(.system(size: size, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 8)
                .frame(maxWidth: .infinity).frame(height: 53)
                .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(BarPress())
    }

    /// #1F6FB5 → #2E8FDB.
    static let blue = LinearGradient(colors: [Theme.primary, Theme.primaryLight], startPoint: .leading, endPoint: .trailing)
}

/// Pressed: a little darker and 2% smaller.
struct BarPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The bottom bars' save button lives in the design system (`TCSaveButton`, also in `TCStepBar` and the gallery).
typealias SaveButton = TCSaveButton

extension Job {
    /// Changes when an answer or a section changes, not when the model stamps `updated` or a Drive link lands.
    var editVersion: Int {
        var h = Hasher()
        h.combine(values); h.combine(modules)
        return h.finalize()
    }
}
#endif
