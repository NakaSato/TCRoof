#if canImport(UIKit)
import SwiftUI
import UIKit

/// ‹ ก่อนหน้า / ถัดไป › of a step's bottom bar.
/// iPad: 53 high, 210–250 wide, `ก่อนหน้า 4/13` over the step name. iPhone: 72 × 53, icon only, the name in VoiceOver.
/// `action == nil` greys it out ("หัวข้อแรก" / last step).
public struct TCStepNavButton: View {
    public enum Direction: Sendable { case previous, next }

    let direction: Direction
    let index: Int
    let count: Int
    let title: String
    let action: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(direction: Direction, index: Int, count: Int, title: String, action: (() -> Void)?) {
        self.direction = direction; self.index = index; self.count = count; self.title = title; self.action = action
    }

    var next: Bool { direction == .next }
    var off: Bool { action == nil }
    var caption: String { (next ? "ถัดไป" : "ก่อนหน้า") + " \(index)/\(count)" }

    public var body: some View {
        Button { action?() } label: {
            if sizeClass == .compact { phone } else { pad }
        }
        .buttonStyle(TCPressStyle())
        .disabled(off)
        .accessibilityLabel((next ? "ถัดไป " : "ก่อนหน้า ") + title)
        .accessibilityValue("ขั้น \(index) จาก \(count)")
    }

    var phone: some View {
        Image(systemName: next ? "chevron.right" : "chevron.left")
            .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.onPrimary)
            .frame(width: 72, height: 53)
            .background(off ? AnyShapeStyle(Theme.capsuleTodo) : AnyShapeStyle(Theme.headerGradient), in: RoundedRectangle(cornerRadius: Radius.md))
    }

    var pad: some View {
        let chevron = Image(systemName: next ? "chevron.right" : "chevron.left").font(.system(size: 18, weight: .semibold))
        return HStack(spacing: 10) {
            if !next { chevron }
            VStack(alignment: next ? .trailing : .leading, spacing: 0) {
                Text(caption).font(.sarabun(12)).opacity(next ? 0.9 : 1).foregroundStyle(next ? Theme.onPrimary : Theme.inkMuted)
                Text(title).font(.sarabun(16, .bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: next ? .trailing : .leading)
            if next { chevron }
        }
        .foregroundStyle(off ? Theme.disabledText : next ? Theme.onPrimary : Theme.navy)
        .padding(.horizontal, 16)
        .frame(minWidth: 150, idealWidth: 230, maxWidth: 230, minHeight: 53, maxHeight: 53)
        .background(next && !off ? AnyShapeStyle(Theme.headerGradient) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay { if !next || off { RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(off ? 0.2 : 0.6)) } }
    }
}

/// The status button at the left of an iPad step bar: green `ครบช่องบังคับแล้ว` when nothing required is missing,
/// orange `ยังขาด n รายการ` otherwise; tapping goes to the first missing item.
public struct TCStatusButton: View {
    let missing: Int
    let detail: String
    let action: () -> Void

    public init(missing: Int, detail: String, action: @escaping () -> Void) {
        self.missing = missing; self.detail = detail; self.action = action
    }

    var ok: Bool { missing == 0 }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(ok ? Theme.success : Theme.warning, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(ok ? "ครบช่องบังคับแล้ว" : "ยังขาด \(missing) รายการ")
                        .font(.sarabun(15, .bold)).foregroundStyle(ok ? Theme.okTick : Theme.pending)
                    Text(detail).font(.sarabun(13)).foregroundStyle(Theme.inkMuted)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(ok ? Theme.okTick : Theme.pending)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 53)
            .background(ok ? Theme.okSoft.opacity(0.5) : Theme.pendingSoft, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(ok ? Theme.success.opacity(0.45) : Theme.warning.opacity(0.45)))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityHint(ok ? "" : "ไปยังรายการที่ขาด")
    }
}

/// Bottom bar of a step (`g-bar`, height 53).
/// iPad: status button · `บันทึกร่าง` · ‹ ก่อนหน้า · ถัดไป ›. iPhone: `บันทึก` stretches, ‹ and › icon only, no status button
/// (the step line in the header carries it).
public struct TCStepBar: View {
    public struct Step: Sendable {
        public let index: Int
        public let title: String
        public init(index: Int, title: String) { self.index = index; self.title = title }
    }

    let count: Int
    let previous: Step?
    let next: Step?
    var missing: Int
    var missingDetail: String
    var onStatus: () -> Void
    var onSave: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(count: Int, previous: Step?, next: Step?, missing: Int, missingDetail: String,
                onStatus: @escaping () -> Void = {}, onSave: @escaping () -> Void,
                onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.count = count; self.previous = previous; self.next = next
        self.missing = missing; self.missingDetail = missingDetail
        self.onStatus = onStatus; self.onSave = onSave; self.onPrevious = onPrevious; self.onNext = onNext
    }

    public var body: some View {
        let compact = sizeClass == .compact
        HStack(spacing: 12) {
            if compact {
                TCButton("บันทึก", kind: .secondary, size: .bar, fullWidth: true, action: onSave)
            } else {
                TCStatusButton(missing: missing, detail: missingDetail, action: onStatus).frame(minWidth: 200, maxWidth: 300).layoutPriority(1)
                Spacer(minLength: 0)
                TCButton("บันทึกร่างตอนนี้", kind: .secondary, size: .bar, action: onSave).frame(width: 170).padding(.trailing, 12)
            }
            nav(.previous, previous, onPrevious)
            nav(.next, next, onNext)
        }
        .padding(.top, 8).padding(.horizontal, compact ? 16 : 24).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Rectangle().fill(Theme.surface.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2))).ignoresSafeArea(edges: .bottom))
    }

    func nav(_ d: TCStepNavButton.Direction, _ s: Step?, _ action: @escaping () -> Void) -> some View {
        TCStepNavButton(direction: d, index: s?.index ?? 0, count: count,
                        title: s?.title ?? (d == .previous ? "หัวข้อแรก" : "ขั้นสุดท้าย"),
                        action: s == nil ? nil : action)
    }
}
#endif
