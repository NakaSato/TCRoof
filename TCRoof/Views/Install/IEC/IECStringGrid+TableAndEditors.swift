import SwiftUI
import TCRoofUI
import TCRoofCore

extension IECStringGrid {

    // MARK: table

    static let labelWidth: CGFloat = 150
    static let rowHeight: CGFloat = 40

    func table(_ r: IECReport, _ inv: IECReport.Inverter, _ index: Int) -> some View {
        let seq = Dictionary(uniqueKeysWithValues: inv.strings.map { ($0.slot, $0.seq) })
        return VStack(spacing: 0) {
            headerRows
            ForEach(rows(phase), id: \.self) { row in
                HStack(spacing: 0) {
                    rowTitle(title(row))
                    ForEach(1...IECReport.slotCount, id: \.self) { slot in
                        cell(r, inv, index, row: row, slot: slot, seq: seq[slot])
                    }
                }
                .frame(height: Self.rowHeight)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
            if phase == .before { checkRow("Continuity", inv.continuity, note: "ทั้ง inverter (ช่อง merge E11:X11)") { v in save { $0.continuity = v } } }
            checkRow("Inverter testing", phase == .before ? inv.functionalBefore : inv.functionalAfter, note: nil) { v in
                let p = phase
                save { if p == .before { $0.functionalBefore = v } else { $0.functionalAfter = v } }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func rowTitle(_ text: String) -> some View {
        Text(text).font(.sarabunFixed(14)).foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 10).frame(width: Self.labelWidth, alignment: .leading)
    }

    /// `รายการ | MPPT 1 … 10` over `ช่อง String | 1 … 20`, on the sheet's green band.
    private var headerRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("รายการ").font(.sarabunFixed(14, .bold)).padding(.horizontal, 10).frame(width: Self.labelWidth, alignment: .leading)
                ForEach(1...IECReport.slotCount / 2, id: \.self) { m in
                    Text("MPPT \(m)").font(.sarabunFixed(13, .bold)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.surface.opacity(0.7)).frame(width: 1) }
                }
            }
            .frame(height: 38)
            HStack(spacing: 0) {
                Text("ช่อง String").font(.sarabunFixed(13)).padding(.horizontal, 10).frame(width: Self.labelWidth, alignment: .leading)
                ForEach(1...IECReport.slotCount, id: \.self) { s in
                    Text("\(s)").font(.sarabunFixed(13)).monospacedDigit().frame(maxWidth: .infinity)
                }
            }
            .frame(height: 30)
        }
        .foregroundStyle(Theme.navy)
        .background(Theme.paperBand)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(_ r: IECReport, _ inv: IECReport.Inverter, _ index: Int, row: Row, slot: Int, seq: Int?) -> some View {
        let s = inv.slots[slot - 1]
        let on = selected == slot
        let content = cellContent(r, inv, row: row, slot: slot, s: s, seq: seq)
        Button {
            selected = slot
            guard s != nil else { return }
            switch row {
            case .polarity: save { $0.slots[slot - 1]?.polarityOK = Self.nextPolarity(s?.polarityOK) }
            case .modules, .testV, .voltage, .current, .insulation: editing = Cell(row: row, slot: slot)
            case .label, .photos: break
            }
        } label: {
            content.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(on ? Theme.primarySoft.opacity(0.45) : .clear)
        .overlay {
            if on {
                Rectangle().fill(Theme.primary).frame(width: 2).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Theme.primary).frame(width: 2).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .popover(isPresented: Binding(get: { editing == Cell(row: row, slot: slot) }, set: { if !$0 { editing = nil } })) {
            editor(row: row, slot: slot, label: seq.map { IECReport.label(inverter: index + 1, seq: $0) } ?? "String \(slot)", s: s)
        }
        .accessibilityLabel("\(title(row)) ช่อง \(slot)")
        .accessibilityValue(spoken(row, s))
    }

    /// What a cell says to VoiceOver (and to the UI tests).
    private func spoken(_ row: Row, _ s: IECReport.Slot?) -> String {
        guard let s else { return "ไม่มีสตริง" }
        func n(_ v: Double?, _ d: Int) -> String { v.map { IECFormat.number($0, digits: d) } ?? "ยังขาด" }
        switch row {
        case .label: return ""
        case .modules: return "\(s.modules) แผง"
        case .polarity: return s.polarityOK.map { $0 ? "ขั้วถูก" : "ขั้วผิด" } ?? "ยังขาด"
        case .testV: return n(s.irTestV.map(Double.init), 0)
        case .voltage: return n(phase == .before ? s.vocV : s.vmpV, 1)
        case .current: return n(phase == .before ? s.iBeforeA : s.impA, 2)
        case .photos: return ""
        case .insulation: return s.irPass.map { $0 ? "ผ่าน" : "ไม่ผ่าน" } ?? "ยังขาด"
        }
    }

    private static func nextPolarity(_ v: Bool?) -> Bool? {
        switch v { case nil: true; case true?: false; case false?: nil }
    }

    @ViewBuilder
    private func cellContent(_ r: IECReport, _ inv: IECReport.Inverter, row: Row, slot: Int, s: IECReport.Slot?, seq: Int?) -> some View {
        if let s {
            switch row {
            case .label: Text("ST\(seq ?? 0)").font(.sarabunFixed(13)).foregroundStyle(Theme.navy)
            case .modules: value(Double(s.modules), digits: 0)
            case .polarity:
                switch s.polarityOK {
                case true?: Text("✓").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                case false?: Text("✗").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.dangerText)
                case nil: missingDot
                }
            case .testV: s.irTestV.map { value(Double($0), digits: 0) } ?? AnyView(missingDot)
            case .voltage:
                let v = phase == .before ? s.vocV : s.vmpV
                let off = phase == .before && (r.vocDeviation(inv, slot: slot).map { abs($0) > IECReport.vocTolerance } ?? false)
                v.map { value($0, digits: 1, ink: off ? Theme.dangerText : Theme.navy) } ?? AnyView(missingDot)
            case .current:
                (phase == .before ? s.iBeforeA : s.impA).map { value($0, digits: 2) } ?? AnyView(missingDot)
            case .photos:
                let kinds: [IECReport.PhotoKind] = phase == .before ? [.voltageBefore, .currentBefore] : [.voltageAfter, .currentAfter]
                let n = kinds.filter { s.photo($0) != nil }.count
                countChip(n, kinds.count)
            case .insulation:
                switch s.irPass {
                case true?: Text(IECFormat.number(min(s.irPosMOhm ?? 0, s.irNegMOhm ?? 0), digits: 0)).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.successInk)
                case false?: Text("✗").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.dangerText)
                case nil: countChip(0, 1)
                }
            }
        } else {
            Text("—").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
        }
    }

    private func value(_ v: Double, digits: Int, ink: Color = Theme.navy) -> AnyView {
        AnyView(Text(IECFormat.number(v, digits: digits)).font(.sarabunFixed(15, .bold)).foregroundStyle(ink)
            .lineLimit(1).minimumScaleFactor(0.6).monospacedDigit())
    }

    private var missingDot: some View {
        Circle().fill(Theme.pending).frame(width: 7, height: 7).accessibilityLabel("ยังขาด")
    }

    private func countChip(_ n: Int, _ of: Int) -> some View {
        let done = n >= of
        return Text("\(n)/\(of)").font(.sarabunFixed(12, .bold)).foregroundStyle(done ? Theme.successInk : Theme.warningInk)
            .padding(.horizontal, 5).frame(height: 22)
            .background(done ? Theme.successSoft : Theme.pendingSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    /// An inverter-wide check across the slot columns, set from a menu.
    private func checkRow(_ title: String, _ value: IECReport.Check?, note: String?, set: @escaping (IECReport.Check?) -> Void) -> some View {
        HStack(spacing: 0) {
            rowTitle(title)
            Menu {
                Button("Normal") { set(.normal) }
                Button("Abnormal") { set(.abnormal) }
                if value != nil { Button("ล้างค่า", role: .destructive) { set(nil) } }
            } label: {
                HStack(spacing: 8) {
                    switch value {
                    case .normal?: Text("Normal").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                    case .abnormal?: Text("Abnormal").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.dangerText)
                    case nil: Text("● ยังไม่ได้ตรวจ").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.warningInk)
                    }
                    if let note { Text("| " + note).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted) }
                    Spacer()
                }
                .padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .accessibilityLabel(title)
        }
        .frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    var legend: some View {
        HStack(spacing: 16) {
            Text("755 ค่าที่วัด")
            Text("✓ ขั้วถูกต้อง")
            HStack(spacing: 4) { countChip(2, 2); Text("รูปครบ") }
            HStack(spacing: 4) { missingDot; Text("ยังขาด") }
            Text("— ช่องว่าง (ไม่มีสตริง)")
            Text("แตะช่องเพื่อกรอก")
        }
        .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        .accessibilityHidden(true)
    }

    // MARK: editor

    @ViewBuilder
    private func editor(row: Row, slot: Int, label: String, s: IECReport.Slot?) -> some View {
        let close = { editing = nil }
        switch row {
        case .modules:
            IECValueEditor(title: "จำนวนแผง | \(label)", unit: "แผง", initial: s.map { Double($0.modules) }, integer: true) { v in
                if let v, v > 0 { save { $0.slots[slot - 1]?.modules = Int(v) } }
                close()
            }
        case .testV:
            IECValueEditor(title: "Test Voltage | \(label)", unit: "V", initial: s?.irTestV.map(Double.init), integer: true) { v in
                save { $0.slots[slot - 1]?.irTestV = v.map { Int($0) } }; close()
            }
        case .voltage:
            let before = phase == .before
            IECValueEditor(title: (before ? "String Voltage (Voc) | " : "Vmp | ") + label, unit: "V", initial: before ? s?.vocV : s?.vmpV,
                           hint: s.map { "คาดไว้ \($0.modules) แผง" }) { v in
                save { if before { $0.slots[slot - 1]?.vocV = v } else { $0.slots[slot - 1]?.vmpV = v } }; close()
            }
        case .current:
            let before = phase == .before
            IECValueEditor(title: (before ? "String Current | " : "Imp | ") + label, unit: "A", initial: before ? s?.iBeforeA : s?.impA,
                           hint: before ? "ก่อนเชื่อมต่อวงจรเปิด ค่า 0 A" : nil) { v in
                save { if before { $0.slots[slot - 1]?.iBeforeA = v } else { $0.slots[slot - 1]?.impA = v } }; close()
            }
        case .insulation:
            IECInsulationEditor(label: label, positive: s?.irPosMOhm, negative: s?.irNegMOhm) { p, n in
                save { $0.slots[slot - 1]?.irPosMOhm = p; $0.slots[slot - 1]?.irNegMOhm = n }; close()
            }
        case .label, .polarity, .photos:
            EmptyView()
        }
    }

    // MARK: bottom bar

    func bottomBar(_ inv: IECReport.Inverter, _ index: Int) -> some View {
        let picked = selected.flatMap { s in inv.strings.first { $0.slot == s } }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                if let selected {
                    Text("ช่องเลือก: String \(selected) (MPPT \(IECReport.mppt(slot: selected)))" +
                         (picked.map { " = ป้ายรูป " + IECReport.label(inverter: index + 1, seq: $0.seq) } ?? " | ไม่มีสตริง"))
                        .font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                } else {
                    Text("แตะช่องในตารางเพื่อเลือกสตริง").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                }
                Text("Word นับเฉพาะสตริงที่ใช้งาน Excel ใช้เลขช่อง แอปเก็บไว้ทั้งสองแบบ").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            if phase == .before { fillRowMenu }
            if picked != nil, let selected {
                Button("เปิดสตริงนี้ ›") { entry = EntryTarget(slot: selected) }.buttonStyle(TCButtonStyle(.primary, size: .card))
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// `กรอกทั้งแถว`: the before values that are the same for every string.
    private var fillRowMenu: some View {
        Menu {
            Button("Polarity ✓ ทุกสตริง") { save { inv in for i in inv.slots.indices where inv.slots[i] != nil { inv.slots[i]?.polarityOK = true } } }
            Button("Test Voltage 1000 V ทุกสตริง") { save { inv in for i in inv.slots.indices where inv.slots[i] != nil { inv.slots[i]?.irTestV = 1000 } } }
            Button("String Current 0 A ทุกสตริง (วงจรเปิด)") { save { inv in for i in inv.slots.indices where inv.slots[i] != nil { inv.slots[i]?.iBeforeA = 0 } } }
        } label: {
            Text("กรอกทั้งแถว").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                .padding(.horizontal, 22).frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.borderControl))
        }
    }
}

/// A number typed in a popover: `เสร็จ` saves it, `ล้าง` clears it.
struct IECValueEditor: View {
    let title: String
    let unit: String
    let initial: Double?
    var integer = false
    var hint: String?
    let done: (Double?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    init(title: String, unit: String, initial: Double?, integer: Bool = false, hint: String? = nil, done: @escaping (Double?) -> Void) {
        self.title = title; self.unit = unit; self.initial = initial; self.integer = integer; self.hint = hint; self.done = done
        _text = State(initialValue: initial.map { IECFormat.number($0, digits: 3).replacingOccurrences(of: ",", with: "") } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
            HStack {
                TextField("0", text: $text).keyboardType(integer ? .numberPad : .decimalPad).focused($focused)
                    .font(.sarabunFixed(24, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                Text(unit).font(.sarabunFixed(16)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 14).frame(height: 54)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.primary, lineWidth: 1.5))
            if let hint { Text(hint).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted) }
            HStack(spacing: 10) {
                Button("ล้าง") { done(nil) }.buttonStyle(TCButtonStyle(.secondary, size: .card))
                Button("เสร็จ") { done(Double(text.replacingOccurrences(of: ",", with: "."))) }.buttonStyle(TCButtonStyle(.primary, size: .card))
            }
        }
        .padding(18)
        .frame(width: 320)
        .onAppear { focused = true }
    }
}

/// IR +E and −E of one string; passes when the lower one is at least 1 MΩ.
struct IECInsulationEditor: View {
    let label: String
    let done: (Double?, Double?) -> Void
    @State private var pos: String
    @State private var neg: String
    @FocusState private var focused: Bool

    init(label: String, positive: Double?, negative: Double?, done: @escaping (Double?, Double?) -> Void) {
        self.label = label; self.done = done
        _pos = State(initialValue: positive.map { IECFormat.number($0, digits: 2).replacingOccurrences(of: ",", with: "") } ?? "")
        _neg = State(initialValue: negative.map { IECFormat.number($0, digits: 2).replacingOccurrences(of: ",", with: "") } ?? "")
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            HStack {
                TextField("เช่น 250", text: text).keyboardType(.decimalPad).font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy)
                Text("MΩ").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 12).frame(height: 48)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderControl))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insulation Resistance | \(label)").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
            HStack(spacing: 10) {
                field("Positive – Earth", $pos).focused($focused)
                field("Negative – Earth", $neg)
            }
            Text("ผ่านเมื่อทั้งสองค่า ≥ 1 MΩ ที่ 1000 V").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 10) {
                Button("ล้าง") { done(nil, nil) }.buttonStyle(TCButtonStyle(.secondary, size: .card))
                Button("เสร็จ") { done(Double(pos.replacingOccurrences(of: ",", with: ".")), Double(neg.replacingOccurrences(of: ",", with: "."))) }
                    .buttonStyle(TCButtonStyle(.primary, size: .card))
            }
        }
        .padding(18)
        .frame(width: 380)
        .onAppear { focused = true }
    }
}
