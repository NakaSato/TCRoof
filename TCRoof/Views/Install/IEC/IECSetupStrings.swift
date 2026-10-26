import SwiftUI
import TCRoofUI
import TCRoofCore

extension IECSetupPage {
    // MARK: string list

    func stringList(_ r: IECReport) -> some View {
        let i = min(inverter, max(r.inverters.count - 1, 0))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("รายการสตริง (String list)").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                // the board has no field for the panel; its W is in every string's Wp
                Button { module = true } label: {
                    Label((r.module.brand.isEmpty ? "แผง" : r.module.brand) + " | " + (r.module.powerW > 0 ? IECFormat.number(r.module.powerW, digits: 0) + " W" : "ยังไม่ระบุ W"),
                          systemImage: "square.grid.3x3")
                        .font(.sarabunFixed(13, .bold)).foregroundStyle(r.module.powerW > 0 ? Theme.primary : Theme.warningInk).frame(minHeight: 44)
                }
                .accessibilityLabel("แผงโซลาร์ แก้ไข")
            }
            tabs(r, i)
            if r.inverters.indices.contains(i) {
                inverterRow(r.inverters[i], i)
                ScrollView { grid(r, r.inverters[i], i) }.scrollIndicators(.hidden)
                totals(r.setupTotals(r.inverters[i]))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    func tabs(_ r: IECReport, _ i: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(r.inverters.enumerated()), id: \.offset) { k, inv in
                let t = r.setupTotals(inv), on = k == i
                Button { inverter = k } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Inverter \(k + 1)").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                        Text(IECFormat.kW(inv.ratedKW)).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: 4)
                        Text("\(t.used)/\(t.slots) สตริง").font(.sarabunFixed(13, .bold)).foregroundStyle(on ? Theme.primary : Theme.inkMuted)
                    }
                    .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 54)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Button { adding = true } label: {
                Text("+ เพิ่มอินเวอร์เตอร์").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.primary, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            }
            .buttonStyle(.plain)
        }
    }

    /// The photo, `รุ่นอินเวอร์เตอร์`, the S/N field, `สแกนป้าย` and delete.
    func inverterRow(_ inv: IECReport.Inverter, _ i: Int) -> some View {
        HStack(spacing: 12) {
            Group {
                if let a = job.iecPhoto(inv.photos[IECReport.InverterPhoto.front.rawValue]), let img = UIImage(data: a.data) {
                    Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }.clipped()
                } else {
                    Image(systemName: "bolt.horizontal").font(.system(size: 20)).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.phonePage)
                }
            }
            .frame(width: 64, height: 52).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("รุ่นอินเวอร์เตอร์").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                Text(inv.model ?? "ไม่ระบุรุ่น | \(inv.mpptCount) MPPT").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
            }
            Spacer(minLength: 8)
            IECSerialField(serial: inv.serial, editing: $editingSerial) { s in job.updateIEC(context) { $0.inverters[i].serial = s } }
                .frame(width: 230)
            Button { scan = .serial(i); scanning = true } label: {
                VStack(spacing: 0) {
                    Image(systemName: "camera")
                    Text("สแกนป้าย").font(.sarabunFixed(13, .bold))
                }
                .foregroundStyle(Theme.onPrimary).frame(width: 96, height: 52)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            Button { deleting = i } label: {
                Image(systemName: "trash").font(.system(size: 18)).foregroundStyle(Theme.dangerText)
                    .frame(width: 52, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.dangerLine))
            }
            .buttonStyle(.plain).accessibilityLabel("ลบ INV\(i + 1)")
        }
        .padding(8)
        .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Two columns of MPPT groups (the first half left), two string rows each.
    func grid(_ r: IECReport, _ inv: IECReport.Inverter, _ i: Int) -> some View {
        let n = inv.mpptCount, half = (n + 1) / 2
        return HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 6) { ForEach(1...half, id: \.self) { mpptGroup(r, inv, i, $0) } }
            VStack(spacing: 6) { if n > half { ForEach((half + 1)...n, id: \.self) { mpptGroup(r, inv, i, $0) } } }
        }
    }

    func mpptGroup(_ r: IECReport, _ inv: IECReport.Inverter, _ i: Int, _ m: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MPPT \(m)").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.inkMuted)
            stringRow(r, inv, i, (m - 1) * 2 + 1)
            stringRow(r, inv, i, (m - 1) * 2 + 2)
        }
    }

    /// `String k  − 16 +  9,120 Wp  ●` or `String k  SPARE  ไม่มีสตริง  ○`.
    func stringRow(_ r: IECReport, _ inv: IECReport.Inverter, _ i: Int, _ slot: Int) -> some View {
        let s = inv.slots[slot - 1]
        let common = Dictionary(grouping: inv.strings.map(\.value.modules), by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? 16
        return HStack(spacing: 10) {
            Text("String \(slot)").font(.sarabunFixed(16, .bold)).foregroundStyle(s == nil ? Theme.disabledText : Theme.navy).frame(width: 82, alignment: .leading)
            if let s {
                IECModuleStepper(value: s.modules) { v in job.updateIEC(context) { $0.setModules(v, slot: slot, inverter: i) } }
                Spacer(minLength: 4)
                Text(IECFormat.number(Double(s.modules) * r.module.powerW, digits: 0, grouping: true) + " Wp").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                    .monospacedDigit().lineLimit(1).fixedSize()
            } else {
                Text("SPARE").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 10).frame(height: 24).background(Theme.track, in: Capsule())
                Spacer(minLength: 4)
                Text("ไม่มีสตริง").font(.sarabunFixed(13)).foregroundStyle(Theme.disabledText)
            }
            Toggle("String \(slot)", isOn: Binding(get: { s != nil }, set: { on in
                job.updateIEC(context) { $0.setSlot(slot, used: on, modules: common, inverter: i) }
            }))
            .labelsHidden().tint(Theme.primary)
        }
        .padding(.leading, 12).padding(.trailing, 8).frame(minHeight: 50)
        .background(s == nil ? Theme.surface : Theme.phonePage, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(s == nil ? Theme.borderSubtle : Color.clear))
    }

    func totals(_ t: IECReport.SetupTotals) -> some View {
        HStack(spacing: 0) {
            totalCell("สตริงที่ใช้", "\(t.used) / \(t.slots) ช่อง")
            totalCell("แผงรวม", "\(t.modules) แผง")
            totalCell("กำลังติดตั้ง (AA9)", IECFormat.number(t.watts, digits: 0, grouping: true) + " Wp")
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    func totalCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - fields

/// `− 16 +`: modules per string.
struct IECModuleStepper: View {
    let value: Int
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            round("minus", "ลดจำนวนแผง") { set(value - 1) }.disabled(value <= 1)
            Text("\(value)").font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy).frame(minWidth: 34).monospacedDigit()
            round("plus", "เพิ่มจำนวนแผง") { set(value + 1) }
        }
        .padding(3).background(Theme.surface, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value) แผง")
    }

    private func round(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: 40, height: 40).background(Theme.keyFill, in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// The inverter's S/N: shown, then a field with a 2 pt border while typing (state 05).
struct IECSerialField: View {
    let serial: String
    @Binding var editing: Bool
    let set: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("S/N").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            TextField("แตะเพื่อพิมพ์", text: $text).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                .textInputAutocapitalization(.characters).autocorrectionDisabled().focused($focused)
                .accessibilityLabel("S/N อินเวอร์เตอร์")
                .onSubmit(commit)
        }
        .padding(.horizontal, 12).frame(height: 52)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(focused ? Theme.primary : Theme.borderSubtle, lineWidth: focused ? 2 : 1))
        .onAppear { text = serial; if editing { focused = true } }
        .onChange(of: serial) { _, s in if !focused { text = s } }
        .onChange(of: focused) { _, on in editing = on; if !on { commit() } }
        .onChange(of: editing) { _, on in if on { focused = true } }
        .onDisappear(perform: commit)
    }

    private func commit() { let t = text.trimmingCharacters(in: .whitespaces); if t != serial { set(t) } }
}

/// `วันที่ทดสอบ *`: dashed `แตะเพื่อเลือก` until set, a date picker after.
struct IECDateField: View {
    let date: Date?
    let set: (Date) -> Void
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            Text(date.map { ThaiFormat.numericDate.string(from: $0) } ?? "แตะเพื่อเลือก").font(.sarabunFixed(17, date == nil ? .regular : .bold))
                .foregroundStyle(date == nil ? Theme.disabledText : Theme.navy)
                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(date == nil ? Theme.disabledText : Theme.borderControl, style: StrokeStyle(lineWidth: 1.2, dash: date == nil ? [5, 4] : [])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("วันที่ทดสอบ")
        .accessibilityValue(date.map { ThaiFormat.numericDate.string(from: $0) } ?? "ยังไม่ได้เลือก")
        .popover(isPresented: $picking) {
            DatePicker("วันที่ทดสอบ", selection: Binding(get: { date ?? .now }, set: { set($0) }), displayedComponents: .date)
                .datePickerStyle(.graphical).environment(\.locale, Locale(identifier: "th_TH")).padding().frame(width: 340)
                .onAppear { if date == nil { set(.now) } }
        }
    }
}

/// A text field with a dashed border while empty (`ผู้ทดสอบ *`).
struct IECDashedTextField: View {
    let placeholder: String
    let text: String
    let set: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $draft).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy).focused($focused)
            .padding(.horizontal, 14).frame(minHeight: 52)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? Theme.primary : draft.isEmpty ? Theme.disabledText : Theme.borderControl,
                              style: StrokeStyle(lineWidth: focused ? 2 : 1.2, dash: draft.isEmpty && !focused ? [5, 4] : [])))
            .accessibilityLabel("ผู้ทดสอบ")
            .onAppear { draft = text }
            .onChange(of: text) { _, t in if !focused { draft = t } }
            .onChange(of: focused) { _, on in if !on, draft != text { set(draft) } }
            .onSubmit { if draft != text { set(draft) } }
            .onDisappear { if draft != text { set(draft) } }
    }
}

/// `อากาศ | E29  34.3 °C`: a condition typed in its tile.
struct IECConditionTile: View {
    let label: String
    let unit: String
    let text: String
    let keyboard: UIKeyboardType
    let set: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("—", text: $draft).font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy).keyboardType(keyboard).focused($focused)
                    .accessibilityLabel(label)
                Text(unit).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? Theme.primary : Theme.borderSubtle, lineWidth: focused ? 2 : 1))
        .onAppear { draft = text }
        .onChange(of: text) { _, t in if !focused { draft = t } }
        .onChange(of: focused) { _, on in if !on, draft != text { set(draft) } }
        .onDisappear { if draft != text { set(draft) } }
    }
}

/// `แคลมป์มิเตอร์   ยังไม่ระบุ  สแกน`: typed, scanned, or picked from the tools register.
struct IECInstrumentRow: View {
    let title: String
    let serial: String
    let tools: [Instrument]
    let set: (String) -> Void
    let scan: () -> Void
    @State private var typing = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
            Spacer()
            Menu {
                Button { draft = serial; typing = true } label: { Label("พิมพ์ S/N", systemImage: "keyboard") }
                if !tools.isEmpty {
                    Section("จากทะเบียนเครื่องมือ") {
                        ForEach(tools) { t in
                            let sn = t.serial.isEmpty ? t.code : t.serial
                            Button(t.name + " | " + sn) { set(sn) }
                        }
                    }
                }
                if !serial.isEmpty { Button("ล้าง", role: .destructive) { set("") } }
            } label: {
                Text(serial.isEmpty ? "ยังไม่ระบุ" : serial).font(.sarabunFixed(15, serial.isEmpty ? .regular : .bold))
                    .foregroundStyle(serial.isEmpty ? Theme.disabledText : Theme.navy).frame(minHeight: 44)
            }
            .accessibilityLabel(title + " S/N")
            .accessibilityValue(serial.isEmpty ? "ยังไม่ระบุ" : serial)
            Button("สแกน", action: scan).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary).frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("สแกน " + title)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
        .alert(title, isPresented: $typing) {
            TextField("S/N", text: $draft).textInputAutocapitalization(.characters)
            Button("บันทึก") { set(draft.trimmingCharacters(in: .whitespaces)) }
            Button("ยกเลิก", role: .cancel) {}
        }
    }
}

/// The panel: brand, W and area (the board shows them only in each string's Wp).
struct IECModuleSheet: View {
    @Bindable var job: Job
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        let r = job.iecReport ?? job.newIECReport
        NavigationStack {
            VStack(spacing: 14) {
                IECTextField(title: "ยี่ห้อ / รุ่นแผง", text: r.module.brand) { t in job.updateIEC(context) { $0.module.brand = t } }
                HStack(spacing: 12) {
                    IECNumberField(title: "กำลังต่อแผง", unit: "W", value: r.module.powerW > 0 ? r.module.powerW : nil) { v in job.updateIEC(context) { $0.module.powerW = v ?? 0 } }
                    IECNumberField(title: "พื้นที่ต่อแผ่น", unit: "m²", value: r.module.areaM2, placeholder: "จาก datasheet") { v in job.updateIEC(context) { $0.module.areaM2 = v } }
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("แผงโซลาร์").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
