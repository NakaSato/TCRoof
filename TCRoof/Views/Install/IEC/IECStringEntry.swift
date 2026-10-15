import SwiftUI
import TCRoofUI
import TCRoofCore

/// `กรอกทีละสตริง` (docs/ui/iec62446-test screen 3): one string's photos beside its readings, a number pad on the right,
/// and `ถัดไป` stepping through the fields and on to the next string (before: voltage → current → IR +E → IR −E;
/// after: voltage → current). The voltage is checked against the median of the strings with as many modules.
struct IECStringEntry: View {
    @Bindable var job: Job
    let inverter: Int
    @State var phase: IECReport.Phase
    /// The 1-based slot shown.
    @State var slot: Int
    @State private var field: Field = .voltage
    /// What the pad has typed into the field, kept as text so `753.` and `0.0` stay as typed.
    @State private var typed: String?
    /// The readings typed since the last save. Keys only change this; it goes to the job on `ถัดไป` / `ค่าก่อนหน้า`,
    /// on another string or phase, with a photo and on leaving, so a key press doesn't redraw the screens beneath
    /// (the install page and the PWA home watch the job).
    @State private var draft: IECReport?
    @Environment(\.modelContext) private var context

    private var report: IECReport { draft ?? job.iecReport ?? job.newIECReport }

    private func commit() {
        guard let d = draft else { return }
        draft = nil
        job.updateIEC(context) { $0 = d }
    }

    /// Another string: the current one is saved first.
    private func go(_ s: Int) { commit(); slot = s; field = .voltage; typed = nil }

    enum Field: CaseIterable { case voltage, current, irPos, irNeg }

    private func fields(_ p: IECReport.Phase) -> [Field] { p == .before ? [.voltage, .current, .irPos, .irNeg] : [.voltage, .current] }

    var body: some View {
        let report = report
        if report.inverters.indices.contains(inverter), let s = report.inverters[inverter].slots[slot - 1] {
            let inv = report.inverters[inverter]
            let seq = inv.strings.first { $0.slot == slot }?.seq ?? 0
            VStack(spacing: 0) {
                IECHeader(title: "\(IECReport.label(inverter: inverter + 1, seq: seq)) · String \(slot) · MPPT \(IECReport.mppt(slot: slot))",
                          subtitle: (phase == .before ? "ก่อนการเชื่อมต่อระบบ" : "หลังการเชื่อมต่อระบบ") +
                            " · " + [s.brand ?? report.module.brand, "\(s.modules) แผง"].filter { !$0.isEmpty }.joined(separator: " ")) {
                    IECPhaseSwitch(phase: Binding(get: { phase }, set: { commit(); phase = $0; field = .voltage; typed = nil }))
                }
                HStack(alignment: .top, spacing: 16) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            strip(inv)
                            measureCard(report, inv, s)
                            if phase == .before { insulationCard(s) }
                        }
                        .padding(.vertical, 18).padding(.leading, 24)
                    }
                    .scrollIndicators(.hidden)
                    padPanel(s, label: IECReport.label(inverter: inverter + 1, seq: seq))
                        .frame(width: 320).padding(.vertical, 18).padding(.trailing, 24)
                }
                bottomBar(inv, s)
            }
            .background(Theme.phonePage.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onDisappear(perform: commit)
        } else {
            Text("ไม่มีสตริงในช่องนี้").font(.sarabunFixed(17)).foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.phonePage)
        }
    }

    // MARK: values

    private func value(_ s: IECReport.Slot, _ f: Field) -> Double? {
        switch f {
        case .voltage: phase == .before ? s.vocV : s.vmpV
        case .current: phase == .before ? s.iBeforeA : s.impA
        case .irPos: s.irPosMOhm
        case .irNeg: s.irNegMOhm
        }
    }

    private func write(_ v: Double?, _ f: Field) {
        let (i, n, before) = (inverter, slot - 1, phase == .before)
        var r = report
        guard r.inverters.indices.contains(i), r.inverters[i].slots[n] != nil else { return }
        switch f {
        case .voltage: if before { r.inverters[i].slots[n]?.vocV = v } else { r.inverters[i].slots[n]?.vmpV = v }
        case .current: if before { r.inverters[i].slots[n]?.iBeforeA = v } else { r.inverters[i].slots[n]?.impA = v }
        case .irPos: r.inverters[i].slots[n]?.irPosMOhm = v
        case .irNeg: r.inverters[i].slots[n]?.irNegMOhm = v
        }
        draft = r
    }

    private func text(_ s: IECReport.Slot, _ f: Field) -> String {
        if f == field, let typed { return typed }
        return value(s, f).map { IECFormat.number($0, digits: 2) } ?? ""
    }

    private func press(_ key: String, _ s: IECReport.Slot) {
        // the first digit after picking a field starts a new reading; ⌫ edits the one there
        let kept = value(s, field).map { IECFormat.number($0, digits: 2) } ?? ""
        var t = typed ?? (key == "⌫" ? kept : "")
        switch key {
        case "⌫": t = String(t.dropLast())
        case ".": if !t.contains(".") { t += t.isEmpty ? "0." : "." }
        default: t = (t == "0" ? "" : t) + key
        }
        typed = t
        write(t.isEmpty ? nil : Double(t), field)
    }

    /// The next field, or the first field of the next string; `back` goes the other way.
    private func step(_ forward: Bool, _ inv: IECReport.Inverter) {
        commit()
        typed = nil
        let fs = fields(phase)
        let i = fs.firstIndex(of: field) ?? 0
        if forward {
            if i + 1 < fs.count { field = fs[i + 1] } else if let n = neighbour(inv, 1) { slot = n; field = fs[0] }
        } else {
            if i > 0 { field = fs[i - 1] } else if let p = neighbour(inv, -1) { slot = p; field = fs[fs.count - 1] }
        }
    }

    private func neighbour(_ inv: IECReport.Inverter, _ d: Int) -> Int? {
        let slots = inv.strings.map(\.slot)
        guard let i = slots.firstIndex(of: slot), slots.indices.contains(i + d) else { return nil }
        return slots[i + d]
    }

    // MARK: strip

    private func done(_ s: IECReport.Slot) -> Bool { fields(phase).allSatisfy { value(s, $0) != nil } }

    private func strip(_ inv: IECReport.Inverter) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(inv.strings, id: \.slot) { st in
                    let on = st.slot == slot, ok = done(st.value)
                    Button { go(st.slot) } label: {
                        Text("ST\(st.seq)").font(.sarabunFixed(14, .bold)).foregroundStyle(on ? Theme.navy : ok ? Theme.successInk : Theme.inkMuted)
                            .padding(.horizontal, 12).frame(height: 40)
                            .background(on ? Theme.primarySoft : ok ? Theme.successSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(IECReport.label(inverter: inverter + 1, seq: st.seq))
                    .accessibilityValue(ok ? "ครบ" : "ยังขาด")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: cards

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func photo(_ kind: IECReport.PhotoKind, _ s: IECReport.Slot, caption: String, reading: String) -> some View {
        let (i, n) = (inverter, slot - 1)
        return IECPhotoTile(caption: caption, asset: job.iecPhoto(s.photo(kind)), stubReading: reading) { data in
            commit()
            let id = job.storeIECPhoto(data, replacing: s.photo(kind), context: context)
            job.updateIEC(context) { $0.inverters[i].slots[n]?.photos[kind.rawValue] = id }
        } remove: {
            commit()
            job.removeIECPhoto(s.photo(kind), context: context)
            job.updateIEC(context) { $0.inverters[i].slots[n]?.photos[kind.rawValue] = nil }
        }
    }

    private func measureCard(_ r: IECReport, _ inv: IECReport.Inverter, _ s: IECReport.Slot) -> some View {
        let before = phase == .before
        return card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Voltage testing และ Current testing").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                HStack(spacing: 12) {
                    photo(before ? .voltageBefore : .voltageAfter, s, caption: "แรงดัน", reading: text(s, .voltage).isEmpty ? "0" : text(s, .voltage))
                    photo(before ? .currentBefore : .currentAfter, s, caption: "กระแส", reading: text(s, .current).isEmpty ? "0.0" : text(s, .current))
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldBox(before ? "String Voltage (Voc)" : "Vmp", "V", s, .voltage)
                        Text(voltageHint(r, inv, s)).font(.sarabunFixed(13)).foregroundStyle(voltageOff(r, inv) ? Theme.dangerText : Theme.inkMuted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        fieldBox(before ? "String Current" : "Imp", "A", s, .current)
                        Text(currentHint(s)).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
    }

    /// `คาดไว้ 16 × 47.0 = 752 V · ต่าง +0.1%`: from the median Voc of the strings with as many modules.
    private func voltageHint(_ r: IECReport, _ inv: IECReport.Inverter, _ s: IECReport.Slot) -> String {
        guard phase == .before else { return "หลังเชื่อมต่อ: แรงดันขณะจ่ายไฟ (Vmp)" }
        let peers = inv.slots.compactMap { $0 }.filter { $0.modules == s.modules }.compactMap(\.vocV).sorted()
        guard peers.count > 1, s.modules > 0 else { return "เทียบกับสตริงที่มีจำนวนแผงเท่ากัน" }
        let median = peers.count % 2 == 1 ? peers[peers.count / 2] : (peers[peers.count / 2 - 1] + peers[peers.count / 2]) / 2
        let per = median / Double(s.modules)
        var line = "คาดไว้ \(s.modules) × \(IECFormat.number(per, digits: 1)) = \(IECFormat.number(median, digits: 0)) V"
        if let d = r.vocDeviation(inv, slot: slot) { line += " · ต่าง " + (d >= 0 ? "+" : "") + IECFormat.number(d * 100, digits: 1) + "%" }
        return line
    }

    private func voltageOff(_ r: IECReport, _ inv: IECReport.Inverter) -> Bool {
        phase == .before && (r.vocDeviation(inv, slot: slot).map { abs($0) > IECReport.vocTolerance } ?? false)
    }

    private func currentHint(_ s: IECReport.Slot) -> String {
        guard phase == .before else { return "สตริงใน MPPT เดียวกันควรใกล้เคียงกัน" }
        guard let a = s.iBeforeA else { return "ก่อนเชื่อมต่อวงจรเปิด ควรได้ 0 A" }
        return a == 0 ? "ก่อนเชื่อมต่อวงจรเปิด ค่า 0 A ถูกต้อง" : "ก่อนเชื่อมต่อควรได้ 0 A · ตรวจวงจร"
    }

    /// A reading's box: tapped, the pad types into it.
    private func fieldBox(_ title: String, _ unit: String, _ s: IECReport.Slot, _ f: Field) -> some View {
        let on = f == field, has = value(s, f) != nil
        return Button { field = f; typed = nil } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(title).font(.sarabunFixed(14)).foregroundStyle(Theme.navy)
                    if has { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.successInk) }
                }
                HStack {
                    Text(text(s, f).isEmpty ? "—" : text(s, f)).font(.sarabunFixed(18, .bold))
                        .foregroundStyle(has || on ? Theme.navy : Theme.inkMuted).monospacedDigit()
                    Spacer()
                    Text(unit).font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 14).frame(height: 50)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.primary : Theme.borderControl, lineWidth: on ? 2 : 1))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(text(s, f).isEmpty ? "ยังขาด" : text(s, f) + " " + unit)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func insulationCard(_ s: IECReport.Slot) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Insulation Resistance testing").font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                    switch s.irPass {
                    case true?: Text("ผ่าน").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.successInk).padding(.horizontal, 10).frame(height: 26).background(Theme.successSoft, in: Capsule())
                    case false?: Text("ไม่ผ่าน").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.dangerText).padding(.horizontal, 10).frame(height: 26).background(Theme.dangerSoft, in: Capsule())
                    case nil: Text("● ยังขาด").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.warningInk).padding(.horizontal, 10).frame(height: 26).background(Theme.pendingSoft, in: Capsule())
                    }
                }
                HStack(alignment: .bottom, spacing: 12) {
                    photo(.insulation, s, caption: "หน้าจอ IR", reading: s.irPosMOhm.map { IECFormat.number($0, digits: 0) } ?? "250").frame(width: 150)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Test Voltage").font(.sarabunFixed(14)).foregroundStyle(Theme.navy)
                        Text(verbatim: s.irTestV.map { String($0) + " V" } ?? "—").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    fieldBox("Positive – Earth", "MΩ", s, .irPos)
                    fieldBox("Negative – Earth", "MΩ", s, .irNeg)
                }
                Text("ผ่านเมื่อทั้งสองค่า ≥ 1 MΩ ที่ 1000 V" + (s.polarityOK == true ? " · ขั้วถูกต้อง ✓" : ""))
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    // MARK: pad

    private func fieldName(_ f: Field) -> String {
        switch f {
        case .voltage: phase == .before ? "String Voltage" : "Vmp"
        case .current: phase == .before ? "String Current" : "Imp"
        case .irPos: "IR +E"
        case .irNeg: "IR −E"
        }
    }

    private func unit(_ f: Field) -> String { f == .voltage ? "V" : f == .current ? "A" : "MΩ" }

    private func padPanel(_ s: IECReport.Slot, label: String) -> some View {
        let inv = report.inverters[inverter]
        let fs = fields(phase), i = fs.firstIndex(of: field) ?? 0
        let after = fs.dropFirst(i + 1).map(fieldName) + (neighbour(inv, 1).flatMap { n in inv.strings.first { $0.slot == n } }
            .map { [IECReport.label(inverter: inverter + 1, seq: $0.seq)] } ?? [])
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("กำลังกรอก").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(text(s, field).isEmpty ? "—" : text(s, field)).font(.sarabunFixed(34, .bold)).foregroundStyle(Theme.navy).monospacedDigit()
                    Text(unit(field)).font(.sarabunFixed(17)).foregroundStyle(Theme.inkMuted)
                }
                Text("\(fieldName(field)) · \(label)").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            IECKeypad(press: { press($0, s) }, back: { step(false, inv) }, next: { step(true, inv) })
            if !after.isEmpty {
                Text("ถัดไป: " + after.joined(separator: " → ")).font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    // MARK: bottom bar

    private func bottomBar(_ inv: IECReport.Inverter, _ s: IECReport.Slot) -> some View {
        let kinds: [IECReport.PhotoKind] = phase == .before ? [.voltageBefore, .currentBefore, .insulation] : [.voltageAfter, .currentAfter]
        let photos = kinds.filter { s.photo($0) != nil }.count
        let values = fields(phase).filter { value(s, $0) != nil }.count
        return HStack(spacing: 10) {
            chip("รูป \(photos)/\(kinds.count)", photos == kinds.count)
            chip("ค่า \(values)/\(fields(phase).count)", values == fields(phase).count)
            Spacer()
            if let p = neighbour(inv, -1), let st = inv.strings.first(where: { $0.slot == p }) {
                Button { go(p) } label: { Text("‹ " + IECReport.label(inverter: inverter + 1, seq: st.seq)) }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card))
            }
            if let n = neighbour(inv, 1), let st = inv.strings.first(where: { $0.slot == n }) {
                Button { go(n) } label: {
                    VStack(spacing: 0) {
                        Text(IECReport.label(inverter: inverter + 1, seq: st.seq) + " ›").font(.sarabunFixed(16, .bold))
                        Text("String \(n) · MPPT \(IECReport.mppt(slot: n))").font(.sarabunFixed(12))
                    }
                }
                .buttonStyle(TCButtonStyle(.primary, size: .card))
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func chip(_ text: String, _ ok: Bool) -> some View {
        Text(text).font(.sarabunFixed(13, .bold)).foregroundStyle(ok ? Theme.successInk : Theme.warningInk)
            .padding(.horizontal, 10).frame(height: 28).background(ok ? Theme.successSoft : Theme.pendingSoft, in: Capsule())
    }
}
