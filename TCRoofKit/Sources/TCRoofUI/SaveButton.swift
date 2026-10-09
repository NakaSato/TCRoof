#if canImport(UIKit)
import SwiftUI

/// The save button of the bottom bars: idle → spinner → green "✓ บันทึกแล้ว" for 1.35 s → white with a green outline
/// until the next edit (`version` changes), which returns it to idle.
/// iPhone (docs/ui/survey-a1-iphone): 104 × 53 "บันทึก". iPad card pages (docs/ui/survey-a1-ipad): 170 × 56 "บันทึกร่างตอนนี้",
/// or a 56-pt icon when the bar is tight.
public struct TCSaveButton: View {
    public enum Phase: Equatable { case idle, busy, saving, justSaved, clean }

    /// `-surveySave saving|saved|clean` opens the button in that state, for screenshots
    /// (`docs/ui/survey-a1-iphone/states/04`–`06`, `docs/ui/survey-a1-ipad/states/03`–`05`).
    public static var startPhase: Phase {
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
    /// nil: the free width (the gallery's iPhone bar).
    var width: CGFloat? = 104
    var height: CGFloat = 53
    var font: CGFloat = 15
    var radius: CGFloat = 10
    /// Diameter of the green check circle right after saving.
    var circle: CGFloat = 18
    var idle = "บันทึก"
    var busy = "บันทึก"
    /// In place of the idle words (a tight iPad bar); the other states keep their icons without words.
    var icon: String? = nil
    let save: @MainActor () async -> Date
    /// Changes whenever the job's answers are edited (`Job.editVersion`).
    var version = 0
    public init(width: CGFloat? = 104, height: CGFloat = 53, font: CGFloat = 15, radius: CGFloat = 10, circle: CGFloat = 18,
                idle: String = "บันทึก", busy: String = "บันทึก", icon: String? = nil,
                save: @escaping @MainActor () async -> Date, version: Int = 0) {
        self.width = width; self.height = height; self.font = font; self.radius = radius; self.circle = circle
        self.idle = idle; self.busy = busy; self.icon = icon; self.save = save; self.version = version
    }

    @State var phase = TCSaveButton.startPhase
    /// An edit came in since the page opened or since the last save.
    @State var edited = false
    /// The check circle's pop-in and its tick drawing, run each time `justSaved` begins.
    @State var popped = false
    @State var drawn = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    public var body: some View {
        Button(action: run) {
            label
                .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 6)
                .frame(maxWidth: width ?? .infinity).frame(width: width, height: height)
                .background(fill, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: phase == .clean ? 2 : 1))
        }
        .buttonStyle(SavePress(radius: radius))
        .allowsHitTesting(phase == .idle || phase == .clean)
        .accessibilityLabel(accessibilityText)
        .onChange(of: version) { _, _ in
            edited = true
            if phase == .justSaved || phase == .clean { phase = .idle }
        }
    }

    var words: Bool { icon == nil }

    @ViewBuilder var label: some View {
        switch phase {
        case .idle, .busy:
            if let icon { Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.navy) }
            else { Text(idle).font(.system(size: font, weight: .semibold)).foregroundStyle(Theme.navy) }
        case .saving:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(Theme.inkMuted)
                if words { Text(busy).font(.system(size: font, weight: .semibold)).foregroundStyle(Theme.inkMuted) }
            }
        case .justSaved:
            savedLabel(circle: true)
        case .clean:
            savedLabel(circle: false)
        }
    }

    /// "✓ บันทึกแล้ว": white check on a green circle that pops in right after saving, a plain green check once settled.
    func savedLabel(circle: Bool) -> some View {
        let d = self.circle
        return HStack(spacing: d > 18 ? 6 : 5) {
            Group {
                if circle {
                    Tick().trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: d * 0.14, lineCap: .round, lineJoin: .round))
                        .frame(width: d * 0.6, height: d * 0.6)
                        .frame(width: d, height: d)
                        .background(Theme.stepDone, in: Circle())
                        .scaleEffect(popped || reduceMotion ? 1 : 0.6)
                        .opacity(popped || reduceMotion ? 1 : 0)
                        .onAppear(perform: pop)
                } else {
                    Image(systemName: "checkmark").font(.system(size: d > 18 ? 15 : 13, weight: .heavy))
                        .foregroundStyle(Theme.okTick)
                        .frame(width: 18, height: 18)
                }
            }
            if words { Text("บันทึกแล้ว").font(.system(size: font, weight: .semibold)).foregroundStyle(Theme.okTick) }
        }
    }

    /// scale 0.6 → 1.15 → 1 in 0.35 s, the tick drawn from 0.15 s.
    func pop() {
        popped = false; drawn = false
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { popped = true }
        withAnimation(.easeOut(duration: 0.35).delay(0.15)) { drawn = true }
    }

    var fill: Color {
        switch phase {
        case .justSaved: Theme.okFlash
        default: .white
        }
    }

    var border: Color {
        switch phase {
        case .justSaved, .clean: Theme.stepDone
        default: Theme.navy.opacity(0.6)
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

/// The ✓ of the save button (the design's `M5 12l5 5 9-10` in a 24-pt box), drawn left to right.
struct Tick: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width / 14, h = r.height / 10
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + 5 * h))
        p.addLine(to: CGPoint(x: r.minX + 5 * w, y: r.minY + 10 * h))
        p.addLine(to: CGPoint(x: r.minX + 14 * w, y: r.minY))
        return p
    }
}

/// Pressed: a little darker and 2% smaller (as the survey bars' `BarPress`).
struct SavePress: ButtonStyle {
    let radius: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: radius).fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
