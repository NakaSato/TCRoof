#if canImport(UIKit)
import SwiftUI
import UIKit

// Section 3 · Inputs (docs/ui/components/sections/03-inputs.png).

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

/// The type menu at the right of a search box: `ทุกประเภท · 10 ▾` on a grey panel.
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
                Text(selection + (count.map { " · \($0)" } ?? "")).font(.sarabun(14.5, .semibold, relativeTo: .body))
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

/// One answer chip (`g-choice`): min 54, radius 10; on = mint; a negative answer ("ไม่ผ่าน", "ไม่ใช่") on = danger 25 %.
public struct TCChoiceChip: View {
    let title: String
    let selected: Bool
    var negative: Bool
    let action: () -> Void

    public init(_ title: String, selected: Bool, negative: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.negative = negative; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sarabun(TypeScale.label, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(fill, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(selected ? 0.2 : 0.5)))
                .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var fill: Color {
        guard selected else { return Theme.surface }
        return negative ? Theme.danger.opacity(0.25) : Theme.mint
    }
}

/// Single-select chips in a row; tapping the selected one clears it. `negative` names the answers that turn red.
public struct TCChoiceChips: View {
    let options: [String]
    @Binding var selection: String?
    var negative: Set<String>

    public init(_ options: [String], selection: Binding<String?>, negative: Set<String> = []) {
        self.options = options; self._selection = selection; self.negative = negative
    }

    public var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.self) { o in
                TCChoiceChip(o, selected: selection == o, negative: negative.contains(o)) {
                    selection = selection == o ? nil : o
                }
            }
        }
    }
}

/// Segmented control: grey track, the selected segment white and bold (`10:00 12:00 14:00`, `แปลน / 3 มิติ`).
/// `.filter` is the iPhone list filter (`7 วัน / 30 วัน / ทั้งหมด`, docs/ui/tcroof-survey-list-iphone):
/// 44 high, padding and gap 3, track r10, segment r8, regular 14 pt when not selected.
public struct TCSegmented: View {
    public enum Style { case standard, filter }

    let options: [String]
    @Binding var selection: String
    var fontSize: CGFloat
    var style: Style

    public init(_ options: [String], selection: Binding<String>, fontSize: CGFloat = 14.5, style: Style = .standard) {
        self.options = options; self._selection = selection; self.fontSize = fontSize; self.style = style
    }

    private var filter: Bool { style == .filter }

    public var body: some View {
        HStack(spacing: filter ? 3 : Space.xs) {
            ForEach(options, id: \.self) { o in
                let on = o == selection
                Button { selection = o } label: {
                    Text(o).font(.sarabun(fontSize, on ? .bold : filter ? .regular : .semibold, relativeTo: .body))
                        .foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: filter ? 38 : 40)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: filter ? 8 : 9).fill(Theme.surface)
                                    .shadow(color: Theme.navy.opacity(0.2), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(filter ? 3 : Space.xs)
        .background(filter ? Theme.segmentTrack : Theme.track, in: RoundedRectangle(cornerRadius: filter ? 10 : Radius.lg))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// Capsule tabs (`7 วัน · 30 วัน · ทั้งหมด`): selected solid blue, others soft blue; 44 high.
public struct TCCapsuleTabs: View {
    let options: [String]
    @Binding var selection: String

    public init(_ options: [String], selection: Binding<String>) {
        self.options = options; self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { o in
                let on = o == selection
                Button { selection = o } label: {
                    Text(o).font(.sarabun(14, .semibold, relativeTo: .body)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(on ? Theme.onPrimary : Theme.primary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: touchMin)
                        .background(on ? Theme.primary : Theme.primarySoft, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Multi-select chips, two per row (an odd last one spans the row): on = mint with ✓.
public struct TCMultiChips: View {
    let options: [String]
    @Binding var selection: Set<String>
    var columns: Int

    public init(_ options: [String], selection: Binding<Set<String>>, columns: Int = 2) {
        self.options = options; self._selection = selection; self.columns = max(1, columns)
    }

    var rows: [[String]] {
        stride(from: 0, to: options.count, by: columns).map { Array(options[$0 ..< min($0 + columns, options.count)]) }
    }

    public var body: some View {
        VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) { ForEach(row, id: \.self) { chip($0) } }
            }
        }
    }

    func chip(_ o: String) -> some View {
        let on = selection.contains(o)
        return Button {
            if on { selection.remove(o) } else { selection.insert(o) }
        } label: {
            Text((on ? "✓ " : "") + o).font(.sarabun(14, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                .padding(.horizontal, Space.s)
                .frame(maxWidth: .infinity, minHeight: touchMin)
                .background(on ? Theme.mint : Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(on ? 0.2 : 0.5)))
                .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityLabel(o)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Checkbox (system spec): 22 × 22, radius 3; on = green fill with a white ✓, off = white with a 75 % black border; row ≥ 44.
public struct TCCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    public init(_ title: String, isOn: Binding<Bool>) { self.title = title; self._isOn = isOn }

    public var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                TCCheckboxMark(on: isOn)
                Text(title).font(.sarabun(15, relativeTo: .body)).foregroundStyle(Theme.navy)
                    .multilineTextAlignment(.leading)
            }
            .frame(minHeight: touchMin, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityValue(isOn ? "เลือกแล้ว" : "ไม่ได้เลือก")
    }
}

/// The 22 pt box of a checkbox alone.
public struct TCCheckboxMark: View {
    let on: Bool
    public init(on: Bool) { self.on = on }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.box).fill(on ? Theme.okTick : Theme.surface)
            if on {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
            } else {
                RoundedRectangle(cornerRadius: Radius.box).strokeBorder(Theme.paperRule, lineWidth: 1)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// Radio card: title over a subtitle; selected = 2 pt blue border, soft blue fill, a ring dot.
public struct TCRadioCard: View {
    let title: String
    var subtitle: String?
    let selected: Bool
    let action: () -> Void

    public init(_ title: String, subtitle: String? = nil, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.subtitle = subtitle; self.selected = selected; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(selected ? Theme.primary : Theme.borderControl, lineWidth: selected ? 6 : 1.5)
                    .background(Circle().fill(Theme.surface))
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.sarabun(16, .bold, relativeTo: .body)).foregroundStyle(Theme.navy)
                    if let subtitle {
                        Text(subtitle).font(.sarabun(12.5, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.m).padding(.vertical, 6)
            .frame(minHeight: 52)
            .background(selected ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(selected ? Theme.primary : Theme.borderControl, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(TCPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Long text in a field box; with `limit` the text stops there and `22/200` shows under it.
public struct TCLongText: View {
    let prompt: String
    @Binding var text: String
    var limit: Int?
    var minHeight: CGFloat
    @FocusState private var typing: Bool

    public init(_ prompt: String = "", text: Binding<String>, limit: Int? = nil, minHeight: CGFloat? = nil) {
        self.prompt = prompt; self._text = text; self.limit = limit; self.minHeight = minHeight ?? (limit == nil ? 96 : 72)
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: Space.xs) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(prompt).foregroundStyle(Theme.muted).padding(.top, 8).padding(.leading, 5).accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .focused($typing)
                    .accessibilityLabel(prompt)
            }
            .font(.sarabun(15, relativeTo: .body)).foregroundStyle(Theme.navy)
            .padding(.vertical, 4)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .tcFieldFrame(typing ? .focused : .normal, minHeight: minHeight, horizontal: 9)
            .onChange(of: text) { _, new in
                if let limit, new.count > limit { text = String(new.prefix(limit)) }
            }
            if let limit {
                Text("\(text.count)/\(limit)").font(.sarabun(11.5, relativeTo: .caption2)).foregroundStyle(Theme.muted)
                    .monospacedDigit()
                    .accessibilityLabel("\(text.count) จาก \(limit) ตัวอักษร")
            }
        }
    }
}

/// Signature box: dashed frame, the strokes drawn with a finger, a rule and the signer's role under it.
public struct TCSignatureBox: View {
    @Binding var strokes: [[CGPoint]]
    var role: String
    var height: CGFloat

    public init(strokes: Binding<[[CGPoint]]>, role: String = "วิศวกรผู้สำรวจ", height: CGFloat = 110) {
        self._strokes = strokes; self.role = role; self.height = height
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Theme.paperRule).frame(height: 1)
                .padding(.horizontal, Space.l).padding(.bottom, 30)
            Text(role).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                .padding(.leading, Space.l).padding(.bottom, 6)
            Path { p in
                for s in strokes where !s.isEmpty {
                    p.move(to: s[0])
                    for q in s.dropFirst() { p.addLine(to: q) }
                }
            }
            .stroke(Theme.navy, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if g.translation == .zero || strokes.isEmpty { strokes.append([g.location]) }
                    else { strokes[strokes.count - 1].append(g.location) }
                }
                .onEnded { _ in strokes.append([]) }
        )
        .accessibilityElement()
        .accessibilityLabel("ช่องลายเซ็น " + role)
        .accessibilityValue(strokes.contains { $0.count > 1 } ? "เซ็นแล้ว" : "ยังไม่ได้เซ็น")
    }
}

/// A source button in a field (`g-pbtn`): blue icon, navy 16 pt text, white, ≥ 46 high (`ตำแหน่งปัจจุบัน`, `อัปโหลด`, `กล้อง`).
public struct TCSourceButton: View {
    let title: String
    let systemImage: String
    var working: Bool
    let action: () -> Void

    public init(_ title: String, systemImage: String, working: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.working = working; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                if working { ProgressView().tint(Theme.primary) }
                else { Image(systemName: systemImage).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary) }
                Text(title).font(.sarabun(16, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.navy.opacity(0.45)))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(TCPressStyle())
        .allowsHitTesting(!working)
    }
}

/// `ตำแหน่งปัจจุบัน`: the location source button.
public struct TCLocationButton: View {
    var working: Bool
    let action: () -> Void
    public init(working: Bool = false, action: @escaping () -> Void) { self.working = working; self.action = action }
    public var body: some View { TCSourceButton("ตำแหน่งปัจจุบัน", systemImage: "location", working: working, action: action) }
}

/// Number field that opens `NumberPadPopover` instead of the system keyboard: bold value, unit and a keypad icon.
/// While the pad is open it shows what's being typed, with the 2 pt blue (or red, out of range) border.
public struct TCNumberField: View {
    let title: String
    @Binding var value: Double?
    var range: ClosedRange<Double>
    var step: Double
    var unit: String
    var allowsDecimal: Bool
    var required: Bool
    @State private var open = false
    @State private var draft = ""

    public init(_ title: String, value: Binding<Double?>, range: ClosedRange<Double>, step: Double = 1, unit: String = "",
                allowsDecimal: Bool = true, required: Bool = false) {
        self.title = title; self._value = value; self.range = range; self.step = step; self.unit = unit
        self.allowsDecimal = allowsDecimal; self.required = required
    }

    var shown: String {
        if open { return draft }
        return value.map { TCNumberFormat.string($0, step: step) } ?? (required ? "—" : "")
    }

    var state: TCFieldState {
        if open { return Double(draft).map { range.contains($0) } == false ? .error : .focused }
        return required && value == nil ? .error : .normal
    }

    public var body: some View {
        Button { open = true } label: {
            HStack(spacing: 6) {
                Text(shown).font(.sarabun(TypeScale.label, .bold, relativeTo: .body))
                    .foregroundStyle(value == nil && !open ? Theme.muted : Theme.navy).monospacedDigit()
                if open {
                    Rectangle().fill(Theme.primary).frame(width: 2, height: 20).accessibilityHidden(true)
                }
                Spacer(minLength: Space.xs)
                Text(unit).font(.sarabun(16, .semibold, relativeTo: .body)).foregroundStyle(Theme.muted)
                Image(systemName: "keyboard").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.primary)
            }
            .tcFieldFrame(state)
        }
        .buttonStyle(.plain)
        .numberPadPopover(isPresented: $open, value: $value, title: title, range: range, step: step, unit: unit,
                          allowsDecimal: allowsDecimal, draft: $draft)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { TCNumberFormat.string($0, step: step) + " " + unit } ?? "ว่าง")
        .accessibilityHint("แตะเพื่อเปิดแป้นตัวเลข")
    }
}
#endif
