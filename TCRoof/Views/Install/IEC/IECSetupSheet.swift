import SwiftUI
import TCRoofUI
import TCRoofCore

/// `ตั้งค่าการทดสอบ`: the panel model, each inverter's size, serial and module count per string slot (10 MPPT × 2, as
/// in the sheet), and who tested with what. Edits a copy; `บันทึก` keeps it.
struct IECSetupSheet: View {
    @State var report: IECReport
    let save: (IECReport) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                moduleSection
                ForEach(report.inverters.indices, id: \.self) { i in inverterSection(i) }
                Section {
                    Button {
                        report.inverters.append(IECReport.Inverter())
                    } label: { Label("เพิ่ม inverter", systemImage: "plus.circle") }
                }
                recordSection
            }
            .font(.sarabunFixed(16))
            .navigationTitle("ตั้งค่าการทดสอบ IEC 62446")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ยกเลิก") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("บันทึก") { save(report); dismiss() } }
            }
        }
    }

    private func numberRow(_ title: String, _ unit: String, _ value: Binding<Double?>, label: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", value: value, format: .number.grouping(.never)).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .accessibilityLabel(label ?? title)
                .frame(width: 140)
            Text(unit).foregroundStyle(Theme.inkMuted).frame(width: 44, alignment: .leading)
        }
    }

    private func optional(_ b: Binding<Double>) -> Binding<Double?> {
        Binding(get: { b.wrappedValue == 0 ? nil : b.wrappedValue }, set: { b.wrappedValue = $0 ?? 0 })
    }

    private var moduleSection: some View {
        Section("แผงโซลาร์") {
            TextField("ยี่ห้อ / รุ่นแผง", text: $report.module.brand)
            numberRow("กำลังต่อแผง", "W", optional($report.module.powerW))
            numberRow("พื้นที่ต่อแผ่น (datasheet)", "m²", $report.module.areaM2)
            TextField("บรรทัดสถานีบนแผ่นงาน", text: $report.stationLine, axis: .vertical)
        }
    }

    private func inverterSection(_ i: Int) -> some View {
        Section {
            numberRow("พิกัด", "kW", optional($report.inverters[i].ratedKW), label: "พิกัด inverter \(i + 1)")
            HStack {
                Text("S/N")
                TextField("serial", text: $report.inverters[i].serial).multilineTextAlignment(.trailing)
                    .accessibilityLabel("S/N inverter \(i + 1)")
            }
            slotGrid(i)
            if report.inverters.count > 1 {
                Button(role: .destructive) { report.inverters.remove(at: i) } label: { Label("ลบ inverter นี้", systemImage: "trash") }
            }
        } header: {
            Text("Inverter \(i + 1)")
        } footer: {
            Text("ใส่จำนวนแผงของแต่ละช่องสตริง ช่องที่เว้นว่างคือไม่มีสตริง | \(report.inverters[i].strings.count) สตริง")
        }
    }

    /// 10 MPPT columns of 2 slots: the module count of each string; empty = no string.
    private func slotGrid(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(1...IECReport.slotCount / 2, id: \.self) { m in
                    Text("MPPT \(m)").font(.sarabunFixed(12, .bold)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(1...IECReport.slotCount / 2, id: \.self) { m in
                        let slot = (m - 1) * 2 + row + 1
                        TextField("\(slot)", value: modules(i, slot), format: .number.grouping(.never))
                            .keyboardType(.numberPad).multilineTextAlignment(.center)
                            .font(.sarabunFixed(16, .bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(report.inverters[i].slots[slot - 1] == nil ? Theme.phonePage : Theme.primarySoft,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityLabel("Inverter \(i + 1) ช่อง \(slot) จำนวนแผง")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// A slot's module count; clearing it (or 0) removes the string, a new count adds one of the panel brand.
    private func modules(_ i: Int, _ slot: Int) -> Binding<Int?> {
        Binding(get: { report.inverters[i].slots[slot - 1]?.modules }, set: { v in
            if let v, v > 0 {
                if report.inverters[i].slots[slot - 1] == nil {
                    report.inverters[i].slots[slot - 1] = IECReport.Slot(modules: v, brand: report.module.brand.isEmpty ? nil : report.module.brand)
                } else {
                    report.inverters[i].slots[slot - 1]?.modules = v
                }
            } else {
                report.inverters[i].slots[slot - 1] = nil
            }
        })
    }

    private var recordSection: some View {
        Section("บันทึกการทดสอบ") {
            Toggle("ระบุวันที่ทดสอบ", isOn: Binding(get: { report.testDate != nil }, set: { report.testDate = $0 ? (report.testDate ?? .now) : nil }))
            if report.testDate != nil {
                DatePicker("วันที่ทดสอบ", selection: Binding(get: { report.testDate ?? .now }, set: { report.testDate = $0 }), displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "th_TH"))
            }
            TextField("ผู้ทดสอบ", text: $report.tester)
            TextField("S/N แคลมป์มิเตอร์", text: $report.instruments.multimeterClamp)
            TextField("S/N เครื่องวัดความเป็นฉนวน (IR)", text: $report.instruments.insulationTester)
            TextField("S/N เครื่องวัดความเข้มแสง", text: $report.instruments.irradianceMeter)
            TextField("S/N กล้องถ่ายภาพความร้อน", text: $report.instruments.thermalCamera)
        }
    }
}
