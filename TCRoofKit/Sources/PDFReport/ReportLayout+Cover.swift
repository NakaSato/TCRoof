import Foundation
import TCRoofCore

/// Cover page, site picture, the MDB tree and the one-page summary.
extension ReportLayout {
    // MARK: cover

    func cover() -> [Unit] {
        var o: [DrawOp] = []
        let W = Self.cw, hh = 46.0
        // header row: logo | title | number/date
        o.append(.rect(Box(0, 0, W, hh), stroke: .black, fill: nil, width: 0.8))
        o.append(.line(Pt(100, 0), Pt(100, hh), width: 0.8, color: .black)); o.append(.line(Pt(W - 110, 0), Pt(W - 110, hh), width: 0.8, color: .black))
        if let logo = header.logo { o.append(.photo(logo, Box(4, 4, 92, hh - 8))) }
        else { o.append(.textBox(header.company, Box(4, 8, 92, hh - 12), size: 8, bold: true, align: .center)) }
        o.append(.text("แบบสำรวจเพื่อออกแบบ (เบื้องต้น)", at: Pt((100 + W - 110) / 2, 16), size: 13, bold: true, align: .center))
        o.append(.text("งานติดตั้งระบบผลิตไฟฟ้าจากพลังงานแสงอาทิตย์", at: Pt((100 + W - 110) / 2, 33), size: 9, align: .center))
        o.append(.line(Pt(W - 110, hh / 2), Pt(W, hh / 2), width: 0.5, color: .black))
        o.append(.text("เลขที่", at: Pt(W - 105, hh / 4), size: 7.5, color: .ink2)); o.append(.text(job.docNo, at: Pt(W - 5, hh / 4), size: 10, bold: true, align: .right))
        o.append(.text("วันที่", at: Pt(W - 105, hh * 3 / 4), size: 7.5, color: .ink2)); o.append(.text(ISODate.thai(j.text("date")), at: Pt(W - 5, hh * 3 / 4), size: 10, bold: true, align: .right))
        // project rows
        let rowH = 16.0, rows = 5.0, y0 = hh, infoW = W - 110
        o.append(.rect(Box(0, y0, W, rowH * rows), stroke: .black, fill: nil, width: 0.8))
        o.append(.line(Pt(infoW, y0), Pt(infoW, y0 + rowH * rows), width: 0.8, color: .black))
        func row(_ i: Double, _ items: [(String, String, Double)]) {
            var x = 6.0
            for (l, v, w) in items { x = field(l, v, x: x, y: y0 + rowH * i + rowH / 2, valueWidth: w, ops: &o) }
        }
        row(0, [("ชื่อโครงการ", job.projectName, infoW - 70)])
        row(1, [("ชื่อผู้ประสานงาน", j.text("coordinator"), 190), ("เบอร์โทร", j.text("phone"), 90)])
        row(2, [("ที่อยู่สถานี", j.text("address"), infoW - 62)])
        row(3, [("ที่อยู่สำนักงาน/สาขา", j.text("officeAddress"), infoW - 104)])
        row(4, [("พิกัด GPS", j.text("gps"), 200), ("อินเตอร์เน็ต", j.choice("internet") ?? "", 50)])
        o.append(.text("วิศวกรผู้สำรวจ", at: Pt(infoW + 6, y0 + 12), size: 7.5, color: .ink2))
        o.append(.textBox(j.text("engineer"), Box(infoW + 6, y0 + 20, 100, 30), size: 9.5, bold: true))
        o.append(.text("REV. \(j.text("rev").isEmpty ? "00" : j.text("rev"))", at: Pt(infoW + 6, y0 + rowH * rows - 9), size: 8))
        // site box
        let sy = y0 + rowH * rows + 10, photoH = 330.0, listH = 5 * 14.0 + 16
        let siteH = Self.band + 20 + photoH + listH
        o += translate(box("ภาพสถานที่ติดตั้ง", height: siteH), dx: 0, dy: sy)
        _ = field("กำลังการผลิตติดตั้ง", j.text("capacity").isEmpty ? "" : j.text("capacity") + " kWp", x: 8, y: sy + Self.band + 10, valueWidth: 120, ops: &o)
        if let p = j.photo("siteMap") {
            let marks = j.marks("siteMarks"), kinds = SiteMarks.usedKinds(marks)
            let lh = SiteMarks.legendHeight(kinds, width: W - 12)
            let note = j.text("siteNote").trimmingCharacters(in: .whitespacesAndNewlines), nh = note.isEmpty ? 0.0 : 22.0
            let area = Box(6, sy + Self.band + 20, W - 12, photoH - 8 - (lh > 0 ? lh + 4 : 0) - nh)
            let pic = area.fit(Double(p.width), Double(p.height))
            o.append(.photo(p, area))
            o += siteDrawing(in: pic)
            // symbol legend under the picture
            o += SiteMarks.legend(kinds, in: Box(pic.x, area.maxY + 4, pic.w, lh))
            if !note.isEmpty {
                o.append(.textBox("หมายเหตุหน้างาน: " + note, Box(pic.x, area.maxY + 4 + (lh > 0 ? lh + 4 : 0), pic.w, nh), size: 7.5))
            }
        }
        let ly = sy + Self.band + 20 + photoH
        o.append(.line(Pt(0, ly), Pt(W, ly), width: 0.8, color: .black))
        o.append(.text("LIST", at: Pt(8, ly + 8), size: 7.5, color: .ink2))
        let sel = j.multi("siteList"), colW = (W - 90) / 3
        for (i, item) in Options.list.enumerated() {
            let c = Double(i / 5), r = Double(i % 5)
            let bx = 8 + c * colW, by = ly + 16 + r * 14
            o.append(.checkbox(Box(bx, by, 8, 8), on: sel.contains(item)))
            o.append(.textBox("- " + item, Box(bx + 11, by - 2, colW - 14, 12), size: 7.2, bold: sel.contains(item)))
        }
        o.append(.line(Pt(W - 86, ly), Pt(W - 86, ly + listH), width: 0.8, color: .black))
        o.append(.text("ทิศทาง", at: Pt(W - 43, ly + 8), size: 7.5, align: .center))
        o += Drawings.compass(j.choice("north"), size: 66).translated(W - 76, ly + 16)
        return [Unit(h: sy + siteH, ops: o)]
    }

    /// Building models, shapes, then symbols, over the site picture drawn in `pic`.
    func siteDrawing(in pic: Box) -> [DrawOp] {
        SiteModels.reportOps(job, in: pic)
            + SiteShapes.ops(j.shapes(SiteShapes.key), in: pic, metersAcross: j.number(SiteShapes.scaleKey))
            + SiteMarks.ops(j.marks("siteMarks"), in: pic)
    }

    // MARK: meter / transformers / MDB tree

    func tree() -> Unit? {
        let tr = j.transformers("trafos").filter { !$0.kva.isEmpty || $0.mdb.contains { !$0.isEmpty } }
        guard !tr.isEmpty || !j.text("meterNo").isEmpty else { return nil }
        let cols = tr.isEmpty ? [Transformer()] : tr
        let W = Self.cw, colW = min(104, (W - 20) / Double(cols.count)), mdbH = 26.0
        let h = Self.band + 50 + 44 + 6 * (mdbH + 4) + 14
        var o = box("ระบบไฟฟ้า — มิเตอร์ / หม้อแปลงไฟฟ้า / ตู้ MDB", height: h)
        let meter = Box(W / 2 - 90, Self.band + 10, 180, 34)
        o.append(.rect(meter, stroke: .black, fill: .band, width: 0.8))
        o.append(.text("มิเตอร์ไฟฟ้า", at: Pt(W / 2, meter.y + 10), size: 8.5, bold: true, align: .center))
        o.append(.text("หมายเลข " + (j.text("meterNo").isEmpty ? "_______________" : j.text("meterNo")), at: Pt(W / 2, meter.y + 24), size: 8.5, color: .blue, align: .center))
        let totalW = colW * Double(cols.count), x0 = (W - totalW) / 2, ty = meter.maxY + 16
        o.append(.line(Pt(W / 2, meter.maxY), Pt(W / 2, ty - 8), width: 0.8, color: .black))
        if cols.count > 1 { o.append(.line(Pt(x0 + colW / 2, ty - 8), Pt(x0 + totalW - colW / 2, ty - 8), width: 0.8, color: .black)) }
        for (i, t) in cols.enumerated() {
            let cx = x0 + Double(i) * colW, mid = cx + colW / 2
            o.append(.line(Pt(mid, ty - 8), Pt(mid, ty), width: 0.8, color: .black))
            let hb = Box(cx + 4, ty, colW - 8, 34)
            o.append(.rect(hb, stroke: .black, fill: RGBA(hex: 0xC6E0B4), width: 0.8))
            o.append(.text("หม้อแปลงไฟฟ้า", at: Pt(mid, hb.y + 10), size: 7.5, align: .center))
            o.append(.text("ขนาด \(t.kva.isEmpty ? "______" : t.kva) KVA", at: Pt(mid, hb.y + 24), size: 8, bold: true, align: .center))
            for k in 0..<6 {
                let by = hb.maxY + 8 + Double(k) * (mdbH + 4)
                o.append(.line(Pt(cx + 10, by - 4 - (k == 0 ? 4 : 0)), Pt(cx + 10, by + mdbH / 2), width: 0.6, color: .ink2))
                o.append(.line(Pt(cx + 10, by + mdbH / 2), Pt(cx + 16, by + mdbH / 2), width: 0.6, color: .ink2))
                let b = Box(cx + 16, by, colW - 20, mdbH)
                o.append(.rect(b, stroke: .black, fill: nil, width: 0.6))
                let bn = t.boards[safe: k]?.name.trimmingCharacters(in: .whitespaces) ?? ""
                o.append(.text(bn.isEmpty ? "ตู้ MDB\(k + 1)" : bn, at: Pt(b.x + 4, b.y + 8), size: 7, bold: true))
                let v = t.mdb[safe: k] ?? ""
                o.append(.text("เบรกเกอร์ \(v.isEmpty ? "_____" : v) A", at: Pt(b.x + 4, b.y + 19), size: 7, color: v.isEmpty ? .black : .blue))
            }
        }
        return Unit(h: h, ops: o)
    }

    // MARK: one-page summary

    /// Just the summary page, for the one-page PDF and the in-app preview.
    public func summaryPage() -> Page {
        let u = summary()
        let fy = Self.pageH - Self.margin - 6
        return Page(ops: [.rect(Box(0, 0, Self.pageW, Self.pageH), stroke: nil, fill: .white)] + translate(u.ops, dx: Self.margin, dy: Self.margin) + [
            .line(Pt(Self.margin, fy - 10), Pt(Self.pageW - Self.margin, fy - 10), width: 0.5, color: .faint),
            .text("สรุปผลการสำรวจ · เลขที่ \(job.docNo.isEmpty ? "-" : job.docNo) · \(job.projectName)", at: Pt(Self.margin, fy), size: 7.5, color: .ink2),
            .text("หน้าสรุป", at: Pt(Self.pageW - Self.margin, fy), size: 7.5, color: .ink2, align: .right)])
    }

    /// Everything on one page: project, verdict, completeness, site picture, transformers, every section's key facts, remarks and gaps.
    func summary() -> Unit {
        let W = Self.cw, fs = 7.8
        var o: [DrawOp] = [], y = 0.0
        let c = job.completion, verdict = j.choice("verdict")
        // header
        o.append(.text("สรุปผลการสำรวจ 1 หน้า · PWA Solar Survey", at: Pt(0, 5), size: 7.5, color: .ink2))
        o.append(.textBox(job.projectName.isEmpty ? "(ยังไม่ตั้งชื่อโครงการ)" : job.projectName, Box(0, 11, W - 170, 20), size: 14, bold: true))
        o.append(.text("เลขที่ \(job.docNo.isEmpty ? "-" : job.docNo) · วันที่ \(ISODate.thai(j.text("date"))) · วิศวกร \(j.text("engineer").isEmpty ? "-" : j.text("engineer"))", at: Pt(0, 38), size: 8.5))
        if let v = verdict {
            let col: RGBA = v == "ติดตั้งได้" ? RGBA(hex: 0x2E7D32) : v.contains("เงื่อนไข") ? RGBA(hex: 0xB26A00) : .tag
            let tw = m.width(v, size: 10, bold: true) + 18
            o.append(.rect(Box(W - tw, 2, tw, 20), stroke: col, fill: nil, width: 1.5))
            o.append(.text(v, at: Pt(W - tw / 2, 12), size: 10, bold: true, color: col, align: .center))
        } else { o.append(.text("ยังไม่ประเมิน", at: Pt(W, 12), size: 9, color: .tag, align: .right)) }
        o.append(.text("ความครบถ้วน \(c.percent)% (\(c.filled)/\(c.total))", at: Pt(W, 32), size: 8, bold: true, align: .right))
        o.append(.rect(Box(W - 170, 29, 60, 6), stroke: nil, fill: RGBA(hex: 0xE5E5E5)))
        o.append(.rect(Box(W - 170, 29, 60 * c.fraction, 6), stroke: nil, fill: .tick))
        o.append(.line(Pt(0, 47), Pt(W, 47), width: 1.5, color: RGBA(hex: 0x375623)))
        y = 53
        // site picture + key facts
        let picW = 250.0, picH = 170.0
        o.append(.rect(Box(0, y, picW, picH), stroke: .black, fill: nil, width: 0.6))
        if let p = j.photo("siteMap") {
            let area = Box(3, y + 3, picW - 6, picH - 6), fit = area.fit(Double(p.width), Double(p.height))
            o.append(.photo(p, area)); o += siteDrawing(in: fit)
        } else { o.append(.text("ยังไม่มีภาพสถานที่ติดตั้ง", at: Pt(picW / 2, y + picH / 2), size: 8, color: .faint, align: .center)) }
        let flood: String = {
            guard let f = j.choice("floodHistory") else { return "" }
            if f == "ไม่ทราบ" { return ["ไม่ทราบ", j.gistda?.summary].compactMap { $0 }.joined(separator: " · ") }
            guard f == "เคย" else { return f }
            return ["เคย", j.text("floodYear").isEmpty ? nil : "ปี " + j.text("floodYear"), j.text("floodDepth").isEmpty ? nil : "สูง \(j.text("floodDepth")) ซม.",
                    j.text("equipHeight").isEmpty ? nil : "ติดตั้งอุปกรณ์ ≥ \(j.text("equipHeight")) ซม."].compactMap { $0 }.joined(separator: " · ")
        }()
        let kv: [(String, String)] = [("กำลังการผลิตติดตั้ง", j.text("capacity").isEmpty ? "" : j.text("capacity") + " kWp"), ("ที่อยู่", j.text("address")), ("พิกัด GPS", j.text("gps")),
                                      ("ผู้ประสานงาน", [j.text("coordinator"), j.text("phone")].filter { !$0.isEmpty }.joined(separator: " · ")),
                                      ("อินเตอร์เน็ต", j.choice("internet") ?? ""), ("หมายเลขมิเตอร์", j.text("meterNo")), ("ประวัติน้ำท่วม", flood)]
        let kx = picW + 8, kw = W - kx, lw = 88.0, rowH = picH / Double(kv.count)
        for (i, (k, v)) in kv.enumerated() {
            let ry = y + Double(i) * rowH
            o.append(.rect(Box(kx, ry, lw, rowH), stroke: .black, fill: RGBA(hex: 0xF4F8F1), width: 0.5))
            o.append(.rect(Box(kx + lw, ry, kw - lw, rowH), stroke: .black, fill: nil, width: 0.5))
            o.append(.textBox(k, Box(kx + 4, ry + 3, lw - 8, rowH - 4), size: fs))
            o.append(.textBox(v.isEmpty ? "—" : v, Box(kx + lw + 4, ry + 3, kw - lw - 8, rowH - 4), size: fs, color: v.isEmpty ? .tag : .black))
        }
        y += picH + 8
        // table helper
        func table(_ cols: [(String, Double)], _ rows: [[(String, RGBA)]]) {
            let flexW = W - cols.map(\.1).filter { $0 > 0 }.reduce(0, +)
            let widths = cols.map { $0.1 > 0 ? $0.1 : flexW }
            var x = 0.0
            for (i, c) in cols.enumerated() {
                o.append(.rect(Box(x, y, widths[i], 14), stroke: .black, fill: .band, width: 0.5))
                o.append(.text(c.0, at: Pt(x + 4, y + 7), size: fs, bold: true)); x += widths[i]
            }
            y += 14
            for r in rows {
                let h = max(13, r.enumerated().map { i, cell in m.height(cell.0, width: widths[i] - 8, size: fs, bold: false) + 4 }.max() ?? 13)
                x = 0
                for (i, cell) in r.enumerated() {
                    o.append(.rect(Box(x, y, widths[i], h), stroke: .black, fill: nil, width: 0.5))
                    o.append(.textBox(cell.0, Box(x + 4, y + 2, widths[i] - 8, h - 2), size: fs, color: cell.1)); x += widths[i]
                }
                y += h
            }
            y += 7
        }
        let trs = j.transformers("trafos")
        // Vector group / %Z / condition come from the A3 wide page; the column shows only when some transformer has them
        func spec(_ t: Transformer) -> String {
            [t.vectorGroup, t.impedance.isEmpty ? "" : "\(t.impedance)%Z", t.condition].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let showSpec = trs.contains { !spec($0).isEmpty }
        let trRows: [[(String, RGBA)]] = trs.isEmpty ? [[("ยังไม่ระบุหม้อแปลง", .tag), ("", .black), ("", .black), ("", .black), ("", .black)]] :
            trs.enumerated().map { i, t in
                let n = Schema.transformerAngles.filter { j.photo("tr\(i)_\($0.key)") != nil }.count
                let mdb = t.mdb.enumerated().filter { !$0.element.isEmpty }.map { "MDB\($0.offset + 1) \($0.element) A" }.joined(separator: ", ")
                let feed = [j.text("tr\(i)_feed"), j.text("tr\(i)_feedLoc")].filter { !$0.isEmpty }.joined(separator: " · ")
                let row: [(String, RGBA)] = [("TR\(i + 1)", .black), ("\(t.kva.isEmpty ? "-" : t.kva) kVA", .black), (mdb.isEmpty ? "-" : mdb, .black),
                        (feed.isEmpty ? "ยังไม่ระบุ" : feed, feed.isEmpty ? .tag : .black), ("\(n)/6", n < 6 ? .tag : .black)]
                return showSpec ? row + [(spec(t).isEmpty ? "-" : spec(t), .black)] : row
            }
        table([("หม้อแปลง", 48), ("ขนาด", 58), ("ตู้ MDB (เบรกเกอร์)", 0), ("ตู้ MDB ปลายสาย", 130), ("ภาพ", 40)]
              + (showSpec ? [("Vector group / %Z / สภาพ", 120)] : []), trRows)
        let secs = job.sectionsByCategory.flatMap(\.sections)
        let secRows: [[(String, RGBA)]] = secs.isEmpty ? [[("-", .black), ("ยังไม่มีหัวข้อสำรวจ", .black), ("", .black), ("", .black)]] :
            secs.map { s in
                let c = s.module.completion
                let f = job.facts(s.module)
                return [(s.number, .black), (s.module.title, .black), (f.isEmpty ? "-" : f, .black), ("\(c.filled)/\(c.total)", c.filled < c.total ? .tag : .black)]
            }
        table([("รหัส", 40), ("หัวข้อ", 150), ("สาระสำคัญ", 0), ("ครบ", 40)], secRows)
        // remarks and gaps
        let miss = job.missingItems
        let missText = miss.isEmpty ? "ครบทุกรายการ ✓" : miss.prefix(8).joined(separator: "\n") + (miss.count > 8 ? "\n… และอีก \(miss.count - 8) รายการ" : "")
        let remarks = j.text("remarks").isEmpty ? "-" : j.text("remarks")
        let half = W * 0.52
        let bodyH = max(60, m.height(missText, width: W - half - 8, size: fs, bold: false) + 6, m.height(remarks, width: half - 8, size: fs, bold: false) + 6)
        let avail = Self.bodyH - y - 14
        let h = min(bodyH, max(40, avail))
        o.append(.rect(Box(0, y, half, 14), stroke: .black, fill: .band, width: 0.5)); o.append(.text("ความเห็น / เงื่อนไข", at: Pt(4, y + 7), size: fs, bold: true))
        o.append(.rect(Box(half, y, W - half, 14), stroke: .black, fill: .band, width: 0.5)); o.append(.text("ยังไม่กรอก / ยังไม่ครบ (\(miss.count))", at: Pt(half + 4, y + 7), size: fs, bold: true))
        y += 14
        o.append(.rect(Box(0, y, half, h), stroke: .black, fill: nil, width: 0.5)); o.append(.textBox(remarks, Box(4, y + 3, half - 8, h - 4), size: fs))
        o.append(.rect(Box(half, y, W - half, h), stroke: .black, fill: nil, width: 0.5))
        o.append(.textBox(missText, Box(half + 4, y + 3, W - half - 8, h - 4), size: fs, color: miss.isEmpty ? RGBA(hex: 0x2E7D32) : .tag))
        y += h
        return Unit(h: min(y, Self.bodyH), ops: o)
    }
}
