#if canImport(UIKit)
import SwiftUI
import TCRoofCore

/// C1 `ชิ้นส่วน` (docs/specs/auto-drawing.md §4.4): details A / B of a truss and the member schedule, from the same
/// geometry as section A-A (`RoofTruss`). Read only: the sizes come from the member rows, the counts from the plan.
extension RoofPageWide {
    var trussSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let s = RoofTruss.schedule(values) {
                        Text(Roof.frame(values).title + " · " + s.summary)
                            .font(.sarabunFixed(15, .bold)).fixedSize(horizontal: false, vertical: true)
                        trussDetails
                        scheduleTable(s)
                        Text(RoofTruss.steelNote(s)).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                        Text(s.note).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("ใส่ระยะช่วงในแปลนก่อน จึงคิดชิ้นส่วนได้").font(.sarabunFixed(15)).foregroundStyle(Theme.inkMuted)
                    }
                }
                .padding(16)
            }
            .navigationTitle("รายละเอียดและตารางชิ้นส่วน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { trussOpen = false } } }
        }
        .foregroundStyle(Theme.navy)
        .tint(Theme.primary)
        .presentationDetents([.large])
    }

    /// Details A and B side by side; nothing for the rafter frames, which have no truss joints to detail.
    @ViewBuilder var trussDetails: some View {
        if let d = RoofTruss.details(values) {
            GeometryReader { g in
                SketchCanvas(ops: d.ops, fit: SketchFit(d.width, d.height, in: g.size))
            }
            .aspectRatio(d.width / d.height, contentMode: .fit)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle))
            .accessibilityElement()
            .accessibilityLabel("รายละเอียด A ที่รองรับ และรายละเอียด B สันหลังคา ไม่ได้มาตราส่วน")
        } else {
            Text("โครง" + Roof.frame(values).label + " ไม่มีรายละเอียดรอยต่อโครงถัก").font(.sarabunFixed(13)).foregroundStyle(Theme.inkMuted)
        }
    }

    func scheduleTable(_ s: RoofTruss.Schedule) -> some View {
        let rafter = Roof.frame(values).isRafter
        return VStack(spacing: 0) {
            scheduleRow(ScheduleLine(n: "", name: "ชิ้นส่วน", size: "ขนาด", per: rafter ? "ต่อคู่ (ชิ้น · ม.)" : "ต่อโครง (ชิ้น · ม.)",
                                     total: "ทั้งหลังคา", kgm: "กก./ม.", perKg: rafter ? "กก./คู่" : "กก./โครง", kg: "กก. รวม"), header: true)
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, r in
                Divider()
                scheduleRow(ScheduleLine(n: r.row.map(String.init) ?? "", name: r.name, size: r.size, per: RoofTruss.perFrameText(r),
                                         total: RoofTruss.totalText(r), kgm: RoofTruss.kgPerMetreText(r),
                                         perKg: RoofTruss.perFrameKgText(r), kg: RoofTruss.kgText(r)), header: false)
            }
            Divider()
            scheduleRow(ScheduleLine(n: "", name: "รวมเหล็ก (ประมาณ)", size: "ไม่รวมแผ่นประกับ", per: "", total: "", kgm: "",
                                     perKg: RoofTruss.steelPerFrameKgText(s), kg: RoofTruss.steelKgText(s)), header: false, total: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle))
    }

    struct ScheduleLine {
        let n, name, size, per, total, kgm, perKg, kg: String
    }

    func scheduleRow(_ l: ScheduleLine, header: Bool, total: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(l.n).frame(width: 18, alignment: .leading).foregroundStyle(Theme.inkMuted)
            scheduleName(l, header: header)
            if !narrow {
                Text(l.size).frame(maxWidth: .infinity, alignment: .leading)
                Text(l.per).frame(width: 92, alignment: .trailing).monospacedDigit()
                Text(l.total).frame(width: 108, alignment: .trailing).monospacedDigit()
                Text(l.kgm).frame(width: 52, alignment: .trailing).monospacedDigit()
                Text(l.perKg).frame(width: 70, alignment: .trailing).monospacedDigit()
                Text(l.kg).frame(width: 70, alignment: .trailing).monospacedDigit()
            } else {
                // iPhone: the weights under the counts, in their columns
                scheduleCell(l.per, l.perKg, header: header, total: total).frame(width: 74, alignment: .trailing)
                scheduleCell(l.total, l.kg, header: header, total: total).frame(width: 104, alignment: .trailing)
            }
        }
        .font(.sarabunFixed(header ? 12.5 : 14, header || total ? .bold : .regular))
        .foregroundStyle(header ? Theme.inkMuted : Theme.navy)
        .lineLimit(2).minimumScaleFactor(0.8)
        .frame(minHeight: 40)
    }

    func scheduleName(_ l: ScheduleLine, header: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l.name).font(.sarabunFixed(header ? 12.5 : 14, .bold))
            // iPhone: the size and kg/m under the name, no columns of their own
            if narrow {
                let sub = header ? "ขนาด · กก./ม." : l.kgm.isEmpty || l.kgm == "-" ? l.size : l.size + " · " + l.kgm + " กก./ม."
                Text(sub).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// iPhone: a count over its weight ("12 · 31.20" / "171.6 กก."); the weight alone on the total line.
    func scheduleCell(_ count: String, _ kg: String, header: Bool, total: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if !count.isEmpty { Text(count).monospacedDigit() }
            if header { Text(kg).font(.sarabunFixed(12.5, .bold)) }
            else if kg != "-" || total { Text(kg == "-" ? kg : kg + " กก.").font(.sarabunFixed(total ? 14 : 12.5, total ? .bold : .regular))
                .foregroundStyle(total ? Theme.navy : Theme.inkMuted).monospacedDigit() }
        }
    }
}
#endif
