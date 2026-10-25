import Foundation
import TCRoofCore

/// The team template's `แผนโครงการ` sheet (docs/specs/project-plan-wbs.md): a header row with `WBS`, `กิจกรรม`,
/// `น้ำหนัก %` … under a row of groups (`Baseline (ล็อก)`, `จริง / นัด`, `คาดการณ์`) that tell its several `เริ่ม` /
/// `เสร็จ` columns apart. Columns are found by their header texts, as the plan sheet's are.
extension MPWorkbook {
    /// The header row (the row of the `WBS` cell) and the column of each heading the reader uses.
    struct WBSHeader {
        let row: Int
        let code: Int, title: Int
        var evidence, responsible, weight, predecessor, lag, days: Int?
        var baselineStart, baselineEnd, forecastStart, forecastEnd: Int?
        var status, note, level, approver: Int?
    }

    static func wbsHeader(_ s: Sheet) -> WBSHeader? {
        func clean(_ t: String) -> String { t.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let wbs = s.texts.filter({ clean($0.text) == "WBS" }).min(by: { ($0.row, $0.col) < ($1.row, $1.col) }) else { return nil }
        let row = wbs.row
        let heads = s.texts.filter { $0.row == row }.map { (col: $0.col, text: clean($0.text)) }
        let groups = s.texts.filter { $0.row == row - 1 }.map { (col: $0.col, text: clean($0.text)) }.sorted { $0.col < $1.col }
        func col(_ prefix: String) -> Int? { heads.filter { $0.text.hasPrefix(prefix) }.map(\.col).min() }
        /// A heading under a group: the group is the nearest group text at or left of the column.
        func col(_ prefix: String, under group: String) -> Int? {
            heads.filter { h in h.text.hasPrefix(prefix) && groups.last { $0.col <= h.col }?.text.hasPrefix(group) == true }.map(\.col).min()
        }
        guard let title = heads.filter({ $0.text == "กิจกรรม" && $0.col > wbs.col }).map(\.col).min(),
              col("น้ำหนัก") != nil else { return nil }
        var h = WBSHeader(row: row, code: wbs.col, title: title)
        h.evidence = col("หลักฐาน"); h.responsible = col("ผู้รับผิดชอบ"); h.weight = col("น้ำหนัก")
        h.predecessor = col("งานก่อนหน้า"); h.lag = col("รอ"); h.days = col("ระยะ")
        h.baselineStart = col("เริ่ม", under: "Baseline"); h.baselineEnd = col("เสร็จ", under: "Baseline")
        h.forecastStart = col("เริ่ม", under: "คาดการณ์"); h.forecastEnd = col("เสร็จ", under: "คาดการณ์")
        h.status = col("สถานะ"); h.note = col("มาตรฐาน"); h.level = col("ชั้น"); h.approver = col("อนุมัติ")
        return h
    }

    /// Every row under the header whose WBS cell is a code (`0`, `1.7.1`), in the sheet's order, down to the first
    /// text in that column that isn't one: the tables under it (installation points, the Inverter station's own
    /// breakdown) are other lists.
    static func wbs(_ s: Sheet, _ cal: Calendar) -> [MasterSchedule.WorkItem] {
        guard let h = wbsHeader(s) else { return [] }
        func text(_ col: Int?, _ r: Int) -> String? {
            guard let col, let t = s.text(col, r)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        func int(_ col: Int?, _ r: Int) -> Int? { col.flatMap { s.number($0, r) }.map { Int($0.rounded()) } }
        func date(_ col: Int?, _ r: Int) -> Date? { col.flatMap { s.date($0, r, cal) } }
        let rows = Set(s.texts.filter { $0.col == h.code && $0.row > h.row }.map(\.row))
            .union(s.numbers(col: h.code).filter { $0.row > h.row }.map(\.row)).sorted()
        var items: [MasterSchedule.WorkItem] = []
        for r in rows {
            // a code is text ("1.7.1"); a whole part number may be stored as a number (0, 1, 2)
            guard let code = text(h.code, r) ?? s.number(h.code, r).flatMap({ $0 == $0.rounded() ? String(Int($0)) : nil }) else { continue }
            guard code.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil else {
                if items.isEmpty { continue } else { break }
            }
            guard let title = text(h.title, r) else { continue }
            var item = MasterSchedule.WorkItem(code: code, title: title, weight: h.weight.flatMap { s.number($0, r) } ?? 0,
                                               level: int(h.level, r) ?? code.split(separator: ".").count - 1)
            item.evidence = text(h.evidence, r)
            item.responsible = text(h.responsible, r)
            item.predecessor = text(h.predecessor, r)
            item.lagDays = int(h.lag, r)
            item.days = int(h.days, r)
            item.baselineStart = date(h.baselineStart, r); item.baselineEnd = date(h.baselineEnd, r)
            item.forecastStart = date(h.forecastStart, r); item.forecastEnd = date(h.forecastEnd, r)
            item.status = text(h.status, r)
            item.note = text(h.note, r)
            item.approver = text(h.approver, r)
            items.append(item)
        }
        return items
    }
}
