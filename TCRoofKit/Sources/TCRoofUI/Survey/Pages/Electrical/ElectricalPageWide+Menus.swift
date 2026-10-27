#if canImport(UIKit)
import SwiftUI
import UIKit
import TCRoofCore

// iPad A3 v3 (docs/ui/survey-a3-ipad-v3): fields that pick from a short list, the transformer size grid, standard values
// on a size pick, and the debug states. The lists are `A3Options` / `TransformerStandard` in TCRoofCore.

/// `A3Input`'s labelled box with a `▾` that opens a short list. The box stays a text field and the list ends with a
/// typed row (`+ เพิ่ม` / `อื่น ๆ`), so a value not in the list can always be entered.
struct A3MenuField: View {
    let label: String
    @Binding var text: String
    let options: [String]
    var required = false
    var unit: String?
    var keyboard: UIKeyboardType = .default
    /// The value came from the A2 picture.
    var a2 = false
    /// The value was read from a nameplate or a sensor.
    var source: FillSource? = nil
    /// Grey words while empty.
    var prompt = "เลือก"
    /// Used while empty (AF อัตโนมัติ): shown in the box on mint with an `อัตโนมัติ` tag and offered first in the list.
    /// Nothing is stored until a value is picked.
    var auto: String? = nil
    /// Red outline while empty (a CB ลูกย่อย's Icu and brand).
    var flagEmpty = false
    /// The list's typed row.
    var addTitle = "+ เพิ่ม"
    /// The list's open state, for a page that opens it itself (debug states); otherwise the field keeps its own.
    var isOpen: Binding<Bool>? = nil
    @State private var ownOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            A3Label(text: label, required: required)
            box
        }
    }

    private var open: Binding<Bool> { isOpen ?? $ownOpen }
    private var usesAuto: Bool { text.isEmpty && auto != nil }

    private var box: some View {
        HStack(spacing: 4) {
            TextField("", text: $text, prompt: Text(usesAuto ? auto ?? "" : prompt).foregroundColor(usesAuto ? Theme.navy : Theme.inkMuted))
                .keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
                .lineLimit(1)
                .accessibilityLabel(label)
            if usesAuto { autoTag }
            if a2 { A2Badge() }
            SourceChip(source: source)
            if let unit { Text(unit).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted) }
            Button { open.wrappedValue = true } label: {
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary)
                    .frame(width: 32, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เลือก" + label)
        }
        .inputBox(calc: usesAuto, error: flagEmpty && text.isEmpty && !usesAuto, minHeight: 44, trailing: 0)
        .popover(isPresented: open, arrowEdge: .top) {
            A3MenuList(text: $text, options: options, unit: unit, keyboard: keyboard, auto: auto, addTitle: addTitle) { open.wrappedValue = false }
                .presentationCompactAdaptation(.popover)
        }
    }

    private var autoTag: some View {
        Text("อัตโนมัติ").font(.sarabunFixed(10.5, .bold)).foregroundStyle(Theme.success)
            .padding(.horizontal, 5).frame(height: 18)
            .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// The list an `A3MenuField` opens: `อัตโนมัติ` first when the field has one, the options with the current value
/// ticked, then a typed row.
struct A3MenuList: View {
    @Binding var text: String
    let options: [String]
    var unit: String?
    var keyboard: UIKeyboardType = .default
    var auto: String?
    var addTitle = "+ เพิ่ม"
    let close: () -> Void
    @State private var custom = ""

    /// The options, with a value typed earlier (not in the list) on top so it shows ticked.
    private var shown: [String] { text.isEmpty || options.contains(text) ? options : [text] + options }
    private var suffix: String { unit.map { " " + $0 } ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let auto {
                            row("อัตโนมัติ (\(auto)\(suffix))", on: text.isEmpty) { text = "" }.id("auto")
                        }
                        ForEach(shown, id: \.self) { o in row(o + suffix, on: o == text) { text = o }.id(o) }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 300)
                .onAppear { if !text.isEmpty { proxy.scrollTo(text, anchor: .center) } }
            }
            Divider()
            customRow.padding(8)
        }
        .frame(width: 250)
        .foregroundStyle(Theme.navy)
    }

    private func row(_ title: String, on: Bool, pick: @escaping () -> Void) -> some View {
        Button { pick(); close() } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.primary).opacity(on ? 1 : 0)
                Text(title).font(.sarabunFixed(16, on ? .bold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44)
            .background(on ? Theme.primarySoft : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var customRow: some View {
        HStack(spacing: 6) {
            TextField("", text: $custom, prompt: Text(addTitle == "+ เพิ่ม" ? "ค่าอื่น" : "พิมพ์เอง"))
                .keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
                .onSubmit(add)
                .inputBox(minHeight: 44, trailing: 8, fontSize: 16)
                .accessibilityLabel("ค่าอื่น")
            if let unit { Text(unit).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted) }
            Button(action: add) {
                Text(addTitle).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary).lineLimit(1).fixedSize()
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        let v = custom.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        text = v
        custom = ""
        close()
    }
}

// MARK: transformer size and nameplate

extension ElectricalPageWide {
    /// One menu open at a time, by key ("size0", "tx0.voltage", "mdb0.at"); debug states open one from launch.
    func menuOpen(_ key: String) -> Binding<Bool> {
        Binding(get: { openMenu == key }, set: { openMenu = $0 ? key : (openMenu == key ? nil : openMenu) })
    }

    /// The meter takes 0.4 kV: no transformer, the boards hang off the meter (iPad; iPhone keeps its cards).
    var lowVoltage: Bool { !narrow && vChoice("meterKV") == A3Options.lowVoltageKV }

    /// The kVA box's `▾`: the size grid in a popover on iPad, the old menu on iPhone.
    @ViewBuilder func kvaPicker(_ i: Int) -> some View {
        if narrow {
            Menu {
                ForEach(Self.kvaSizes, id: \.self) { k in Button(k + " kVA") { edit(i) { $0.kva = k }; job.values.forgetSource("tr\(i)_kva") } }
            } label: { Image(systemName: "chevron.down").frame(width: 36, height: 44) }
        } else {
            Button { openMenu = "size\(i)" } label: {
                Image(systemName: "chevron.down").frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เลือกขนาดหม้อแปลง TX \(i + 1)")
            .popover(isPresented: menuOpen("size\(i)"), arrowEdge: .top) { sizeGrid(i).presentationCompactAdaptation(.popover) }
        }
    }

    /// docs/ui/survey-a3-ipad-v3 state 02: the standard sizes four across.
    func sizeGrid(_ i: Int) -> some View {
        let now = trafos[safe: i]?.kva ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            Text("ขนาดหม้อแปลง (kVA)").font(.sarabunFixed(15, .bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Self.kvaSizes, id: \.self) { k in
                    let on = k == now
                    Button { pickSize(i, k); openMenu = nil } label: {
                        Text(k).font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Theme.primarySoft : Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.primary : Theme.navy.opacity(0.25), lineWidth: on ? 2 : 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(k + " kVA")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text("เลือกขนาดแล้วจะใส่แรงดัน | Vector group | %Z มาตรฐานในช่องที่ยังว่าง | ค่าจากป้ายพิกัดหรือที่กรอกไว้ไม่ถูกทับ")
                .font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 340)
        .foregroundStyle(Theme.navy)
    }

    /// Sets transformer `i`'s size and fills only its empty voltage, vector group and %Z with the size's standard values;
    /// a value typed or read from the plate stays.
    func pickSize(_ i: Int, _ kva: String) {
        let std = TransformerStandard.values(kva: kva, meterKV: vChoice("meterKV"))
        var filled: [String] = []
        edit(i) { t in
            t.kva = kva
            guard let std else { return }
            let blank = { (s: String) in s.trimmingCharacters(in: .whitespaces).isEmpty }
            if blank(t.voltage) { t.voltage = std.voltage; filled.append("voltage") }
            if blank(t.vectorGroup) { t.vectorGroup = std.vectorGroup; filled.append("vectorGroup") }
            if blank(t.impedance) { t.impedance = std.impedance; filled.append("impedance") }
        }
        job.values.forgetSource("tr\(i)_kva")
        // a standard value is a suggestion, not a reading: no source chip
        for k in filled { job.values.forgetSource("tr\(i)_\(k)") }
    }

    /// The line under the size: the low-voltage current, and whether the plate's values were read or the size's
    /// standard values are in place.
    @ViewBuilder func sizeHint(_ i: Int) -> some View {
        if let t = trafos[safe: i], let amps = TransformerStandard.lvCurrent(kva: t.kva) {
            let plate = job.values.source("tr\(i)_kva") == .nameplate
            let std = TransformerStandard.values(kva: t.kva, meterKV: vChoice("meterKV"))
            let isStd = !plate && std.map { $0.voltage == t.voltage && $0.vectorGroup == t.vectorGroup && $0.impedance == t.impedance } == true
            let current = "In แรงต่ำ ≈ \(amps) A"
            let text = plate ? "อ่านจากป้ายพิกัดแล้ว | ตรวจทานได้ | " + current
                : isStd ? "ค่ามาตรฐานของ \(t.kva) kVA (%Z \(std?.impedance ?? "")%) | \(current) | แก้ตามป้ายพิกัดได้"
                : current
            Text(text).font(.sarabunFixed(12, .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(plate ? Theme.success : isStd ? Theme.pending : Theme.inkMuted)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                .background(plate ? Theme.mint.opacity(0.3) : isStd ? Theme.pendingSoft : Theme.phonePage, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// V, vector group and %Z, then brand, serial and year: menus on iPad, plain boxes on iPhone.
    @ViewBuilder func nameplateRows(_ i: Int) -> some View {
        if narrow {
            inputRow {
                A3Input(label: "แรงดัน", text: plateText(i, \.voltage, key: "voltage"), required: true, unit: "V",
                        source: job.values.source("tr\(i)_voltage"))
                A3Input(label: "Vector group", text: plateText(i, \.vectorGroup, key: "vectorGroup"), required: true,
                        source: job.values.source("tr\(i)_vectorGroup"))
                A3Input(label: "%Z", text: plateText(i, \.impedance, key: "impedance"), required: true, unit: "%", keyboard: .decimalPad,
                        source: job.values.source("tr\(i)_impedance"))
            }
            inputRow {
                A3Input(label: "ยี่ห้อ", text: tText(i, \.brand))
                A3Input(label: "Serial no.", text: tText(i, \.serial))
                A3Input(label: "ปีผลิต", text: plateText(i, \.year, key: "year", number: true), keyboard: .numberPad,
                        source: job.values.source("tr\(i)_year"))
            }
        } else {
            HStack(alignment: .top, spacing: 8) { voltageMenu(i); vectorGroupMenu(i); impedanceMenu(i) }
            HStack(alignment: .top, spacing: 8) { brandMenu(i); A3Input(label: "Serial no.", text: tText(i, \.serial)); yearMenu(i) }
        }
    }

    func voltageMenu(_ i: Int) -> some View {
        A3MenuField(label: "แรงดัน", text: plateText(i, \.voltage, key: "voltage"), options: A3Options.transformerVoltages, required: true,
                    unit: "V", source: job.values.source("tr\(i)_voltage"), prompt: "เลือก / ดูจากป้าย", addTitle: "อื่น ๆ",
                    isOpen: menuOpen("tx\(i).voltage"))
    }
    func vectorGroupMenu(_ i: Int) -> some View {
        A3MenuField(label: "Vector group", text: plateText(i, \.vectorGroup, key: "vectorGroup"), options: A3Options.vectorGroups, required: true,
                    source: job.values.source("tr\(i)_vectorGroup"), prompt: "เลือก / ดูจากป้าย", addTitle: "อื่น ๆ",
                    isOpen: menuOpen("tx\(i).vectorGroup"))
    }
    func impedanceMenu(_ i: Int) -> some View {
        A3MenuField(label: "%Z", text: plateText(i, \.impedance, key: "impedance"), options: A3Options.impedances, required: true,
                    unit: "%", keyboard: .decimalPad, source: job.values.source("tr\(i)_impedance"), prompt: "เลือก",
                    isOpen: menuOpen("tx\(i).impedance"))
    }
    func brandMenu(_ i: Int) -> some View {
        A3MenuField(label: "ยี่ห้อ", text: tText(i, \.brand), options: A3Options.transformerBrands, prompt: "เลือก / ดูจากป้าย",
                    addTitle: "อื่น ๆ", isOpen: menuOpen("tx\(i).brand"))
    }
    func yearMenu(_ i: Int) -> some View {
        A3MenuField(label: "ปีผลิต", text: plateText(i, \.year, key: "year", number: true), options: A3Options.years(),
                    keyboard: .numberPad, source: job.values.source("tr\(i)_year"), prompt: "เลือก / ดูจากป้าย", addTitle: "อื่น ๆ",
                    isOpen: menuOpen("tx\(i).year"))
    }
}

// MARK: main breaker

extension ElectricalPageWide {
    /// The MDB's main breaker on iPad: AT, AF (อัตโนมัติ) and Icu menus with `+ เพิ่ม`, poles, and ยี่ห้อ split from รุ่น.
    func mainBreakerFields(_ i: Int, _ b: Board) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                A3MenuField(label: "AT (ตั้งตัด)", text: bText(i, 0, \.at, number: true), options: A3Options.mainAT, required: true, unit: "A",
                            keyboard: .numberPad, a2: a2Badges.contains(.boardAT(i, 0)), isOpen: menuOpen("mdb\(i).at"))
                A3MenuField(label: "AF (เฟรม)", text: bText(i, 0, \.af, number: true), options: A3Options.mainAF, required: true, unit: "A",
                            keyboard: .numberPad, auto: A3Options.autoAF(at: b.at, frames: A3Options.mainAF), isOpen: menuOpen("mdb\(i).af"))
            }
            HStack(alignment: .bottom, spacing: 8) {
                A3MenuField(label: "Icu", text: bText(i, 0, \.icu, number: true), options: A3Options.mainIcu, required: true, unit: "kA",
                            keyboard: .decimalPad, isOpen: menuOpen("mdb\(i).icu"))
                VStack(alignment: .leading, spacing: 3) {
                    A3Label(text: "จำนวนขั้ว", required: true)
                    A3Segments(options: ["3P", "4P"], selected: b.poles) { v in editBoards(i) { $0[0].poles = v } }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                A3MenuField(label: "ยี่ห้อ", text: bText(i, 0, \.brand), options: A3Options.breakerBrands, prompt: "เลือกยี่ห้อ",
                            addTitle: "อื่น ๆ", isOpen: menuOpen("mdb\(i).brand"))
                A3Input(label: "รุ่น", text: bText(i, 0, \.model))
            }
        }
    }
}

// MARK: meter

extension ElectricalPageWide {
    /// `0.4 kV ไม่มีหม้อแปลง`, above the meter while it takes low voltage.
    var lowVoltageChip: some View {
        (Text("0.4 kV  ").bold().foregroundColor(Theme.primary) + Text("ไม่มีหม้อแปลง"))
            .font(.sarabunFixed(15)).lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.navy.opacity(0.25)))
            .shadow(color: Theme.navy.opacity(0.08), radius: 3, y: 2)
    }

    /// The meter's size: `15(45) A | 30(100) A | 50(150) A | CT`, written into `meterCT` (the size itself, or the CT's ratio).
    var meterSizeField: some View {
        let v = job.values.text("meterCT").trimmingCharacters(in: .whitespaces)
        let isSize = A3Options.meterSizes.contains(v)
        let picked = isSize ? v : (!v.isEmpty || meterCTPicked) ? A3Options.meterCT : ""
        let all = A3Options.meterSizes + [A3Options.meterCT]
        return VStack(alignment: .leading, spacing: 6) {
            A3Label(text: "ขนาดมิเตอร์ / CT")
            A3Segments(options: Array(all.prefix(2)), selected: picked) { setMeterSize($0) }
            A3Segments(options: Array(all.suffix(2)), selected: picked) { setMeterSize($0) }
            if picked == A3Options.meterCT {
                A3Input(label: "อัตราส่วน CT", text: Binding(get: { isSize ? "" : v }, set: { job.values["meterCT"] = $0.isEmpty ? nil : .text($0) }),
                        unit: "A", keyboard: .numbersAndPunctuation)
            }
        }
    }

    func setMeterSize(_ s: String) {
        let v = job.values.text("meterCT")
        if s == A3Options.meterCT {
            meterCTPicked = true
            if A3Options.meterSizes.contains(v) { job.values["meterCT"] = nil }
        } else {
            meterCTPicked = false
            job.values["meterCT"] = s.isEmpty ? nil : .text(s)
        }
    }
}

// MARK: debug states

#if DEBUG
extension ElectricalPageWide {
    /// `-surveyA3 size|size400|field|mdbat|cb|lv|hv|meter` (with `-surveyPage electrical`) opens docs/ui/survey-a3-ipad-v3's
    /// states 02, 03, 04, 05, 06 and 07 on TX 1: `size400` clears TX 1's nameplate fields and picks 400 kVA, `lv` sets the
    /// meter to 0.4 kV on the opened job and `hv` back to 22, `meter` unfolds the meter's more fields (its size).
    func applyA3Debug() async {
        guard let state = UserDefaults.standard.string(forKey: "surveyA3") else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        if ["size", "size400", "field", "mdbat", "cb"].contains(state) {
            if trafos.isEmpty { add() }
            open = 0
        }
        switch state {
        case "size": openMenu = "size0"
        case "size400":
            edit(0) { $0.voltage = ""; $0.vectorGroup = ""; $0.impedance = ""; $0.brand = ""; $0.serial = ""; $0.year = "" }
            pickSize(0, "400")
        case "field": openMenu = "tx0.vectorGroup"
        case "mdbat": openMenu = "mdb0.at"
        case "cb":
            if boards(0)[0].breakers.isEmpty { editBoards(0) { $0[0].breakers.append(Breaker(at: "100", poles: "3")) } }
            let list = boards(0)[0].breakers
            if let br = list.first(where: { $0.ic.isEmpty || $0.brand.isEmpty }) ?? list.first {
                try? await Task.sleep(nanoseconds: 300_000_000)
                editBreaker = BreakerEdit(id: br.id, trafo: 0, board: 0)
            }
        case "lv": setChoice("meterKV", A3Options.lowVoltageKV)
        case "meter": withAnimation { moreMeter = true }
        case "hv": setChoice("meterKV", "22")
        default: break
        }
    }
}
#endif
#endif
