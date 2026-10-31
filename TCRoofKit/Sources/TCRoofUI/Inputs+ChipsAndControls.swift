#if canImport(UIKit)
import SwiftUI
import UIKit

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
/// `.view` is the iPhone view switch (`เดือน / สัปดาห์`, docs/ui/tcroof-plan-calendar-iphone):
/// 44 high, padding and gap 2, track r12, segment r10, bold `inkStrong` when not selected.
public struct TCSegmented: View {
    public enum Style { case standard, filter, view }

    let options: [String]
    @Binding var selection: String
    var fontSize: CGFloat
    var style: Style

    public init(_ options: [String], selection: Binding<String>, fontSize: CGFloat = 14.5, style: Style = .standard) {
        self.options = options; self._selection = selection; self.fontSize = fontSize; self.style = style
    }

    private var filter: Bool { style == .filter }
    private var gap: CGFloat { style == .view ? 2 : filter ? 3 : Space.xs }
    private var segmentHeight: CGFloat { style == .view ? 40 : filter ? 38 : 40 }
    private var segmentRadius: CGFloat { style == .view ? 10 : filter ? 8 : 9 }
    private var trackRadius: CGFloat { style == .view ? Radius.lg : filter ? 10 : Radius.lg }

    private func weight(_ on: Bool) -> Font.Weight {
        if on || style == .view { return .bold }
        return filter ? .regular : .semibold
    }

    public var body: some View {
        HStack(spacing: gap) {
            ForEach(options, id: \.self) { o in
                let on = o == selection
                Button { selection = o } label: {
                    Text(o).font(.sarabun(fontSize, weight(on), relativeTo: .body))
                        .foregroundStyle(on ? Theme.navy : style == .view ? Theme.inkStrong : Theme.inkMuted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: segmentHeight)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: segmentRadius).fill(Theme.surface)
                                    .shadow(color: Theme.navy.opacity(style == .view ? 0.25 : 0.2), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(gap)
        .background(style == .standard ? Theme.track : Theme.segmentTrack, in: RoundedRectangle(cornerRadius: trackRadius))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// Capsule tabs (`7 วัน | 30 วัน | ทั้งหมด`): selected solid blue, others soft blue; 44 high.
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
