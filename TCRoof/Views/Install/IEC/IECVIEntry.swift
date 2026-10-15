import SwiftUI
import TCRoofUI
import TCRoofCore

/// Step 2's entry dialog (states 03, 04, 05, 09): the string's photo with its place in the DC box, the value typed
/// from it on the pad, the reading Vision found in the photo, and for Voc the polarity. `บันทึก` hands the value to
/// the page, which goes on V → the clamp's photo → A → the next string.
struct IECVIEntry: View {
    enum Kind: Hashable {
        case voltage, current
        var cardTitle: String { self == .voltage ? "มิเตอร์ V" : "แคลมป์ A" }
        var unit: String { self == .voltage ? "V" : "A" }
        func format(_ v: Double) -> String { self == .voltage ? String(format: "%.1f", v) : String(format: "%.2f", v) }

        /// Before: Voc and the open-circuit current (rows 16, 18); after: Vmp and Imp (rows 17, 19).
        func fieldTitle(_ phase: IECReport.Phase) -> String {
            switch (self, phase) {
            case (.voltage, .before): "แรงดัน Voc"
            case (.current, .before): "กระแส (วงจรเปิด)"
            case (.voltage, .after): "แรงดัน Vmp"
            case (.current, .after): "กระแส Imp"
            }
        }
        func short(_ phase: IECReport.Phase) -> String { self == .voltage ? (phase == .before ? "Voc" : "Vmp") : (phase == .before ? "กระแส" : "Imp") }
        func row(_ phase: IECReport.Phase) -> Int { (self == .voltage ? 16 : 18) + (phase == .after ? 1 : 0) }
        func photoKind(_ phase: IECReport.Phase) -> IECReport.PhotoKind {
            switch (self, phase) {
            case (.voltage, .before): .voltageBefore
            case (.current, .before): .currentBefore
            case (.voltage, .after): .voltageAfter
            case (.current, .after): .currentAfter
            }
        }
        func value(_ s: IECReport.Slot, _ phase: IECReport.Phase) -> Double? {
            switch (self, phase) {
            case (.voltage, .before): s.vocV
            case (.current, .before): s.iBeforeA
            case (.voltage, .after): s.vmpV
            case (.current, .after): s.impA
            }
        }
    }

    /// `โหมดต่อเนื่อง · 13/16 สตริง`.
    struct Continuous: Hashable { var done: Int; var total: Int }

    struct Target: Hashable, Identifiable {
        let slot: Int
        let kind: Kind
        var continuous: Continuous?
        var id: String { "\(slot)-\(kind)" }
    }

    @Bindable var job: Job
    let phase: IECReport.Phase
    let report: IECReport
    let inverter: Int
    let slot: IECReport.Slot
    let target: Target
    /// The value Vision read in the photo, once read.
    let reading: Double?
    /// The demo's photos are drawn: labelled `รูปตัวอย่าง`.
    let sample: Bool
    let nextLabel: String
    let save: (Double) -> Void
    /// Keeps a typed value without going on: the app is going to the background, where it may be closed.
    let keep: (Double) -> Void
    let retake: () -> Void
    let close: () -> Void

    @State private var typed: String?
    /// The field was filled from the photo and not touched since.
    @State private var fromPhoto = false
    @State private var zoom = false
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    private var inv: IECReport.Inverter { report.inverters[inverter] }
    private var seq: Int { inv.strings.first { $0.slot == target.slot }?.seq ?? 0 }
    private var label: String { IECReport.label(inverter: inverter + 1, seq: seq) }
    private var stored: Double? { target.kind.value(slot, phase) }
    private var photoKind: IECReport.PhotoKind { target.kind.photoKind(phase) }
    /// `ก่อนออน` / `หลังออน`, and the sheet's `ก่อน` / `หลัง`.
    private var phaseName: String { phase == .before ? "ก่อนออน" : "หลังออน" }
    private var sheetSide: String { phase == .before ? "ก่อน" : "หลัง" }
    private var text: String { typed ?? stored.map(target.kind.format) ?? "" }
    private var value: Double? { Double(text) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 24) {
                photoColumn.frame(width: 470)
                VStack(spacing: 14) {
                    valueTile
                    if target.kind == .voltage, phase == .before { polarityRow }
                    readingRow
                    pad
                }
            }
            .padding(24)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.navy.opacity(0.25), radius: 30, y: 10)
        .onAppear {
            prefill()
            #if DEBUG
            // state 09: a value typed over the photo's reading
            if IECVIPage.debugState == "differs", typed == nil || fromPhoto { typed = "735"; fromPhoto = false }
            #endif
        }
        .onChange(of: reading) { _, _ in prefill() }
        .fullScreenCover(isPresented: $zoom) { zoomView }
        .onChange(of: scenePhase) { _, p in if p != .active, typed != nil, let v = value, v != stored { keep(v) } }
        .accessibilityAddTraits(.isModal)
    }

    /// The first time a field opens empty, it takes the photo's reading.
    private func prefill() {
        #if DEBUG
        if IECVIPage.debugState == "differs" { return }
        #endif
        guard typed == nil, stored == nil, let reading else { return }
        typed = target.kind.format(reading); fromPhoto = true
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            Text(label).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 12).frame(height: 36).background(Theme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(target.kind.cardTitle + " · " + phaseName).font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                Text("รูป \(target.kind == .voltage ? 1 : 2)/2 · \(slot.modules) แผง · เติม \(IECReport.excelColumn(slot: target.slot))\(target.kind.row(phase)) · INV \(String(format: "%02d", inverter + 1))-\(sheetSide) · รูปไปที่รายงาน \(phase == .before ? 6 : 7) หน้า \(report.reportPage(inverter: inverter, seq: seq, phase))")
                    .font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            if let c = target.continuous {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("โหมดต่อเนื่อง · \(c.done)/\(c.total) สตริง").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.primary)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(Theme.primary).frame(width: g.size.width * Double(c.done) / Double(max(c.total, 1)))
                        }
                    }
                    .frame(width: 160, height: 4)
                }
                Button("หยุด", action: close).buttonStyle(TCButtonStyle(.secondary, size: .card)).fixedSize()
            }
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.navy)
                    .frame(width: 44, height: 44).background(Theme.phonePage, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("ปิด")
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    // MARK: photo

    private var photoColumn: some View {
        VStack(spacing: 12) {
            Group {
                if let a = job.iecPhoto(slot.photo(photoKind)), let img = UIImage(data: a.data) {
                    Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }.clipped()
                } else {
                    Theme.phonePage.overlay { Text("ยังไม่มีรูป").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted) }
                }
            }
            .frame(height: 350)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if sample { Text("รูปตัวอย่าง").font(.sarabunFixed(13)).foregroundStyle(Theme.onPrimary).padding(10) }
            }
            locationStrip
            HStack(spacing: 10) {
                Button(action: retake) { Label("ถ่ายใหม่", systemImage: "camera") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                Button { zoom = true } label: { Text("ซูมรูป") }
                    .buttonStyle(TCButtonStyle(.secondary, size: .card, fullWidth: true))
                    .disabled(slot.photo(photoKind) == nil)
            }
        }
    }

    /// `ตำแหน่งในตู้ DC · MPPT 1 · ฟิวส์ F1 (+/−)` and the DC box's slots, this one yellow.
    private var locationStrip: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ตำแหน่งในตู้ DC").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                Text("MPPT \(IECReport.mppt(slot: target.slot)) · ฟิวส์ F\(target.slot) (+/−)").font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy)
            }
            HStack(spacing: 3) {
                ForEach(1...inv.mpptCount, id: \.self) { m in
                    VStack(spacing: 3) {
                        Text("\(m)").font(.sarabunFixed(9, IECReport.mppt(slot: target.slot) == m ? .bold : .regular)).foregroundStyle(Theme.inkMuted)
                        boxCell((m - 1) * 2 + 1)
                        boxCell((m - 1) * 2 + 2)
                    }
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ตำแหน่งในตู้ DC MPPT \(IECReport.mppt(slot: target.slot)) ฟิวส์ F\(target.slot)")
    }

    private func boxCell(_ n: Int) -> some View {
        let on = n == target.slot, used = inv.slots[n - 1] != nil
        return RoundedRectangle(cornerRadius: 2).fill(on ? Theme.hudYellow : used ? Theme.track : Theme.surface)
            .frame(width: 18, height: 9)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(on ? Theme.warningInk : Theme.borderSubtle, lineWidth: on ? 1.5 : 0.5))
    }

    private var zoomView: some View {
        ZStack(alignment: .topTrailing) {
            Theme.mediaBackdrop.ignoresSafeArea()
            if let a = job.iecPhoto(slot.photo(photoKind)), let img = UIImage(data: a.data) {
                IECZoomableImage(image: img)
            }
            Button { zoom = false } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 44, height: 44).background(Theme.navy.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain).padding(20).accessibilityLabel("ปิด")
        }
    }

    // MARK: value

    private enum Tone { case ok, bad, warn, info }

    /// The hint under the number and the tile's colour.
    private var hint: (text: String, tone: Tone)? {
        guard let v = value else { return nil }
        if let reading, IECReport.differsFromReading(abs(v), abs(reading)) {
            return ("! ต่างจากค่าที่อ่านได้ในรูป " + target.kind.format(reading) + " " + target.kind.unit, .warn)
        }
        if fromPhoto { return ("✓ อ่านจากรูปแล้ว · ตรวจแล้วกดบันทึก", .ok) }
        if target.kind == .current {
            // after the connection Imp is only recorded
            if phase == .after { return ("✓ บันทึกแล้ว", .ok) }
            return IECReport.currentPassesBefore(v) ? ("✓ วงจรเปิด 0 A", .ok) : ("× ก่อนออนต้องเป็น 0 A", .bad)
        }
        // the voltage against its group's median, as if this value were kept
        var r = report
        if phase == .before { r.setVoc(v, inverter: inverter, slot: target.slot) } else { r.inverters[inverter].slots[target.slot - 1]?.vmpV = v }
        let inv2 = r.inverters[inverter]
        guard let d = r.voltageDeviation(inv2, slot: target.slot, phase) else { return ("✓ ไม่มีสตริงขนาดเดียวกันให้เทียบ", .ok) }
        let ok = abs(d) <= IECReport.vocTolerance
        return ((ok ? "✓ " : "× ") + "ต่างจากมัธยฐาน " + IECReport.signedPercent(d), ok ? .ok : .bad)
    }

    private var valueTile: some View {
        let tone = hint?.tone ?? .info
        let (border, fill): (Color, Color) = switch tone {
        case .warn: (Theme.warning, Theme.warningTint)
        case .bad: (Theme.danger, Theme.dangerSoft)
        default: (Theme.primary, Theme.surface)
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(target.kind.fieldTitle(phase)).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text("\(IECReport.excelColumn(slot: target.slot))\(target.kind.row(phase))").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(text.isEmpty ? "—" : text).font(.sarabunFixed(40, .bold)).foregroundStyle(text.isEmpty ? Theme.disabledText : Theme.navy).monospacedDigit()
                Rectangle().fill(Theme.primary).frame(width: 2, height: 34)
                Text(target.kind.unit).font(.sarabunFixed(17)).foregroundStyle(Theme.inkMuted)
            }
            if let hint {
                Text(hint.text).font(.sarabunFixed(13, .bold))
                    .foregroundStyle(hint.tone == .warn ? Theme.warningInk : hint.tone == .bad ? Theme.dangerText : Theme.okText)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(border, lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(target.kind.fieldTitle(phase))
        .accessibilityValue(text.isEmpty ? "ว่าง" : text + " " + target.kind.unit)
    }

    /// `ขั้วสาย E12`: from the Voc's sign until set here.
    private var polarityRow: some View {
        let ok = slot.polarityOK
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("ขั้วสาย ").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                    + Text("\(IECReport.excelColumn(slot: target.slot))12").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                Text(slot.polarityByHand == true ? "ตั้งเองแล้ว · แตะเพื่อเปลี่ยน" : "อัตโนมัติจากเครื่องหมาย Voc (บวก = ถูกต้อง) · แตะเพื่อเปลี่ยน")
                    .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            HStack(spacing: 2) {
                polaritySegment("✓ ถูกต้อง", on: ok == true) { setPolarity(true) }
                polaritySegment("× กลับขั้ว", on: ok == false) { setPolarity(false) }
            }
            .padding(3).background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func polaritySegment(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sarabunFixed(14, on ? .bold : .regular)).foregroundStyle(on ? Theme.navy : Theme.inkMuted)
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(on ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func setPolarity(_ ok: Bool) {
        let i = inverter, n = target.slot
        job.updateIEC(context) { $0.setPolarity(ok, inverter: i, slot: n) }
    }

    /// `อ่านจากรูป Voc 755.0 V · ใช้ค่านี้`, hidden until the photo gives a reading.
    @ViewBuilder private var readingRow: some View {
        if let reading {
            Button { typed = target.kind.format(reading); fromPhoto = true } label: {
                HStack {
                    Text("อ่านจากรูป").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                    Text("\(target.kind.short(phase)) \(target.kind.format(reading)) \(target.kind.unit)").font(.sarabunFixed(14)).foregroundStyle(Theme.navy)
                    Spacer()
                    Text("ใช้ค่านี้").font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.primary)
                }
                .padding(.horizontal, 14).frame(minHeight: 46)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.primary, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: pad

    /// 7 8 9 ⌫ / 4 5 6 ล้างค่า / 1 2 3 บันทึก / 0 (2 wide) . — บันทึก two rows tall.
    private var pad: some View {
        GeometryReader { g in
            let col = (g.size.width - 30) / 4, row: CGFloat = 54
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) { key("7"); key("8"); key("9") }
                    HStack(spacing: 10) { key("4"); key("5"); key("6") }
                    HStack(spacing: 10) { key("1"); key("2"); key("3") }
                    HStack(spacing: 10) { key("0").frame(width: col * 2 + 10); key(".") }
                }
                VStack(spacing: 10) {
                    key("⌫"); key("ล้างค่า")
                    saveKey.frame(height: row * 2 + 10)
                }
                .frame(width: col)
            }
        }
        .frame(height: 54 * 4 + 30)
    }

    private func key(_ k: String) -> some View {
        Button { press(k) } label: {
            Group {
                if k == "⌫" { Image(systemName: "delete.left") } else { Text(k) }
            }
            .font(.sarabunFixed(k.count > 1 ? 16 : 24, .bold)).foregroundStyle(Theme.navy)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderControl))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(k == "⌫" ? "ลบ" : k == "." ? "จุด" : k)
    }

    private var saveKey: some View {
        Button { if let v = value { save(v) } } label: {
            VStack(spacing: 2) {
                Text("บันทึก").font(.sarabunFixed(20, .bold))
                Text(nextLabel).font(.sarabunFixed(12))
            }
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(value == nil ? AnyShapeStyle(Theme.disabledText) : AnyShapeStyle(Theme.primary), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(value == nil)
        .accessibilityLabel("บันทึก " + nextLabel)
    }

    /// Max 6 digits and one dot; a reading's minus sign stays until the field is cleared.
    private func press(_ k: String) {
        var t = text
        fromPhoto = false
        switch k {
        case "⌫": if !t.isEmpty { t.removeLast() }
        case "ล้างค่า": t = ""
        case ".": if !t.contains(".") { t += t.isEmpty || t == "-" ? "0." : "." }
        default: if t.filter(\.isNumber).count < 6 { t = (t == "0" ? "" : t) + k }
        }
        typed = t
    }
}

/// A photo that pinches and pans, for `ซูมรูป`.
struct IECZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var last: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .scaleEffect(scale).offset(offset)
            .gesture(MagnifyGesture().onChanged { scale = max(1, last * $0.magnification) }.onEnded { _ in last = scale })
            .simultaneousGesture(DragGesture().onChanged { offset = CGSize(width: lastOffset.width + $0.translation.width, height: lastOffset.height + $0.translation.height) }
                .onEnded { _ in lastOffset = offset })
            .onTapGesture(count: 2) { withAnimation { scale = 1; last = 1; offset = .zero; lastOffset = .zero } }
            .accessibilityLabel("รูปขยาย")
    }
}
