import Foundation
import TCRoofCore

/// Transformer photos and the flood history.
extension ReportLayout {
    // MARK: transformer photos (all sides) and the MDB each one feeds

    func transformerPhotos() -> [Unit] {
        let trs = j.transformers("trafos")
        var units: [Unit] = []
        for (i, t) in trs.enumerated() where Schema.transformerPresent(j, i) {
            let photos: [(Photo?, String?)] = Schema.transformerAngles.map { (j.photo("tr\(i)_\($0.key)"), $0.label) }
            let title = "หม้อแปลง TR\(i + 1)" + (t.kva.isEmpty ? "" : " ขนาด \(t.kva) kVA")
            let feed = j.text("tr\(i)_feed"), loc = j.text("tr\(i)_feedLoc")
            let missing = Schema.transformerAngles.filter { j.photo("tr\(i)_\($0.key)") == nil }.map(\.label)
            // info strip: which MDB this transformer feeds, and any missing required photos
            var o = box(title + " — ตู้ MDB ปลายสาย", height: Self.band + 22)
            var x = field("ตู้ MDB ปลายสาย", feed, x: 8, y: Self.band + 11, valueWidth: 110, ops: &o)
            x = field("ตำแหน่ง", loc, x: x, y: Self.band + 11, valueWidth: Self.cw - x - 60, ops: &o)
            units.append(Unit(h: Self.band + 22, ops: o))
            if !missing.isEmpty {
                units.append(Unit(h: 12, ops: [.text("ยังไม่มีภาพ: " + missing.joined(separator: ", "), at: Pt(0, 6), size: 8, color: .tag)]))
            }
            var all = photos
            if let fp = j.photo("tr\(i)_feedPhoto") { all.append((fp, "ตู้ MDB ปลายสาย " + feed)) }
            for (key, label) in [("mdbOpen", "เปิดตู้ ภายใน"), ("mdbBreaker", "เมนเบรกเกอร์"), ("mdbSpace", "ที่ว่างติดตั้ง CB โซลาร์")] {
                if let p = j.photo("tr\(i)_\(key)") { all.append((p, "ตู้ MDB " + label)) }
            }
            units += grid("ภาพหม้อแปลง TR\(i + 1) (ทุกมุม)", all, cellH: 165)
        }
        return units
    }

    // MARK: flood history

    func flood() -> [Unit] {
        guard let v = j.choice("floodHistory") else { return [] }
        let W = Self.cw, labelW = 190.0, unitW = 44.0, valW = W - labelW - unitW
        var o: [DrawOp] = [], y = Self.band
        func row(_ label: String, _ cell: (Double) -> ([DrawOp], Double), unit: String = "") {
            let (ops, ch) = cell(y), lh = m.height(label, width: labelW - 10, size: 8, bold: false) + 5, rh = max(17, ch, lh)
            o.append(.rect(Box(0, y, labelW, rh), stroke: .black, fill: RGBA(hex: 0xF4F8F1), width: 0.5))
            o.append(.rect(Box(labelW, y, valW, rh), stroke: .black, fill: nil, width: 0.5))
            o.append(.rect(Box(labelW + valW, y, unitW, rh), stroke: .black, fill: nil, width: 0.5))
            o.append(.textBox(label, Box(5, y + 3, labelW - 10, rh - 4), size: 8))
            o += ops
            o.append(.text(unit, at: Pt(labelW + valW + unitW / 2, y + rh / 2), size: 8, align: .center))
            y += rh
        }
        row("พื้นที่เคยมีน้ำท่วมหรือไม่") { y in
            let (ops, h) = checks(["ไม่เคย", "เคย", "ไม่ทราบ"], chosen: { $0 == v }, x: labelW + 6, y: y + 1, width: valW - 12, size: 8); return (ops, h + 2)
        }
        // the equipment heights are in the check table below; photos and the GISTDA result have their own boxes
        for f in Schema.flood.fields where f.id != "floodHistory" && !["invFloorCm", "invMountCm", "emgMountCm"].contains(f.id) && f.isVisible(j) {
            if case .photo = f.kind { continue }
            if case .photos = f.kind { continue }
            var unit = ""
            if case .number(let u) = f.kind { unit = u }
            var t = f.displayText(j)
            if !unit.isEmpty, t.hasSuffix(" " + unit) { t = String(t.dropLast(unit.count + 1)) }
            row(f.label, { y in
                let h = self.m.height(t.isEmpty ? "—" : t, width: valW - 12, size: 8.5, bold: true) + 5
                return ([.textBox(t.isEmpty ? "—" : t, Box(labelW + 6, y + 3, valW - 12, h), size: 8.5, bold: true, color: t.isEmpty ? .faint : .blue)], h)
            }, unit: unit)
        }
        var units = [Unit(h: y, ops: box("ประวัติน้ำท่วม", height: y) + o)]
        if let g = j.gistda { units.append(gistdaBox(g)) }
        units += floodSection()
        let evidence = ([j.photo("floodPhoto")] + j.photos("floodPhotos").map { Optional($0) }).compactMap { $0 }
        units += grid("ภาพคราบระดับน้ำ / หลักฐานน้ำท่วม", evidence.map { ($0, nil) }, cellH: 230, columns: 1)
        return units
    }

    /// GISTDA lookup rows under the flood table, with the source footnote.
    func gistdaBox(_ g: FloodGistda) -> Unit {
        let W = Self.cw, labelW = 110.0, valW = W - labelW
        var o: [DrawOp] = [], y = Self.band
        for r in g.rows {
            let h = max(17, m.height(r.value, width: valW - 12, size: 8.5, bold: true) + 6)
            o.append(.rect(Box(0, y, labelW, h), stroke: .black, fill: RGBA(hex: 0xF4F8F1), width: 0.5))
            o.append(.rect(Box(labelW, y, valW, h), stroke: .black, fill: nil, width: 0.5))
            o.append(.text(r.label, at: Pt(6, y + h / 2), size: 8))
            let c: RGBA = r.tone == .good ? RGBA(hex: 0x3B7420) : r.tone == .warn ? RGBA(hex: 0xB45309) : r.tone == .bad ? RGBA(hex: 0xB42318) : .blue
            o.append(.textBox(r.value, Box(labelW + 6, y + 3, valW - 12, h - 3), size: 8.5, bold: true, color: c))
            y += h
        }
        if g.manual != true, !g.years.isEmpty {
            let cw = W - 40, k = min(1, cw / 480), ch = FloodGistda.chartHeight * k + 8
            o.append(.rect(Box(0, y, W, ch), stroke: .black, fill: nil, width: 0.5))
            o += g.chart(width: cw / k).translated(20, y + 4, scale: k)
            y += ch
        }
        let fh = m.height(g.footnote, width: W - 12, size: 7, bold: false) + 6
        o.append(.rect(Box(0, y, W, fh), stroke: .black, fill: nil, width: 0.5))
        o.append(.textBox(g.footnote, Box(6, y + 3, W - 12, fh - 3), size: 7, color: .ink2))
        y += fh
        return Unit(h: y, ops: box("ข้อมูลน้ำท่วมจาก GISTDA · ตามพิกัด A1 \(GPS.format(g.lat, g.lon))", height: y) + o)
    }

    /// The cross-section drawing (the same geometry as the editor) and the equipment height check.
    func floodSection() -> [Unit] {
        let W = Self.cw, k = W / FloodSection.width, dh = FloodSection.height * k
        let sk = FloodSection.sketch(job)
        var units = [Unit(h: Self.band + dh + 4, ops: box("ภาพตัดระดับน้ำ", height: Self.band + dh + 4) + sk.translated(0, Self.band + 2, scale: k))]
        let r = job.floodCheck
        guard !r.rows.isEmpty else { return units }
        let nameW = 230.0, tagW = 40.0, hW = 90.0, sW = W - nameW - tagW - hW
        var o: [DrawOp] = [.text(FloodCheck.requirement(j), at: Pt(W - 6, Self.band / 2), size: 8, color: .ink2, align: .right)], y = Self.band
        for row in r.rows {
            let h = 17.0
            let c: RGBA = row.status.tone == .good ? RGBA(hex: 0x3B7420) : row.status.tone == .bad ? RGBA(hex: 0xB42318) : RGBA(hex: 0xB45309)
            o.append(.rect(Box(0, y, W, h), stroke: .black, fill: nil, width: 0.5))
            o.append(.text(row.name, at: Pt(6, y + h / 2), size: 8.5))
            o.append(.text(row.tag, at: Pt(nameW + 4, y + h / 2), size: 8, color: .ink2))
            o.append(.text(row.height, at: Pt(nameW + tagW + hW - 8, y + h / 2), size: 8.5, bold: true, color: .blue, align: .right))
            o.append(.text(row.status.text, at: Pt(nameW + tagW + hW + 6, y + h / 2), size: 8.5, bold: true, color: c))
            y += h
        }
        _ = sW
        units.append(Unit(h: y, ops: box("ตรวจความสูงอุปกรณ์", height: y, left: true) + o))
        return units
    }
}
