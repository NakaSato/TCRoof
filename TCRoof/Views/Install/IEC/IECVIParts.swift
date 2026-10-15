import SwiftUI
import PhotosUI
import TCRoofUI
import TCRoofCore

/// `2/7` and the step's name over 7 capsules: the current one blue, done ones green. A capsule opens its step.
struct IECStepProgress: View {
    let current: IECReport.Stage
    let report: IECReport
    let open: (IECReport.Stage) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(current.rawValue)/\(IECReport.Stage.allCases.count)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text(current.title).font(.sarabunFixed(15)).foregroundStyle(Theme.navy)
            }
            HStack(spacing: 8) {
                ForEach(IECReport.Stage.allCases) { s in
                    Button { if s != current { open(s) } } label: {
                        Capsule().fill(s == current ? AnyShapeStyle(Theme.actionGradient) : report.isDone(s) ? AnyShapeStyle(Theme.stepDone) : AnyShapeStyle(Theme.track))
                            .frame(height: 8).frame(maxWidth: .infinity, minHeight: 30).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ขั้น \(s.rawValue) \(s.title)" + (report.isDone(s) ? " ครบ" : ""))
                    .accessibilityAddTraits(s == current ? .isSelected : [])
                }
            }
        }
    }
}

/// `ช่อง DC input · MPPT 1–10`: one column per MPPT with its two slots, done / to do / failed / empty.
struct IECDCInputMap: View {
    let report: IECReport
    let inverter: Int
    var phase: IECReport.Phase = .before
    let selected: Int
    let select: (Int) -> Void
    let toggleEmpty: (Int) -> Void

    var body: some View {
        let inv = report.inverters[inverter], mppts = inv.mpptCount
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ช่อง DC input · MPPT 1–\(mppts)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Button(inv.slots[selected - 1] == nil ? "+ มีสตริงในช่อง \(selected)" : "ตั้งช่อง \(selected) เป็นว่าง") { toggleEmpty(selected) }
                    .font(.sarabunFixed(13, .bold)).underline().foregroundStyle(Theme.primary).frame(minHeight: 44)
            }
            HStack(spacing: 4) {
                ForEach(1...mppts, id: \.self) { m in
                    // the selected slot's MPPT column is yellow, as the dialog's DC box strip
                    let on = IECReport.mppt(slot: selected) == m
                    VStack(spacing: 6) {
                        Text("\(m)").font(.sarabunFixed(11, on ? .bold : .regular)).foregroundStyle(on ? Theme.slotColumnInk : Theme.inkMuted)
                        dot(inv, (m - 1) * 2 + 1)
                        dot(inv, (m - 1) * 2 + 2)
                    }
                    .padding(.vertical, 6).frame(maxWidth: .infinity)
                    .background(on ? Theme.slotColumnFill : Theme.phonePage, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay { if on { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.slotColumnLine, lineWidth: 1.5) } }
                }
            }
            legend
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func dot(_ inv: IECReport.Inverter, _ slot: Int) -> some View {
        let status = report.viStatus(inv, slot: slot, phase)
        let seq = inv.strings.first { $0.slot == slot }?.seq
        let text = seq.map { "ST\($0)" } ?? "\(slot)"
        let (fill, ink): (Color, Color) = switch status {
        case .pass: (Theme.stepDone, Theme.onPrimary)
        case .fail: (Theme.danger, Theme.onPrimary)
        case .todo: (Theme.surface, Theme.navy)
        case .empty: (Color.clear, Theme.disabledText)
        }
        return Button { select(slot) } label: {
            Text(text).font(.sarabunFixed(text.count > 4 ? 10 : 12, .bold)).foregroundStyle(ink).minimumScaleFactor(0.7)
                .frame(width: 32, height: 32)
                .background(fill, in: Circle())
                .overlay {
                    if status == .todo { Circle().strokeBorder(Theme.borderControl, lineWidth: 1.5) }
                    if status == .empty { Circle().strokeBorder(Theme.disabledText, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                }
                // selected: a 2 pt gap, a 3 pt yellow ring and its 1 pt outline
                .padding(2)
                .overlay { if slot == selected { Circle().strokeBorder(Theme.surface, lineWidth: 2) } }
                .padding(3)
                .overlay {
                    if slot == selected {
                        Circle().strokeBorder(Theme.slotRing, lineWidth: 3)
                        Circle().strokeBorder(Theme.slotRingLine, lineWidth: 1)
                    }
                }
                .frame(minWidth: 38, minHeight: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seq.map { "สตริง \($0) ช่อง \(slot)" } ?? "ช่อง \(slot) ว่าง")
        .accessibilityValue(status == .pass ? "ครบ" : status == .fail ? "ไม่ผ่าน" : status == .todo ? "ยังไม่ครบ" : "ว่าง")
        .accessibilityAddTraits(slot == selected ? .isSelected : [])
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Spacer()
            legendItem(Theme.stepDone, "ครบ")
            legendItem(Theme.surface, "ยังไม่ครบ", ring: true)
            legendItem(Theme.danger, "ไม่ผ่าน")
            legendItem(Color.clear, "ว่าง", ring: true, dashed: true)
            Spacer()
        }
        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
    }

    private func legendItem(_ fill: Color, _ title: String, ring: Bool = false, dashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            Circle().fill(fill).frame(width: 11, height: 11)
                .overlay { if ring { Circle().strokeBorder(dashed ? Theme.disabledText : Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: dashed ? [2, 2] : [])) } }
            Text(title)
        }
    }
}

/// `ตารางค่าวัด · INV1 ก่อนออนระบบ`: every slot of the inverter with its readings and result; a row selects its slot.
struct IECVITable: View {
    let report: IECReport
    let inverter: Int
    var phase: IECReport.Phase = .before
    let selected: Int
    @Binding var filter: IECVIPage.Filter
    let select: (Int) -> Void

    private static let widths: [CGFloat] = [130, 90, 60, 90, 70, 100, 50]

    var body: some View {
        let inv = report.inverters[inverter]
        let statuses = (1...inv.slotsInUse).map { report.viStatus(inv, slot: $0, phase) }
        VStack(spacing: 0) {
            HStack {
                Text("ตารางค่าวัด · INV\(inverter + 1) \(phase == .before ? "ก่อนออนระบบ" : "หลังออนระบบ")").font(.sarabunFixed(18, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                filterSwitch(slots: inv.slotsInUse, todo: statuses.filter { $0 == .todo }.count, failed: statuses.filter { $0 == .fail }.count)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            headerRow
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows(statuses), id: \.self) { slot in row(inv, slot, statuses[slot - 1]).id(slot) }
                    }
                }
                .onChange(of: selected) { _, s in withAnimation { proxy.scrollTo(s) } }
            }
            footer(inv)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderSubtle))
    }

    private func rows(_ statuses: [IECReport.BeforeVIStatus]) -> [Int] {
        (1...statuses.count).filter { n in
            switch filter {
            case .all: true
            case .todo: statuses[n - 1] == .todo
            case .failed: statuses[n - 1] == .fail
            }
        }
    }

    private func filterSwitch(slots: Int, todo: Int, failed: Int) -> some View {
        HStack(spacing: 2) {
            segment("\(slots) ช่อง", .all)
            segment("ยังไม่ครบ \(todo)", .todo)
            segment("ไม่ผ่าน \(failed)", .failed)
        }
        .padding(3).background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func segment(_ title: String, _ f: IECVIPage.Filter) -> some View {
        Button { filter = f } label: {
            Text(title).font(.sarabunFixed(14, filter == f ? .bold : .regular)).foregroundStyle(filter == f ? Theme.navy : Theme.inkMuted)
                .padding(.horizontal, 12).frame(minHeight: 38)
                .background(filter == f ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == f ? .isSelected : [])
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            cell("สตริง", 0, .leading)
            cell("MPPT · ช่อง", 1, .leading)
            cell("แผง", 2, .leading)
            Text(phase == .before ? "Voc (V)" : "Vmp (V)").frame(maxWidth: .infinity, alignment: .trailing)
            cell("ต่าง", 3, .trailing)
            cell(phase == .before ? "กระแส (A)" : "Imp (A)", 5, .trailing)
            // no polarity after the connection
            if phase == .before { cell("ขั้ว", 6, .center) }
            Text("ผล").frame(width: 100)
        }
        .font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 16).frame(height: 32)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func cell(_ text: String, _ w: Int, _ a: Alignment) -> some View { Text(text).frame(width: Self.widths[w], alignment: a) }

    @ViewBuilder private func row(_ inv: IECReport.Inverter, _ slot: Int, _ status: IECReport.BeforeVIStatus) -> some View {
        let on = slot == selected
        Button { select(slot) } label: {
            Group {
                if let s = inv.slots[slot - 1] { stringRow(inv, slot, s, status) } else { emptyRow(slot) }
            }
            .padding(.horizontal, 16).frame(height: 42)
            .background(on ? Theme.rowSelected : Color.clear)
            .overlay(alignment: .leading) { if on { Rectangle().fill(Theme.primary).frame(width: 3) } }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func emptyRow(_ slot: Int) -> some View {
        HStack(spacing: 0) {
            cell("ช่อง \(slot) · ว่าง", 0, .leading)
            cell("\(IECReport.mppt(slot: slot)) · \(slot)", 1, .leading)
            Text("ไม่มีสตริงต่อเข้าช่องนี้").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.sarabunFixed(14)).foregroundStyle(Theme.disabledText)
        .accessibilityElement(children: .combine)
    }

    private func stringRow(_ inv: IECReport.Inverter, _ slot: Int, _ s: IECReport.Slot, _ status: IECReport.BeforeVIStatus) -> some View {
        let seq = inv.strings.first { $0.slot == slot }?.seq ?? 0
        let volts = IECVIEntry.Kind.voltage.value(s, phase), amps = IECVIEntry.Kind.current.value(s, phase)
        let vocBad = (phase == .before ? report.vocPasses(inv, slot: slot) : report.vmpPasses(inv, slot: slot)) == false
        // after the connection Imp is only recorded
        let ampBad = phase == .before && (amps.map { !IECReport.currentPassesBefore($0) } ?? false)
        let dev = volts == nil ? nil : report.voltageDeviation(inv, slot: slot, phase)
        return HStack(spacing: 0) {
            // the board's `String n` (the chip, the dialog and the map keep `INV1ST1` / `ST1`)
            Text("String \(seq)").font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.navy)
                .frame(width: Self.widths[0], alignment: .leading)
            cell("\(IECReport.mppt(slot: slot)) · \(slot)", 1, .leading)
            cell("\(s.modules)", 2, .leading)
            value(volts.map { IECFormat.number($0, digits: 1) }, bad: vocBad).frame(maxWidth: .infinity, alignment: .trailing)
            value(dev.map(IECReport.signedPercent), bad: vocBad).frame(width: Self.widths[3], alignment: .trailing)
            value(amps.map { String(format: "%.2f", $0) }, bad: ampBad).frame(width: Self.widths[5], alignment: .trailing)
            if phase == .before { polarity(s.polarityOK).frame(width: Self.widths[6]) }
            resultPill(status).frame(width: 100)
        }
        .font(.sarabunFixed(15)).foregroundStyle(Theme.navy).monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private func value(_ text: String?, bad: Bool) -> some View {
        Text(text ?? "—").fontWeight(bad ? .bold : .regular)
            .foregroundStyle(text == nil ? Theme.disabledText : bad ? Theme.dangerText : Theme.navy)
    }

    @ViewBuilder private func polarity(_ ok: Bool?) -> some View {
        switch ok {
        case true?: Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.okText)
        case false?: Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.dangerText)
        case nil: Text("—").foregroundStyle(Theme.disabledText)
        }
    }

    private func resultPill(_ s: IECReport.BeforeVIStatus) -> some View {
        let (t, ink, fill): (String, Color, Color) = switch s {
        case .pass: ("ผ่าน", Theme.okText, Theme.okSoft)
        case .fail: ("ไม่ผ่าน", Theme.dangerText, Theme.dangerSoft)
        default: ("ยังไม่ครบ", Theme.inkMuted, Theme.phonePage)
        }
        return Text(t).font(.sarabunFixed(13, .bold)).foregroundStyle(ink).frame(width: 80, height: 22).background(fill, in: Capsule())
    }

    /// `วัดแล้ว` · the median of each module-count group (or one median and V per module) · polarity.
    /// Step 4's footer: measured · the Vmp median(s) · Σ Imp · the Excel rows.
    private func afterCells(_ inv: IECReport.Inverter, _ t: IECReport.BeforeVITally) -> [(String, String)] {
        let medians = report.vmpMedians(inv)
        let median = medians.isEmpty ? "—" : medians.map { String(format: "%.1f V", $0.median) + (medians.count > 1 ? " (\($0.modules))" : "") }.joined(separator: " · ")
        let amps = inv.strings.compactMap(\.value.impA)
        return [("วัดแล้ว", "\(t.done) / \(t.total) สตริง"), ("มัธยฐาน Vmp", median),
                ("กระแสรวม", amps.isEmpty ? "—" : String(format: "%.1f A", amps.reduce(0, +))), ("Excel", "แถว 17 · 19")]
    }

    private func footer(_ inv: IECReport.Inverter) -> some View {
        let t = report.viTally(inv, phase), medians = report.vocMedians(inv)
        let reversed = phase == .before ? inv.strings.filter { $0.value.polarityOK == false }.count : 0
        var cells: [(String, String)] = [("วัดแล้ว", "\(t.done) / \(t.total) สตริง")]
        if medians.count > 1 {
            cells += medians.prefix(2).map { ("มัธยฐาน \($0.modules) แผง", String(format: "%.1f V", $0.median)) }
        } else if let m = medians.first {
            cells += [("มัธยฐาน \(m.modules) แผง", String(format: "%.1f V", m.median)), ("V ต่อแผง", String(format: "%.2f V", m.median / Double(max(m.modules, 1))))]
        } else {
            cells += [("มัธยฐาน", "—"), ("V ต่อแผง", "—")]
        }
        cells.append(("ขั้วสาย", reversed == 0 ? "ถูกทุกสตริง" : "กลับขั้ว \(reversed)"))
        if phase == .after { cells = afterCells(inv, t) }
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { k, c in
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.0).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
                    Text(c.1).font(.sarabunFixed(16, .bold)).foregroundStyle(k == cells.count - 1 && reversed > 0 ? Theme.dangerText : Theme.navy)
                }
                .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { if k > 0 { Rectangle().fill(Theme.hairline).frame(width: 1) } }
                .accessibilityElement(children: .combine)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle))
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// One of the selected string's photos with its value: `ยังไม่มีรูป` (dashed orange) → `แตะเพื่อป้อนค่า` (blue) →
/// the value with ✓ / ✗ (green or red).
struct IECValuePhotoCard: View {
    let kind: IECVIEntry.Kind
    let asset: PhotoAsset?
    let value: Double?
    let cell: String
    let hint: (text: String, ok: Bool)?
    let tap: () -> Void

    private var ok: Bool { hint?.ok ?? true }

    private var border: Color {
        if asset == nil { return Theme.warning }
        if value == nil { return Theme.primary }
        return ok ? Theme.stepDone : Theme.danger
    }

    private var hintColor: Color {
        if asset == nil { return Theme.warningInk }
        guard let hint else { return Theme.inkMuted }
        return hint.ok ? Theme.okText : Theme.dangerText
    }

    private var spoken: String {
        if let value { return kind.cardTitle + " " + kind.format(value) + " " + kind.unit }
        return kind.cardTitle + (asset == nil ? " ยังไม่มีรูป" : " แตะเพื่อป้อนค่า")
    }

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 0) {
                photo
                footer
            }
            .background(asset == nil ? Theme.warningTint : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(frame)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }

    private var frame: some View {
        let dashed = asset == nil
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(border, style: StrokeStyle(lineWidth: dashed ? 1.5 : 2, dash: dashed ? [6, 4] : []))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(kind.cardTitle).font(.sarabunFixed(14, .bold)).foregroundStyle(Theme.navy)
                Spacer()
                Text(cell).font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            valueLine
            Text(asset == nil ? "ยังไม่มีรูป" : hint?.text ?? "ถ่ายแล้ว · ② ป้อนค่าจากรูป").font(.sarabunFixed(12))
                .foregroundStyle(hintColor).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    @ViewBuilder private var valueLine: some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kind.format(value)).font(.sarabunFixed(24, .bold)).foregroundStyle(ok ? Theme.navy : Theme.dangerText)
                Text(kind.unit).font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
            }
        } else {
            Text(asset == nil ? "—" : "แตะเพื่อป้อนค่า").font(.sarabunFixed(20, .bold))
                .foregroundStyle(asset == nil ? Theme.disabledText : Theme.primary)
        }
    }

    @ViewBuilder private var photo: some View {
        if let asset, let img = UIImage(data: asset.data) {
            Color.clear.frame(height: 168)
                .overlay { Image(uiImage: img).resizable().scaledToFill() }
                .clipped()
                .overlay(alignment: .topLeading) {
                    Label("ถ่ายแล้ว", systemImage: "checkmark").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.okText)
                        .padding(.horizontal, 8).frame(height: 24).background(Theme.surface, in: Capsule()).padding(8)
                }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "camera").font(.system(size: 30, weight: .semibold))
                Text("① ถ่ายรูป" + kind.cardTitle).font(.sarabunFixed(16, .bold))
                Text("ให้เห็นหน้าจอและจุดที่วัด").font(.sarabunFixed(12))
            }
            .foregroundStyle(Theme.warningInk)
            .frame(maxWidth: .infinity).frame(height: 168)
        }
    }
}

/// Takes a photo for `shot`: the drawn stub with `-iecCameraStub`, else the camera, else the library.
struct IECShutter: ViewModifier {
    @Binding var shot: IECVIPage.Shot?
    let job: Job
    var stubReading: (IECVIPage.Shot) -> String = { _ in "0.0" }
    let store: (IECVIPage.Shot, Data) -> Void
    @State private var camera: IECVIPage.Shot?
    @State private var library = false
    @State private var picked: PhotosPickerItem?
    @State private var pending: IECVIPage.Shot?

    func body(content: Content) -> some View {
        content
            .onChange(of: shot) { _, s in
                guard let s else { return }
                shot = nil
                if IECCamera.stub { store(s, IECCamera.stubPhoto(stubReading(s))) }
                else if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = s }
                else { pending = s; library = true }
            }
            .fullScreenCover(item: $camera) { s in StampedCamera { store(s, $0) } }
            .photosPicker(isPresented: $library, selection: $picked, matching: .images)
            .onChange(of: picked) { _, item in
                guard let item, let s = pending else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { store(s, ImageUtil.compressed(data)) }
                    picked = nil; pending = nil
                }
            }
    }
}
