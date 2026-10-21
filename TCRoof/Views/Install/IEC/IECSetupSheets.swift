import SwiftUI
import SwiftData
import TCRoofUI
import TCRoofCore

extension IECSetupPage {
    @ViewBuilder func sheets(_ r: IECReport) -> some View {
        if adding {
            dim { closeAdd() }
                .overlay { IECAddInverterSheet(job: job, number: r.inverters.count + 1, serial: $newSerial, scan: { scan = .newInverter; scanning = true },
                                               close: { closeAdd() }, add: { i in adding = false; inverter = i }) }
        } else if let i = deleting, r.inverters.indices.contains(i) {
            dim { deleting = nil }
                .overlay { deleteConfirm(r, i) }
        }
    }

    func closeAdd() { adding = false; newSerial = "" }

    func dim(_ tap: @escaping () -> Void) -> some View {
        Theme.navy.opacity(0.45).ignoresSafeArea().onTapGesture(perform: tap)
    }

    /// `ลบ INVn ?` with what goes with it. The job keeps no edit history for the test, so no restore is promised.
    func deleteConfirm(_ r: IECReport, _ i: Int) -> some View {
        let inv = r.inverters[i], measured = inv.strings.filter { $0.value.vocV != nil || $0.value.vmpV != nil || !$0.value.photos.isEmpty }.count
        let last = r.inverters.count == 1
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "trash").font(.system(size: 22)).foregroundStyle(Theme.dangerText).frame(width: 56, height: 56).background(Theme.dangerSoft, in: Circle())
                Text("ลบ INV\(i + 1) ?").font(.sarabunFixed(24, .bold)).foregroundStyle(Theme.navy)
            }
            Text(["INV\(i + 1)", inv.model, inv.serial.isEmpty ? nil : "S/N \(inv.serial)"].compactMap { $0 }.joined(separator: " | ") + " จะถูกนำออกจากงานนี้")
                .font(.sarabunFixed(16)).foregroundStyle(Theme.navy)
            VStack(alignment: .leading, spacing: 6) {
                bullet("รายการสตริง \(inv.strings.count) ช่อง และค่าที่วัดแล้ว \(measured) สตริง (รวมรูป) ของ INV\(i + 1) จะถูกลบ")
                bullet("Excel จะไม่มีแผ่น INV \(String(format: "%02d", i + 1))-ก่อน / -หลัง | อินเวอร์เตอร์ที่เหลือเรียงเลขแผ่นใหม่")
                bullet("ลบแล้วกู้คืนไม่ได้")
                if last { bullet("ต้องมีอินเวอร์เตอร์อย่างน้อย 1 เครื่อง จึงลบเครื่องสุดท้ายไม่ได้") }
            }
            HStack(spacing: 12) {
                Spacer()
                Button("ยกเลิก") { deleting = nil }.buttonStyle(TCButtonStyle(.secondary, size: .bar, fullWidth: true)).frame(width: 200)
                Button("ลบ INV\(i + 1)") { delete(i) }
                    .font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 290, height: 53).background(last ? Theme.disabledText : Theme.danger, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .buttonStyle(.plain).disabled(last)
            }
        }
        .padding(28).frame(width: 790)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityAddTraits(.isModal)
    }

    func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(Theme.navy)
            Text(text).font(.sarabunFixed(15)).foregroundStyle(Theme.navy).fixedSize(horizontal: false, vertical: true)
        }
    }

    func delete(_ i: Int) {
        guard !report.isLocked else { deleting = nil; return }
        var ids: [String] = []
        job.updateIEC(context) { ids = $0.removeInverter(at: i) }
        for id in ids { job.removeIECPhoto(id, context: context) }
        inverter = max(0, min(inverter, (job.iecReport?.inverters.count ?? 1) - 1))
        deleting = nil
    }

    #if DEBUG
    /// `-iecSheet add|delete|sn` opens that sheet; `-iecStep1State inv2|spare` the board's states 02 and 06.
    func applyDebug() {
        guard !debugApplied else { return }
        debugApplied = true
        let d = UserDefaults.standard
        switch d.string(forKey: "iecStep1State") {
        case "inv2": inverter = 1
        case "spare": job.updateIEC(context) { $0.setSlot(3, used: false, modules: 16, inverter: 0) }
        default: break
        }
        switch d.string(forKey: "iecSheet") {
        case "add": adding = true
        case "delete": deleting = 0
        case "sn": editingSerial = true
        default: break
        }
    }
    #endif
}

/// `เพิ่มอินเวอร์เตอร์` (state 03): the model from the catalogue (its kW and MPPT), the S/N, modules per string and
/// the photos, two of them required. Photos are kept as they're taken; closing without adding removes them.
struct IECAddInverterSheet: View {
    @Bindable var job: Job
    let number: Int
    @Binding var serial: String
    let scan: () -> Void
    let close: () -> Void
    let add: (Int) -> Void

    @State private var model: EquipmentCatalog.Inverter?
    @State private var modules = 16
    @State private var photos: [String: String] = [:]
    @State private var added = false
    @Environment(\.modelContext) private var context

    private let catalog = EquipmentCatalog.bundled.inverters.sorted { $0.kw > $1.kw }
    private var report: IECReport { job.iecReport ?? job.newIECReport }
    private var ready: Bool { model != nil && IECReport.InverterPhoto.allCases.filter(\.required).allSatisfy { photos[$0.rawValue] != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                models
                fields
                info
                photoSlots
            }
            .padding(24)
            buttons
        }
        .frame(width: 1100)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityAddTraits(.isModal)
        .onAppear {
            model = catalog.first { Double($0.kw) == report.inverters.last?.ratedKW } ?? catalog.first
            modules = report.inverters.flatMap { $0.strings.map(\.value.modules) }.first ?? 16
        }
        .onDisappear { if !added { for id in photos.values { job.removeIECPhoto(id, context: context) } } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("INV\(number)").font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 14).frame(height: 44).background(Theme.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("เพิ่มอินเวอร์เตอร์").font(.sarabunFixed(20, .bold)).foregroundStyle(Theme.navy)
                Text("ข้อมูลจากป้ายพิกัด").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.navy).frame(width: 44, height: 44).background(Theme.phonePage, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("ปิด")
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("รุ่นอินเวอร์เตอร์").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                    + Text("  *").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.dangerText)
                Spacer()
                Text("จากแคตตาล็อกอุปกรณ์ | รุ่นกำหนด kW และ MPPT ให้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                ForEach(catalog, id: \.self) { m in modelCard(m) }
            }
        }
    }

    private func modelCard(_ m: EquipmentCatalog.Inverter) -> some View {
        let on = model == m
        return Button { model = m } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").font(.system(size: 22)).foregroundStyle(on ? Theme.primary : Theme.borderControl)
                Image(systemName: "bolt.horizontal").font(.system(size: 18)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 56, height: 40).background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 0) {
                    Text(m.brand + " " + m.model).font(.sarabunFixed(17, .bold)).foregroundStyle(Theme.navy)
                    Text("\(m.kw) kW | \(m.mppt) MPPT | \(m.mppt * 2) ช่อง").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).frame(minHeight: 64)
            .background(on ? Theme.rowSelected : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.primary : Theme.borderSubtle, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var fields: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("S/N").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy); Spacer()
                    Text("O5 | แผ่น INV \(String(format: "%02d", number))").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted) }
                HStack(spacing: 0) {
                    TextField("แตะเพื่อพิมพ์ หรือสแกนป้าย", text: $serial).font(.sarabunFixed(16)).textInputAutocapitalization(.characters)
                        .autocorrectionDisabled().padding(.horizontal, 14).accessibilityLabel("S/N ใหม่")
                    Divider()
                    Button("สแกนป้าย", action: scan).font(.sarabunFixed(15, .bold)).foregroundStyle(Theme.primary).padding(.horizontal, 14).frame(minHeight: 52)
                        .accessibilityLabel("สแกนป้าย S/N ใหม่")
                }
                .frame(height: 52)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.warning, style: StrokeStyle(lineWidth: 1.2, dash: serial.isEmpty ? [5, 4] : [])))
                Text("ใส่ภายหลังได้").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("MPPT").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy); Spacer()
                    Text("จากรุ่น").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted) }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(model?.mppt ?? 0)").font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy)
                    Text("MPPT | \((model?.mppt ?? 0) * 2) ช่อง DC input").font(.sarabunFixed(14)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).background(Theme.phonePage, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("\(model?.kw ?? 0) kW | 2 สตริงต่อ MPPT").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("แผงต่อสตริง").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                HStack {
                    Button { modules = max(1, modules - 1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel("ลดจำนวนแผง")
                    Spacer()
                    Text("\(modules)").font(.sarabunFixed(22, .bold)).foregroundStyle(Theme.navy)
                    Spacer()
                    Button { modules = min(60, modules + 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("เพิ่มจำนวนแผง")
                }
                .foregroundStyle(Theme.primary).padding(.horizontal, 6).frame(height: 52)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.primary, lineWidth: 1.5))
                Text(IECFormat.number(Double(modules) * report.module.powerW, digits: 0, grouping: true) + " Wp ต่อสตริง").font(.sarabunFixed(12)).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private var info: some View {
        let nn = String(format: "%02d", number)
        return Text("เพิ่มแท็บ INV\(number) ในรายการสตริง (ทุกช่องเริ่มเป็นสตริง \(modules) แผง แล้วตั้ง SPARE ช่องที่ไม่ได้ใช้) | Excel เพิ่มแผ่น INV \(nn)-ก่อน และ INV \(nn)-หลัง ที่ลิงก์หัวเรื่องจาก INV 01")
            .font(.sarabunFixed(14)).foregroundStyle(Theme.navy).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var photoSlots: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("รูปอินเวอร์เตอร์").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.navy)
                + Text("  *").font(.sarabunFixed(16, .bold)).foregroundStyle(Theme.dangerText)
            HStack(spacing: 12) {
                ForEach(IECReport.InverterPhoto.allCases, id: \.self) { k in
                    VStack(alignment: .leading, spacing: 4) {
                        IECPhotoTile(caption: k.title, asset: job.iecPhoto(photos[k.rawValue]), height: 110, stubReading: "INV") { data in
                            photos[k.rawValue] = job.storeIECPhoto(data, replacing: photos[k.rawValue], context: context)
                        } remove: {
                            job.removeIECPhoto(photos[k.rawValue], context: context); photos[k.rawValue] = nil
                        }
                        Text(k.title).font(.sarabunFixed(13, .bold)).foregroundStyle(Theme.navy).lineLimit(1)
                        Text(k.required ? "จำเป็น" : "ไม่บังคับ").font(.sarabunFixed(12)).foregroundStyle(k.required && photos[k.rawValue] == nil ? Theme.dangerText : Theme.inkMuted)
                    }
                }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            Spacer()
            Button("ยกเลิก", action: close).buttonStyle(TCButtonStyle(.secondary, size: .bar, fullWidth: true)).frame(width: 200)
            Button(ready ? "เพิ่ม INV\(number)" : "ถ่ายรูปด้านหน้าและป้าย S/N ก่อน") { commit() }
                .font(.sarabunFixed(17, .bold)).foregroundStyle(ready ? Theme.onPrimary : Theme.disabledText)
                .frame(width: 350, height: 53).background(ready ? Theme.primary : Theme.disabledFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .buttonStyle(.plain).disabled(!ready)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func commit() {
        guard let m = model else { return }
        var index = 0
        let sn = serial.trimmingCharacters(in: .whitespaces), kept = photos, n = modules
        job.updateIEC(context) { index = $0.addInverter(model: m.brand + " " + m.model, ratedKW: Double(m.kw), mppt: m.mppt, serial: sn, modules: n, photos: kept) }
        added = true
        serial = ""
        add(index)
    }
}
