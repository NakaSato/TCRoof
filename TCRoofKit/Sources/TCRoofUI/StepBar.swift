#if canImport(UIKit)
import SwiftUI
import UIKit

/// ‹ ก่อนหน้า / ถัดไป › of a step's bottom bar (docs/ui/survey-bar-ipad).
/// iPad: 230 × 53, `ก่อนหน้า 4/13` over the step name, the name truncating; an off ‹ reads `หัวข้อแรก` on one line.
/// iPhone: 72 × 53, icon only, the name in VoiceOver. `action == nil` greys it out.
public struct TCStepNavButton: View {
    public enum Direction: Sendable { case previous, next }

    let direction: Direction
    let index: Int
    let count: Int
    let title: String
    /// In place of `ถัดไป 6/13` (E1: `ขั้นสุดท้าย`).
    var caption: String?
    var width: CGFloat
    /// The narrowest iPad bar: the chevron alone.
    var iconOnly: Bool
    let action: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(direction: Direction, index: Int, count: Int, title: String, caption: String? = nil,
                width: CGFloat = 230, iconOnly: Bool = false, action: (() -> Void)?) {
        self.direction = direction; self.index = index; self.count = count; self.title = title
        self.caption = caption; self.width = width; self.iconOnly = iconOnly; self.action = action
    }

    var next: Bool { direction == .next }
    var off: Bool { action == nil }
    var kicker: String { caption ?? (next ? "ถัดไป" : "ก่อนหน้า") + " \(index)/\(count)" }

    public var body: some View {
        Button { action?() } label: {
            if sizeClass == .compact { phone } else { pad }
        }
        .buttonStyle(TCPressStyle())
        .disabled(off)
        .accessibilityLabel(off ? title : caption.map { $0 + " " + title } ?? (next ? "ถัดไป " : "ก่อนหน้า ") + title)
        .accessibilityValue(off || caption != nil ? "" : "ขั้น \(index) จาก \(count)")
        .accessibilityHint(off && !next ? "ไม่มีหัวข้อก่อนหน้า" : "")
    }

    var phone: some View {
        Image(systemName: next ? "chevron.right" : "chevron.left")
            .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.onPrimary)
            .frame(width: 72, height: 53)
            .background(off ? AnyShapeStyle(Theme.capsuleTodo) : AnyShapeStyle(Theme.headerGradient), in: RoundedRectangle(cornerRadius: Radius.md))
    }

    var chevron: some View {
        Image(systemName: next ? "chevron.right" : "chevron.left").font(.system(size: 18, weight: .semibold))
    }

    var pad: some View {
        HStack(spacing: off ? 8 : 10) {
            if !next { chevron }
            if iconOnly {
            } else if off {
                Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
            } else {
                VStack(alignment: next ? .trailing : .leading, spacing: 0) {
                    Text(kicker).font(.system(size: 12)).opacity(next ? 0.9 : 1).foregroundStyle(next ? Theme.onPrimary : Theme.inkMuted)
                    Text(title).font(.system(size: 16, weight: .semibold))
                }
                .lineLimit(1)
            }
            if next { chevron }
        }
        .foregroundStyle(off ? Theme.navOff : next ? Theme.onPrimary : Theme.navy)
        .padding(.horizontal, iconOnly ? 0 : 14)
        .frame(minWidth: min(width, 150), idealWidth: width, maxWidth: width, minHeight: 53, maxHeight: 53)
        .background(next && !off ? AnyShapeStyle(Theme.headerGradient) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay {
            if !next || off { RoundedRectangle(cornerRadius: Radius.md).strokeBorder(off ? Theme.navOff.opacity(0.5) : Theme.navy.opacity(0.6)) }
        }
    }
}

/// The left of an iPad step bar: how complete the page is. Each page supplies its own words.
public enum TCBarStatus {
    /// Green ✓ and a muted line: `ครบ 11/11 ช่องในหน้านี้`.
    case complete(String)
    /// Orange ! and a red line (orange when `warn`: a warning that doesn't block completion).
    /// `action`: tapping the line goes to the first missing item.
    case missing(String, warn: Bool = false, action: (() -> Void)? = nil)
    /// Orange chip: `ยังขาด 7 รายการ ใน 2 อาคาร` over `อาคารนี้: ภาพเบรกเกอร์`; tapping goes to the first missing item.
    /// `emphasis` follows `sub` in semibold.
    case gapChip(title: String, sub: String, emphasis: String = "", label: String, action: () -> Void)
    /// The same chip in green: `ครบช่องบังคับแล้ว` over the optional items still missing.
    case okChip(title: String, sub: String, emphasis: String = "", label: String, action: () -> Void)
    /// Green ✓ and a bold green line: `ครบทุกอาคารแล้ว`.
    case allDone(String)
}

/// Draws a `TCBarStatus`; one line, truncating, so the bar's buttons keep their widths.
public struct TCBarStatusView: View {
    let status: TCBarStatus
    public init(_ status: TCBarStatus) { self.status = status }

    public var body: some View {
        switch status {
        case let .complete(text):
            line(ok: true, Text(text).font(.system(size: 13)).foregroundStyle(Theme.inkMuted))
        case let .missing(text, warn, action):
            let row = line(ok: false, Text(text).font(.system(size: 13)).foregroundStyle(warn ? Theme.pending : Theme.danger))
            if let action {
                Button(action: action) { row.frame(minHeight: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint("แตะเพื่อไปที่รายการแรกที่ยังขาด")
            } else {
                row
            }
        case let .allDone(text):
            line(ok: true, Text(text).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.okText))
        case let .gapChip(title, sub, emphasis, label, action):
            chip(ok: false, title: title, sub: sub, emphasis: emphasis, label: label, action: action)
        case let .okChip(title, sub, emphasis, label, action):
            chip(ok: true, title: title, sub: sub, emphasis: emphasis, label: label, action: action)
        }
    }

    /// 24-pt green ✓ or orange ! circle.
    func badge(ok: Bool) -> some View {
        Text(ok ? "✓" : "!").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(ok ? Theme.success : Theme.warning, in: Circle())
    }

    func line(ok: Bool, _ text: Text) -> some View {
        HStack(spacing: 10) {
            badge(ok: ok).accessibilityLabel(ok ? "ครบแล้ว" : "ยังขาดข้อมูล")
            text.lineLimit(1).truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }

    func chip(ok: Bool, title: String, sub: String, emphasis: String, label: String, action: @escaping () -> Void) -> some View {
        let tint = ok ? Theme.okText : Theme.pending
        return Button(action: action) {
            HStack(spacing: 10) {
                badge(ok: ok)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                    (Text(sub) + Text(emphasis).fontWeight(.semibold).foregroundStyle(Theme.pending))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.inkMuted)
                }
                .lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
            }
            .padding(.leading, 10).padding(.trailing, 14)
            .frame(minHeight: 53)
            .background(ok ? Theme.okFlash : Theme.pendingSoft, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(ok ? Theme.success.opacity(0.4) : Theme.warning.opacity(0.45)))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
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

    public var body: some View {
        TCBarStatusView(missing == 0
            ? .okChip(title: "ครบช่องบังคับแล้ว", sub: detail, label: "ครบช่องบังคับแล้ว · " + detail, action: action)
            : .gapChip(title: "ยังขาด \(missing) รายการ", sub: detail, label: "ไปยังรายการที่ขาด · " + detail, action: action))
    }
}

/// The iPad bottom bar of every survey step (docs/ui/survey-bar-ipad, `g-bar`): status · `บันทึกร่างตอนนี้` · ‹ · ›
/// in a centred 1240-wide row, all 53 high. The status shrinks and truncates first.
public struct TCPadStepBar: View {
    let status: TCBarStatus
    let save: TCSaveButton
    let previous: TCStepNavButton
    let next: TCStepNavButton
    var sides: CGFloat

    public init(status: TCBarStatus, save: TCSaveButton, previous: TCStepNavButton, next: TCStepNavButton, sides: CGFloat = 24) {
        self.status = status; self.save = save; self.previous = previous; self.next = next; self.sides = sides
    }

    public var body: some View {
        HStack(spacing: 12) {
            TCBarStatusView(status).frame(maxWidth: .infinity, alignment: .leading)
            // the extra 12 groups ‹ and ›
            save.padding(.trailing, 12)
            previous
            next
        }
        .frame(maxWidth: 1240)
        .padding(.top, 8).padding(.horizontal, sides).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Rectangle().fill(Theme.surface.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2))).ignoresSafeArea(edges: .bottom))
    }
}

/// Bottom bar of a step (`g-bar`, height 53).
/// iPad: status button · `บันทึกร่างตอนนี้` · ‹ ก่อนหน้า · ถัดไป ›. iPhone: `บันทึก` stretches, ‹ and › icon only, no status button
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
    /// Changes when the answers change; returns the save button from "บันทึกแล้ว" to idle.
    var saveVersion: Int
    var onPrevious: () -> Void
    var onNext: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(count: Int, previous: Step?, next: Step?, missing: Int, missingDetail: String,
                onStatus: @escaping () -> Void = {}, onSave: @escaping () -> Void, saveVersion: Int = 0,
                onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.count = count; self.previous = previous; self.next = next
        self.missing = missing; self.missingDetail = missingDetail
        self.onStatus = onStatus; self.onSave = onSave; self.saveVersion = saveVersion; self.onPrevious = onPrevious; self.onNext = onNext
    }

    @ViewBuilder public var body: some View {
        if sizeClass == .compact {
            HStack(spacing: 12) {
                TCSaveButton(width: nil, save: save, version: saveVersion)
                nav(.previous, previous, onPrevious)
                nav(.next, next, onNext)
            }
            .padding(.top, 8).padding(.horizontal, 16).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(Rectangle().fill(Theme.surface.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2))).ignoresSafeArea(edges: .bottom))
        } else {
            TCPadStepBar(status: missing == 0
                            ? .okChip(title: "ครบช่องบังคับแล้ว", sub: missingDetail, label: "ครบช่องบังคับแล้ว · " + missingDetail, action: onStatus)
                            : .gapChip(title: "ยังขาด \(missing) รายการ", sub: missingDetail, label: "ไปยังรายการที่ขาด · " + missingDetail, action: onStatus),
                         save: .pad(save: save, version: saveVersion),
                         previous: nav(.previous, previous, onPrevious), next: nav(.next, next, onNext))
        }
    }

    /// Runs `onSave`; the button then shows "บันทึกแล้ว".
    @MainActor func save() async -> Date {
        onSave()
        return Date()
    }

    func nav(_ d: TCStepNavButton.Direction, _ s: Step?, _ action: @escaping () -> Void) -> TCStepNavButton {
        TCStepNavButton(direction: d, index: s?.index ?? 0, count: count,
                        title: s?.title ?? (d == .previous ? "หัวข้อแรก" : "ขั้นสุดท้าย"),
                        action: s == nil ? nil : action)
    }
}
#endif
