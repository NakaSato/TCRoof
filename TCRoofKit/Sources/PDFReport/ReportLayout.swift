import Foundation
import TCRoofCore

/// Measures text; the UIKit renderer supplies real font metrics, tests use the estimate.
public protocol TextMeasuring: Sendable {
    func width(_ s: String, size: Double, bold: Bool) -> Double
    func height(_ s: String, width: Double, size: Double, bold: Bool) -> Double
    /// The width of a mixed-font line (`DrawOp.runs`).
    func width(_ runs: [TextRun]) -> Double
}

public extension TextMeasuring {
    /// Each run as if it were Sarabun, when the measure has no other fonts.
    func width(_ runs: [TextRun]) -> Double { runs.reduce(0) { $0 + width($1.text, size: $1.size, bold: $1.bold) } }
}
public struct ApproxMeasure: TextMeasuring {
    public init() {}
    public func width(_ s: String, size: Double, bold: Bool) -> Double { ApproxText.width(s, size: size, bold: bold) }
    public func height(_ s: String, width: Double, size: Double, bold: Bool) -> Double { ApproxText.height(s, width: width, size: size, bold: bold) }
}

public struct ReportHeader: Sendable {
    public var company: String
    public var logo: Photo?
    /// Print each camera photo's position, direction and time under it (`Photo.stampLine`).
    public var photoStamps: Bool
    /// Changes from the previous issued REV (`FormDiff`), for the รายการแก้ไข page; the caller reads the snapshots.
    public var changes: [FieldChange]
    public init(company: String = "", logo: Photo? = nil, photoStamps: Bool = false, changes: [FieldChange] = []) {
        self.company = company; self.logo = logo; self.photoStamps = photoStamps; self.changes = changes
    }
}

/// The NO.215 report laid out on A4 pages as vector drawing operations.
public struct ReportLayout {
    public static let pageW = 595.28, pageH = 841.89
    static let margin = 30.0, footerH = 22.0
    static var cw: Double { pageW - 2 * margin }
    static var bodyH: Double { pageH - 2 * margin - footerH }

    public struct Page: Sendable {
        public var ops: [DrawOp]
        /// A4 portrait unless the page says otherwise (the single line diagram is A3 landscape).
        public var width = ReportLayout.pageW
        public var height = ReportLayout.pageH
    }
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
        units += revisionUnits()
        if let t = tree() { var u = t; u.newPage = true; units.append(u) }
        units += transformerPhotos()
        let a3End = units.count
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
        // page holding the last A3 unit: the single line diagram follows it
        var sldAfter = 0
        for (ui, u) in units.enumerated() {
            if (u.newPage && y > 0) || (y > 0 && y + u.h > Self.bodyH) { pages.append([]); y = 0 }
            pages[pages.count - 1] += translate(u.ops, dx: Self.margin, dy: Self.margin + y)
            y += u.h + gap
            if ui == a3End - 1 { sldAfter = pages.count - 1 }
        }
        let n = pages.count
        let title = "แบบสำรวจเพื่อออกแบบ (เบื้องต้น) | เลขที่ \(job.docNo.isEmpty ? "-" : job.docNo) | \(job.projectName)"
        var result: [Page] = pages.enumerated().map { i, ops in
            let fy = Self.pageH - Self.margin - 6
            return Page(ops: ops + [
                .line(Pt(Self.margin, fy - 10), Pt(Self.pageW - Self.margin, fy - 10), width: 0.5, color: .faint),
                .text(title, at: Pt(Self.margin, fy), size: 7.5, color: .ink2),
                .text("หน้า \(i + 1) / \(n)", at: Pt(Self.pageW - Self.margin, fy), size: 7.5, color: .ink2, align: .right),
            ])
        }
        // "แนบในรายงาน": the A3 diagram goes in after the A3 electrical pages; the A4 pages keep their own numbering
        if Self.attachesSingleLine(job) { result.insert(singleLinePage(), at: min(sldAfter + 1, result.count)) }
        return result
    }

    /// `sldAttach` (optional answer, "1") — the single line diagram is added to the report.
    public static func attachesSingleLine(_ job: Job) -> Bool { job.values.text("sldAttach") == "1" }

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
        var area = Box(x, top, w, y + h - top).inset(4)
        if let p, header.photoStamps, let line = p.stampLine {
            area.h -= 11
            ops.append(.text(line, at: Pt(x + w / 2, area.maxY + 6), size: 6.5, color: .ink2, align: .center))
        }
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

