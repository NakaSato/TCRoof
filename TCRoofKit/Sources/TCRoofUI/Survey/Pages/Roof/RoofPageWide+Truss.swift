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
                        Text(Roof.frame(values).title + " | " + s.summary)
                            .font(.sarabunFixed(15, .bold)).fixedSize(horizontal: false, vertical: true)
                        trussDetails
                        scheduleTable(s)
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
        VStack(spacing: 0) {
            scheduleRow("", "ชิ้นส่วน", "ขนาด", Roof.frame(values).isRafter ? "ต่อคู่ (ชิ้น | ม.)" : "ต่อโครง (ชิ้น | ม.)", "ทั้งหลังคา", header: true)
            ForEach(Array(s.rows.enumerated()), id: \.offset) { _, r in
                Divider()
                scheduleRow(r.row.map(String.init) ?? "", r.name, r.size, RoofTruss.perFrameText(r), RoofTruss.totalText(r), header: false)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle))
    }

    func scheduleRow(_ n: String, _ name: String, _ size: String, _ per: String, _ total: String, header: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(n).frame(width: 18, alignment: .leading).foregroundStyle(Theme.inkMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.sarabunFixed(header ? 12.5 : 14, .bold))
                // iPhone: the size under the name, no column of its own
                if narrow && !header { Text(size).font(.sarabunFixed(12.5)).foregroundStyle(Theme.inkMuted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !narrow { Text(size).frame(maxWidth: .infinity, alignment: .leading) }
            Text(per).frame(width: narrow ? 74 : 130, alignment: .trailing).monospacedDigit()
            Text(total).frame(width: narrow ? 104 : 140, alignment: .trailing).monospacedDigit()
        }
        .font(.sarabunFixed(header ? 12.5 : 14, header ? .bold : .regular))
        .foregroundStyle(header ? Theme.inkMuted : Theme.navy)
        .lineLimit(2).minimumScaleFactor(0.8)
        .frame(minHeight: 40)
    }
}
#endif
