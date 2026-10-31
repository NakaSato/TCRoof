#if canImport(UIKit)
import SwiftUI
import UIKit

// Section 3 | Inputs (docs/ui/components/sections/03-inputs.png).

/// Field name: 17 semibold navy, red `*` when required, grey `ไม่บังคับ` at the end when optional.
public struct TCFieldLabel: View {
    let title: String
    var required: Bool
    var optional: Bool

    public init(_ title: String, required: Bool = false, optional: Bool = false) {
        self.title = title; self.required = required; self.optional = optional
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.sarabun(TypeScale.label, .semibold, relativeTo: .headline)).foregroundStyle(Theme.navy)
            if required {
                Text("*").font(.sarabun(TypeScale.label, .semibold, relativeTo: .headline)).foregroundStyle(Theme.danger)
                    .accessibilityLabel("บังคับ")
            }
            if optional {
                Spacer(minLength: Space.s)
                Text("ไม่บังคับ").font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The look of a field box (`g-input`): min 50 high, radius 10, navy 45 % border.
public enum TCFieldState: Sendable {
    case normal
    /// 2 pt blue border while typing or while its number pad is open.
    case focused
    /// Required but empty, or out of range: red border, pink fill.
    case error
    /// Filled by the system: mint fill.
    case calculated
    /// From another step: grey fill, quiet border.
    case readOnly
}

public extension View {
    /// Draws the field box around `self` for `state`.
    func tcFieldFrame(_ state: TCFieldState, minHeight: CGFloat = 50, horizontal: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md)
        let fill: Color = switch state {
        case .calculated: Theme.mint.opacity(0.3)
        case .readOnly: Theme.background
        case .error: Theme.dangerSoft.opacity(0.45)
        default: Theme.surface
        }
        let border: Color = switch state {
        case .focused: Theme.primary
        case .error: Theme.danger
        case .readOnly: Theme.borderSubtle
        default: Theme.navy.opacity(0.45)
        }
        return padding(.horizontal, horizontal)
            .frame(minHeight: minHeight)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: state == .focused || state == .error ? 2 : 1))
            .contentShape(shape)
    }
}

/// Where a pre-filled value came from: grey `ตั้งต้น` (the default, type over it) or green `ป้าย` (read off the nameplate).
public enum TCValueSource: Sendable {
    case defaultValue(String)
    case nameplate
}

/// Text or number field with an optional unit.
/// - `calculated`: mint fill, the system filled it.
/// - `required`: when empty (and not being typed in) red border, pink fill, `—`; it counts in `ยังขาด n ช่อง`.
/// - `readOnly`: grey with a lock; the value comes from another step, so edit it there.
/// - `source`: the `ตั้งต้น` / `ป้าย` tag.
public struct TCTextField: View {
    let placeholder: String
    @Binding var text: String
    var unit: String?
    var calculated: Bool
    var required: Bool
    var readOnly: Bool
    var source: TCValueSource?
    var keyboard: UIKeyboardType
    var focused: Bool
    @FocusState private var typing: Bool

    public init(_ placeholder: String = "", text: Binding<String>, unit: String? = nil, calculated: Bool = false,
                required: Bool = false, readOnly: Bool = false, source: TCValueSource? = nil,
                keyboard: UIKeyboardType = .default, focused: Bool = false) {
        self.placeholder = placeholder; self._text = text; self.unit = unit; self.calculated = calculated
        self.required = required; self.readOnly = readOnly; self.source = source; self.keyboard = keyboard; self.focused = focused
    }

    var state: TCFieldState {
        if readOnly { return .readOnly }
        if typing || focused { return .focused }
        if required && text.isEmpty { return .error }
        return calculated ? .calculated : .normal
    }

    public var body: some View {
        HStack(spacing: 10) {
            if readOnly {
                Text(text + (unit.map { " " + $0 } ?? "")).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "lock").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
            } else {
                field
                if let unit { Text(unit).font(.sarabun(16, relativeTo: .body)).foregroundStyle(Theme.muted) }
                tag
            }
        }
        .font(.sarabun(TypeScale.label, relativeTo: .body))
        .foregroundStyle(Theme.navy)
        .tcFieldFrame(state, horizontal: source == nil ? 14 : 10)
        .onTapGesture { if !readOnly { typing = true } }
        .accessibilityElement(children: readOnly ? .combine : .contain)
        .accessibilityHint(readOnly ? "อ่านอย่างเดียว แก้ที่ขั้นต้นทาง" : "")
    }

    var field: some View {
        TextField(text: $text) {
            Text(prompt).foregroundStyle(Theme.muted)
        }
        .keyboardType(keyboard)
        .focused($typing)
        .fontWeight(sourceWeight)
        .accessibilityLabel(placeholder)
    }

    var prompt: String {
        if case .defaultValue(let d) = source { return d }
        return required ? "—" : placeholder
    }

    var sourceWeight: Font.Weight {
        if source == nil { return .regular }
        return text.isEmpty ? .semibold : .bold
    }

    @ViewBuilder var tag: some View {
        switch source {
        case .defaultValue where text.isEmpty:
            Text("ตั้งต้น").font(.sarabun(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.primary)
        case .nameplate where !text.isEmpty:
            Text("ป้าย").font(.sarabun(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.okTick)
        default:
            EmptyView()
        }
    }
}

/// Dropdown: bold value and a chevron in a field box; the menu marks the current value with ✓ and closes after a pick.
public struct TCDropdown: View {
    let options: [String]
    @Binding var selection: String
    var placeholder: String
    var accessibilityTitle: String

    public init(_ options: [String], selection: Binding<String>, placeholder: String = "เลือก", accessibilityTitle: String = "") {
        self.options = options; self._selection = selection; self.placeholder = placeholder; self.accessibilityTitle = accessibilityTitle
    }

    public var body: some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Button { selection = o } label: {
                    if o == selection { Label(o, systemImage: "checkmark") } else { Text(o) }
                }
            }
        } label: {
            TCDropdownLabel(title: selection.isEmpty ? placeholder : selection, placeholder: selection.isEmpty)
        }
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(selection)
    }
}

/// The closed dropdown box; `open` draws the 2 pt focus border.
public struct TCDropdownLabel: View {
    let title: String
    var placeholder: Bool
    var open: Bool

    public init(title: String, placeholder: Bool = false, open: Bool = false) {
        self.title = title; self.placeholder = placeholder; self.open = open
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Text(title).font(.sarabun(TypeScale.label, placeholder ? .regular : .bold, relativeTo: .body))
                .foregroundStyle(placeholder ? Theme.muted : Theme.navy).lineLimit(1)
            Spacer(minLength: Space.xs)
            Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.navy)
        }
        .tcFieldFrame(open ? .focused : .normal)
    }
}

/// The open list of a dropdown, for screens that draw it inline: 44 pt rows, the current one tinted with ✓.
public struct TCDropdownList: View {
    let options: [String]
    let selection: String
    let pick: (String) -> Void

    public init(_ options: [String], selection: String, pick: @escaping (String) -> Void) {
        self.options = options; self.selection = selection; self.pick = pick
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(options, id: \.self) { o in
                Button { pick(o) } label: {
                    HStack(spacing: Space.s) {
                        Text(o).font(.sarabun(15, o == selection ? .bold : .regular, relativeTo: .body)).foregroundStyle(Theme.navy)
                        Spacer(minLength: 0)
                        if o == selection { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.primary) }
                    }
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: touchMin)
                    .background(o == selection ? Theme.primarySoft : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(o == selection ? .isSelected : [])
            }
        }
        .padding(Space.xs)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.borderSubtle))
        .shadow(color: Theme.navy.opacity(0.18), radius: 14, y: 10)
    }
}

/// Date (`29/9/2569`, calendar icon) or time (`10:30 น.`, clock icon) in a field box; tapping opens the system picker.
public struct TCDateField: View {
    public enum Kind: Sendable { case date, time }

    @Binding var date: Date
    var kind: Kind
    var accessibilityTitle: String

    public init(date: Binding<Date>, kind: Kind = .date, accessibilityTitle: String = "") {
        self._date = date; self.kind = kind; self.accessibilityTitle = accessibilityTitle
    }

    static let thai = Locale(identifier: "th_TH")

    var text: String {
        switch kind {
        case .date:
            var cal = Calendar(identifier: .buddhist); cal.locale = Self.thai
            let c = cal.dateComponents([.day, .month, .year], from: date)
            return "\(c.day ?? 0)/\(c.month ?? 0)/\(c.year ?? 0)"
        case .time:
            return date.formatted(Date.FormatStyle(locale: Self.thai).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) + " น."
        }
    }

    public var body: some View {
        HStack {
            Text(text).font(.sarabun(TypeScale.label, relativeTo: .body)).foregroundStyle(Theme.navy)
            Spacer(minLength: Space.xs)
            Image(systemName: kind == .date ? "calendar" : "clock").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
        }
        .tcFieldFrame(.normal)
        .overlay {
            // the compact picker opens its own calendar / wheel on tap; it is invisible over the drawn field
            DatePicker("", selection: $date, displayedComponents: kind == .date ? .date : .hourAndMinute)
                .labelsHidden()
                .environment(\.locale, Self.thai)
                .scaleEffect(x: 3, y: 1.4)
                // drawn fully clear (still tappable): a low opacity alone leaves a ghost of its text
                .colorMultiply(.clear)
                .opacity(0.02)
                .accessibilityLabel(accessibilityTitle)
        }
        .clipped()
    }
}

/// − value + in one box (52 × 50 buttons, 18 pt bold value).
public struct TCStepperField: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var unit: String
    var title: String

    public init(value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, unit: String = "", title: String = "") {
        self._value = value; self.range = range; self.step = step; self.unit = unit; self.title = title
    }

    var text: String { TCNumberFormat.string(value, step: step) + (unit.isEmpty ? "" : " " + unit) }

    public var body: some View {
        HStack(spacing: 0) {
            button("minus", "ลด \(TCNumberFormat.string(step, step: step))", enabled: value - step >= range.lowerBound - 1e-9) {
                value = max(range.lowerBound, value - step)
            }
            Text(text).font(.sarabun(18, .bold, relativeTo: .body)).foregroundStyle(Theme.navy).monospacedDigit()
                .frame(minWidth: 70).frame(maxWidth: .infinity)
            button("plus", "เพิ่ม \(TCNumberFormat.string(step, step: step))", enabled: value + step <= range.upperBound + 1e-9) {
                value = min(range.upperBound, value + step)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.45)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    func button(_ symbol: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                .foregroundStyle(enabled ? Theme.primary : Theme.disabledText)
                .frame(width: 52, height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// From – to, two small boxes (`06:00 – 18:00`, a min–max distance).
public struct TCRangeField: View {
    @Binding var from: String
    @Binding var to: String
    var fromPrompt: String
    var toPrompt: String
    var keyboard: UIKeyboardType

    public init(from: Binding<String>, to: Binding<String>, fromPrompt: String = "จาก", toPrompt: String = "ถึง", keyboard: UIKeyboardType = .numbersAndPunctuation) {
        self._from = from; self._to = to; self.fromPrompt = fromPrompt; self.toPrompt = toPrompt; self.keyboard = keyboard
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            box($from, fromPrompt)
            Text("–").font(.sarabun(17, relativeTo: .body)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            box($to, toPrompt)
        }
    }

    func box(_ text: Binding<String>, _ prompt: String) -> some View {
        TextField(text: text) { Text(prompt).foregroundStyle(Theme.muted) }
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.sarabun(TypeScale.label, relativeTo: .body)).foregroundStyle(Theme.navy)
            .tcFieldFrame(.normal, horizontal: 10)
            .accessibilityLabel(prompt)
    }
}

/// A yes/no value that needs nothing more: label and a green switch, 44 pt row.
public struct TCSwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    public init(_ title: String, isOn: Binding<Bool>) { self.title = title; self._isOn = isOn }

    public var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).font(.sarabun(15, relativeTo: .body)).foregroundStyle(Theme.navy)
        }
        .tint(Theme.success)
        .frame(minHeight: touchMin)
    }
}

/// Search box: magnifier, prompt, ✕ (only when there is text, 44 pt target), and an optional accessory on the right
/// (`TCSearchTypePicker`).
public struct TCSearchField<Accessory: View>: View {
    let prompt: String
    @Binding var text: String
    var accessory: Accessory

    public init(_ prompt: String, text: Binding<String>, @ViewBuilder accessory: () -> Accessory) {
        self.prompt = prompt; self._text = text; self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.navy)
                .padding(.leading, Space.m)
                .accessibilityHidden(true)
            TextField(text: $text) { Text(prompt).foregroundStyle(Theme.muted) }
                .font(.sarabun(16, relativeTo: .body)).foregroundStyle(Theme.navy)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(prompt)
            if !text.isEmpty { TCClearButton { text = "" } }
            accessory
        }
        .frame(minHeight: 50)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

public extension TCSearchField where Accessory == EmptyView {
    init(_ prompt: String, text: Binding<String>) { self.init(prompt, text: text) { EmptyView() } }
}

/// Grey ✕ in a 20 pt circle, 44 pt target: clears a field.
public struct TCClearButton: View {
    let action: () -> Void
    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Theme.chevron, in: Circle())
                .frame(width: touchMin, height: touchMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ล้าง")
    }
}

/// The type menu at the right of a search box: `ทุกประเภท | 10 ▾` on a grey panel.
public struct TCSearchTypePicker: View {
    let options: [String]
    @Binding var selection: String
    var count: Int?

    public init(_ options: [String], selection: Binding<String>, count: Int? = nil) {
        self.options = options; self._selection = selection; self.count = count
    }

    public var body: some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Button { selection = o } label: {
                    if o == selection { Label(o, systemImage: "checkmark") } else { Text(o) }
                }
            }
        } label: {
            HStack(spacing: Space.s) {
                Text(selection + (count.map { " | \($0)" } ?? "")).font(.sarabun(14.5, .semibold, relativeTo: .body))
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Theme.navy)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .frame(minHeight: 50)
            .background(Theme.background)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.borderSubtle).frame(width: 1) }
        }
        .accessibilityLabel("ประเภท")
        .accessibilityValue(selection)
    }
}
#endif
