import Foundation
import TCRoofCore

/// รายการแก้ไข after the cover from REV 01 on, and the check code in the footer of a locked job
/// (docs/specs/review-lock-revisions-swift.md §3.5).
extension ReportLayout {
    /// "REV 01 · รหัสตรวจสอบ A1B2-C3D4", left of the page number, once the job is locked.
    func revisionFooter(y: Double) -> [DrawOp] {
        guard let lock = job.lock else { return [] }
        let right = Self.pageW - Self.margin - m.width("หน้า 00 / 00", size: 7.5, bold: false) - 14
        return [.text("REV \(lock.rev) · รหัสตรวจสอบ \(FormHash.short(lock.hash))", at: Pt(right, y), size: 7.5, bold: true, color: .ink2, align: .right)]
    }

    /// One row of the revision table: every issued REV, then the current draft when it isn't issued yet.
    struct RevisionRow { let rev, date, by, reason, code: String }
    var revisionRows: [RevisionRow] {
        let issued = (job.revisions ?? []).map {
            RevisionRow(rev: $0.rev, date: ISODate.thai(ISODate.string($0.issuedAt)), by: $0.issuedBy, reason: $0.reason.isEmpty ? "ออกครั้งแรก" : $0.reason,
                        code: $0.shortCode)
        }
        guard !issued.contains(where: { $0.rev == job.rev }) else { return issued }
        return issued + [RevisionRow(rev: job.rev, date: ISODate.thai(j.text("date")), by: j.text("engineer"), reason: job.pendingReason ?? "",
                                     code: "ยังไม่ออก")]
    }

    func revisionUnits() -> [Unit] {
        guard job.rev != "00" else { return [] }
        let W = Self.cw, rowH = 16.0
        // the revision table
        let cols: [(String, Double)] = [("REV", 40), ("วันที่", 70), ("ผู้แก้ไข", 110), ("เหตุผล", W - 40 - 70 - 110 - 90), ("รหัสตรวจสอบ", 90)]
        let rows = revisionRows
        let tableH = Self.band + rowH * Double(rows.count + 1)
        var o = box("รายการแก้ไข (REV \(job.rev))", height: tableH)
        func cells(_ values: [String], y: Double, bold: Bool) {
            var x = 0.0
            for (i, c) in cols.enumerated() {
                if i > 0 { o.append(.line(Pt(x, y), Pt(x, y + rowH), width: 0.5, color: .black)) }
                o.append(.textBox(values[i], Box(x + 4, y + 3, c.1 - 8, rowH - 4), size: 7.5, bold: bold))
                x += c.1
            }
            o.append(.line(Pt(0, y + rowH), Pt(W, y + rowH), width: 0.5, color: .black))
        }
        cells(cols.map(\.0), y: Self.band, bold: true)
        for (i, r) in rows.enumerated() { cells([r.rev, r.date, r.by, r.reason, r.code], y: Self.band + rowH * Double(i + 1), bold: false) }
        var units = [Unit(h: tableH, ops: o, newPage: true)]

        // changes since the previous REV, a page-sized chunk per unit with the column titles repeated
        let from = job.previousRevision?.rev ?? "00"
        let list = header.changes
        let changeCols: [(String, Double)] = [("หัวข้อ", 130), ("รายการ", 150), ("เดิม", (W - 280) / 2), ("ใหม่", (W - 280) / 2)]
        func height(_ c: FieldChange) -> Double {
            if c.isPhoto { return 68 }
            let tw = changeCols[2].1 - 8
            return max(rowH, max(m.height(c.old, width: tw, size: 7.5, bold: false), m.height(c.new, width: tw, size: 7.5, bold: false),
                                 m.height(c.field, width: changeCols[1].1 - 8, size: 7.5, bold: false)) + 6)
        }
        let title = "รายการที่แก้จาก REV \(from)"
        guard !list.isEmpty else {
            var e = box(title, height: Self.band + 24)
            e.append(.text("ไม่มีรายการแก้ไข", at: Pt(8, Self.band + 12), size: 8.5, color: .ink2))
            return units + [Unit(h: Self.band + 24, ops: e)]
        }
        var start = 0
        while start < list.count {
            var h = Self.band + rowH, end = start
            while end < list.count && (end == start || h + height(list[end]) <= Self.bodyH - 30) { h += height(list[end]); end += 1 }
            var u = box(start == 0 ? title : title + " (ต่อ)", height: h)
            var y = Self.band
            func header() {
                var x = 0.0
                for (i, c) in changeCols.enumerated() {
                    if i > 0 { u.append(.line(Pt(x, y), Pt(x, y + rowH), width: 0.5, color: .black)) }
                    u.append(.text(c.0, at: Pt(x + 4, y + rowH / 2), size: 7.5, bold: true))
                    x += c.1
                }
                y += rowH
                u.append(.line(Pt(0, y), Pt(W, y), width: 0.5, color: .black))
            }
            header()
            for c in list[start..<end] {
                let rh = height(c)
                var x = 0.0
                for (i, col) in changeCols.enumerated() {
                    if i > 0 { u.append(.line(Pt(x, y), Pt(x, y + rh), width: 0.5, color: .black)) }
                    let cell = Box(x + 4, y + 3, col.1 - 8, rh - 6)
                    switch i {
                    case 0: u.append(.textBox(c.group, cell, size: 7.5))
                    case 1: u.append(.textBox(c.field, cell, size: 7.5))
                    case 2:
                        if let p = c.oldPhoto { u.append(.photo(p, Box(x + 4, y + 4, 60, 60))) }
                        else { u.append(.textBox(c.old, cell, size: 7.5, color: .tag)) }
                    default:
                        if let p = c.newPhoto { u.append(.photo(p, Box(x + 4, y + 4, 60, 60))) }
                        else { u.append(.textBox(c.new, cell, size: 7.5, bold: true, color: RGBA(hex: 0x2E7D32))) }
                    }
                    x += col.1
                }
                y += rh
                u.append(.line(Pt(0, y), Pt(W, y), width: 0.5, color: .black))
            }
            units.append(Unit(h: h, ops: u))
            start = end
        }
        return units
    }
}
