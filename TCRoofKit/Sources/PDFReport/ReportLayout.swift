import Foundation
import TCRoofCore

/// Measures text; the UIKit renderer supplies real font metrics, tests use the estimate.
public protocol TextMeasuring: Sendable {
    func width(_ s: String, size: Double, bold: Bool) -> Double
    func height(_ s: String, width: Double, size: Double, bold: Bool) -> Double
}
public struct ApproxMeasure: TextMeasuring {
    public init() {}
    public func width(_ s: String, size: Double, bold: Bool) -> Double { ApproxText.width(s, size: size, bold: bold) }
    public func height(_ s: String, width: Double, size: Double, bold: Bool) -> Double { ApproxText.height(s, width: width, size: size, bold: bold) }
}

public struct ReportHeader: Sendable {
    public var company: String
    public var logo: Photo?
    public init(company: String = "", logo: Photo? = nil) { self.company = company; self.logo = logo }
}

/// The NO.215 report laid out on A4 pages as vector drawing operations.
public struct ReportLayout {
    public static let pageW = 595.28, pageH = 841.89
    static let margin = 30.0, footerH = 22.0
    static var cw: Double { pageW - 2 * margin }
    static var bodyH: Double { pageH - 2 * margin - footerH }

    public struct Page: Sendable { public var ops: [DrawOp] }
    struct Unit { var h: Double; var ops: [DrawOp]; var newPage = false }

    let job: Job
    let header: ReportHeader
    let m: TextMeasuring

    public init(job: Job, header: ReportHeader = ReportHeader(), measure: TextMeasuring = ApproxMeasure()) {
        self.job = job; self.header = header; self.m = measure
    }

    // MARK: pagination

    public func pages() -> [Page] {
        var units = [summary()]
        var cov = cover(); cov[0].newPage = true
        units += cov
        if let t = tree() { var u = t; u.newPage = true; units.append(u) }
        units += transformerPhotos()
        units += flood()
        var first = true
        // same order as the app's section list: B electrical, C roof & structure, D water works
        for mod in job.sectionsByCategory.flatMap({ $0.sections.map(\.module) }) {
            for (i, var u) in moduleUnits(mod).enumerated() {
                u.newPage = i == 0 && (first || [.roof, .tank, .sed, .house, .roofForm].contains(mod.type))
                units.append(u)
            }
            first = false
        }
        units.append(final())

        var pages: [[DrawOp]] = [[]], y = 0.0
        let gap = 10.0
        for u in units {
            if (u.newPage && y > 0) || (y > 0 && y + u.h > Self.bodyH) { pages.append([]); y = 0 }
            pages[pages.count - 1] += translate(u.ops, dx: Self.margin, dy: Self.margin + y)
            y += u.h + gap
        }
        let n = pages.count
        let title = "แบบสำรวจเพื่อออกแบบ (เบื้องต้น) · เลขที่ \(job.docNo.isEmpty ? "-" : job.docNo) · \(job.projectName)"
        return pages.enumerated().map { i, ops in
            let fy = Self.pageH - Self.margin - 6
            return Page(ops: ops + [
                .line(Pt(Self.margin, fy - 10), Pt(Self.pageW - Self.margin, fy - 10), width: 0.5, color: .faint),
                .text(title, at: Pt(Self.margin, fy), size: 7.5, color: .ink2),
                .text("หน้า \(i + 1) / \(n)", at: Pt(Self.pageW - Self.margin, fy), size: 7.5, color: .ink2, align: .right),
            ])
        }
    }

    func translate(_ ops: [DrawOp], dx: Double, dy: Double) -> [DrawOp] { Sketch(width: 0, height: 0, ops: ops).translated(dx, dy) }

    // MARK: building blocks

    var j: Values { job.values }
    static let band = 17.0

    /// Frame with a green title band; returns ops and the y where content starts.
    func box(_ title: String, height h: Double, width w: Double = cw, x: Double = 0, y: Double = 0, left: Bool = false) -> [DrawOp] {
        [.rect(Box(x, y, w, h), stroke: .black, fill: nil, width: 0.8),
         .rect(Box(x, y, w, Self.band), stroke: .black, fill: .band, width: 0.8),
         left ? .text(title, at: Pt(x + 6, y + Self.band / 2), size: 9, bold: true) : .text(title, at: Pt(x + w / 2, y + Self.band / 2), size: 9, bold: true, align: .center)]
    }
    /// "label ____value____" on one line; returns next x.
    func field(_ label: String, _ value: String, x: Double, y: Double, valueWidth: Double, ops: inout [DrawOp], size: Double = 8.5) -> Double {
        var cx = x
        if !label.isEmpty { ops.append(.text(label, at: Pt(cx, y), size: size)); cx += m.width(label, size: size, bold: false) + 4 }
        ops.append(.line(Pt(cx, y + size * 0.6), Pt(cx + valueWidth, y + size * 0.6), width: 0.5, color: .faint, dash: [1.5, 1.5]))
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty { ops.append(.text(v, at: Pt(cx + valueWidth / 2, y - 0.5), size: size, bold: true, color: .blue, align: .center)) }
        return cx + valueWidth + 8
    }
    /// Checkbox + label items flowing left to right; returns ops and the height used.
    func checks(_ options: [String], chosen: (String) -> Bool, extra: (String) -> String = { _ in "" }, x: Double, y: Double, width: Double, size: Double = 8.5) -> ([DrawOp], Double) {
        var ops: [DrawOp] = [], cx = x, cy = y
        let lh = size * 1.7
        for o in options {
            let label = o + (chosen(o) && !extra(o).isEmpty ? ": " + extra(o) : "")
            let w = size + 4 + m.width(label, size: size, bold: chosen(o)) + 10
            if cx > x && cx + w > x + width { cx = x; cy += lh }
            ops.append(.checkbox(Box(cx, cy + (lh - size) / 2, size, size), on: chosen(o)))
            ops.append(.text(label, at: Pt(cx + size + 4, cy + lh / 2), size: size, bold: chosen(o)))
            cx += w
        }
        return (ops, cy - y + lh)
    }
    func photoCell(_ p: Photo?, label: String?, x: Double, y: Double, w: Double, h: Double) -> [DrawOp] {
        var ops: [DrawOp] = []
        var top = y
        if let label, !label.isEmpty {
            ops.append(.textBox(label, Box(x + 4, y + 2, w - 8, 12), size: 7.5))
            ops.append(.line(Pt(x, y + 15), Pt(x + w, y + 15), width: 0.5, color: .black))
            top += 15
        }
        let area = Box(x, top, w, y + h - top).inset(4)
        if let p { ops.append(.photo(p, area)) }
        return ops
    }
    /// Photos two per row, up to four per box.
    func grid(_ title: String, _ items: [(Photo?, String?)], cellH: Double = 170, columns: Int = 2) -> [Unit] {
        let list = items.compactMap { p, c in p.map { ($0, c) } }
        guard !list.isEmpty else { return [] }
        let per = columns == 1 ? 1 : 4, pages = (list.count + per - 1) / per
        return stride(from: 0, to: list.count, by: per).map { i in
            let chunk = Array(list[i..<min(i + per, list.count)])
            let rows = (chunk.count + columns - 1) / columns
            let cellW = Self.cw / Double(columns), h = Self.band + Double(rows) * cellH
            var ops = box(title + (pages > 1 ? " (\(i / per + 1)/\(pages))" : ""), height: h)
            for (k, it) in chunk.enumerated() {
                let cx = Double(k % columns) * cellW, cy = Self.band + Double(k / columns) * cellH
                ops += photoCell(it.0, label: it.1, x: cx, y: cy, w: cellW, h: cellH)
                if k % columns > 0 { ops.append(.line(Pt(cx, cy), Pt(cx, cy + cellH), width: 0.5, color: .black)) }
                if k / columns > 0 && k % columns == 0 { ops.append(.line(Pt(0, cy), Pt(Self.cw, cy), width: 0.5, color: .black)) }
            }
            return Unit(h: h, ops: ops)
        }
    }

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

    /// Shapes, then symbols, over the site picture drawn in `pic`.
    func siteDrawing(in pic: Box) -> [DrawOp] {
        SiteShapes.ops(j.shapes(SiteShapes.key), in: pic, metersAcross: j.number(SiteShapes.scaleKey))
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
            let (ops, h) = checks(["ไม่เคย", "เคย"], chosen: { $0 == v }, x: labelW + 6, y: y + 1, width: valW - 12, size: 8); return (ops, h + 2)
        }
        for f in Schema.flood.fields where f.id != "floodHistory" && f.isVisible(j) {
            if case .photo = f.kind { continue }
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
        if Schema.flooded(j), let p = j.photo("floodPhoto") { units += grid("ภาพคราบระดับน้ำ / หลักฐานน้ำท่วม", [(p, nil)], cellH: 230, columns: 1) }
        return units
    }

    // MARK: sections

    func two(_ title: String, _ l: Photo?, _ lt: String, right r: Photo?, _ rt: String, detail: String? = nil,
             infoL: ((Double, inout [DrawOp]) -> Void)?, infoR: ((Double, inout [DrawOp]) -> Void)?, photoH: Double = 170, infoH: Double = 36) -> Unit {
        let W = Self.cw, half = W / 2, hasInfo = infoL != nil || infoR != nil
        let h = Self.band + photoH + (hasInfo ? infoH : 0)
        var o = box(title, height: h)
        o += photoCell(l, label: lt, x: 0, y: Self.band, w: half, h: photoH)
        if r != nil || detail == nil { o += photoCell(r, label: rt, x: half, y: Self.band, w: half, h: photoH) }
        else {
            o.append(.textBox(rt, Box(half + 4, Self.band + 2, half - 8, 12), size: 7.5))
            o.append(.line(Pt(half, Self.band + 15), Pt(W, Self.band + 15), width: 0.5, color: .black))
            o.append(.textBox(detail ?? "", Box(half + 6, Self.band + 20, half - 12, photoH - 24), size: 8.5, color: .blue))
        }
        o.append(.line(Pt(half, Self.band), Pt(half, h), width: 0.5, color: .black))
        if hasInfo {
            let y = Self.band + photoH
            o.append(.line(Pt(0, y), Pt(W, y), width: 0.5, color: .black))
            var a: [DrawOp] = [], b: [DrawOp] = []
            infoL?(y, &a); infoR?(y, &b)
            o += a; o += translate(b, dx: half, dy: 0)
        }
        return Unit(h: h, ops: o)
    }

    func moduleUnits(_ mod: SurveyModule) -> [Unit] {
        let d = mod.values, spec = mod.spec, half = Self.cw / 2
        let named = mod.name.isEmpty ? "" : " " + mod.name
        let ofBuilding = mod.name.isEmpty ? "" : " ของอาคาร" + mod.name
        let firstDetail = Fill.lines(d.text("detail")).first ?? ""
        let detailLine: (Double, inout [DrawOp]) -> Void = { y, o in _ = field("รายละเอียดเพิ่มเติม", firstDetail, x: 6, y: y + 12, valueWidth: half - 90, ops: &o) }
        switch mod.type {
        case .panel:
            return [two(spec.reportTitle + named, d.photo("photoBreaker"), "ภาพถ่ายเบรกเกอร์เมนของตู้ไฟฟ้า", right: d.photo("photoWide"), "ภาพถ่ายมุมกว้างของตู้ไฟฟ้า (เพื่อพิจารณาจุดเชื่อมต่อระบบโซล่าเซลล์)",
                        infoL: { y, o in
                            _ = field("ขนาดเบรกเกอร์เมน", d.text("breakerAT") + (d.text("breakerAT").isEmpty ? "" : " AT"), x: 6, y: y + 11, valueWidth: 90, ops: &o)
                            let nx = field("ปริมาณการใช้ไฟ (kW)", d.text("loadKW"), x: 6, y: y + 26, valueWidth: 60, ops: &o)
                            _ = field("เวลา", d.text("loadTime"), x: nx, y: y + 26, valueWidth: 50, ops: &o) },
                        infoR: detailLine)]
        case .inverter:
            let n = d.number("inverterCount")
            let need = n.map { "\(fmt($0)) เครื่อง → \(String(format: "%.2f", 1.5 * $0 + 1.5)) x 2.00 ม." } ?? ""
            return [two(spec.reportTitle + ofBuilding, d.photo("photoArea"), "ภาพถ่ายพื้นที่ติดตั้ง Inverter Station", right: d.photo("photoDetail"), "รายละเอียด", detail: d.text("detail"),
                        infoL: { y, o in
                            _ = field("ขนาดพื้นที่ติดตั้ง (ก x ย x ส)", d.text("sizeLWH"), x: 6, y: y + 11, valueWidth: 100, ops: &o)
                            o.append(.textBox("**ยาว = (1.5 x จำนวนอินเวอร์เตอร์) + 1.5 เมตร กว้าง 2 เมตร", Box(6, y + 19, half - 12, 14), size: 7)) },
                        infoR: { y, o in _ = field("พื้นที่ที่ต้องการ", need, x: 6, y: y + 11, valueWidth: half - 80, ops: &o)
                            if d.photo("photoDetail") != nil { o.append(.textBox(firstDetail, Box(6, y + 20, half - 12, 14), size: 8, color: .blue)) } })]
        case .water:
            return [two(spec.reportTitle + ofBuilding, d.photo("photoArea"), "ภาพถ่ายพื้นที่ติดตั้ง", right: d.photo("photoWide"), "ภาพถ่ายมุมกว้างของพื้นที่ติดตั้ง",
                        infoL: { y, o in o += checks(["ติดตั้งระบบน้ำใหม่", "ติดตั้งร่วมกับระบบน้ำเดิม"], chosen: { d.choice("waterMode") == $0 }, x: 6, y: y + 4, width: half - 12).0 },
                        infoR: detailLine)]
        case .backfeed:
            return [two(spec.reportTitle + ofBuilding, d.photo("photoArea"), "ภาพถ่ายพื้นที่ติดตั้ง", right: d.photo("photoDetail"), "รายละเอียด", detail: d.text("detail"),
                        infoL: { y, o in
                            o += checks(["กันย้อนที่แรงต่ำ", "กันย้อนที่แรงสูง"], chosen: { d.choice("level") == $0 }, x: 6, y: y + 2, width: half - 12).0
                            o += checks(["เสาเดิม", "เสาใหม่"], chosen: { d.choice("pole") == $0 }, x: 6, y: y + 18, width: half - 12).0 },
                        infoR: { y, o in _ = field("รายละเอียดเพิ่มเติม", d.photo("photoDetail") != nil ? firstDetail : "", x: 6, y: y + 12, valueWidth: half - 90, ops: &o) },
                        photoH: 240)]
        case .fts:
            return [two(spec.reportTitle + ofBuilding, d.photo("photoFTS"), "ภาพถ่ายพื้นที่ติดตั้งตู้ FTS", right: d.photo("photoEmg"), "ภาพถ่ายพื้นที่ติดตั้งปุ่ม Emergency",
                        infoL: d.text("detail").isEmpty ? nil : detailLine, infoR: nil, photoH: 150)]
        case .roof, .tank: return planSection(mod)
        case .sed: return sed(mod)
        case .house, .roofForm: return formSection(mod)
        }
    }

    func planSection(_ mod: SurveyModule) -> [Unit] {
        let d = mod.values, tank = mod.type == .tank, W = Self.cw
        let title = mod.spec.reportTitle + (mod.name.isEmpty ? "" : " " + mod.name)
        var U: [Unit] = []
        // plan
        var body: [DrawOp] = [], bh: Double
        if let p = d.photo("planPhoto") { bh = 260; body.append(.photo(p, Box(8, 0, W - 16, bh))) }
        else if let sk = Drawings.plan(d, tank: tank, width: 690) {
            let k = (W - 16) / sk.width; bh = sk.height * k
            body += sk.translated(8, 0, scale: k)
        } else { bh = 90; body.append(.text("— ยังไม่ได้กรอกระยะ —", at: Pt(W / 2, 45), size: 9, color: .faint, align: .center)) }
        let panelsH = 32.0, tankH = tank ? 36.0 : 0
        let h = Self.band + panelsH + bh + 10 + tankH
        var o = box(title, height: h)
        let pb = d.text("panelsBefore"), pc = d.text("panelsCut")
        o.append(.text("จำนวนแผงก่อนเข้าสำรวจ \(pb.isEmpty ? "-" : pb) แผง", at: Pt(W / 2, Self.band + 9), size: 9, bold: true, align: .center))
        o.append(.text("จำนวนแผงที่ตัดออกหลังสำรวจ \(pc.isEmpty ? "-" : pc) แผง", at: Pt(W / 2, Self.band + 23), size: 9, bold: true, align: .center))
        o += translate(body, dx: 0, dy: Self.band + panelsH)
        if tank {
            let y = h - tankH
            o.append(.line(Pt(0, y), Pt(W, y), width: 0.5, color: .black))
            var x = field("ความสูงของถังน้ำใส", d.text("tankHeight").isEmpty ? "" : d.text("tankHeight") + " M", x: 6, y: y + 10, valueWidth: 50, ops: &o)
            x = field("ผิวของถังน้ำใส", d.text("surface"), x: x, y: y + 10, valueWidth: 70, ops: &o)
            _ = field("กรณีมีดินกลบ ชั้นดินลึก", d.text("soilDepth").isEmpty ? "" : d.text("soilDepth") + " M", x: x, y: y + 10, valueWidth: 50, ops: &o)
            let ty = d.choice("tankType").map { $0 == "อื่นๆ" ? d.other("tankType") : $0 } ?? ""
            x = field("ชนิดถัง", ty, x: 6, y: y + 26, valueWidth: 50, ops: &o)
            x = field("ตำแหน่งถัง", d.choice("tankPos") ?? "", x: x, y: y + 26, valueWidth: 50, ops: &o)
            _ = field("เงาบัง", Schema.shadeText(d).map { $0 == "ไม่มีเงาบัง" ? "ไม่มี" : String($0.dropFirst("เงาบัง".count)).trimmingCharacters(in: CharacterSet(charactersIn: ": ")) } ?? "", x: x, y: y + 26, valueWidth: W - x - 60, ops: &o)
        }
        o.append(.text(tank ? "* ระบุตำแหน่งสิ่งกีดขวางบนถังน้ำใส เช่น ปล่องระบายอากาศ ช่องเซอร์วิส ท่อ เสาสัญญาณ" : "* ระบุตำแหน่งเสาและระยะสำหรับโครงสร้างหลังคา", at: Pt(0, h + 8), size: 7.5, color: .tag))
        U.append(Unit(h: h + 14, ops: o))

        if !tank {
            // structure: truss + component table + option rows
            let tableW = 250.0, rowH = 15.0, th = Self.band + 10 + rowH * 8 + 8
            var s = box("โครงสร้าง", height: th)
            s.append(.text("แนะนำองค์ประกอบของหลังคา", at: Pt(8, Self.band + 10), size: 7.5))
            let tr = Drawings.truss(width: W - tableW - 30)
            s += tr.translated(8, Self.band + 18)
            let tx = W - tableW - 8, ty = Self.band + 8
            let cols: [Double] = [22, 60, tableW - 82]
            for r in 0...7 {
                let y = ty + Double(r) * rowH
                var x = tx
                for (ci, cwid) in cols.enumerated() {
                    s.append(.rect(Box(x, y, cwid, rowH), stroke: .black, fill: r == 0 ? .band : nil, width: 0.5))
                    let txt: String
                    if r == 0 { txt = ["", "องค์ประกอบ", "รายละเอียด"][ci] }
                    else { let v = d.text("comp\(r)"); txt = [String(r), Options.components[r - 1], v.isEmpty ? "-" : v][ci] }
                    s.append(.textBox(txt, Box(x + 2, y + 2, cwid - 4, rowH - 2), size: 7.5, bold: ci == 2 && r > 0, align: .center))
                    x += cwid
                }
            }
            U.append(Unit(h: th, ops: s))
            var c: [DrawOp] = [], cy = 0.0
            for (label, id, opts) in [("**1.รูปแบบหลังคา", "roofShape", Options.roofShape), ("**2.วัสดุมุงหลังคา", "roofMaterial", Options.roofMaterial), ("**3.ชนิดโครงสร้างหลังคา", "roofStructure", Options.structure)] {
                c.append(.text(label, at: Pt(0, cy + 7), size: 8.5, bold: true))
                let (ops, hh) = checks(opts, chosen: { d.choice(id) == $0 }, extra: { $0 == "อื่นๆ" ? d.other(id) : "" }, x: 120, y: cy - 1.5, width: W - 120)
                c += ops; cy += hh
            }
            U.append(Unit(h: cy, ops: c))
            if let a = d.photo("aerialPhoto") { U += grid(title, [(a, nil)], cellH: 330, columns: 1) }
            U += grid("โครงสร้าง", d.photos("structPhotos").map { ($0, nil) })
            U += grid(title + " — ภาพเพิ่มเติม", d.photos("generalPhotos").map { ($0, nil) })
        } else {
            let ob = d.photos("obstPhotos"), list = d.obstacles("obst")
            let imgH = ob.isEmpty ? 90.0 : 250, tableH = list.isEmpty ? 0 : Double(list.count + 1) * 15 + 8
            let h2 = Self.band + 15 + imgH + tableH
            var s = box("สิ่งกีดขวาง", height: h2)
            s.append(.text("สำหรับวาดขนาดของสิ่งกีดขวาง", at: Pt(8, Self.band + 8), size: 8, bold: true))
            if let p = ob.first { s.append(.photo(p, Box(60, Self.band + 16, W - 120, imgH - 8))) }
            if !list.isEmpty {
                let cols: [Double] = [W - 16 - 240, 120, 120], y0 = Self.band + 15 + imgH
                for r in 0...list.count {
                    var x = 8.0
                    for (ci, cwid) in cols.enumerated() {
                        let y = y0 + Double(r) * 15
                        s.append(.rect(Box(x, y, cwid, 15), stroke: .black, fill: r == 0 ? .band : nil, width: 0.5))
                        let t: String
                        if r == 0 { t = ["สิ่งกีดขวาง", "ตำแหน่ง X, Y (ม.)", "ขนาด ก x ย (ม.)"][ci] }
                        else { let q = list[r - 1]; t = [q.label.isEmpty ? "-" : q.label, "\(q.x), \(q.y)", "\(q.w) x \(q.h)"][ci] }
                        s.append(.textBox(t, Box(x + 2, y + 2, cwid - 4, 13), size: 7.5, align: ci == 0 ? .left : .center))
                        x += cwid
                    }
                }
            }
            s.append(.text("รูปภาพเพิ่มเติม: *รูปมุมสูง/รูปโดรน  *รูปสิ่งกีดขวาง  *รูปข้างถัง (สำหรับทางเดินรางสายไฟ)", at: Pt(0, h2 + 9), size: 8))
            U.append(Unit(h: h2 + 16, ops: s))
            if let a = d.photo("aerialPhoto") { U += grid(title, [(a, nil)], cellH: 330, columns: 1) }
            U += grid("สิ่งกีดขวาง", ob.dropFirst().map { ($0, nil) })
            U += grid(title + " — รูปข้างถัง / รูปเพิ่มเติม", d.photos("sidePhotos").map { ($0, nil) })
        }
        return U
    }

    func sed(_ mod: SurveyModule) -> [Unit] {
        let d = mod.values, W = Self.cw, named = mod.name.isEmpty ? "" : " " + mod.name
        let title = mod.spec.reportTitle + named
        var U = grid("ภาพบ่อตกตะกอน (Google Earth/Google Map)" + named, d.photos("sitePhotos").map { ($0, nil) })
        let rowH = 15.0, imgH = 270.0, h = Self.band + imgH + rowH * 7 + 6
        var o = box("โครงสร้างบ่อตกตะกอน" + named, height: h)
        if let p = d.photo("drawing") { o.append(.photo(p, Box(8, Self.band + 6, W - 16, imgH - 12))) }
        let cols: [Double] = [30, W / 2 - 90, 60, 30, W / 2 - 90, 60], y0 = Self.band + imgH
        for r in 0...6 {
            var x = 0.0
            for (ci, cwid) in cols.enumerated() {
                let y = y0 + Double(r) * rowH
                o.append(.rect(Box(x, y, cwid, rowH), stroke: .black, fill: r == 0 ? .band : nil, width: 0.5))
                var t = ""
                if r == 0 { t = ["ระยะ", "องค์ประกอบ", "ซม.", "ระยะ", "องค์ประกอบ", "ซม."][ci] }
                else if let dim = Options.sedDims[safe: (ci < 3 ? r - 1 : r + 5)] { t = [dim.0, dim.1, d.text("dist" + dim.0)][ci % 3] }
                o.append(.textBox(t, Box(x + 2, y + 2, cwid - 4, rowH - 2), size: 7.5, bold: ci % 3 == 2 && r > 0, align: ci % 3 == 1 ? .left : .center))
                x += cwid
            }
        }
        U.append(Unit(h: h, ops: o))
        U += grid(title + " — ภาพถ่ายมุมสูง", [(d.photo("aerialPhoto"), nil)], cellH: 330, columns: 1)
        U += grid(title + " — ภาพถ่ายแต่ละด้าน", [(d.photo("pFront"), "ด้านหน้า"), (d.photo("pBack"), "ด้านหลัง"), (d.photo("pLeft"), "ด้านซ้าย"), (d.photo("pRight"), "ด้านขวา")])
        U += grid("ภาพถ่ายสิ่งกีดขวางหรือบริเวณที่ไม่สามารถติดตั้งระบบได้", [(d.photo("obstPhoto"), nil)])
        return U
    }

    /// House / roof-form sections: numbered question tables like the paper form, then all photos.
    func formSection(_ mod: SurveyModule) -> [Unit] {
        let d = mod.values, W = Self.cw, labelW = 190.0, unitW = 44.0, valW = W - labelW - unitW
        var U: [Unit] = [], photos: [(Photo?, String?)] = []
        for g in mod.spec.groups {
            for f in g.fields { if case .photo = f.kind, let p = d.photo(f.id) { photos.append((p, (g.no.map { "ข้อ \($0) · " } ?? "") + f.label)) } }
            let rows = g.fields.filter { f in
                guard f.countable, f.isVisible(d) else { return false }
                switch f.kind { case .photo, .photos, .signature: return false; default: return true }
            }
            if rows.isEmpty { continue }
            var o: [DrawOp] = [], y = Self.band
            for f in rows {
                var cell: [DrawOp] = [], rh: Double
                var unit = ""
                switch f.kind {
                case .choice(let opts, _):
                    let (ops, hh) = checks(opts, chosen: { d.choice(f.id) == $0 }, extra: { $0 == "อื่นๆ" ? d.other(f.id) : "" }, x: labelW + 6, y: y + 1, width: valW - 12, size: 8)
                    cell = ops; rh = hh + 2
                case .number(let u):
                    unit = u; rh = 17
                    cell = [.text(d.text(f.id).isEmpty ? "—" : d.text(f.id), at: Pt(labelW + 6, y + 8.5), size: 8.5, bold: true, color: d.text(f.id).isEmpty ? .faint : .blue)]
                default:
                    let t = f.displayText(d)
                    rh = max(17, m.height(t.isEmpty ? "—" : t, width: valW - 12, size: 8.5, bold: true) + 5)
                    cell = [.textBox(t.isEmpty ? "—" : t, Box(labelW + 6, y + 3, valW - 12, rh - 4), size: 8.5, bold: true, color: t.isEmpty ? .faint : .blue)]
                }
                let lh = m.height(f.label, width: labelW - 10, size: 8, bold: false) + 5
                rh = max(rh, lh)
                o.append(.rect(Box(0, y, labelW, rh), stroke: .black, fill: RGBA(hex: 0xF4F8F1), width: 0.5))
                o.append(.rect(Box(labelW, y, valW, rh), stroke: .black, fill: nil, width: 0.5))
                o.append(.rect(Box(labelW + valW, y, unitW, rh), stroke: .black, fill: nil, width: 0.5))
                o.append(.textBox(f.label, Box(5, y + 3, labelW - 10, rh - 4), size: 8))
                o += cell
                o.append(.text(unit, at: Pt(labelW + valW + unitW / 2, y + rh / 2), size: 8, align: .center))
                y += rh
            }
            let title = (g.no.map { $0 + ". " } ?? "") + (g.title ?? "") + (mod.name.isEmpty ? "" : " — " + mod.name)
            U.append(Unit(h: y, ops: box(title, height: y, left: true) + o))
        }
        if mod.type == .house, let n = d.number("inverterCount"), n > 0 {
            U.append(Unit(h: 12, ops: [.text("ข้อ 18: อินเวอร์เตอร์ \(fmt(n)) เครื่อง ต้องการพื้นที่ยาว \(String(format: "%.2f", 1.5 * n + 1.5)) ม. กว้าง 2.00 ม.", at: Pt(0, 6), size: 8, color: .tag)]))
        }
        U += grid("ภาพถ่ายประกอบ — " + mod.spec.reportTitle + (mod.name.isEmpty ? "" : " " + mod.name), photos)
        return U
    }

    // MARK: summary and signatures

    func final() -> Unit {
        let W = Self.cw
        let remarks = j.text("remarks")
        let remH = max(40, m.height(remarks.isEmpty ? "—" : remarks, width: W - 16, size: 9, bold: false) + 12)
        let signH = 110.0, verdictH = 28.0
        let h = Self.band + verdictH + remH + signH
        var o = box("สรุปผลการสำรวจ", height: h)
        o.append(.text("ผลการประเมินความเหมาะสมในการติดตั้ง", at: Pt(8, Self.band + verdictH / 2), size: 9))
        if let v = j.choice("verdict") {
            let color: RGBA = v == "ติดตั้งได้" ? RGBA(hex: 0x2E7D32) : v.contains("เงื่อนไข") ? RGBA(hex: 0xB26A00) : .tag
            let tw = m.width(v, size: 10, bold: true) + 20
            o.append(.rect(Box(200, Self.band + 5, tw, verdictH - 10), stroke: color, fill: nil, width: 1.5))
            o.append(.text(v, at: Pt(200 + tw / 2, Self.band + verdictH / 2), size: 10, bold: true, color: color, align: .center))
        } else { o.append(.text("— ยังไม่ประเมิน —", at: Pt(200, Self.band + verdictH / 2), size: 9, color: .faint)) }
        var y = Self.band + verdictH
        o.append(.line(Pt(0, y), Pt(W, y), width: 0.5, color: .black))
        o.append(.textBox(remarks.isEmpty ? "ความเห็น / เงื่อนไข: —" : remarks, Box(8, y + 6, W - 16, remH - 8), size: 9, color: remarks.isEmpty ? .faint : .black))
        y += remH
        o.append(.line(Pt(0, y), Pt(W, y), width: 0.5, color: .black))
        let cols: [(String, Photo?, String)] = [("วิศวกรผู้สำรวจ", j.photo("surveyorSign"), j.text("engineer")), ("ผู้ตรวจสอบ", nil, j.text("reviewer")),
                                                ("ผู้ประสานงาน / เจ้าของสถานที่", j.photo("customerSign"), j.text("customerName"))]
        let cwid = W / 3, date = ISODate.thai(j.text("date"))
        for (i, c) in cols.enumerated() {
            let x = Double(i) * cwid
            if i > 0 { o.append(.line(Pt(x, y), Pt(x, h), width: 0.5, color: .black)) }
            o.append(.text(c.0, at: Pt(x + cwid / 2, y + 10), size: 8, color: .ink2, align: .center))
            if let s = c.1 { o.append(.photo(s, Box(x + 10, y + 18, cwid - 20, 50))) }
            o.append(.text("( \(c.2.isEmpty ? "...................................." : c.2) )", at: Pt(x + cwid / 2, y + 80), size: 8.5, align: .center))
            o.append(.text("วันที่ \(date.isEmpty ? "......../......../........" : date)", at: Pt(x + cwid / 2, y + 96), size: 7.5, align: .center))
        }
        return Unit(h: h, ops: o)
    }
}

enum Fill {
    static func lines(_ t: String) -> [String] { t.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

