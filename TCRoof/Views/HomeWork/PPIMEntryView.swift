import SwiftUI
import TCRoofUI
import TCRoofCore

/// PPIM part 3 for a home: the meter, location, panel and inverter tables to type in, the answers that never change,
/// and a copy button on each value so the team can fill PPIM from the iPad.
struct PPIMEntryView: View {
    @Binding var home: HomeJob
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    meterCard
                    panelsCard
                    invertersCard
                    fixedCard
                }
                .padding(Space.l)
            }
            .tcPageBackground()
            .navigationTitle("ข้อมูลกรอก PPIM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { sync(); dismiss() } }
            }
        }
    }

    /// The tables' totals become the job's sizes, as PPIM uses them.
    private func sync() {
        if let kwp = home.ppim.panelKWp { home.pvKWp = PPIMEntryView.text(kwp) }
        if let kw = home.ppim.inverterKW { home.inverterKW = PPIMEntryView.text(kw) }
    }

    static func text(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private var meterCard: some View {
        PermitSection(title: "เครื่องวัดและที่ตั้ง", subtitle: "ส่วนที่ 3 | ข้อมูลเครื่องวัดหน่วยไฟฟ้า และพิกัดภูมิศาสตร์") {
            PermitRow {
                PermitField("หมายเลขเครื่องวัด (PEA No.)", text: $home.ppim.peaMeterNo, required: true, keyboard: .numberPad)
                copyRow("ระดับแรงดันของเครื่องวัด", PPIMEntry.meterVoltage(home.phase) ?? "เลือกระบบไฟในหน้างานบ้าน")
            }
            PermitRow {
                PermitField("ละติจูด (°N)", text: $home.ppim.latitude, required: true, keyboard: .decimalPad)
                PermitField("ลองจิจูด (°E)", text: $home.ppim.longitude, required: true, keyboard: .decimalPad)
            }
            ForEach(home.ppim.issues, id: \.self) { issue in
                Text(issue).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.dangerText)
            }
        }
    }

    private var panelsCard: some View {
        PermitSection(title: "ข้อมูลแผงพลังงานแสงอาทิตย์",
                      subtitle: home.ppim.panelKWp.map { "กำลังการผลิตทั้งหมด \(PPIMEntryView.text($0)) kWp" } ?? "ชนิดแผง ยี่ห้อ รุ่น Wp/แผง จำนวน") {
            ForEach(home.ppim.panels.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: Space.s) {
                    PermitRow {
                        PermitField("ชนิดแผง", text: $home.ppim.panels[i].type)
                        PermitField("ยี่ห้อ", text: $home.ppim.panels[i].brand, required: true)
                        PermitField("รุ่น", text: $home.ppim.panels[i].model, required: true)
                    }
                    PermitRow {
                        PermitField("กำลังการผลิต/แผง", text: $home.ppim.panels[i].watt, required: true, keyboard: .decimalPad, unit: "Wp")
                        PermitField("จำนวน", text: $home.ppim.panels[i].count, required: true, keyboard: .numberPad, unit: "แผง")
                    }
                    if home.ppim.panels.count > 1 {
                        TCButton("ลบแถวนี้", systemImage: "trash", kind: .secondary, size: .card) { home.ppim.panels.remove(at: i) }
                    }
                }
            }
            TCButton("เพิ่มแผงอีกรุ่น", systemImage: "plus", kind: .secondary, size: .card) { home.ppim.panels.append(.init()) }
        }
    }

    private var invertersCard: some View {
        PermitSection(title: "ข้อมูลอินเวอร์เตอร์",
                      subtitle: home.ppim.inverterKW.map { "กำลังการผลิตทั้งหมด \(PPIMEntryView.text($0)) kW = ขนาดที่ขอเชื่อมต่อ" } ?? "ยี่ห้อ รุ่น kW จำนวน") {
            ForEach(home.ppim.inverters.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: Space.s) {
                    PermitRow {
                        PermitField("ยี่ห้อ", text: $home.ppim.inverters[i].brand, required: true)
                        PermitField("รุ่น", text: $home.ppim.inverters[i].model, required: true)
                    }
                    PermitRow {
                        PermitField("กำลังการผลิต", text: $home.ppim.inverters[i].kW, required: true, keyboard: .decimalPad, unit: "kW")
                        PermitField("จำนวน", text: $home.ppim.inverters[i].count, required: true, keyboard: .numberPad, unit: "เครื่อง")
                    }
                    if home.ppim.inverters.count > 1 {
                        TCButton("ลบแถวนี้", systemImage: "trash", kind: .secondary, size: .card) { home.ppim.inverters.remove(at: i) }
                    }
                }
            }
            TCButton("เพิ่มอินเวอร์เตอร์", systemImage: "plus", kind: .secondary, size: .card) { home.ppim.inverters.append(.init()) }
        }
    }

    private var fixedCard: some View {
        PermitSection(title: "คำตอบที่เหมือนกันทุกงานบ้าน (ผลิตใช้เอง)", subtitle: "ส่วนที่ 2 ผู้ประสานงาน ใช้ข้อมูลทีมเรา") {
            ForEach(PPIMEntry.fixedAnswers.indices, id: \.self) { i in
                copyRow(PPIMEntry.fixedAnswers[i].0, PPIMEntry.fixedAnswers[i].1)
            }
        }
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .center, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.sarabun(TypeScale.caption, relativeTo: .caption)).foregroundStyle(Theme.inkMuted)
                Text(value).font(.sarabun(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { UIPasteboard.general.string = value } label: {
                Image(systemName: "doc.on.doc").frame(width: touchMin, height: touchMin)
            }
            .buttonStyle(.plain).foregroundStyle(Theme.primary)
            .accessibilityLabel("คัดลอก \(label)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
