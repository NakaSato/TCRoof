import Foundation

extension RoofDXF {
    /// The member schedule (`RoofTruss.schedule`, as the PDF prints it) with its top-left corner at `o` (metres): the
    /// title and summary, a line per member row with its count and length per truss and for the roof, its weight per
    /// metre, per truss and in all, the steel total and the notes. Returns the y under it.
    static func memberSchedule(_ dxf: inout SketchDXF, _ s: RoofTruss.Schedule, rafter: Bool, title: String,
                               at o: (Double, Double), text h: Double) -> Double {
        let L = CADLayers.roofTable, rh = h * 2.2
        let widths: [Double] = [0.6, 3.4, 4.2, 2.6, 3.2, 1.4, 1.8, 1.8]
        let xs = widths.reduce(into: [0.0]) { $0.append($0.last! + $1) }, w = xs.last!
        let right: Set<Int> = [3, 4, 5, 6, 7]
        let head = ["", "ชิ้นส่วน", "ขนาด", rafter ? "ต่อคู่ (ชิ้น | ม.)" : "ต่อโครง (ชิ้น | ม.)", "ทั้งหลังคา (ชิ้น | ม.)",
                    "กก./ม.", rafter ? "กก./คู่" : "กก./โครง", "กก. รวม"]
        let rows = [head]
            + s.rows.map { r in [r.row.map(String.init) ?? "", r.name, r.size, RoofTruss.perFrameText(r), RoofTruss.totalText(r),
                                 RoofTruss.kgPerMetreText(r), RoofTruss.perFrameKgText(r), RoofTruss.kgText(r)] }
            + [["", "รวมเหล็ก (ประมาณ)", "ไม่รวมแผ่นประกับ", "", "", "", RoofTruss.steelPerFrameKgText(s), RoofTruss.steelKgText(s)]]
        dxf.text(L, (o.0, o.1), height: h * 1.6, title)
        dxf.text(L, (o.0, o.1 - h * 2), height: h, s.summary)
        let top = o.1 - h * 3
        for (ri, cells) in rows.enumerated() {
            let y = top - Double(ri) * rh
            dxf.line(L, (o.0, y), (o.0 + w, y))
            for (ci, t) in cells.enumerated() where !t.isEmpty {
                let r = right.contains(ci) && ri > 0
                dxf.text(L, (o.0 + (r ? xs[ci + 1] - 0.1 : xs[ci] + 0.1), y - rh / 2), height: ri == 0 && ci >= 3 ? h * 0.85 : h, t,
                         align: r ? .right : .left, middle: true)
            }
        }
        let bottom = top - Double(rows.count) * rh
        dxf.line(L, (o.0, bottom), (o.0 + w, bottom))
        for x in xs { dxf.line(L, (o.0 + x, top), (o.0 + x, bottom)) }
        dxf.text(L, (o.0, bottom - h * 1.6), height: h * 0.8, RoofTruss.steelNote(s))
        dxf.text(L, (o.0, bottom - h * 3), height: h * 0.8, s.note)
        return bottom - h * 3.5
    }
}
