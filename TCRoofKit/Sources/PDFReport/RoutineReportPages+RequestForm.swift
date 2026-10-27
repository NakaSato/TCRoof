import Foundation
import TCRoofCore

/// R1 in the customer's WORK REQUEST CIVIL-ELECTRICAL form (docs/ui/weekly-request-pdf): the daily form's frame and
/// header with the request's titles, then manpower and tools side by side, the work plan, the risk assessment and the two
/// signatures. Rows past the form's continue on more pages; the signatures sit on the last one. Drawn in the board's
/// pixels and scaled onto `dailyFormPage`, as the daily form.
extension RoutineReportPages {
    static let requestTitles = FormTitles(en: "WORK REQUEST CIVIL-ELECTRICAL", enSize: 13, th: "คำขอปฏิบัติงานรายสัปดาห์ (Weekly Request)")

    /// The filled form's rows per page, and the blank form's.
    static let requestRows = (crew: 8, tools: 8, work: 7, risks: 4)
    static let requestBlankRows = (crew: 11, tools: 11, work: 10, risks: 4)

    /// The sizes that differ between the filled board (`RptWeekly32`) and the tighter blank one (`RptWeeklyForm`), in px.
    struct RequestStyle {
        var head: Double, countRow: Double, workRow: Double, riskRow: Double, footer: Double
        /// A section title's height and the gap under it.
        var title: Double, titleGap: Double
        var pad: Double
        var band: Double
        /// Work plan's Qty. and Unit, risk's level and prevention.
        var qtyW: Double, levelW: Double, preventionW: Double
        var blank: Bool

        static let filled = RequestStyle(head: 36, countRow: 20, workRow: 20, riskRow: 20, footer: 22, title: 18, titleGap: 6, pad: 12,
                                         band: 136, qtyW: 56, levelW: 130, preventionW: 250, blank: false)
        static let empty = RequestStyle(head: 32, countRow: 17, workRow: 18, riskRow: 18, footer: 20, title: 16, titleGap: 4, pad: 8,
                                        band: 124, qtyW: 66, levelW: 170, preventionW: 228, blank: true)
    }

    // MARK: - Report

    /// The weekly request in the customer's form, every page numbered "n / N". `signature` is the requester's drawn
    /// signature, on the Site Engineer's line.
    public func requestForm(_ r: RoutineReport.WeeklyRequest, signature: Photo? = nil) -> [ReportLayout.Page] {
        let s = station.settings
        let header = FormHeader(contract: Self.contractText(s), kWp: String(format: "%.2f", station.capacityKWp),
                                date: Self.requestDate(r), workingTime: Self.workingTime(Self.clock(r.workStart ?? s.workStart),
                                                                                         Self.clock(r.workEnd ?? s.workEnd)),
                                from: s.contractor, to: s.employer, station: station.projectLine,
                                titles: Self.requestTitles, dateNote: "(สัปดาห์ที่ \(r.weekNumber))")
        let n = Self.requestRows, style = RequestStyle.filled
        let crew = r.crew.filter { $0.count > 0 }, tools = r.tools.filter { $0.count > 0 }
        let work = r.work.enumerated().map { i, w in
            [String(i + 1), w.description.isEmpty ? (w.task?.title ?? "") : w.description, w.location, w.qty > 0 ? Self.num(w.qty) : "", w.unit, ""]
        }
        let risks = r.risks.filter { !$0.description.isEmpty }.enumerated().map { i, k in
            [String(i + 1), k.description, k.level.title, k.prevention]
        }
        let x0 = Self.frameX0 + style.pad, w = Self.frameX1 - style.pad - x0
        let workPages = workPages(work, widths: workWidths(w, style), budget: Double(n.work) * style.workRow, row: style.workRow)
        let count = max(1, Self.chunks(crew.count, n.crew), Self.chunks(tools.count, n.tools), workPages.count, Self.chunks(risks.count, n.risks))

        let bodies: [[DrawOp]] = (0..<count).map { i in
            let crewRows = Self.slice(crew, i, n.crew), toolRows = Self.slice(tools, i, n.tools)
            // a total prints with its rows: on the first page, or a later one that carries more of them
            return requestBody(crew: crewRows.map { [String($0.offset + 1), $0.element.name, "\($0.element.count)"] },
                        crewTotal: i == 0 || !crewRows.isEmpty ? "\(crew.reduce(0) { $0 + $1.count })" : "",
                        tools: toolRows.map { [String($0.offset + 1), $0.element.name, "\($0.element.count)"] },
                        toolTotal: i == 0 || !toolRows.isEmpty ? "\(tools.reduce(0) { $0 + $1.count })" : "",
                        work: workPages[safe: i] ?? [],
                        risks: Self.slice(risks, i, n.risks).map(\.element),
                        rows: n, style: style,
                        signatures: i == count - 1 ? requestSigners(r, drawn: signature) : nil)
        }
        return finishForm(bodies, header: header)
    }

    /// Who signs: the site engineer when they signed (with their drawn signature), the inspector when approved.
    private func requestSigners(_ r: RoutineReport.WeeklyRequest, drawn: Photo?) -> Signers {
        let s = station.settings
        return Signers(engineer: s.siteEngineer, engineerDate: r.engineerSignedAt.map(Self.signDate), drawn: drawn,
                       inspector: r.approvedBy.isEmpty ? s.inspector : r.approvedBy, inspectorDate: r.approvedAt.map(Self.signDate))
    }

    struct Signers {
        var engineer: String, engineerDate: String?, drawn: Photo?
        var inspector: String, inspectorDate: String?
        static let blank = Signers(engineer: "", engineerDate: nil, drawn: nil, inspector: "", inspectorDate: nil)
    }

    // MARK: - Blank form

    /// The form blank, for printing and filling in by hand: dotted lines for the kW, date, working time and station,
    /// numbered empty rows (11 / 11 / 10 / 4), English titles only, as `RptWeeklyForm`.
    public static func requestBlankForm(settings: RoutineReport.Settings = .init(), measure: TextMeasuring = ApproxMeasure()) -> [ReportLayout.Page] {
        let p = RoutineReportPages(station: .init(name: "", code: "", mpNumber: nil, capacityKWp: 0, settings: settings), measure: measure)
        let header = FormHeader(contract: contractText(settings), kWp: nil, date: nil, workingTime: nil,
                                from: settings.contractor, to: settings.employer, station: nil, titles: requestTitles)
        let n = requestBlankRows
        let numbered = { (k: Int, columns: Int) in (1...k).map { [String($0)] + Array(repeating: "", count: columns - 1) } }
        let body = p.requestBody(crew: numbered(n.crew, 3), crewTotal: "", tools: numbered(n.tools, 3), toolTotal: "",
                                 work: numbered(n.work, 6).map { ($0, RequestStyle.empty.workRow) }, risks: numbered(n.risks, 4),
                                 rows: n, style: .empty, signatures: .blank)
        return p.finishForm([body], header: header)
    }

    // MARK: - Body

    /// One page's body: manpower and tools, work plan, risks, spread down the page like the board, and the signatures.
    func requestBody(crew: [[String]], crewTotal: String, tools: [[String]], toolTotal: String, work: [([String], Double)],
                     risks: [[String]], rows: (crew: Int, tools: Int, work: Int, risks: Int), style: RequestStyle,
                     signatures: Signers?) -> [DrawOp] {
        let x0 = Self.frameX0 + style.pad, w = Self.frameX1 - style.pad - x0, half = (w - 16) / 2
        let band = Self.frameBottom - style.band
        let titled = style.title + style.titleGap
        // the work plan keeps its rows' height: wrapped lines take more, padding rows fill the rest
        let workBudget = Double(rows.work) * style.workRow
        let used = work.reduce(0) { $0 + $1.1 }
        let fill = Array(repeating: (Array(repeating: "", count: 6), style.workRow), count: max(0, Int(((workBudget - used) / style.workRow).rounded(.down))))
        let workRows = work + fill
        let countH = titled + style.head + Double(max(rows.crew, rows.tools)) * style.countRow + style.footer + 1.5
        let workH = titled + style.head + workRows.reduce(0) { $0 + $1.1 } + 1.5
        let riskH = titled + style.head + Double(rows.risks) * style.riskRow + 1.5
        let ys = Self.spaced([countH, workH, riskH], top: Self.bodyTop + style.pad, bottom: band - style.pad)

        let thai = !style.blank
        var o: [DrawOp] = []
        // manpower and tools
        for (k, list, total, title, qty, label) in [(0, crew, crewTotal, ("MANPOWER PLAN", "แผนกำลังคน"), ("Qty.", "จำนวน"), "Total Man-Day"),
                                                    (1, tools, toolTotal, ("TOOL & MACHINERY PLAN", "แผนเครื่องมือและเครื่องจักร"), ("Used", "ใช้งาน"),
                                                     "Total Tool & Machinery")] {
            let x = x0 + Double(k) * (half + 16)
            o += requestTitle(title.0, thai ? title.1 : nil, x: x, y: ys[0], h: style.title)
            let r = k == 0 ? rows.crew : rows.tools
            o += formTable(x: x, y: ys[0] + titled, widths: [52, half - 52 - 58, 58],
                           header: [("Item", "ลำดับที่"), ("Description", "รายการ"), qty], style: style,
                           rows: Self.padded(list, r, columns: 3).map { ($0, style.countRow) }, aligns: [.center, .left, .center], latin: [0, 2],
                           footer: (label, total, style.blank ? .center : .right))
        }
        // work plan
        o += requestTitle("WORK PLAN", thai ? "แผนงานประจำสัปดาห์" : nil, x: x0, y: ys[1], h: style.title)
        o += formTable(x: x0, y: ys[1] + titled, widths: workWidths(w, style),
                       header: [("Item", "ลำดับที่"), ("Description", "รายการ"), ("LOCAL/LINE", style.blank ? "" : "ตำแหน่ง"), ("Qty.", "จำนวน"),
                                ("Unit", "หน่วย"), ("Remark", style.blank ? "" : "หมายเหตุ")], style: style,
                       rows: workRows, aligns: [.center, .left, .center, .center, .center, .left], latin: [0, 3], wrap: [1, 2])
        // risks
        o += requestTitle(style.blank ? "ประเมินความเสี่ยง" : "RISK ASSESSMENT", style.blank ? nil : "ประเมินความเสี่ยง", x: x0, y: ys[2], h: style.title)
        o += formTable(x: x0, y: ys[2] + titled, widths: [52, w - 52 - style.levelW - style.preventionW, style.levelW, style.preventionW],
                       header: [("Item", "ลำดับที่"), ("Description", "รายการ"), (style.blank ? "" : "Risk Level", "ระดับความเสี่ยง"),
                                (style.blank ? "" : "Prevention", "แนวทางการป้องกันความเสี่ยง")], style: style,
                       rows: Self.padded(risks, rows.risks, columns: 4).map { ($0, style.riskRow) }, aligns: [.center, .left, .center, .left], latin: [0])

        // the signatures, on the last page
        if let s = signatures {
            let mid = (Self.frameX0 + Self.frameX1) / 2, top = style.blank ? band - 8 : band
            o.append(.line(Pt(Self.frameX0, band + 0.75), Pt(Self.frameX1, band + 0.75), width: 1.5, color: .black))
            o.append(.line(Pt(mid, band + 1.5), Pt(mid, Self.frameBottom), width: 1, color: .black))
            o += signature(("For Approve / ", "เพื่อขออนุมัติ"), name: s.engineer, date: s.engineerDate, drawn: s.drawn, role: "Site Engineer",
                           x: Self.frameX0, w: mid - Self.frameX0, top: top)
            o += signature(("Approve / ", "อนุมัติ"), name: s.inspector, date: s.inspectorDate, role: "Inspector", x: mid,
                           w: Self.frameX1 - mid, top: top)
        }
        return o
    }

    /// Item / Description / LOCAL/LINE / Qty. / Unit / Remark.
    func workWidths(_ w: Double, _ style: RequestStyle) -> [Double] {
        [52, w - 52 - 170 - style.qtyW * 2 - 96, 170, style.qtyW, style.qtyW, 96]
    }

    /// A work line's height: one line in 20 px, more lines at 15 px each when its description or place wraps.
    func workRowHeight(_ cells: [String], widths: [Double], row: Double) -> Double {
        let lines = [1, 2].map { i -> Double in
            guard let t = cells[safe: i], !t.isEmpty else { return 1 }
            let pad = i == 1 ? 16.0 : 12
            return (measure.height(t, width: widths[i] - pad, size: 11, bold: false) / measure.height("ก", width: 1000, size: 11, bold: false)).rounded()
        }.max() ?? 1
        return lines <= 1 ? row : lines * 15 + 4
    }

    /// The work lines split into pages by the rows' height, at least one line a page.
    func workPages(_ work: [[String]], widths: [Double], budget: Double, row: Double) -> [[([String], Double)]] {
        var pages: [[([String], Double)]] = [], page: [([String], Double)] = [], used = 0.0
        for cells in work {
            let h = workRowHeight(cells, widths: widths, row: row)
            if !page.isEmpty, used + h > budget { pages.append(page); page = []; used = 0 }
            page.append((cells, h)); used += h
        }
        if !page.isEmpty { pages.append(page) }
        return pages
    }

    /// "MANPOWER PLAN แผนกำลังคน", underlined; the blank form's titles have no Thai.
    func requestTitle(_ en: String, _ th: String?, x: Double, y: Double, h: Double) -> [DrawOp] {
        let latinTitle = en.unicodeScalars.allSatisfy { $0.isASCII }
        var runs = [TextRun(en + (th == nil ? "" : " "), size: latinTitle ? 10 : 11, bold: true, face: latinTitle ? .helvetica : .sarabun, underline: true)]
        if let th { runs.append(TextRun(th, size: 11, bold: true, underline: true)) }
        return [.runs(runs, at: Pt(x, y + h / 2))]
    }

    /// A form table with its own row heights: a two-line header (English over Thai; either may be empty), rows that wrap
    /// in the `wrap` columns, and an optional total row under a 1.5 px rule.
    func formTable(x: Double, y: Double, widths: [Double], header: [(String, String)], style: RequestStyle, rows: [([String], Double)],
                   aligns: [TextAlign], latin: Set<Int>, wrap: Set<Int> = [], footer: (label: String, value: String, align: TextAlign)? = nil) -> [DrawOp] {
        let w = widths.reduce(0, +), head = style.head
        let body = rows.reduce(0) { $0 + $1.1 }, foot = footer == nil ? 0 : style.footer
        let h = head + body + foot
        let xs = widths.indices.map { i in x + widths[..<i].reduce(0, +) }
        var o: [DrawOp] = []
        for (i, cell) in header.enumerated() {
            let b = Box(xs[i], y, widths[i], head), cx = b.x + b.w / 2, cy = b.y + b.h / 2
            switch (cell.0.isEmpty, cell.1.isEmpty) {
            case (false, false): o += headerCell(cell.0, cell.1, b)
            case (false, true): o.append(Self.latin(cell.0, 10, bold: true, at: Pt(cx, cy), align: .center))
            case (true, _): o.append(.text(cell.1, at: Pt(cx, cy), size: 11, bold: true, align: .center))
            }
        }
        var top = y + head
        for (r, (cells, rh)) in rows.enumerated() {
            if r > 0 { o.append(.line(Pt(x, top), Pt(x + w, top), width: 1, color: .black)) }
            for (i, c) in cells.enumerated() where i < widths.count && !c.isEmpty {
                let b = Box(xs[i], top, widths[i], rh)
                if rh > style.workRow, wrap.contains(i) {
                    let pad = i == 1 ? 8.0 : 6
                    o.append(.textBox(c, Box(b.x + pad, b.y + 2, b.w - 2 * pad, b.h - 4), size: 11, align: aligns[i]))
                } else {
                    o.append(cell(c, b, align: aligns[i], latin: latin.contains(i)))
                }
            }
            top += rh
        }
        if let footer {
            o.append(.line(Pt(x, top), Pt(x + w, top), width: 1.5, color: .black))
            let label = footer.align == .center ? Pt(xs[1] + widths[1] / 2, top + foot / 2) : Pt(xs[1] + widths[1] - 8, top + foot / 2)
            o.append(Self.latin(footer.label, 10, bold: true, at: label, align: footer.align))
            o.append(Self.latin(footer.value, 10, bold: true, at: Pt(x + w - widths[widths.count - 1] / 2, top + foot / 2), align: .center))
        }
        for i in 1..<widths.count { o.append(.line(Pt(xs[i], y), Pt(xs[i], y + h), width: 1, color: .black)) }
        o.append(.line(Pt(x, y + head), Pt(x + w, y + head), width: 1.5, color: .black))
        o.append(.rect(Box(x, y, w, h), stroke: .black, fill: nil, width: 1.5))
        return o
    }

    /// "04–10 August 2025": the request's Monday to Sunday, English, Gregorian, Bangkok; months and years named once
    /// each when they differ ("28 July – 03 August 2025").
    static func requestDate(_ r: RoutineReport.WeeklyRequest) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = RoutineReport.calendar.timeZone
        let a = r.date(ofDay: 0), b = RoutineReport.add(r.weekStart, 7)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = cal
        f.timeZone = cal.timeZone
        func fmt(_ d: Date, _ p: String) -> String { f.dateFormat = p; return f.string(from: d) }
        if cal.component(.year, from: a) != cal.component(.year, from: b) { return fmt(a, "dd MMMM yyyy") + " – " + fmt(b, "dd MMMM yyyy") }
        if cal.component(.month, from: a) != cal.component(.month, from: b) { return fmt(a, "dd MMMM") + " – " + fmt(b, "dd MMMM yyyy") }
        return fmt(a, "dd") + "–" + fmt(b, "dd MMMM yyyy")
    }
}
