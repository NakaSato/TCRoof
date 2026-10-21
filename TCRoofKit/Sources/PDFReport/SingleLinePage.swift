import Foundation
import TCRoofCore

/// The single line diagram on one A3 landscape page: the shared vector layout, a title block, the PV data and the breaker check.
public extension ReportLayout {
    static let a3W = 1190.55, a3H = 841.89

    /// - Parameter hv: previews the other zero-export side (only when the job has no B4 section); nil follows B4.
    func singleLinePage(hv: Bool? = nil) -> Page {
        let sl = SingleLine.build(job, hvOverride: hv)
        let drawing = SingleLineLayout.draw(sl)
        let W = Self.a3W, H = Self.a3H, mg = 28.0
        var o: [DrawOp] = [.rect(Box(0, 0, W, H), stroke: nil, fill: .white)]
        let ink = RGBA(hex: 0x16325C), muted = RGBA(hex: 0x5B6B82), red = RGBA(hex: 0xD9453B), green = RGBA(hex: 0x2E7D4F), amber = RGBA(hex: 0xB7791F)

        // title block
        let docNo = job.docNo.isEmpty ? "-" : job.docNo
        o.append(.text("แผนภาพเส้นเดียว (Single Line Diagram)", at: Pt(mg, mg + 10), size: 17, bold: true, color: ink))
        o.append(.text("เลขที่ \(docNo) | \(job.projectName.isEmpty ? "(ยังไม่ตั้งชื่อโครงการ)" : job.projectName) | วันที่ \(ISODate.thai(job.values.text("date")))"
                       + (job.values.text("engineer").isEmpty ? "" : " | วิศวกร \(job.values.text("engineer"))"), at: Pt(mg, mg + 30), size: 10, color: .dark))
        o.append(.text("สร้างจากข้อมูลสำรวจ ไม่ใช่แบบก่อสร้าง", at: Pt(W - mg, mg + 10), size: 11, bold: true, color: red, align: .right))
        o.append(.text("ข้อมูล A1 | A3 | A4 | B1 | B2 | B4 | B5 | ยังขาด \(sl.missing.count) จุด", at: Pt(W - mg, mg + 30), size: 9, color: muted, align: .right))
        o.append(.line(Pt(mg, mg + 42), Pt(W - mg, mg + 42), width: 1, color: ink))

        // diagram, vector
        let sideW = 318.0
        let areaX = mg, areaY = mg + 52, areaW = W - 2 * mg - sideW - 14, areaH = H - areaY - mg - 34
        let k = min(areaW / drawing.width, areaH / drawing.height)
        let dx = areaX + (areaW - drawing.width * k) / 2
        o += drawing.sketch.translated(dx, areaY, scale: k)
        // legend under the diagram
        let ly = H - mg - 12
        o.append(.line(Pt(areaX, ly), Pt(areaX + 26, ly), width: 1.6, color: SingleLineLayout.ink))
        o.append(.text("อุปกรณ์เดิม", at: Pt(areaX + 32, ly), size: 8.5, color: .dark))
        o.append(.line(Pt(areaX + 100, ly), Pt(areaX + 126, ly), width: 1.6, color: SingleLineLayout.blue))
        o.append(.text("อุปกรณ์ใหม่ (PV)", at: Pt(areaX + 132, ly), size: 8.5, color: .dark))
        o.append(.line(Pt(areaX + 230, ly), Pt(areaX + 256, ly), width: 1.3, color: SingleLineLayout.blue, dash: [4, 3]))
        o.append(.text("สายสัญญาณควบคุม", at: Pt(areaX + 262, ly), size: 8.5, color: .dark))

        // side column
        let sx = W - mg - sideW
        var y = areaY
        func heading(_ t: String, _ trailing: String? = nil) {
            o.append(.text(t, at: Pt(sx, y + 6), size: 10.5, bold: true, color: ink))
            if let trailing { o.append(.text(trailing, at: Pt(sx + sideW, y + 6), size: 9, color: muted, align: .right)) }
            o.append(.line(Pt(sx, y + 15), Pt(sx + sideW, y + 15), width: 0.6, color: .rule))
            y += 22
        }
        heading("ข้อมูลฝั่ง PV", "400 V 3 เฟส")
        for r in sl.pv.rows {
            o.append(.text(r.label, at: Pt(sx, y + 5), size: 9, color: muted))
            let c: RGBA = r.value.isMissing ? red : ink
            o.append(.text(r.value.text, at: Pt(sx + sideW, y + 5), size: 9.5, bold: true, color: c, align: .right))
            y += 15
        }
        y += 8
        heading("เบรกเกอร์ทนลัดวงจร \(sl.isc.map { SingleLine.fmt($0) } ?? "?") kA ได้ไหม")
        for c in sl.checks {
            let (sym, col): (String, RGBA) = { switch c.state { case .ok: return ("✓", green); case .marginal: return ("!", amber); case .insufficient: return ("✗", red); case .unknown: return ("?", red) } }()
            o.append(.text(sym, at: Pt(sx + 5, y + 5), size: 9.5, bold: true, color: col, align: .center))
            o.append(.text(c.name.count > 26 ? String(c.name.prefix(25)) + "…" : c.name, at: Pt(sx + 16, y + 5), size: 9, color: .dark))
            o.append(.text(c.value, at: Pt(sx + sideW, y + 5), size: 9, bold: true, color: col, align: .right))
            y += 14
        }
        if sl.iscAssumedZ { o.append(.text("คำนวณด้วย %Z สมมติ \(SingleLine.fmt(SLConstants.defaultZPercent)) %", at: Pt(sx, y + 5), size: 8, color: muted)); y += 14 }
        y += 8
        if !sl.blocking.isEmpty {
            heading("ต้องเก็บก่อนออกแบบ", "\(sl.blocking.count) จาก \(sl.missing.count)")
            for b in sl.blocking.prefix(9) {
                let t = b.label.count > 52 ? String(b.label.prefix(51)) + "…" : b.label
                o.append(.text(t, at: Pt(sx, y + 5), size: 8.5, color: red))
                o.append(.text(b.target.linkLabel, at: Pt(sx + sideW, y + 5), size: 8.5, bold: true, color: ink, align: .right))
                y += 13
            }
            if sl.blocking.count > 9 { o.append(.text("… และอีก \(sl.blocking.count - 9) รายการ", at: Pt(sx, y + 5), size: 8, color: muted)); y += 13 }
            y += 8
        }
        if let f = sl.flood {
            let h = m.height(f.text, width: sideW - 12, size: 8.5, bold: false) + 14
            o.append(.rect(Box(sx, y, sideW, h), stroke: amber, fill: RGBA(hex: 0xFFF4E3), width: 0.8))
            o.append(.textBox("จุดเชื่อมต่อเคยน้ำท่วม | " + f.text, Box(sx + 6, y + 6, sideW - 12, h - 8), size: 8.5, color: RGBA(hex: 0x7A4A00)))
            y += h + 10
        }
        heading("สรุป")
        var notes = ["ข้อมูลที่ขาดอื่นๆ \(sl.others.count) จุด | ไม่กระทบแบบ"]
        if sl.conditionCounts.bad + sl.conditionCounts.fair > 0 { notes.append("สภาพอุปกรณ์ ชำรุด \(sl.conditionCounts.bad) | พอใช้ \(sl.conditionCounts.fair)") }
        if !sl.assumptions.isEmpty { notes.append("ค่าสมมติ \(sl.assumptions.count) ข้อ" + (sl.pv.totalCableM > 0 ? " | รวมระยะสาย \(sl.pv.totalCableM) ม." : "")) }
        for n in notes { o.append(.text(n, at: Pt(sx, y + 5), size: 8.5, color: .dark)); y += 13 }
        for a in sl.assumptions.prefix(5) {
            let h = m.height("| " + a.text, width: sideW, size: 7.5, bold: false)
            o.append(.textBox("| " + a.text, Box(sx, y, sideW, h), size: 7.5, color: muted))
            y += h + 2
        }
        return Page(ops: o, width: W, height: H)
    }
}
