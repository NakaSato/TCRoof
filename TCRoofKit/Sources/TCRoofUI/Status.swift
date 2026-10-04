#if canImport(UIKit)
import SwiftUI
import UIKit

/// Section 4 · Status & feedback (docs/ui/components/sections/04-status.png).

/// Status chip: capsule 24 high, 12.5 pt bold, optional 7 pt dot.
public struct TCStatusChip: View {
    public enum Kind: CaseIterable, Sendable {
        /// `พร้อมใช้`: okSoft / okText.
        case ok
        /// `ครบ`: okSoft / okTick.
        case done
        /// `ใช้งานอยู่`: primarySoft / primary.
        case active
        /// `เกินกำหนดคืน`: dangerSoft / dangerText.
        case overdue
        /// `ส่งซ่อม`, `ขาด 3 ช่อง`: pendingSoft / pending.
        case pending

        var colors: (fill: Color, text: Color) {
            switch self {
            case .ok: (Theme.okSoft, Theme.okText)
            case .done: (Theme.okSoft, Theme.okTick)
            case .active: (Theme.primarySoft, Theme.primary)
            case .overdue: (Theme.dangerSoft, Theme.dangerText)
            case .pending: (Theme.pendingSoft, Theme.pending)
            }
        }
    }

    let title: String
    let fill: Color
    let text: Color
    var dot: Bool

    public init(_ title: String, kind: Kind, dot: Bool = false) {
        self.title = title; self.fill = kind.colors.fill; self.text = kind.colors.text; self.dot = dot
    }

    /// Any pair, e.g. the team chip or a section count (`B ระบบไฟฟ้า ×5`: primarySoft / navy).
    public init(_ title: String, fill: Color, text: Color, dot: Bool = false) {
        self.title = title; self.fill = fill; self.text = text; self.dot = dot
    }

    public var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(text).frame(width: 7, height: 7) }
            Text(title)
        }
        .font(.sarabun(12.5, .bold, relativeTo: .caption))
        .foregroundStyle(text)
        .lineLimit(1).fixedSize()
        .padding(.horizontal, 10).frame(minHeight: 24)
        .background(fill, in: Capsule())
    }
}

/// `ข้อมูลตัวอย่าง`: sun fill, navy text; marks a screen filled with example data.
public struct TCSampleChip: View {
    let title: String
    public init(_ title: String = "ข้อมูลตัวอย่าง") { self.title = title }
    public var body: some View { TCStatusChip(title, fill: Theme.sun, text: Theme.onSun) }
}

/// Team chip `ทีม TCR03`: blue dot on 10 % blue.
public struct TCTeamChip: View {
    let team: String
    public init(_ team: String) { self.team = team }
    public var body: some View { TCStatusChip("ทีม " + team, fill: Theme.primary.opacity(0.1), text: Theme.primary, dot: true) }
}

/// `ค่าตัวอย่าง`: a value that is only an example, in pending orange with no fill.
public struct TCSampleValue: View {
    let title: String
    public init(_ title: String = "ค่าตัวอย่าง") { self.title = title }
    public var body: some View { TCStatusChip(title, fill: .clear, text: Theme.pending) }
}

/// Dot + bold text: `● พร้อมใช้`, `● เกินกำหนดคืน · เกิน 1 วัน`. Wraps.
public struct TCDotLine: View {
    let title: String
    let color: Color

    public init(_ title: String, kind: TCStatusChip.Kind) { self.title = title; self.color = kind.colors.text }
    public init(_ title: String, color: Color) { self.title = title; self.color = color }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("●")
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        .font(.sarabun(14, .bold, relativeTo: .subheadline))
        .foregroundStyle(color)
    }
}

/// Progress ring with the number inside: `72 %`, or days left (`76 วัน`, `-10 วัน` in red).
/// Blue in progress, green at 100 %, red when days run out.
public struct TCProgressRing: View {
    public enum Value: Sendable {
        /// 0…1.
        case percent(Double)
        /// Days left of `total`; negative is overdue.
        case days(Int, total: Int)
    }

    let value: Value
    var size: CGFloat

    /// Board sizes: 28 (inline), 44 (iPhone card), 58 (card), 110 (hero).
    public init(_ value: Value, size: CGFloat = 58) { self.value = value; self.size = size }

    var fraction: Double {
        switch value {
        case .percent(let p): min(max(p, 0), 1)
        case .days(let d, let total): d < 0 ? 1 : min(max(Double(d) / Double(max(total, 1)), 0), 1)
        }
    }
    var tint: Color {
        switch value {
        case .percent(let p): p >= 1 ? Theme.stepDone : Theme.primary
        case .days(let d, _): d < 0 ? Theme.danger : Theme.primary
        }
    }
    var number: String {
        switch value {
        case .percent(let p): "\(Int((p * 100).rounded()))"
        case .days(let d, _): "\(d)"
        }
    }
    var unit: String {
        if case .days = value { return "วัน" }
        return "%"
    }

    public var body: some View {
        let line = max(3, size * 0.07)
        ZStack {
            Circle().stroke(Theme.track, lineWidth: line)
            Circle().trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if size >= 40 {
                VStack(spacing: -size * 0.04) {
                    Text(number).font(.sarabun(size * 0.26, .bold)).foregroundStyle(Theme.navy)
                    Text(unit).font(.sarabun(size * 0.17)).foregroundStyle(Theme.inkMuted)
                }
                .monospacedDigit().minimumScaleFactor(0.6)
            } else {
                Text(number).font(.system(size: size * 0.32, weight: .bold)).monospacedDigit().foregroundStyle(Theme.navy)
            }
        }
        .padding(line / 2)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit == "%" ? "ความคืบหน้า" : "วันที่เหลือ")
        .accessibilityValue(unit == "%" ? "\(number) เปอร์เซ็นต์" : "\(number) วัน")
    }
}

/// A bar split into segments, one per step: done green, current blue, late orange, todo grey.
/// `thin` is the 13-step look (6 high, 3 apart); otherwise the wider 5-step look (6 high, 6 apart).
public struct TCSegmentedProgress: View {
    public enum Segment: Sendable { case done, current, late, todo }

    let segments: [Segment]
    var thin: Bool

    public init(_ segments: [Segment], thin: Bool = true) { self.segments = segments; self.thin = thin }

    /// `done` steps done, the next one current, the rest todo.
    public init(done: Int, count: Int, thin: Bool = true) {
        self.segments = (0..<count).map { $0 < done ? .done : $0 == done ? .current : .todo }
        self.thin = thin
    }

    public var body: some View {
        HStack(spacing: thin ? 3 : 6) {
            ForEach(segments.indices, id: \.self) { i in
                Capsule().fill(color(segments[i])).frame(height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ความคืบหน้า")
        .accessibilityValue("ครบ \(segments.filter { $0 == .done }.count) จาก \(segments.count)")
    }

    func color(_ s: Segment) -> Color {
        switch s {
        case .done: Theme.stepDone
        case .current: Theme.primary
        case .late: Theme.pending
        case .todo: Theme.borderSubtle
        }
    }
}

/// `ทำต่อ 12/13  D1 ถังน้ำใส  ›`: resumes a draft at its step. 38 high (44 hit), r10.
public struct TCResumeStrip: View {
    let index: Int
    let count: Int
    let step: String
    let action: () -> Void

    public init(index: Int, count: Int, step: String, action: @escaping () -> Void) {
        self.index = index; self.count = count; self.step = step; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Text("ทำต่อ \(index)/\(count)").font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                Text(step).font(.sarabun(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.navy).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Theme.keyFill, in: RoundedRectangle(cornerRadius: Radius.md))
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(TCPressStyle())
        .accessibilityLabel("ทำต่อ ขั้น \(index) จาก \(count) \(step)")
    }
}

/// Warning banner: pendingSoft, triangle, bold title over a navy body line.
public struct TCWarningBanner: View {
    let title: String
    let message: String?

    public init(_ title: String, message: String? = nil) { self.title = title; self.message = message }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 20, weight: .semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.sarabun(16, .bold))
                if let message { Text(message).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.navy) }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.pending)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.pendingSoft, in: RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
    }
}

/// Result summary box: a sentence on pendingSoft (`โหลดรวม 107 kW น้อยกว่า PV 120 kW → ต้องมีระบบกันย้อน (B4)`).
public struct TCResultBox: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(Theme.navy)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.pendingSoft, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}

/// Missing-item line: orange `!` and `ยังขาด — โรงกรอง: ภาพมุมกว้าง` in red.
public struct TCMissingLine: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        HStack(spacing: Space.s) {
            Text("!").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Theme.warning, in: Circle())
                .accessibilityHidden(true)
            Text(text).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Dark toast, up to 2 lines.
public struct TCToast: View {
    let message: String
    public init(_ message: String) { self.message = message }
    public var body: some View {
        Text(message)
            .font(.sarabun(14, relativeTo: .subheadline)).foregroundStyle(.white)
            .lineLimit(2)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.toast, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct TCToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                TCToast(message)
                    .padding(.horizontal, Space.l).padding(.bottom, Space.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { dismiss() }
                    .task(id: message) {
                        AccessibilityNotification.Announcement(message).post()
                        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                        if !Task.isCancelled { dismiss() }
                    }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: message)
    }

    func dismiss() { message = nil }
}

public extension View {
    /// Shows `message` as a toast at the bottom, then clears it after `duration` seconds (or on tap).
    func tcToast(_ message: Binding<String?>, duration: Double = 2.5) -> some View {
        modifier(TCToastModifier(message: message, duration: duration))
    }
}
#endif
