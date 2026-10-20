#if canImport(UIKit)
import SwiftUI
import UIKit

// Section 9 | Number pad (docs/ui/components/sections/09-number-pad.png).

/// Numbers shown with as many decimals as the step has (0.1 → `1.2`, 1 → `48`, 0.05 → `0.35`).
public enum TCNumberFormat {
    public static func decimals(for step: Double) -> Int {
        var d = 0, s = abs(step)
        while d < 4 && abs(s - s.rounded()) > 1e-9 { s *= 10; d += 1 }
        return d
    }

    public static func string(_ value: Double, step: Double) -> String {
        String(format: "%.\(decimals(for: step))f", value)
    }
}

/// The pad itself: header with the accepted range, − display +, the message line with `ล้าง`, 3 × 4 keys,
/// `ยกเลิก` / `ตกลง`. It edits `text`; `ตกลง` (disabled when empty or out of range) hands back the number.
/// Shown in a popover by `numberPadPopover`, or inline (the gallery).
public struct NumberPad: View {
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let allowsDecimal: Bool
    let original: Double?
    @Binding var text: String
    let onCancel: () -> Void
    let onConfirm: (Double) -> Void

    public init(title: String, range: ClosedRange<Double>, step: Double, unit: String, allowsDecimal: Bool = true,
                original: Double?, text: Binding<String>, onCancel: @escaping () -> Void, onConfirm: @escaping (Double) -> Void) {
        self.title = title; self.range = range; self.step = step; self.unit = unit; self.allowsDecimal = allowsDecimal
        self.original = original; self._text = text; self.onCancel = onCancel; self.onConfirm = onConfirm
    }

    var number: Double? { Double(text) }
    var empty: Bool { number == nil }
    var out: Bool { number.map { !range.contains($0) } ?? false }
    func fmt(_ v: Double) -> String { TCNumberFormat.string(v, step: step) }

    public var body: some View {
        VStack(spacing: 10) {
            header
            HStack(spacing: Space.s) {
                stepButton(-1)
                display
                stepButton(1)
            }
            .fixedSize(horizontal: false, vertical: true)
            message
            keys
            actions.padding(.top, 2)
        }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(title).font(.sarabun(15, .bold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            Spacer(minLength: Space.xs)
            Text("ช่วง \(fmt(range.lowerBound))–\(fmt(range.upperBound)) \(unit)")
                .font(.sarabun(12, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
        }
    }

    var display: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Spacer(minLength: 0)
            Text(empty ? "—" : text).font(.sarabun(30, .bold, relativeTo: .largeTitle)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(out ? Theme.dangerText : Theme.navy)
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(out ? Theme.dangerSoft.opacity(0.45) : Theme.primarySoft.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(out ? Theme.danger : Theme.primary, lineWidth: 2))
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(empty ? "ยังไม่มีค่า" : text + " " + unit)
    }

    func stepButton(_ k: Double) -> some View {
        Button {
            let base = number ?? range.lowerBound
            let next = ((base + k * step) / step).rounded() * step
            text = fmt(next)
        } label: {
            VStack(spacing: 0) {
                Image(systemName: k < 0 ? "minus" : "plus").font(.system(size: 20, weight: .semibold))
                Text(fmt(step)).font(.sarabun(13, .bold, relativeTo: .caption))
            }
            .foregroundStyle(Theme.primary)
            .frame(width: 52).frame(maxHeight: .infinity)
            .frame(minHeight: 56)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.3)))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityLabel((k < 0 ? "ลด " : "เพิ่ม ") + fmt(step))
    }

    var message: some View {
        HStack(spacing: Space.s) {
            Group {
                if let n = number, n > range.upperBound {
                    Text("เกินค่าสูงสุด \(fmt(range.upperBound)) \(unit)").foregroundStyle(Theme.dangerText).fontWeight(.semibold)
                } else if let n = number, n < range.lowerBound {
                    Text("ต่ำกว่าค่าต่ำสุด \(fmt(range.lowerBound)) \(unit)").foregroundStyle(Theme.dangerText).fontWeight(.semibold)
                } else if empty {
                    Text("ยังไม่มีค่า").foregroundStyle(Theme.inkMuted)
                } else {
                    Text("ค่าเดิม " + (original.map { "\(fmt($0)) \(unit)" } ?? "—")).foregroundStyle(Theme.inkMuted)
                }
            }
            .font(.sarabun(12.5, relativeTo: .caption))
            Spacer(minLength: Space.xs)
            Button("ล้าง") { text = "" }
                .font(.sarabun(13, .bold, relativeTo: .caption)).foregroundStyle(Theme.primary)
                .frame(minWidth: touchMin, minHeight: 32)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityLabel("ล้างทั้งหมด")
        }
        .frame(minHeight: 18)
    }

    var keys: some View {
        let rows = [["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"], [".", "0", "⌫"]]
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(rows, id: \.self) { row in
                GridRow { ForEach(row, id: \.self) { key($0) } }
            }
        }
    }

    @ViewBuilder func key(_ k: String) -> some View {
        if k == "." && !allowsDecimal {
            Color.clear.frame(maxWidth: .infinity, minHeight: 52)
        } else {
            Button { press(k) } label: {
                Group {
                    if k == "⌫" { Image(systemName: "delete.left").font(.system(size: 20, weight: .semibold)) }
                    else { Text(k).font(.sarabun(22, .semibold, relativeTo: .title2)) }
                }
                .foregroundStyle(Theme.navy)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.md))
                .contentShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(TCPressStyle())
            .accessibilityLabel(k == "⌫" ? "ลบหนึ่งตัว" : k == "." ? "จุดทศนิยม" : k)
        }
    }

    func press(_ k: String) {
        switch k {
        case "⌫": if !text.isEmpty { text.removeLast() }
        case ".": if allowsDecimal && !text.contains(".") { text = (text.isEmpty ? "0" : text) + "." }
        default:
            guard text.replacingOccurrences(of: ".", with: "").count < 5 else { return }
            text = text == "0" ? k : text + k
        }
    }

    var actions: some View {
        let ok = !empty && !out
        // widths 1 : 1.4
        return GeometryReader { g in
        HStack(spacing: Space.s) {
            Button(action: onCancel) {
                Text("ยกเลิก").font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.45)))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(TCPressStyle())
            .frame(width: max(0, g.size.width - Space.s) / 2.4)
            Button { if let n = number, ok { onConfirm(n) } } label: {
                Text("ตกลง").font(.sarabun(15, .bold, relativeTo: .body)).foregroundStyle(ok ? Theme.onPrimary : .white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(ok ? AnyShapeStyle(Theme.headerGradient) : AnyShapeStyle(Theme.disabledText.opacity(0.6)),
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(TCPressStyle())
            .disabled(!ok)
        }
        }
        .frame(height: 48)
    }
}

/// Opens `NumberPad` in a popover under the view, its arrow pointing at it; it stays a popover on iPhone.
/// `ตกลง` writes `value` and closes; `ยกเลิก` or a tap outside leaves the old value. Pass `draft` to show what's
/// being typed in the field itself.
public struct NumberPadPopover: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var value: Double?
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let allowsDecimal: Bool
    var draft: Binding<String>?
    @State private var ownDraft = ""

    public init(isPresented: Binding<Bool>, value: Binding<Double?>, title: String, range: ClosedRange<Double>,
                step: Double, unit: String, allowsDecimal: Bool = true, draft: Binding<String>? = nil) {
        self._isPresented = isPresented; self._value = value; self.title = title; self.range = range
        self.step = step; self.unit = unit; self.allowsDecimal = allowsDecimal; self.draft = draft
    }

    var text: Binding<String> { draft ?? $ownDraft }

    public func body(content: Content) -> some View {
        content
            .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                NumberPad(title: title, range: range, step: step, unit: unit, allowsDecimal: allowsDecimal,
                          original: value, text: text,
                          onCancel: { isPresented = false },
                          onConfirm: { value = $0; isPresented = false })
                    .padding(14)
                    .frame(width: 328)
                    .presentationCompactAdaptation(.popover)
            }
            .onChange(of: isPresented, initial: true) { _, open in
                if open { text.wrappedValue = value.map { TCNumberFormat.string($0, step: step) } ?? "" }
            }
    }
}

public extension View {
    /// See `NumberPadPopover`.
    func numberPadPopover(isPresented: Binding<Bool>, value: Binding<Double?>, title: String, range: ClosedRange<Double>,
                          step: Double, unit: String, allowsDecimal: Bool = true, draft: Binding<String>? = nil) -> some View {
        modifier(NumberPadPopover(isPresented: isPresented, value: value, title: title, range: range, step: step,
                                  unit: unit, allowsDecimal: allowsDecimal, draft: draft))
    }
}
#endif
