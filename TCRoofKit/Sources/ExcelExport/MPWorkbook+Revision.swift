import Foundation
import TCRoofCore

/// The `แผนโครงการ` sheet's baseline box (CHA-79): `Baseline แผนนี้` over `ฉบับ | REV 00 … | อนุมัติโดย | … | วันที่ | …`.
/// Export writes the plan's current revision there, once it was re-planned in the app; each cell is found by its own
/// label, and one the file lacks, or that holds a formula, is left as it is.
extension MPWorkbook {
    struct RevisionCells {
        /// `REV 00 (จากกำหนดรอบ), ยังไม่อนุมัติ` under `Baseline แผนนี้`.
        var summary: (col: Int, row: Int)?
        var number: (col: Int, row: Int)?
        var approver: (col: Int, row: Int)?
        var date: (col: Int, row: Int)?
    }

    static func revisionCells(_ s: Sheet) -> RevisionCells {
        var cells = RevisionCells()
        let top = s.texts.filter { $0.row <= 6 }
        func label(_ t: String, row: Int? = nil) -> (col: Int, row: Int)? {
            top.filter { $0.text.trimmingCharacters(in: .whitespaces) == t && (row == nil || $0.row == row) }
                .min { ($0.row, $0.col) < ($1.row, $1.col) }.map { ($0.col, $0.row) }
        }
        // the value sits right of its label, in a cell the sheet has (a merged, formatted box)
        func right(_ at: (col: Int, row: Int)?) -> (col: Int, row: Int)? {
            at.flatMap { s.cell(Sheet.ref($0.col + 1, $0.row)) != nil ? ($0.col + 1, $0.row) : nil }
        }
        guard let issue = label("ฉบับ") else { return cells }
        cells.number = right(issue)
        cells.approver = right(label("อนุมัติโดย", row: issue.row))
        cells.date = right(label("วันที่", row: issue.row))
        if let above = top.first(where: { $0.col == issue.col && $0.row == issue.row - 1 && $0.text.hasPrefix("REV") }) {
            cells.summary = (above.col, above.row)
        }
        return cells
    }

    /// Writes `revision` into the box: `REV 02 (CR-014)`, the approver's name, the approval day and `REV 02, อนุมัติแล้ว`.
    /// Returns how many cells changed.
    static func writeRevision(_ revision: MasterSchedule.Revision, approver: String?, into s: inout Sheet,
                              calendar cal: Calendar) -> Int {
        let cells = revisionCells(s)
        var n = 0
        func put(_ at: (col: Int, row: Int)?, _ value: SheetCells.Value) {
            guard let at, let cell = s.cell(Sheet.ref(at.col, at.row)), !cell.formula else { return }
            let same: Bool = switch value {
            case .inline(let t): s.text(at.col, at.row) == t
            case .number(let v): cell.number.map { abs($0 - v) < 1e-9 } ?? false
            default: false
            }
            guard !same else { return }
            s.cells.set(Sheet.ref(at.col, at.row), value)
            n += 1
        }
        put(cells.number, .inline(revision.label + (revision.changeRequest.map { " (\($0))" } ?? "")))
        if let who = approver ?? revision.by { put(cells.approver, .inline(who)) }
        if let at = revision.at { put(cells.date, .number(Sheet.serial(cal.startOfDay(for: at), cal))) }
        put(cells.summary, .inline(revision.label + ", อนุมัติแล้ว"))
        return n
    }
}
