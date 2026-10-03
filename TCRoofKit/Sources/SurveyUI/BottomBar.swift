#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

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
        case steps(save: @MainActor () async -> Date, previous: Nav, next: Nav)
        case detail(destructive: Action, primary: Action)
        case pair(secondary: Action, primary: Action)
    }

    let variant: Variant

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.top, 8).padding(.horizontal, 24).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(Rectangle().fill(Color.white.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2))).ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder var content: some View {
        switch variant {
        case let .steps(save, previous, next):
            SaveButton(save: save).padding(.trailing, 12)
            navButton(previous, symbol: "chevron.left")
            navButton(next, symbol: "chevron.right")
        case let .detail(destructive, primary):
            // widths 1 : 1.4
            GeometryReader { g in
                HStack(spacing: 12) {
                    outline(destructive, size: 15, weight: .bold, tint: Home.red, border: Home.danger.opacity(0.5))
                        .frame(width: max(0, g.size.width - 12) / 2.4)
                    gradient(primary, colors: [Home.primary, Home.primaryLight], size: 17)
                }
            }
            .frame(height: 53)
        case let .pair(secondary, primary):
            outline(secondary, size: 16, weight: .semibold, tint: Home.navy, border: Home.navy.opacity(0.6))
            gradient(primary, colors: [Home.teal, Home.tealLight], size: 16)
        }
    }

    func navButton(_ nav: Nav, symbol: String) -> some View {
        Button { nav.action?() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(width: 72, height: 53)
                .background(nav.action == nil ? AnyShapeStyle(Home.navOff) : AnyShapeStyle(Self.blue), in: RoundedRectangle(cornerRadius: 10))
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
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
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
    static let blue = LinearGradient(colors: [Home.primary, Home.primaryLight], startPoint: .leading, endPoint: .trailing)
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

/// "บันทึก" → (spinner "กำลังบันทึก…" when the save takes 300 ms or more) → "✓ บันทึกแล้ว hh:mm" for 1.5 s → "บันทึก".
struct SaveButton: View {
    enum Phase: Equatable { case idle, busy, saving, saved(Date) }

    let save: @MainActor () async -> Date
    @State var phase = Phase.idle
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Button(action: run) {
            label
                .frame(maxWidth: .infinity).frame(height: 53)
                .background(fill, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border))
        }
        .buttonStyle(BarPress())
        .allowsHitTesting(phase == .idle)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder var label: some View {
        switch phase {
        case .idle, .busy:
            Text("บันทึก").font(.system(size: 17, weight: .semibold)).foregroundStyle(Home.navy)
                .lineLimit(1).minimumScaleFactor(0.8)
        case .saving:
            HStack(spacing: 8) {
                ProgressView().tint(Home.muted)
                Text("กำลังบันทึก…").font(.system(size: 17, weight: .semibold)).foregroundStyle(Home.muted)
            }
            .lineLimit(1).minimumScaleFactor(0.8)
        case .saved(let d):
            Text("✓ บันทึกแล้ว " + d.formatted(.dateTime.hour().minute())).font(.system(size: 17, weight: .semibold)).foregroundStyle(Home.okTick)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    var fill: Color {
        switch phase {
        case .saving: Home.savingBG
        case .saved: Home.okSoftBG
        default: .white
        }
    }

    var border: Color {
        if case .saved = phase { return Home.okTick.opacity(0.5) }
        return Home.navy.opacity(0.6)
    }

    var accessibilityText: String {
        switch phase {
        case .saving: "กำลังบันทึก"
        case .saved(let d): "บันทึกแล้ว " + d.formatted(.dateTime.hour().minute())
        default: "บันทึก"
        }
    }

    func run() {
        guard phase == .idle else { return }
        phase = .busy
        Task { @MainActor in
            // a save shorter than 300 ms goes straight to "บันทึกแล้ว"
            let slow = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled, phase == .busy { phase = .saving }
            }
            let when = await save()
            slow.cancel()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { phase = .saved(when) }
            AccessibilityNotification.Announcement("บันทึกแล้ว " + when.formatted(.dateTime.hour().minute())).post()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { phase = .idle }
        }
    }
}
#endif
