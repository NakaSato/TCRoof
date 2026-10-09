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
        case steps(save: @MainActor () async -> Date, version: Int = 0, previous: Nav, next: Nav)
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
        case let .steps(save, version, previous, next):
            SaveButton(save: save, version: version)
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
                .frame(maxWidth: .infinity, minHeight: 53, maxHeight: 53)
                .frame(minWidth: 72)
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

/// The 104-pt "บันทึก" button of the iPhone bar (docs/ui/survey-a1-iphone): idle → spinner → green "✓ บันทึกแล้ว" for
/// 1.35 s → white with a green outline until the next edit (`version` changes), which returns it to idle.
struct SaveButton: View {
    enum Phase: Equatable { case idle, busy, saving, justSaved, clean }

    static let width: CGFloat = 104

    /// `-surveySave saving|saved|clean` opens the button in that state, for screenshots (`docs/ui/survey-a1-iphone/states/04`–`06`).
    static var startPhase: Phase {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "surveySave") {
        case "saving": return .saving
        case "saved": return .justSaved
        case "clean": return .clean
        default: break
        }
        #endif
        return .idle
    }
    let save: @MainActor () async -> Date
    /// Changes whenever the job's answers are edited (`Job.editVersion`).
    var version = 0
    @State var phase = SaveButton.startPhase
    /// An edit came in since the page opened or since the last save.
    @State var edited = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Button(action: run) {
            label
                .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 6)
                .frame(width: Self.width, height: 53)
                .background(fill, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: phase == .clean ? 2 : 1))
        }
        .buttonStyle(BarPress())
        .allowsHitTesting(phase == .idle || phase == .clean)
        .accessibilityLabel(accessibilityText)
        .onChange(of: version) { _, _ in
            edited = true
            if phase == .justSaved || phase == .clean { phase = .idle }
        }
    }

    @ViewBuilder var label: some View {
        switch phase {
        case .idle, .busy:
            Text("บันทึก").font(.system(size: 15, weight: .semibold)).foregroundStyle(Home.navy)
        case .saving:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(Home.muted)
                Text("บันทึก").font(.system(size: 15, weight: .semibold)).foregroundStyle(Home.muted)
            }
        case .justSaved:
            savedLabel(circle: true)
        case .clean:
            savedLabel(circle: false)
        }
    }

    /// "✓ บันทึกแล้ว": white check on a green circle right after saving, a plain green check once settled.
    func savedLabel(circle: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark").font(.system(size: circle ? 9 : 13, weight: .heavy))
                .foregroundStyle(circle ? Color.white : Home.okTick)
                .frame(width: 18, height: 18)
                .background(circle ? Home.stepDone : Color.clear, in: Circle())
            Text("บันทึกแล้ว").font(.system(size: 15, weight: .semibold)).foregroundStyle(Home.okTick)
        }
    }

    var fill: Color {
        switch phase {
        case .justSaved: Home.okSoftBG
        default: .white
        }
    }

    var border: Color {
        switch phase {
        case .justSaved, .clean: Home.stepDone
        default: Home.navy.opacity(0.6)
        }
    }

    var accessibilityText: String {
        switch phase {
        case .saving, .busy: "กำลังบันทึก"
        case .justSaved, .clean: "บันทึกล่าสุดแล้ว · ยังไม่มีการแก้ไขใหม่"
        case .idle: edited ? "บันทึกแบบร่าง · มีการแก้ไขที่ยังไม่ได้บันทึก" : "บันทึกแบบร่าง"
        }
    }

    func run() {
        guard phase == .idle || phase == .clean else { return }
        phase = .busy
        Task { @MainActor in
            // the spinner shows for at least 0.45 s, so a quick save still reads as a save
            let slow = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !Task.isCancelled, phase == .busy { phase = .saving }
            }
            async let minimum: Void = { try? await Task.sleep(nanoseconds: 450_000_000) }()
            let when = await save()
            await minimum
            slow.cancel()
            edited = false
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { phase = .justSaved }
            AccessibilityNotification.Announcement("บันทึกแล้ว " + when.formatted(.dateTime.hour().minute())).post()
            try? await Task.sleep(nanoseconds: 1_350_000_000)
            // an edit during these 1.35 s has already put the button back to idle
            if phase == .justSaved { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { phase = .clean } }
        }
    }
}

extension Job {
    /// Changes when an answer or a section changes, not when the model stamps `updated` or a Drive link lands.
    var editVersion: Int {
        var h = Hasher()
        h.combine(values); h.combine(modules)
        return h.finalize()
    }
}
#endif
