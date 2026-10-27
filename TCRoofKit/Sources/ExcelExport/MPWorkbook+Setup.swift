import Foundation
import TCRoofCore

/// The project facts of a station's plan file (`ProjectSetup`): the `แผนโครงการ` sheet's title and set-up lines, its
/// installation points table and Inverter station type, and the plan sheet's `PROJECT`, `OWNER` and `รหัส` lines.
/// Each is found by its own words, as the plan's columns are.
extension MPWorkbook {
    /// Where the two lines sit on the `แผนโครงการ` sheet.
    struct SetupCells {
        var title: (col: Int, row: Int)?
        var line: (col: Int, row: Int)?
    }

    /// The title (`แผนโครงการ …`) and the set-up line (the first text near the top with three of its parts).
    static func setupCells(_ s: Sheet) -> SetupCells {
        let top = s.texts.filter { $0.row <= 6 }.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
        var cells = SetupCells()
        if let t = top.first(where: { $0.text.trimmingCharacters(in: .whitespaces).hasPrefix("แผนโครงการ ") }) { cells.title = (t.col, t.row) }
        if let l = top.first(where: { ProjectSetup.isSetupLine($0.text) }) { cells.line = (l.col, l.row) }
        return cells
    }

    static func setup(_ book: Book) -> ProjectSetup {
        var s = ProjectSetup()
        if let detail = book.detail {
            let cells = setupCells(detail)
            s = .parse(title: cells.title.flatMap { detail.text($0.col, $0.row) },
                       line: cells.line.flatMap { detail.text($0.col, $0.row) })
            s.points = points(detail)
            if let station = inverterStation(detail) { s.inverterStation = station.type; s.inverterStationDetail = station.detail }
        }
        // the plan sheet's lines fill what the detail sheet didn't give (an older Master Plan Weekly has only these)
        if let code = book.layout.code { s.readCodeLine(code) }
        if let project = book.layout.project {
            let p = station(project: project, fileName: "")
            if s.stationName == nil, let name = p.name, !name.isEmpty { s.stationName = name }
            if s.kWp == nil { s.kWp = p.kWp }
        }
        if let owner = book.layout.owner, !owner.isEmpty { s.owner = owner }
        return s
    }

    /// Writes the job's facts into the file's lines, each only where it says something else: the `แผนโครงการ` title
    /// and set-up line (`ProjectSetup.rewrite`), and the plan sheet's `PROJECT` (station and kWp) and `รหัส` (code,
    /// subcontractor, engineer) lines. Returns how many cells changed in each sheet.
    static func writeSetup(_ setup: ProjectSetup, plan: inout Sheet, layout: Layout, detail: inout Sheet?) -> (plan: Int, detail: Int) {
        var planChanged = 0, detailChanged = 0
        func put(_ s: inout Sheet, _ at: (col: Int, row: Int)?, _ new: (String) -> String) -> Bool {
            guard let at, let old = s.text(at.col, at.row), let cell = s.cell(Sheet.ref(at.col, at.row)), !cell.formula else { return false }
            let want = new(old)
            guard want != old else { return false }
            s.cells.set(Sheet.ref(at.col, at.row), .inline(want))
            return true
        }
        // what the file says now, to find the station and kWp in its PROJECT line
        var was = ProjectSetup()
        if var d = detail {
            let cells = setupCells(d)
            was = .parse(title: cells.title.flatMap { d.text($0.col, $0.row) }, line: cells.line.flatMap { d.text($0.col, $0.row) })
            if put(&d, cells.title, { setup.rewrite(title: $0) }) { detailChanged += 1 }
            if put(&d, cells.line, { setup.rewrite(line: $0) }) { detailChanged += 1 }
            detail = d
        }
        if let project = layout.project {
            let p = station(project: project, fileName: "")
            if was.stationName == nil { was.stationName = p.name }
            if was.kWp == nil { was.kWp = p.kWp }
        }
        let projectCell = lineCell(plan, "PROJECT", above: layout)
        if put(&plan, projectCell, { old in
            var t = old
            if let a = was.stationName, let b = setup.stationName, a != b, !a.isEmpty { t = t.replacingOccurrences(of: a, with: b) }
            if let a = was.branch.map(ProjectSetup.branchName), let b = setup.branch.map(ProjectSetup.branchName), !a.isEmpty, !b.isEmpty, a != b {
                t = t.replacingOccurrences(of: "สาขา" + a, with: "สาขา" + b)
            }
            if let a = was.kWp, let b = setup.kWp, abs(a - b) >= 0.005 {
                t = t.replacingOccurrences(of: ProjectSetup.format(a) + " kWp", with: ProjectSetup.format(b) + " kWp")
            }
            return t
        }) { planChanged += 1 }
        if put(&plan, lineCell(plan, "รหัส", above: layout), { old in
            var line = ProjectSetup()
            line.contractor = setup.contractor
            line.engineer = setup.engineer
            var t = line.rewrite(line: old)
            if let code = setup.code, let r = t.range(of: #"P\d+-\d+"#, options: .regularExpression) { t.replaceSubrange(r, with: code) }
            // the line keeps its leading ": "
            if old.hasPrefix(": "), !t.hasPrefix(": ") { t = ": " + t.drop { $0 == ":" || $0 == " " } }
            return t
        }) { planChanged += 1 }
        return (planChanged, detailChanged)
    }

    /// The text right of a label (`PROJECT`, `รหัส`) above the plan's header.
    static func lineCell(_ s: Sheet, _ label: String, above layout: Layout) -> (col: Int, row: Int)? {
        let status = s.texts.filter { $0.text.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Status") == .orderedSame }
            .map(\.row).min() ?? .max
        guard let at = s.texts.filter({ $0.row < status && $0.text.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(label) == .orderedSame })
            .min(by: { ($0.row, $0.col) < ($1.row, $1.col) }) else { return nil }
        return s.texts.filter { $0.row == at.row && $0.col > at.col }.min { $0.col < $1.col }.map { ($0.col, $0.row) }
    }

    /// The installation points table (`ประเภทหน้างาน` | `จุด` | `แผง` | `kWp`): each type with any points, down to `รวม`.
    static func points(_ s: Sheet) -> [ProjectSetup.Point] {
        func clean(_ t: String) -> String { t.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let head = s.texts.first(where: { clean($0.text) == "ประเภทหน้างาน" }) else { return [] }
        let row = s.texts.filter { $0.row == head.row }.map { (col: $0.col, text: clean($0.text)) }
        func col(_ t: String) -> Int? { row.first { $0.text == t }?.col }
        guard let countCol = col("จุด") else { return [] }
        let modulesCol = col("แผง"), kWpCol = col("kWp")
        var out: [ProjectSetup.Point] = []
        for (r, text) in s.texts(col: head.col) where r > head.row {
            let type = clean(text)
            if type == "รวม" || r > head.row + 20 { break }
            guard let n = s.number(countCol, r), n > 0 else { continue }
            out.append(.init(type: type, count: Int(n.rounded()), modules: modulesCol.flatMap { s.number($0, r) }.map { Int($0.rounded()) } ?? 0,
                             kWp: kWpCol.flatMap { s.number($0, r) } ?? 0))
        }
        return out
    }

    /// The Inverter station table's `รูปแบบ` line: its type, and the detail written further right.
    static func inverterStation(_ s: Sheet) -> (type: String, detail: String?)? {
        guard let mark = s.texts.first(where: { $0.text.trimmingCharacters(in: .whitespaces).hasPrefix("รูปแบบ") }) else { return nil }
        let rest = s.texts.filter { $0.row == mark.row && $0.col > mark.col }.sorted { $0.col < $1.col }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let type = rest.first else { return nil }
        return (type, rest.count > 1 ? rest.dropFirst().joined(separator: " · ") : nil)
    }
}
