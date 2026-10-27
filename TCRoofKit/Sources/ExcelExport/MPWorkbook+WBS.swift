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
        /// `เสร็จ / นัด` under `จริง / นัด` and `เสร็จ (Y · S)`: where a tick goes (docs/specs/project-plan-wbs.md, step 3).
        var doneDate, doneMark: Int?
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
        h.doneDate = col("เสร็จ", under: "จริง"); h.doneMark = col("เสร็จ (Y")
        return h
    }

    /// Every row under the header whose WBS cell is a code (`0`, `1.7.1`), in the sheet's order, down to the first
    /// text in that column that isn't one. Of the tables under it, the Inverter station's steps (`2.5.1.1`…, each a
    /// % of 2.5.1) join the list after their row (`stationSteps`); the installation points are the template's own
    /// figures, which the survey holds for a real station, and are left out.
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
        var tail: [Int] = []
        for (k, r) in rows.enumerated() {
            // a code is text ("1.7.1"); a whole part number may be stored as a number (0, 1, 2)
            guard let code = text(h.code, r) ?? s.number(h.code, r).flatMap({ $0 == $0.rounded() ? String(Int($0)) : nil }) else { continue }
            guard code.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil else {
                if items.isEmpty { continue } else { tail = Array(rows[k...]); break }
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
        // the tables' lines without a code (the station's `รูปแบบ`) count too
        let below = tail.first.map { first in Set(s.texts.map(\.row)).filter { $0 >= first }.union(tail).sorted() } ?? []
        return stationSteps(s, h, rows: below, into: items)
    }

    /// Every row with a WBS code in its first column, the station table's steps included.
    static func codeRows(_ s: Sheet, _ h: WBSHeader) -> [(code: String, row: Int)] {
        s.texts(col: h.code).filter { $0.row > h.row }.compactMap { r in
            let code = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return code.range(of: #"^\d+(\.\d+)+$"#, options: .regularExpression) != nil ? (code, r.row) : nil
        }
    }

    /// The first row under the header whose WBS cell is text but not a code (`Inverter station (งาน 2.5.1)`): the list
    /// ends there, and the tables under it begin. `Int.max` for a sheet with nothing under the list.
    static func listEnd(_ s: Sheet, _ h: WBSHeader) -> Int {
        s.texts(col: h.code).first { $0.row > h.row
            && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) == nil
        }?.row ?? .max
    }

    /// The Inverter station table's own `เสร็จ (Y)` column (its header row starts `ขั้นงาน`): its steps' ticks sit
    /// there, not in the list's `เสร็จ (Y · S)`. Nil for a sheet without the table.
    static func stationMark(_ s: Sheet, _ h: WBSHeader) -> (row: Int, col: Int)? {
        func clean(_ t: String) -> String { t.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let head = s.texts.filter({ $0.row > h.row && clean($0.text).hasPrefix("ขั้นงาน") }).min(by: { $0.row < $1.row }),
              let mark = s.texts.first(where: { $0.row == head.row && clean($0.text).hasPrefix("เสร็จ (Y") }) else { return nil }
        return (head.row, mark.col)
    }

    /// Where a row's tick goes: the list's `เสร็จ (Y · S)` with its `เสร็จ` date, or for a step of the Inverter station
    /// table (`2.5.1.1`) that table's own `เสร็จ (Y)`, which has no date. A table further down whose rows also start
    /// with a code (P4-001's drawings per task) has no ticks.
    static func tickCells(_ s: Sheet, _ h: WBSHeader) -> [(code: String, row: Int, mark: Int, date: Int?)] {
        let station = stationMark(s, h)
        return codeRows(s, h).compactMap { r in
            if let station, r.row > station.row {
                return r.code.split(separator: ".").count >= 4 ? (r.code, r.row, station.col, nil) : nil
            }
            return h.doneMark.map { (r.code, r.row, $0, h.doneDate) }
        }
    }

    /// The rows the sheet marks done: `Y` in `เสร็จ (Y · S)` (or the Inverter station table's `เสร็จ (Y)`), with the
    /// `เสร็จ` date where there is one.
    static func wbsDone(_ s: Sheet, _ h: WBSHeader, _ cal: Calendar) -> (codes: Set<String>, dates: [String: Date]) {
        var codes = Set<String>(), dates: [String: Date] = [:]
        for r in tickCells(s, h) where s.text(r.mark, r.row)?.trimmingCharacters(in: .whitespaces).uppercased() == "Y" {
            codes.insert(r.code)
            if let col = r.date, let d = s.date(col, r.row, cal) { dates[r.code] = d }
        }
        return (codes, dates)
    }

    /// The Inverter station table under the list: its `รูปแบบ` line (the station's type and size) goes into its row's
    /// note, and each step (`2.5.1.1`, `% ของ 2.5.1` in the weight column) follows that row, weighing its share of it.
    static func stationSteps(_ s: Sheet, _ h: WBSHeader, rows: [Int], into items: [MasterSchedule.WorkItem]) -> [MasterSchedule.WorkItem] {
        func text(_ col: Int, _ r: Int) -> String? {
            guard let t = s.text(col, r)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        var out = items
        var style: String?
        var steps: [String: [MasterSchedule.WorkItem]] = [:]
        for r in rows {
            if let t = text(h.title, r), t.hasPrefix("รูปแบบ") {
                let rest = s.texts.filter { $0.row == r && $0.col > h.title }.sorted { $0.col < $1.col }
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !rest.isEmpty { style = rest.joined(separator: " · ") }
                continue
            }
            guard let code = text(h.code, r), code.range(of: #"^\d+(\.\d+){3,}$"#, options: .regularExpression) != nil,
                  let dot = code.lastIndex(of: "."), let parent = out.first(where: { $0.code == String(code[..<dot]) }),
                  let title = text(h.title, r), let share = h.weight.flatMap({ s.number($0, r) }) else { continue }
            var step = MasterSchedule.WorkItem(code: code, title: title, weight: parent.weight * share / 100, level: parent.level + 1)
            let pct = share == share.rounded() ? String(Int(share)) : String(format: "%.1f", share)
            step.note = "\(pct)% ของ \(parent.code)"
            step.responsible = parent.responsible
            steps[parent.code, default: []].append(step)
        }
        for (parent, list) in steps {
            guard let i = out.firstIndex(where: { $0.code == parent }) else { continue }
            if let style { out[i].note = [out[i].note, "รูปแบบ: " + style].compactMap { $0 }.joined(separator: " | ") }
            out.insert(contentsOf: list, at: i + 1)
        }
        return out
    }
}
