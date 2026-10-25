import Foundation
import TCRoofCore

/// A station's own plan workbook (`Master Plan Weekly PWA <station>.xlsx`, sheet `Weekly PLAN`): the 18 MP tasks, each a
/// Plan row (weight, start, finish, the weekly plan by formula) over an Actual row (actual start and finish, and weight
/// points typed per week), with the week columns dated in the header row.
///
/// `read` takes the plan, its weights and the actual points into the app. `export` writes the app's plan and actual back
/// into the same file: only the input cells whose value changed are replaced, in place, keeping their style, so every
/// other part (formulas, conditional formats, the S-curve chart, print set-up) stays as the file came. A plan with no
/// change gives back the very same bytes.
///
/// The layout is found from the header texts (`Status`, `Start`, `Finished`, `Weight`, `Description`), not fixed cells,
/// so the station copies with more or fewer rows and weeks read the same.
public enum MPWorkbook {
    public enum Failure: Error, Equatable {
        case notWorkbook
        case noPlanSheet
        case noTasks
        /// A cell to write holds the formula other cells share; replacing it would break them.
        case sharedFormula(String)

        public var message: String {
            switch self {
            case .notWorkbook: "ไฟล์นี้ไม่ใช่ Excel (.xlsx)"
            case .noPlanSheet: "ไม่พบชีตแผนงาน (หัวตาราง Status / Start / Finished)"
            case .noTasks: "ไม่พบงาน 1.1–3.2 ในไฟล์"
            case .sharedFormula(let ref): "เซลล์ \(ref) เป็นสูตรที่เซลล์อื่นใช้ร่วม เขียนทับไม่ได้"
            }
        }
    }

    /// What `read` found.
    public struct Imported: Sendable {
        public var input: MasterSchedule.Input
        public var actual: MasterSchedule.Actual
        /// The file's `PROJECT` and `OWNER` lines, without the leading ": ".
        public var project: String?
        public var owner: String?
        /// The tasks found, in the file's order.
        public var tasks: [MasterSchedule.Task]
        /// The first and last week column.
        public var weeks: ClosedRange<Date>?
        /// Whether the app works out the file's formulas as Excel did.
        public var formulas: FormulaCheck
        /// The Actual cells the file has: what taking its progress may change (`Actual.merging`).
        public var coverage: MasterSchedule.Actual.Coverage
        /// The progress the file held when the app last exported it (`Snapshot`); nil for a file the app never wrote.
        public var base: MasterSchedule.Actual?
        /// The team template's work breakdown (`แผนโครงการ` sheet), every row in the sheet's order; empty for a file
        /// without one. Read only: export leaves that sheet as it came.
        public var wbs: [MasterSchedule.WorkItem] = []
    }

    /// The plan sheet's formulas worked out on the untouched file and compared with the results Excel saved in it.
    public struct FormulaCheck: Sendable, Equatable {
        public var count: Int
        /// Formulas the app can't work out (another sheet, a function it doesn't know), and those that read them: they
        /// keep Excel's saved result, so a preview shows it until the file is opened in Excel.
        public var unknown: [String]
        /// Formulas the app works out differently from Excel: the app misreads this file, so export writes no results
        /// of its own into it.
        public var differs: [String]
        public var isComplete: Bool { unknown.isEmpty && differs.isEmpty }
    }

    static func check(_ sheet: Sheet, _ cal: Calendar) -> FormulaCheck {
        var f = sheet.formulas(cal)
        var unknown: [String] = [], differs: [String] = []
        let cells = f.formulas.keys.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
        for p in cells {
            let ref = Sheet.ref(p.col, p.row), v = f.value(p)
            if v == .unknown { unknown.append(ref) }
            else if let saved = sheet.cell(ref)?.cached, !Sheet.same(saved, v) { differs.append(ref) }
        }
        return FormulaCheck(count: cells.count, unknown: unknown, differs: differs)
    }

    /// What `export` wrote.
    public struct Export: Sendable {
        public var data: Data
        /// Input cells replaced. 0 with no change at all gives back the original file; 0 can also come with only the
        /// file's kept progress record brought up to date (`Snapshot`).
        public var changedCells: Int
        /// Weeks with actual points the file has no column for (`yyyy-MM-dd`), left out.
        public var weeksOutside: [String]
    }

    // MARK: read

    public static func read(_ data: Data, calendar cal: Calendar = MasterSchedule.calendar) throws -> Imported {
        let book = try Book(data)
        let sheet = book.sheet, layout = book.layout
        var fixed: [String: MasterSchedule.FixedTask] = [:]
        for row in layout.rows {
            fixed[row.task.rawValue] = .init(start: sheet.date(layout.startCol, row.plan, cal), end: sheet.date(layout.endCol, row.plan, cal),
                                             weight: sheet.number(layout.weightCol, row.plan) ?? 0)
        }
        let actual = progress(sheet, layout, cal)

        let plan = layout.rows.map { (task: $0.task, f: fixed[$0.task.rawValue]!) }
        func first(_ t: MasterSchedule.Task) -> Date? { fixed[t.rawValue]?.start }
        let site = plan.filter { $0.task.part != .permit }
        let starts = site.compactMap(\.f.start), ends = site.compactMap(\.f.end)
        let anyStart = plan.compactMap(\.f.start).min() ?? cal.startOfDay(for: .now)
        let installStart = starts.min() ?? anyStart
        let installEnd = max(ends.max() ?? installStart, installStart)
        let kickoff = first(.kickoff) ?? anyStart
        var input = MasterSchedule.Input(installStart: installStart, installEnd: installEnd, kickoff: kickoff,
                                         engineeringStart: first(.engineering) ?? kickoff,
                                         siteHandover: first(.siteHandover) ?? installStart,
                                         over200kVA: (fixed[MasterSchedule.Task.pk2.rawValue]?.weight ?? 0) > 0)
        func days(_ t: MasterSchedule.Task) -> Int? {
            guard let f = fixed[t.rawValue], let s = f.start, let e = f.end else { return nil }
            let n = cal.dateComponents([.day], from: s, to: e).day ?? 0
            return n > 0 ? n : nil
        }
        input.engineeringDays = days(.engineering) ?? input.engineeringDays
        input.buildingPermitDays = days(.buildingPermit) ?? input.buildingPermitDays
        input.pk2Days = days(.pk2) ?? input.pk2Days
        input.gridConnectionDays = days(.gridConnection) ?? input.gridConnectionDays
        input.fixed = fixed

        let weekDates = layout.weeks.map(\.date)
        return Imported(input: input, actual: actual, project: layout.project, owner: layout.owner,
                        tasks: layout.rows.map(\.task),
                        weeks: weekDates.min().flatMap { a in weekDates.max().map { a...$0 } },
                        formulas: check(sheet, cal),
                        coverage: .init(tasks: Set(layout.rows.filter { $0.actual != nil }.map(\.task.rawValue)),
                                        weeks: Set(layout.weeks.map(\.key))),
                        base: Snapshot.read(book.zip),
                        wbs: book.detail.map { wbs($0, cal) } ?? [])
    }

    /// The Actual rows' start, finish and weekly points as the sheet holds them.
    static func progress(_ sheet: Sheet, _ layout: Layout, _ cal: Calendar) -> MasterSchedule.Actual {
        var actual = MasterSchedule.Actual()
        for row in layout.rows {
            guard let a = row.actual else { continue }
            let t = row.task.rawValue
            if let d = sheet.date(layout.startCol, a, cal) { actual.started[t] = d }
            if let d = sheet.date(layout.endCol, a, cal) { actual.finished[t] = d }
            for w in layout.weeks {
                guard let v = sheet.number(w.col, a), v > 0 else { continue }
                actual.points[t, default: [:]][w.key, default: 0] += v
            }
        }
        return actual
    }

    // MARK: export

    public static func export(_ original: Data, input: MasterSchedule.Input, actual: MasterSchedule.Actual,
                              calendar cal: Calendar = MasterSchedule.calendar) throws -> Export {
        let book = try Book(original)
        let layout = book.layout
        var sheet = book.sheet
        var changed = 0, frozeFormula = false
        var written: [SheetFormulas.Pos: SheetFormulas.Value] = [:]

        func put(_ col: Int, _ row: Int, _ value: Double?, force: Bool = false) throws {
            let ref = Sheet.ref(col, row)
            let cell = sheet.cell(ref)
            let now = cell?.number
            let same = value.map { v in now.map { abs($0 - v) < 1e-9 } ?? false } ?? (now == nil || now == 0)
            if same && !(force && cell?.formula == true) { return }
            guard cell != nil else { return }
            if cell?.sharedMaster == true { throw Failure.sharedFormula(ref) }
            if cell?.formula == true { frozeFormula = true }
            sheet.cells.set(ref, value.map { .number($0) } ?? .empty)
            written[SheetFormulas.Pos(col: col, row: row)] = value.map { .number($0) } ?? .empty
            changed += 1
        }

        // the plan: the tasks that changed take their new values; a formula elsewhere is kept while it still works out
        // to the app's plan, and becomes a value when it no longer would (1.3's start is 2.1's: moving 2.1 alone
        // would drag 1.3 along in Excel)
        let plan = Dictionary(MasterSchedule.plan(input, calendar: cal).map { ($0.task, $0) }) { a, _ in a }
        func serial(_ d: Date?) -> Double? { d.map { Sheet.serial($0, cal) } }
        func targets(_ row: Layout.Row, _ p: MasterSchedule.PlannedTask) -> [(col: Int, want: Double?)] {
            [(layout.weightCol, p.weight), (layout.startCol, serial(p.start)), (layout.endCol, serial(p.end))]
        }
        let changedRows = layout.rows.filter { row in
            guard let p = plan[row.task] else { return false }
            return targets(row, p).contains { !close(sheet.number($0.col, row.plan), $0.want) }
        }
        if !changedRows.isEmpty {
            for row in changedRows {
                guard let p = plan[row.task] else { continue }
                for t in targets(row, p) where sheet.cell(Sheet.ref(t.col, row.plan))?.formula != true {
                    try put(t.col, row.plan, t.want)
                }
                // Day: H − G as the file's rows count it, 1 for a one-day task
                let moved = !close(sheet.number(layout.startCol, row.plan), serial(p.start))
                    || !close(sheet.number(layout.endCol, row.plan), serial(p.end))
                if moved, let dayCol = layout.dayCol, let s = p.start, let e = p.end,
                   sheet.cell(Sheet.ref(dayCol, row.plan))?.formula != true {
                    try put(dayCol, row.plan, Double(max(cal.dateComponents([.day], from: s, to: e).day ?? 0, 1)))
                }
            }
            // one formula at a time, the changed tasks' own first, as freezing one can put others right (2.3's end is
            // its start + Day) or move them
            var formulas = sheet.formulas(cal)
            for (p, v) in written { formulas.setInput(p, v) }
            let order = changedRows + layout.rows.filter { r in !changedRows.contains { $0.plan == r.plan } }
            let cells = order.flatMap { row -> [(pos: SheetFormulas.Pos, want: Double?)] in
                guard let p = plan[row.task] else { return [] }
                return targets(row, p).compactMap { t in
                    sheet.cell(Sheet.ref(t.col, row.plan))?.formula == true ? (SheetFormulas.Pos(col: t.col, row: row.plan), t.want) : nil
                }
            }
            var frozen = Set<SheetFormulas.Pos>()
            while let next = cells.first(where: { c in
                guard !frozen.contains(c.pos) else { return false }
                switch formulas.value(c.pos) {
                case .number(let n): return !close(n, c.want)
                case .empty: return !close(nil, c.want)
                default: return true
                }
            }) {
                frozen.insert(next.pos)
                try put(next.pos.col, next.pos.row, next.want, force: true)
                formulas.setInput(next.pos, next.want.map { .number($0) } ?? .empty)
            }
        }

        // the actual: start, finish and the points per week
        var outside = Set<String>()
        let columns = Dictionary(layout.weeks.map { ($0.key, $0.col) }) { a, _ in a }
        for row in layout.rows {
            guard let a = row.actual else { continue }
            let t = row.task.rawValue
            try put(layout.startCol, a, serial(actual.started[t]))
            try put(layout.endCol, a, serial(actual.finished[t]))
            let points = actual.points[t] ?? [:]
            for w in layout.weeks { try put(w.col, a, points[w.key].flatMap { $0 > 0 ? $0 : nil }) }
            for (k, v) in points where v > 0 && columns[k] == nil { outside.insert(k) }
        }

        // the progress as the file now holds it, kept in the file so a later import can tell what was changed in Excel;
        // an unchanged file with no record, or an up-to-date one, comes back as it was
        let held = progress(Sheet(sheet.cells.xml, shared: []), layout, cal)
        let kept = Snapshot.read(book.zip)
        guard changed > 0 || (kept != nil && kept != held) else {
            return Export(data: original, changedCells: 0, weeksOutside: outside.sorted())
        }
        var zip = book.zip
        Snapshot.write(held, into: &zip)

        // the formulas' results from the new values, so a viewer that doesn't recalculate shows them too; not when the
        // app works out the untouched file differently from Excel, as it would write wrong numbers
        var formulas = sheet.formulas(cal)
        for (p, v) in written { formulas.setInput(p, v) }
        let trusted = check(book.sheet, cal).differs.isEmpty
        for p in Array(formulas.formulas.keys) where trusted {
            let ref = Sheet.ref(p.col, p.row)
            guard let cell = sheet.cell(ref), let el = sheet.cells.element(ref) else { continue }
            let v = formulas.value(p)
            guard v != .unknown, !Sheet.same(cell.cached, v), let new = Sheet.cached(el, v) else { continue }
            sheet.cells.replace(ref, new)
        }
        if trusted { refreshCharts(&zip, sheet: book.sheetName, formulas: &formulas) }

        zip.set(book.sheetPath, sheet.cells.xml)
        // the formulas recalculate when the file opens; a cell that lost its formula leaves the calc chain stale, and
        // Excel rebuilds a missing one
        if frozeFormula { removeCalcChain(&zip) }
        if var wb = zip.string("xl/workbook.xml") { wb = fullCalcOnLoad(wb); zip.set("xl/workbook.xml", wb) }
        return Export(data: try zip.write(), changedCells: changed, weeksOutside: outside.sorted())
    }

    /// `MP 37 แผนงาน 2026-10-17.xlsx`-style name kept from the imported file: the original name, unchanged, so the
    /// team's folders still match.
    public static func fileName(original: String?, fallback: String) -> String {
        let name = (original ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return fallback.replacingOccurrences(of: "/", with: "-") + ".xlsx" }
        return name.lowercased().hasSuffix(".xlsx") ? name : name + ".xlsx"
    }

    static func close(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): abs(x - y) < 1e-9
        case let (x?, nil), let (nil, x?): x == 0
        }
    }

    /// The charts' saved series (the S-curve's cumulative plan and actual) from the sheet's new values.
    static func refreshCharts(_ zip: inout ZipArchive, sheet name: String, formulas: inout SheetFormulas) {
        for path in zip.paths where path.hasPrefix("xl/charts/chart") && path.hasSuffix(".xml") {
            guard var xml = zip.string(path) else { continue }
            var out = "", at = xml.startIndex, touched = false
            while let open = xml.range(of: "<c:numRef>", range: at..<xml.endIndex),
                  let close = xml.range(of: "</c:numRef>", range: open.upperBound..<xml.endIndex) {
                out += xml[at..<open.upperBound]
                let inner = String(xml[open.upperBound..<close.lowerBound])
                let fresh = chartSeries(inner, sheet: name, formulas: &formulas)
                if let fresh, fresh != inner { touched = true }
                out += fresh ?? inner
                at = close.lowerBound
            }
            out += xml[at...]
            if touched { xml = out; zip.set(path, xml) }
        }
    }

    /// One `<c:numRef>`'s inside with its cache worked out, or nil when it reads another sheet or something unknown.
    static func chartSeries(_ inner: String, sheet name: String, formulas: inout SheetFormulas) -> String? {
        guard let f = SheetXML.between(inner, "<c:f>", "</c:f>"),
              let cacheOpen = inner.range(of: "<c:numCache>"), let cacheClose = inner.range(of: "</c:numCache>") else { return nil }
        let ref = SharedStrings.unescape(f)
        guard let bang = ref.lastIndex(of: "!") else { return nil }
        var sheet = String(ref[..<bang])
        if sheet.hasPrefix("'") && sheet.hasSuffix("'") { sheet = String(sheet.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        let parts = ref[ref.index(after: bang)...].replacingOccurrences(of: "$", with: "").split(separator: ":").map(String.init)
        guard sheet == name, (1...2).contains(parts.count), let a = Sheet.split(parts[0]), let b = Sheet.split(parts.last!) else { return nil }
        var points = ""
        var i = 0
        for row in min(a.1, b.1)...max(a.1, b.1) {
            for col in min(a.0, b.0)...max(a.0, b.0) {
                let v = formulas.value(SheetFormulas.Pos(col: col, row: row))
                if v == .unknown { return nil }
                if case .number(let n) = v { points += "<c:pt idx=\"\(i)\"><c:v>\(IECExcel.number(n))</c:v></c:pt>" }
                i += 1
            }
        }
        let cache = String(inner[cacheOpen.upperBound..<cacheClose.lowerBound])
        let format = cache.range(of: "<c:formatCode>").flatMap { s in cache.range(of: "</c:formatCode>").map { String(cache[s.lowerBound..<$0.upperBound]) } } ?? ""
        let body = format + "<c:ptCount val=\"\(i)\"/>" + points
        return String(inner[..<cacheOpen.upperBound]) + body + String(inner[cacheClose.lowerBound...])
    }

    static func removeCalcChain(_ zip: inout ZipArchive) {
        guard zip.contains("xl/calcChain.xml") else { return }
        zip.remove("xl/calcChain.xml")
        if var rels = zip.string("xl/_rels/workbook.xml.rels"),
           let r = rels.range(of: #"<Relationship [^>]*Target="(/xl/)?calcChain\.xml"[^>]*/>"#, options: .regularExpression) {
            rels.removeSubrange(r)
            zip.set("xl/_rels/workbook.xml.rels", rels)
        }
        if var ct = zip.string("[Content_Types].xml"),
           let r = ct.range(of: #"<Override PartName="/xl/calcChain\.xml"[^>]*/>"#, options: .regularExpression) {
            ct.removeSubrange(r)
            zip.set("[Content_Types].xml", ct)
        }
    }

    /// `<calcPr … fullCalcOnLoad="1"/>`, so Excel works out the weekly plan, the sums and the S-curve again on opening.
    static func fullCalcOnLoad(_ wb: String) -> String {
        var wb = wb
        if let r = wb.range(of: #"<calcPr\b[^>]*?/?>"#, options: .regularExpression) {
            let tag = String(wb[r])
            guard !tag.contains("fullCalcOnLoad") else { return wb }
            let at = tag.hasSuffix("/>") ? tag.index(tag.endIndex, offsetBy: -2) : tag.index(before: tag.endIndex)
            wb.replaceSubrange(r, with: tag[..<at] + #" fullCalcOnLoad="1""# + tag[at...])
            return wb
        }
        // calcPr comes after definedNames and before the rest of the workbook's tail
        for next in ["<oleSize", "<customWorkbookViews", "<pivotCaches", "<smartTagPr", "<smartTagTypes", "<webPublishing",
                     "<fileRecoveryPr", "<webPublishObjects", "<extLst", "</workbook>"] {
            if let r = wb.range(of: next) {
                wb.insert(contentsOf: #"<calcPr fullCalcOnLoad="1"/>"#, at: r.lowerBound)
                break
            }
        }
        return wb
    }

    // MARK: the workbook

    /// The package, its plan sheet and the sheet's layout.
    struct Book {
        let zip: ZipArchive
        let sheetPath: String
        let sheetName: String
        let sheet: Sheet
        let layout: Layout
        /// The team template's `แผนโครงการ` sheet (its header has `WBS`), when the file has one.
        let detail: Sheet?

        init(_ data: Data) throws {
            guard let zip = try? ZipArchive(data), let wb = zip.string("xl/workbook.xml") else { throw Failure.notWorkbook }
            self.zip = zip
            let shared = Sheet.sharedStrings(zip.string("xl/sharedStrings.xml") ?? "")
            let rels = zip.string("xl/_rels/workbook.xml.rels") ?? ""
            // only a file whose strings have `WBS` is looked through for the detail sheet, so other plans read as before
            var lookForDetail = shared.contains("WBS")
            var noTasks = false, found: (path: String, name: String, sheet: Sheet, layout: Layout)?, detail: Sheet?
            for (name, id) in Self.sheetIDs(wb) {
                guard let path = Self.target(id, rels), let xml = zip.string(path) else { continue }
                let sheet = Sheet(xml, shared: shared)
                if lookForDetail, MPWorkbook.wbsHeader(sheet) != nil { detail = sheet; lookForDetail = false; continue }
                if found == nil, let layout = Layout(sheet) {
                    if layout.rows.isEmpty { noTasks = true } else { found = (path, name, sheet, layout) }
                }
                if found != nil && !lookForDetail { break }
            }
            guard let found else { throw noTasks ? Failure.noTasks : Failure.noPlanSheet }
            sheetPath = found.path; sheetName = found.name; sheet = found.sheet; layout = found.layout
            self.detail = detail
        }

        /// The sheets' names and relationship ids in tab order.
        static func sheetIDs(_ wb: String) -> [(name: String, id: String)] {
            var out: [(String, String)] = [], at = wb.startIndex
            while let r = wb.range(of: "<sheet ", range: at..<wb.endIndex), let end = wb.range(of: ">", range: r.upperBound..<wb.endIndex) {
                let tag = String(wb[r.lowerBound..<end.upperBound])
                if let id = SheetXML.between(tag, "r:id=\"", "\"") {
                    out.append((SharedStrings.unescape(SheetXML.between(tag, "name=\"", "\"") ?? ""), id))
                }
                at = end.upperBound
            }
            return out
        }

        static func target(_ id: String, _ rels: String) -> String? {
            guard let r = rels.range(of: "Id=\"\(id)\"") else { return nil }
            let start = rels[..<r.lowerBound].range(of: "<Relationship", options: .backwards)?.lowerBound ?? r.lowerBound
            guard let end = rels.range(of: ">", range: r.upperBound..<rels.endIndex) else { return nil }
            guard let t = SheetXML.between(String(rels[start..<end.upperBound]), "Target=\"", "\"") else { return nil }
            return t.hasPrefix("/") ? String(t.dropFirst()) : "xl/" + t
        }
    }

    /// Where the plan sits on the sheet.
    struct Layout {
        struct Row { let task: MasterSchedule.Task; let plan: Int; let actual: Int? }
        struct Week { let col: Int; let date: Date; let key: String }

        let weightCol: Int, startCol: Int, endCol: Int, dayCol: Int?
        let rows: [Row]
        let weeks: [Week]
        let project: String?, owner: String?

        /// Nil when the sheet has no `Status` / `Start` / `Finished` header.
        init?(_ s: Sheet, calendar cal: Calendar = MasterSchedule.calendar) {
            func find(_ text: String, row: Int? = nil) -> (col: Int, row: Int)? {
                s.texts.filter { $0.text.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(text) == .orderedSame && (row == nil || $0.row == row) }
                    .min { ($0.row, $0.col) < ($1.row, $1.col) }.map { ($0.col, $0.row) }
            }
            guard let status = find("Status"), let start = find("Start", row: status.row) ?? find("Start"),
                  let end = find("Finished", row: start.row) ?? find("Finish", row: start.row),
                  let weight = find("Weight") ?? find("%", row: status.row) else { return nil }
            let desc = find("Description")?.col ?? 1
            weightCol = weight.col; startCol = start.col; endCol = end.col
            dayCol = find("Day", row: start.row)?.col

            // week columns: the dated cells of the header row right of the dates
            let firstWeekCol = max(start.col, end.col, dayCol ?? 0) + 1
            var weeks: [Week] = [], seen = Set<String>()
            for (col, v) in s.numbers(row: start.row) where col >= firstWeekCol && (36_526...73_051).contains(v) {
                let d = Sheet.date(v, cal), key = MasterSchedule.Actual.key(d, calendar: cal)
                guard seen.insert(key).inserted else { continue }
                weeks.append(Week(col: col, date: MasterSchedule.weekStart(d, calendar: cal), key: key))
            }
            self.weeks = weeks

            // task rows: "2.1 ติดตั้ง…" with Status Plan, its Actual row under it
            var rows: [Row] = [], used = Set<MasterSchedule.Task>()
            for (r, text) in s.texts(col: desc) where r > status.row {
                guard s.text(status.col, r)?.trimmingCharacters(in: .whitespaces).lowercased() == "plan",
                      let task = Self.task(text, taken: used) else { continue }
                used.insert(task)
                let isActual = s.text(status.col, r + 1)?.trimmingCharacters(in: .whitespaces).lowercased() == "actual"
                rows.append(Row(task: task, plan: r, actual: isActual ? r + 1 : nil))
            }
            self.rows = rows

            func line(_ label: String) -> String? {
                guard let at = find(label), at.row < status.row else { return nil }
                let t = s.texts.filter { $0.row == at.row && $0.col > at.col }.min { $0.col < $1.col }?.text
                return t.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ": ").union(.whitespaces)) }.flatMap { $0.isEmpty ? nil : $0 }
            }
            project = line("PROJECT"); owner = line("OWNER")
        }

        /// The task a row's description names: by its number, or by its words when the number is taken (some copies
        /// number grid connection 1.6 a second time).
        static func task(_ text: String, taken: Set<MasterSchedule.Task>) -> MasterSchedule.Task? {
            let t = text.trimmingCharacters(in: .whitespaces)
            guard let r = t.range(of: #"^\d+\.\d+"#, options: .regularExpression) else { return nil }
            let code = String(t[r])
            if let task = MasterSchedule.Task.allCases.first(where: { $0.code == code }), !taken.contains(task),
               !(task == .cop && t.contains("ขนานไฟ")) {
                return task
            }
            let byWords: [(String, MasterSchedule.Task)] = [("ขนานไฟ", .gridConnection), ("COP", .cop), ("พค.2", .pk2)]
            return byWords.first { t.contains($0.0) && !taken.contains($0.1) }?.1
        }
    }

    /// A sheet's cells, read once.
    struct Sheet {
        struct Cell {
            var number: Double?; var text: String?; var formula: Bool; var sharedMaster: Bool
            /// The formula as written (nil for a cell sharing another's), its shared index, and the cell's type attribute.
            var formulaText: String? = nil
            var sharedIndex: String? = nil
            var type: String? = nil

            /// The saved result of a formula cell, as the evaluator gives it.
            var cached: SheetFormulas.Value {
                switch type {
                case "str": return .text(text ?? "")
                case "e": return .error(text ?? "")
                case "b": return .bool((number ?? 0) != 0)
                default: return number.map { .number($0) } ?? .empty
                }
            }
        }

        var cells: SheetCells
        private var byRef: [String: Cell] = [:]
        /// Every text cell.
        let texts: [(col: Int, row: Int, text: String)]

        init(_ xml: String, shared: [String]) {
            cells = SheetCells(xml)
            var texts: [(Int, Int, String)] = []
            for ref in cells.refs {
                guard let el = cells.element(ref), let (col, row) = Self.split(ref) else { continue }
                let c = Self.parse(el, shared: shared)
                byRef[ref] = c
                if let t = c.text, !t.isEmpty { texts.append((col, row, t)) }
            }
            self.texts = texts.map { (col: $0.0, row: $0.1, text: $0.2) }
        }

        func cell(_ ref: String) -> Cell? { byRef[ref] }
        func number(_ col: Int, _ row: Int) -> Double? { byRef[Self.ref(col, row)]?.number }
        func text(_ col: Int, _ row: Int) -> String? { byRef[Self.ref(col, row)]?.text }
        /// A date cell's day; nil when empty or 0 (Excel's blank date).
        func date(_ col: Int, _ row: Int, _ cal: Calendar) -> Date? {
            guard let v = number(col, row), v >= 1 else { return nil }
            return Self.date(v, cal)
        }

        func numbers(row: Int) -> [(col: Int, value: Double)] {
            byRef.compactMap { ref, c in
                guard let v = c.number, let (col, r) = Self.split(ref), r == row else { return nil }
                return (col, v)
            }.sorted { $0.col < $1.col }
        }

        func numbers(col: Int) -> [(row: Int, value: Double)] {
            byRef.compactMap { ref, c in
                guard let v = c.number, let (cl, r) = Self.split(ref), cl == col else { return nil }
                return (r, v)
            }.sorted { $0.row < $1.row }
        }

        func texts(col: Int) -> [(row: Int, text: String)] {
            texts.filter { $0.col == col }.map { ($0.row, $0.text) }.sorted { $0.row < $1.row }
        }

        static func parse(_ el: String, shared: [String]) -> Cell {
            let head = el.prefix { $0 != ">" }
            let type = SheetXML.between(String(head), " t=\"", "\"")
            let v = SheetXML.between(el, "<v>", "</v>")
            let hasF = el.contains("<f>") || el.contains("<f ")
            var master = false, fText: String?, si: String?
            if let f = el.range(of: "<f") {
                let tag = String(el[f.lowerBound...].prefix { $0 != ">" })
                master = tag.contains("t=\"shared\"") && tag.contains("ref=\"")
                if tag.contains("t=\"shared\"") { si = SheetXML.between(tag, "si=\"", "\"") }
                if !tag.hasSuffix("/"), let body = SheetXML.between(String(el[f.lowerBound...]), ">", "</f>") {
                    fText = SharedStrings.unescape(body)
                }
            }
            var c: Cell
            switch type {
            case "s": c = Cell(number: nil, text: v.flatMap(Int.init).flatMap { shared.indices.contains($0) ? shared[$0] : nil }, formula: hasF, sharedMaster: master)
            case "str", "e": c = Cell(number: nil, text: v.map(SharedStrings.unescape), formula: hasF, sharedMaster: master)
            case "inlineStr": c = Cell(number: nil, text: XML.runsText(el), formula: hasF, sharedMaster: master)
            default: c = Cell(number: v.flatMap(Double.init), text: nil, formula: hasF, sharedMaster: master)
            }
            c.formulaText = fText; c.sharedIndex = si; c.type = type
            return c
        }

        /// The sheet's formulas and values, ready to work out.
        func formulas(_ cal: Calendar) -> SheetFormulas {
            var f = SheetFormulas(calendar: cal)
            var masters: [String: SheetFormulas.Pos] = [:], sharing: [(SheetFormulas.Pos, String)] = []
            for (ref, c) in byRef {
                guard let (col, row) = Self.split(ref) else { continue }
                let p = SheetFormulas.Pos(col: col, row: row)
                if c.formula {
                    if let text = c.formulaText {
                        f.setFormula(p, text: text, master: p)
                        if let si = c.sharedIndex { masters[si] = p }
                    } else if let si = c.sharedIndex {
                        sharing.append((p, si))
                    }
                } else if let n = c.number {
                    f.setInput(p, c.type == "b" ? .bool(n != 0) : .number(n))
                } else if let t = c.text {
                    f.setInput(p, c.type == "e" ? .error(t) : .text(t))
                }
            }
            for (p, si) in sharing {
                if let m = masters[si] { f.share(p, from: m) }
            }
            return f
        }

        static func same(_ a: SheetFormulas.Value, _ b: SheetFormulas.Value) -> Bool {
            if case .number(let x) = a, case .number(let y) = b { return abs(x - y) <= 1e-9 * max(1, abs(x)) }
            return a == b
        }

        /// A formula cell's element with `v` as its saved result; the formula and style stay.
        static func cached(_ el: String, _ v: SheetFormulas.Value) -> String? {
            guard let gt = el.firstIndex(of: ">"), el.hasSuffix("</c>"), el[el.index(before: gt)] != "/" else { return nil }
            var open = String(el[...gt])
            if let r = open.range(of: #" t="[^"]*""#, options: .regularExpression) { open.removeSubrange(r) }
            var body = String(el[el.index(after: gt)..<el.index(el.endIndex, offsetBy: -4)])
            if let a = body.range(of: "<v>"), let b = body.range(of: "</v>", range: a.upperBound..<body.endIndex) {
                body.removeSubrange(a.lowerBound..<b.upperBound)
            }
            let type: String?, text: String
            switch v {
            case .number(let n): type = nil; text = IECExcel.number(n)
            case .text(let t): type = "str"; text = SharedStrings.escape(t)
            case .bool(let b): type = "b"; text = b ? "1" : "0"
            case .error(let e): type = "e"; text = e
            case .empty: type = "str"; text = ""
            case .unknown: return nil
            }
            if let type { open.insert(contentsOf: #" t="\#(type)""#, at: open.index(before: open.endIndex)) }
            // the result follows the formula
            let fEnd = body.range(of: "</f>")?.upperBound
                ?? body.range(of: "<f").flatMap { f in body.range(of: "/>", range: f.upperBound..<body.endIndex)?.upperBound }
                ?? body.startIndex
            return open + body[..<fEnd] + "<v>\(text)</v>" + body[fEnd...] + "</c>"
        }

        static func sharedStrings(_ xml: String) -> [String] {
            xml.components(separatedBy: "<si>").dropFirst().map { XML.runsText($0.components(separatedBy: "</si>").first ?? "") }
        }

        /// "BX29" → (75, 29), columns 0-based.
        static func split(_ ref: String) -> (Int, Int)? {
            var col = 0, letters = 0
            for ch in ref.unicodeScalars {
                guard ch.value >= 65 && ch.value <= 90 else { break }
                col = col * 26 + Int(ch.value - 64); letters += 1
            }
            guard letters > 0, let row = Int(ref.dropFirst(letters)) else { return nil }
            return (col - 1, row)
        }

        static func ref(_ col: Int, _ row: Int) -> String { IECExcel.column(col) + String(row) }

        /// Excel's day serial (1900 system) of a day in `cal`'s time zone.
        static func serial(_ d: Date, _ cal: Calendar) -> Double {
            Double(cal.dateComponents([.day], from: epoch(cal), to: cal.startOfDay(for: d)).day ?? 0)
        }

        static func date(_ serial: Double, _ cal: Calendar) -> Date {
            cal.date(byAdding: .day, value: Int(serial.rounded(.down)), to: epoch(cal))!
        }

        static func epoch(_ cal: Calendar) -> Date { cal.date(from: DateComponents(year: 1899, month: 12, day: 30))! }
    }
}
