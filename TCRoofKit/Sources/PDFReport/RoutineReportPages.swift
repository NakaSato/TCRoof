import Foundation
import TCRoofCore

/// รายงานประจำ R1–R4 (docs/specs/routine-reports-swift.md §4.6) as A4 portrait pages of vector drawing operations.
/// Tables are vector, rows grow to fit wrapped text, and a section that doesn't fit starts a new page.
public struct RoutineReportPages {
    /// The station facts printed on every report.
    public struct Station: Sendable {
        public var name: String
        public var code: String
        public var mpNumber: Int?
        public var capacityKWp: Double
        public var settings: RoutineReport.Settings
        /// The PWA branch (`สาขาโชคชัย`), from เอกสารสถานี's station facts; empty when not typed.
        public var branch: String
        public init(name: String, code: String, mpNumber: Int?, capacityKWp: Double, settings: RoutineReport.Settings, branch: String = "") {
            self.name = name; self.code = code; self.mpNumber = mpNumber; self.capacityKWp = capacityKWp; self.settings = settings
            self.branch = branch
        }

        /// `สถานีผลิตน้ำโชคชัย การประปาส่วนภูมิภาคสาขาโชคชัย`, the DAILY REPORT's ชื่อโครงการ; the name alone without a branch.
        public var projectLine: String {
            let b = branch.trimmingCharacters(in: .whitespaces)
            guard !b.isEmpty else { return name }
            return name + " การประปาส่วนภูมิภาค" + (b.hasPrefix("สาขา") ? b : "สาขา" + b)
        }
    }

    /// A photo of the day with what it shows.
    public struct DayPhoto: Sendable {
        public var photo: Photo
        public var date: Date
        public var caption: String
        public init(photo: Photo, date: Date, caption: String) { self.photo = photo; self.date = date; self.caption = caption }
    }

    /// The daily report and its signing state, as stored on the install log.
    public struct DailyEntry: Sendable {
        public var report: RoutineReport.Daily
        public var photos: [DayPhoto]
        public var engineerSignedAt: Date?
        public var inspectorAckAt: Date?
        /// The drawn signatures, printed above their lines on the form's page 3 while the report is signed.
        public var engineerSignature: Photo?
        public var inspectorSignature: Photo?
        public init(report: RoutineReport.Daily, photos: [DayPhoto], engineerSignedAt: Date?, inspectorAckAt: Date?,
                    engineerSignature: Photo? = nil, inspectorSignature: Photo? = nil) {
            self.report = report; self.photos = photos; self.engineerSignedAt = engineerSignedAt; self.inspectorAckAt = inspectorAckAt
            self.engineerSignature = engineerSignature; self.inspectorSignature = inspectorSignature
        }
    }

    /// The station picture (A2's site picture) and where each location is on it, as fractions of its size.
    public struct KeyPlan: Sendable {
        public var photo: Photo
        /// Width / height of the picture.
        public var aspect: Double
        public var points: [(name: String, x: Double, y: Double)]
        public init(photo: Photo, aspect: Double, points: [(name: String, x: Double, y: Double)]) {
            self.photo = photo; self.aspect = aspect; self.points = points
        }
    }

    /// The MP plan, when the station has one.
    public struct Schedule: Sendable {
        public var input: MasterSchedule.Input
        public var actual: MasterSchedule.Actual
        public init(input: MasterSchedule.Input, actual: MasterSchedule.Actual) { self.input = input; self.actual = actual }
    }

    let station: Station
    let measure: TextMeasuring

    public init(station: Station, measure: TextMeasuring = ApproxMeasure()) {
        self.station = station; self.measure = measure
    }

    static let pageW = ReportLayout.pageW, pageH = ReportLayout.pageH
    static let margin = 32.0
    static var cw: Double { pageW - 2 * margin }
    static let navy = RGBA(hex: 0x16325C), primary = RGBA(hex: 0x1F6FB5), muted = RGBA(hex: 0x6B7A90)
    static let soft = RGBA(hex: 0xE3EEF8), line = RGBA(hex: 0xC9D3DF), red = RGBA(hex: 0xB42318), green = RGBA(hex: 0x2E7D32)
    static let sun = RGBA(hex: 0xFCE7A6), cloud = RGBA(hex: 0xD5DCE5), rain = RGBA(hex: 0x9CC3E8)

    // MARK: - Flow

    /// Places blocks down the page and starts a new page when one doesn't fit.
    struct Flow {
        let title: String
        let subtitle: String
        var pages: [[DrawOp]] = []
        var ops: [DrawOp] = []
        var y = 0.0
        var bottom: Double { RoutineReportPages.pageH - RoutineReportPages.margin - 20 }

        init(title: String, subtitle: String) {
            self.title = title; self.subtitle = subtitle
            newPage()
        }

        mutating func newPage() {
            if !ops.isEmpty { pages.append(ops) }
            let m = RoutineReportPages.margin
            ops = [.text(title, at: Pt(m, m + 8), size: 15, bold: true, color: RoutineReportPages.navy),
                   .text(subtitle, at: Pt(m, m + 26), size: 9.5, color: RoutineReportPages.muted),
                   .line(Pt(m, m + 38), Pt(RoutineReportPages.pageW - m, m + 38), width: 1.2, color: RoutineReportPages.primary)]
            y = m + 50
        }

        /// Starts a new page unless `h` fits below the cursor.
        mutating func need(_ h: Double) { if y + h > bottom, y > RoutineReportPages.margin + 50 { newPage() } }

        /// Appends ops drawn from y = 0 and moves the cursor by `h`.
        mutating func place(_ h: Double, _ block: [DrawOp]) {
            need(h)
            ops += block.map { $0.offsetY(y) }
            y += h
        }

        mutating func finish() -> [ReportLayout.Page] {
            pages.append(ops); ops = []
            let n = pages.count, m = RoutineReportPages.margin
            return pages.enumerated().map { i, p in
                ReportLayout.Page(ops: p + [
                    .text("สร้างจาก TCRoof", at: Pt(m, RoutineReportPages.pageH - m + 4), size: 7.5, color: RoutineReportPages.muted),
                    .text("หน้า \(i + 1)/\(n)", at: Pt(RoutineReportPages.pageW - m, RoutineReportPages.pageH - m + 4), size: 7.5,
                          color: RoutineReportPages.muted, align: .right),
                ])
            }
        }
    }

    // MARK: - Blocks

    struct Column { var title: String; var width: Double; var align: TextAlign = .left }

    func heading(_ f: inout Flow, _ text: String) {
        f.need(60)
        f.place(22, [.rect(Box(Self.margin, 2, Self.cw, 17), stroke: nil, fill: Self.soft),
                     .text(text, at: Pt(Self.margin + 6, 10.5), size: 10.5, bold: true, color: Self.navy)])
    }

    func note(_ f: inout Flow, _ text: String, color: RGBA = muted) {
        let h = measure.height(text, width: Self.cw - 12, size: 9, bold: false) + 6
        f.place(h, [.textBox(text, Box(Self.margin + 6, 2, Self.cw - 12, h), size: 9, color: color)])
    }

    /// A table: header band, then rows tall enough for their wrapped text. Long tables continue on the next page with
    /// the header repeated.
    func table(_ f: inout Flow, _ cols: [Column], _ rows: [[String]], bold: Set<Int> = [], size: Double = 9) {
        let total = cols.reduce(0) { $0 + $1.width }, k = Self.cw / max(total, 1)
        let widths = cols.map { $0.width * k }
        let xs = widths.indices.map { i in Self.margin + widths[..<i].reduce(0, +) }
        func row(_ cells: [String], header: Bool, h: Double) -> [DrawOp] {
            var o: [DrawOp] = [.rect(Box(Self.margin, 0, Self.cw, h), stroke: Self.line, fill: header ? Self.soft : nil, width: 0.6)]
            for (i, c) in cells.enumerated() where i < cols.count {
                if i > 0 { o.append(.line(Pt(xs[i], 0), Pt(xs[i], h), width: 0.6, color: Self.line)) }
                o.append(.textBox(c, Box(xs[i] + 3, 3, widths[i] - 6, h - 4), size: size, bold: header,
                                  color: header ? Self.navy : .black, align: header ? .center : cols[i].align))
            }
            return o
        }
        let headH = cols.enumerated().map { i, c in measure.height(c.title, width: widths[i] - 6, size: size, bold: true) }.max().map { $0 + 6 } ?? 16
        f.need(headH + 18)
        f.place(headH, row(cols.map(\.title), header: true, h: headH))
        for (r, cells) in rows.enumerated() {
            let h = max(16, cells.enumerated().map { i, c in
                i < widths.count ? measure.height(c, width: widths[i] - 6, size: size, bold: bold.contains(r)) : 0 }.max() ?? 0) + 8
            if f.y + h > f.bottom {
                f.newPage()
                f.place(headH, row(cols.map(\.title), header: true, h: headH))
            }
            var o = row(cells, header: false, h: h)
            if bold.contains(r) {
                o = o.map { if case let .textBox(t, b, s, _, c, a) = $0 { .textBox(t, b, size: s, bold: true, color: c, align: a) } else { $0 } }
            }
            f.place(h, o)
        }
        f.y += 6
    }

    /// Two-column facts: "label  value" pairs.
    func facts(_ f: inout Flow, _ pairs: [(String, String)]) {
        let colW = Self.cw / 2
        for chunk in stride(from: 0, to: pairs.count, by: 2) {
            let two = Array(pairs[chunk..<min(chunk + 2, pairs.count)])
            let h = two.map { measure.height($0.1, width: colW - 96, size: 9, bold: false) }.max().map { max($0 + 4, 15) } ?? 15
            var o: [DrawOp] = []
            for (i, p) in two.enumerated() {
                let x = Self.margin + Double(i) * colW
                o.append(.text(p.0, at: Pt(x, 7), size: 9, color: Self.muted))
                o.append(.textBox(p.1, Box(x + 92, 0, colW - 96, h), size: 9, bold: true, color: .black))
            }
            f.place(h, o)
        }
        f.y += 6
    }

    /// The weather strip: one row per day, 15 hour cells coloured F / C / R.
    func weather(_ f: inout Flow, _ days: [(String, [RoutineReport.Weather?])]) {
        let labelW = 70.0, cell = (Self.cw - labelW) / Double(RoutineReport.weatherHours.count), rowH = 16.0
        var o: [DrawOp] = []
        for (i, h) in RoutineReport.weatherHours.enumerated() {
            o.append(.text(String(format: "%02d", h), at: Pt(Self.margin + labelW + (Double(i) + 0.5) * cell, 7), size: 8,
                           color: Self.muted, align: .center))
        }
        f.place(14, o)
        for (label, slots) in days {
            var r: [DrawOp] = [.text(label, at: Pt(Self.margin, rowH / 2), size: 8.5, color: .black)]
            for (i, w) in slots.enumerated() {
                let b = Box(Self.margin + labelW + Double(i) * cell, 0, cell, rowH)
                let fill: RGBA? = switch w { case .fine?: Self.sun; case .cloudy?: Self.cloud; case .rain?: Self.rain; case nil: nil }
                r.append(.rect(b, stroke: Self.line, fill: fill, width: 0.5))
                if let w { r.append(.text(w.rawValue, at: Pt(b.x + cell / 2, rowH / 2), size: 8, bold: true, color: Self.navy, align: .center)) }
            }
            f.place(rowH, r)
        }
        f.place(16, [.text("F = ท้องฟ้าโปร่ง   C = เมฆครึ้ม   R = ฝนตก", at: Pt(Self.margin, 9), size: 8, color: Self.muted)])
    }

    /// Photos two per row with a caption under each.
    func photos(_ f: inout Flow, _ list: [DayPhoto], perRow: Int = 2, height: Double = 170) {
        let gap = 10.0, w = (Self.cw - gap * Double(perRow - 1)) / Double(perRow)
        for chunk in stride(from: 0, to: list.count, by: perRow) {
            var o: [DrawOp] = []
            for (i, p) in list[chunk..<min(chunk + perRow, list.count)].enumerated() {
                let x = Self.margin + Double(i) * (w + gap)
                o.append(.rect(Box(x, 0, w, height), stroke: Self.line, fill: nil, width: 0.5))
                o.append(.photo(p.photo, Box(x + 2, 2, w - 4, height - 4)))
                o.append(.textBox(p.caption.isEmpty ? RoutineReport.thaiDate(p.date) : p.caption,
                                  Box(x, height + 2, w, 24), size: 8.5, color: Self.navy, align: .center))
            }
            f.place(height + 30, o)
        }
    }

    /// Signature boxes side by side: role, name, and the date signed (or a blank line).
    /// The signature lines, each with its name and role; a drawn signature (`drawn`, by box) sits on its line, with the
    /// date under the role, else the date stands over the line.
    func signatures(_ f: inout Flow, _ boxes: [(role: String, name: String, signed: Date?, verb: String)], drawn: [Photo?] = []) {
        let w = Self.cw / Double(max(boxes.count, 1))
        var o: [DrawOp] = []
        let anyDrawn = drawn.contains { $0 != nil }
        for (i, s) in boxes.enumerated() {
            let cx = Self.margin + w * (Double(i) + 0.5)
            let image = drawn.indices.contains(i) ? drawn[i] : nil
            o.append(.line(Pt(cx - 80, 30), Pt(cx + 80, 30), width: 0.6, color: .black))
            if let image { o.append(.photo(image, Box(cx - 60, 2, 120, 27))) }
            if let d = s.signed {
                o.append(.text("\(s.verb) \(RoutineReport.thaiDate(d))", at: Pt(cx, image == nil ? 20 : 69), size: 9, bold: true, color: Self.green, align: .center))
            }
            o.append(.text("(\(s.name.isEmpty ? "                              " : s.name))", at: Pt(cx, 42), size: 9, align: .center))
            o.append(.text(s.role, at: Pt(cx, 56), size: 9, color: Self.muted, align: .center))
        }
        f.need(anyDrawn ? 92 : 80)
        f.y += 10
        f.place(anyDrawn ? 78 : 66, o)
    }

    var stationLine: String {
        [station.mpNumber.map { "MP \($0)" }, station.name, station.capacityKWp > 0 ? String(format: "%.2f kWp", station.capacityKWp) : nil]
            .compactMap { $0 }.joined(separator: " | ")
    }

    func projectFacts(_ f: inout Flow) {
        let s = station.settings
        facts(&f, [("โครงการ", s.contractName.isEmpty ? station.name : s.contractName), ("สถานี", station.name),
                   ("ผู้ว่าจ้าง", s.employer), ("ผู้รับจ้าง", s.contractor)])
    }

    static func counts(_ list: [RoutineReport.Count]) -> [[String]] {
        list.filter { $0.count > 0 }.map { [$0.name, "\($0.count)"] }
    }

    static func num(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%.2f", x)
    }

    // MARK: - R2 daily

    /// รายงานประจำวัน in the customer's DAILY REPORT form (`dailyForm`). `all` holds every report of the station, for the
    /// Today column.
    public func daily(_ e: DailyEntry, all: [RoutineReport.Daily], keyPlan: KeyPlan? = nil) -> [ReportLayout.Page] {
        dailyForm(e, all: all, keyPlan: keyPlan)
    }

    // MARK: - R1 weekly request

    /// R1, in the customer's WORK REQUEST form (`requestForm`, docs/ui/weekly-request-pdf). `signature` is the
    /// requester's drawn signature, on the Site Engineer's line.
    public func request(_ r: RoutineReport.WeeklyRequest, signature: Photo? = nil) -> [ReportLayout.Page] {
        requestForm(r, signature: signature)
    }

    /// Minutes after midnight as `08:00`.
    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    // MARK: - R3 weekly

    /// รายงานประจำสัปดาห์ of the week holding `week`, from that week's daily reports.
    public func weekly(week: Date, entries: [DailyEntry], all: [RoutineReport.Daily], schedule: Schedule?,
                       nextRequest: RoutineReport.WeeklyRequest?, installStart: Date?, asOf: Date = Date()) -> [ReportLayout.Page] {
        let range = RoutineReport.week(of: week)
        let days = entries.filter { range.contains(RoutineReport.calendar.startOfDay(for: $0.report.date)) }
            .sorted { $0.report.date < $1.report.date }
        let reports = days.map(\.report)
        let rangeText = "\(RoutineReport.thaiDate(range.lowerBound)) – \(RoutineReport.thaiDate(range.upperBound))"
        var weekNo = ""
        if let schedule {
            let plan = MasterSchedule.plan(schedule.input)
            let first = plan.compactMap(\.start).min() ?? range.lowerBound
            if let i = MasterSchedule.weeks(from: first, to: range.lowerBound).firstIndex(of: range.lowerBound) { weekNo = "สัปดาห์ที่ \(i + 1) | " }
        }
        var f = Flow(title: "รายงานประจำสัปดาห์ (Weekly Report)", subtitle: stationLine + " | " + weekNo + rangeText)
        projectFacts(&f)
        facts(&f, [("สัปดาห์", weekNo + rangeText), ("รายงานประจำวัน", "\(reports.count) วัน")])

        if let schedule { progressSummary(&f, schedule, through: min(range.upperBound, asOf), monthOf: nil) }

        heading(&f, "งานที่ทำในสัปดาห์")
        if days.isEmpty { note(&f, "ไม่มีรายงานประจำวันในสัปดาห์นี้") }
        for e in days {
            let done = RoutineReport.workDone(e.report, in: all)
            let text = done.isEmpty
                ? (e.report.stopReason.isEmpty ? "ไม่มีความก้าวหน้า" : "หยุดงาน: " + e.report.stopReason)
                : done.map { "• \($0.line.title)  +\(RoutineReport.percent($0.delta)) (สะสม \(RoutineReport.percent($0.line.percent)))" }.joined(separator: "\n")
            let h = measure.height(text, width: Self.cw - 100, size: 9, bold: false) + 8
            f.place(max(h, 18), [.text(RoutineReport.thaiDate(e.report.date), at: Pt(Self.margin, 8), size: 9.5, bold: true, color: Self.navy),
                                 .textBox(text, Box(Self.margin + 96, 1, Self.cw - 100, h), size: 9)])
            let tagged = e.photos.filter { !$0.caption.isEmpty }
            let pick = Array((tagged.isEmpty ? e.photos : tagged).prefix(4))
            if !pick.isEmpty { photos(&f, pick, perRow: 4, height: 100) }
        }

        heading(&f, "สภาพอากาศ")
        weather(&f, RoutineReport.workingDays(settings: .allDays, from: range.lowerBound, to: range.upperBound).map { d in
            (RoutineReport.thaiDate(d), reports.first { RoutineReport.dayKey($0.date) == RoutineReport.dayKey(d) }?.weather
                ?? Array(repeating: nil, count: RoutineReport.weatherHours.count))
        })
        note(&f, "ฝนตกรวม \(RoutineReport.rainHours(reports)) ชั่วโมง ใน \(RoutineReport.rainDays(reports)) วัน")

        labour(&f, reports)
        problemsBlock(&f, reports)
        missing(&f, reports, from: max(range.lowerBound, installStart ?? range.lowerBound), to: min(range.upperBound, Date()))

        heading(&f, "แผนงานสัปดาห์ถัดไป")
        if let n = nextRequest, !n.work.isEmpty {
            table(&f, [Column(title: "งาน MP", width: 0.9, align: .center), Column(title: "รายละเอียด", width: 4), Column(title: "ตำแหน่ง", width: 2)],
                  n.work.map { [$0.task?.code ?? "อื่น", $0.description, $0.location] })
        } else { note(&f, "ยังไม่มีคำขอปฏิบัติงานสัปดาห์ถัดไป") }

        signatures(&f, [("Site Engineer", station.settings.siteEngineer, nil, ""), ("Inspector", station.settings.inspector, nil, "")])
        return f.finish()
    }

    /// Plan vs actual: whole station, then by task (only tasks with weight). `date` is clamped to today by the callers, so a
    /// report of the running week or month doesn't count plan that is still to come against the actual done so far.
    func progressSummary(_ f: inout Flow, _ s: Schedule, through date: Date, monthOf: Date?) {
        let plan = MasterSchedule.plan(s.input)
        let st = MasterSchedule.status(plan: plan, actual: s.actual, through: date)
        heading(&f, "ความก้าวหน้าตามแผน MP")
        let v = st.variance
        facts(&f, [("แผนสะสม", RoutineReport.percent(st.planned)), ("ทำได้สะสม", RoutineReport.percent(st.actual)),
                   ("ผลต่าง", v < -0.05 ? "ช้ากว่าแผน " + RoutineReport.percent(-v) : v > 0.05 ? "เร็วกว่าแผน " + RoutineReport.percent(v) : "ตามแผน")])
        if let m = monthOf {
            let c = MasterSchedule.calendar.dateComponents([.year, .month], from: m)
            let mo = MasterSchedule.month(plan: plan, actual: s.actual, year: c.year ?? 0, month: c.month ?? 0)
            facts(&f, [("แผนเดือนนี้", RoutineReport.percent(mo.planned.values.reduce(0, +))),
                       ("ทำได้เดือนนี้", RoutineReport.percent(mo.actual.values.reduce(0, +)))])
        }
        let rows = plan.filter { $0.weight > 0 }.map { p in
            [p.task.code, p.task.title, RoutineReport.percent(p.weight),
             RoutineReport.percent(st.plannedByTask[p.task] ?? 0), RoutineReport.percent(st.actualByTask[p.task] ?? 0)]
        }
        table(&f, [Column(title: "ข้อ", width: 0.6, align: .center), Column(title: "งาน", width: 5), Column(title: "น้ำหนัก", width: 0.9, align: .right),
                   Column(title: "แผน", width: 0.9, align: .right), Column(title: "ทำได้", width: 0.9, align: .right)], rows, size: 8.5)
    }

    func labour(_ f: inout Flow, _ reports: [RoutineReport.Daily]) {
        heading(&f, "แรงงานและเครื่องมือ")
        let men = RoutineReport.manDays(reports), tools = RoutineReport.toolDays(reports)
        if men.isEmpty { note(&f, "ไม่มี") } else {
            table(&f, [Column(title: "ตำแหน่ง", width: 4), Column(title: "แรงงาน (คน-วัน)", width: 1.6, align: .center)],
                  men.map { [$0.name, "\($0.days)"] } + [["รวม", "\(men.reduce(0) { $0 + $1.days })"]], bold: [men.count])
        }
        if !tools.isEmpty {
            table(&f, [Column(title: "เครื่องมือ", width: 4), Column(title: "เครื่อง-วัน", width: 1.6, align: .center)], tools.map { [$0.name, "\($0.days)"] })
        }
        let unconfirmed = reports.filter { !$0.crewConfirmed && $0.crewTotal > 0 }.count
        if unconfirmed > 0 { note(&f, "* \(unconfirmed) วันใช้กำลังคนจากวันก่อนโดยไม่ได้ยืนยัน", color: Self.red) }
    }

    func problemsBlock(_ f: inout Flow, _ reports: [RoutineReport.Daily]) {
        heading(&f, "ปัญหา / อุปสรรค")
        let p = RoutineReport.problems(reports)
        if p.open.isEmpty, p.closed.isEmpty { note(&f, "ไม่มี"); return }
        table(&f, [Column(title: "ปัญหา", width: 3), Column(title: "แนวทางแก้ไข", width: 3), Column(title: "สถานะ", width: 1, align: .center)],
              p.open.map { [$0.description, $0.solution, "ยังเปิด"] } + p.closed.map { [$0.description, $0.solution, "ปิดแล้ว"] })
    }

    func missing(_ f: inout Flow, _ reports: [RoutineReport.Daily], from: Date, to: Date) {
        guard from <= to else { return }
        let m = RoutineReport.missingDays(reported: reports.map(\.date), settings: station.settings, from: from, to: to)
        guard !m.isEmpty else { return }
        note(&f, "วันทำงานที่ไม่มีรายงานประจำวัน: " + m.map(RoutineReport.thaiDate).joined(separator: ", "), color: Self.red)
    }

    // MARK: - R4 monthly

    /// รายงานผลความก้าวหน้าประจำเดือน of the month holding `month`; titled ติดตั้งแล้วเสร็จ once the MP actual is 100 %.
    public func monthly(month: Date, entries: [DailyEntry], all: [RoutineReport.Daily], schedule: Schedule?,
                        installStart: Date?, asOf: Date = Date()) -> [ReportLayout.Page] {
        let range = RoutineReport.month(of: month)
        let days = entries.filter { range.contains(RoutineReport.calendar.startOfDay(for: $0.report.date)) }
            .sorted { $0.report.date < $1.report.date }
        let reports = days.map(\.report)
        let plan = schedule.map { MasterSchedule.plan($0.input) }
        let done = schedule.flatMap { s in plan.map { MasterSchedule.status(plan: $0, actual: s.actual, through: range.upperBound).actual } } ?? 0
        let title = done >= 99.95 ? "รายงานผลการติดตั้งแล้วเสร็จ 100%" : "รายงานผลความก้าวหน้าประจำเดือน"
        var f = Flow(title: title, subtitle: stationLine + " | ประจำเดือน " + RoutineReport.thaiMonth(range.lowerBound))

        heading(&f, "ส่วนที่ 1 รายละเอียดโครงการ")
        projectFacts(&f)
        facts(&f, [("กำลังผลิต", station.capacityKWp > 0 ? String(format: "%.2f kWp", station.capacityKWp) : "-"),
                   ("ประจำเดือน", RoutineReport.thaiMonth(range.lowerBound)),
                   ("Site Engineer", station.settings.siteEngineer), ("Inspector", station.settings.inspector)])

        f.need(200)
        f.place(4, [])
        heading(&f, "ส่วนที่ 2 ความก้าวหน้า")
        if let schedule { progressSummary(&f, schedule, through: min(range.upperBound, asOf), monthOf: range.lowerBound) }
        else { note(&f, "สถานีนี้ยังไม่มีแผน MP") }
        if let schedule, let plan {
            heading(&f, "สถานะการยื่นขออนุญาต")
            let rows = RoutineReport.permits(plan: plan, actual: schedule.actual, at: range.upperBound)
            table(&f, [Column(title: "ข้อ", width: 0.6, align: .center), Column(title: "เรื่อง", width: 3.8),
                       Column(title: "ช่วงตามแผน", width: 2.2, align: .center), Column(title: "ทำได้", width: 0.8, align: .right),
                       Column(title: "สถานะ", width: 1.4, align: .center)],
                  rows.map { r in
                      let span = r.start.flatMap { s in r.end.map { e in "\(RoutineReport.thaiDate(s)) – \(RoutineReport.thaiDate(e))" } } ?? "-"
                      return [r.task.code, r.task.title, span, RoutineReport.percent(r.percent), r.state.title]
                  }, size: 8.5)
        }
        let photosPick = days.flatMap { $0.photos.filter { !$0.caption.isEmpty } }
        let chosen = Array((photosPick.isEmpty ? days.flatMap(\.photos) : photosPick).prefix(8))
        if !chosen.isEmpty {
            heading(&f, "ภาพความก้าวหน้า")
            photos(&f, chosen, perRow: 2, height: 150)
        }

        heading(&f, "ส่วนที่ 3 แผนงานเดือนถัดไป")
        if let plan, let schedule {
            let next = RoutineReport.month(of: RoutineReport.calendar.date(byAdding: .day, value: 1, to: range.upperBound)!)
            let rows = plan.filter { p in
                guard p.weight > 0, let s = p.start, let e = p.end else { return false }
                return s <= next.upperBound && e >= next.lowerBound && schedule.actual.done(p.task, through: range.upperBound) < p.weight - 1e-9
            }.map { [$0.task.code, $0.task.title, "\(RoutineReport.thaiDate($0.start!)) – \(RoutineReport.thaiDate($0.end!))"] }
            if rows.isEmpty { note(&f, "ไม่มีงานตามแผน") } else {
                table(&f, [Column(title: "ข้อ", width: 0.6, align: .center), Column(title: "งาน", width: 4.5), Column(title: "ช่วงตามแผน", width: 2.2, align: .center)], rows)
            }
        } else { note(&f, "สถานีนี้ยังไม่มีแผน MP") }

        heading(&f, "ส่วนที่ 4 สรุปแรงงาน")
        let weeks = MasterSchedule.weeks(from: range.lowerBound, to: range.upperBound)
        let roles = RoutineReport.manDays(reports).map(\.name)
        if roles.isEmpty { note(&f, "ไม่มีรายงานประจำวันในเดือนนี้") } else {
            let cols = [Column(title: "ตำแหน่ง", width: 2.6)] + weeks.map { w in
                let end = min(RoutineReport.calendar.date(byAdding: .day, value: 6, to: w)!, range.upperBound)
                return Column(title: "\(RoutineReport.calendar.component(.day, from: max(w, range.lowerBound)))–\(RoutineReport.calendar.component(.day, from: end))",
                              width: 0.8, align: .center)
            } + [Column(title: "รวม", width: 0.8, align: .center)]
            var rows: [[String]] = roles.map { role in
                let per = weeks.map { w in
                    reports.filter { MasterSchedule.weekStart($0.date) == w }.flatMap(\.crew).filter { $0.name == role }.reduce(0) { $0 + $1.count }
                }
                return [role] + per.map(String.init) + ["\(per.reduce(0, +))"]
            }
            let totals = weeks.map { w in reports.filter { MasterSchedule.weekStart($0.date) == w }.reduce(0) { $0 + $1.crewTotal } }
            rows.append(["รวม"] + totals.map(String.init) + ["\(totals.reduce(0, +))"])
            table(&f, cols, rows, bold: [rows.count - 1], size: 8.5)
        }
        note(&f, "รายงานประจำวัน \(reports.count) วัน | ฝนตกรวม \(RoutineReport.rainHours(reports)) ชั่วโมง ใน \(RoutineReport.rainDays(reports)) วัน")
        missing(&f, reports, from: max(range.lowerBound, installStart ?? range.lowerBound), to: min(range.upperBound, Date()))
        problemsBlock(&f, reports)

        signatures(&f, [("Site Engineer", station.settings.siteEngineer, nil, ""), ("ผู้รับจ้าง", "", nil, "")])
        return f.finish()
    }
}

extension RoutineReport.Settings {
    /// Every day of the week counts, for tables that list all seven days.
    static var allDays: Self { var s = Self(); s.workingWeekdays = Set(1...7); return s }
}

extension DrawOp {
    /// The same op moved down by `dy`.
    func offsetY(_ dy: Double) -> DrawOp {
        func p(_ a: Pt) -> Pt { Pt(a.x, a.y + dy) }
        func b(_ r: Box) -> Box { r.offset(0, dy) }
        switch self {
        case let .line(a, c, w, col, dash): return .line(p(a), p(c), width: w, color: col, dash: dash)
        case let .rect(r, s, f, w): return .rect(b(r), stroke: s, fill: f, width: w)
        case let .hatch(r, c, sp): return .hatch(b(r), color: c, spacing: sp)
        case let .circle(c, r, s, f, w): return .circle(p(c), r: r, stroke: s, fill: f, width: w)
        case let .polygon(ps, s, f, w): return .polygon(ps.map(p), stroke: s, fill: f, width: w)
        case let .polyline(ps, w, col, dash): return .polyline(ps.map(p), width: w, color: col, dash: dash)
        case let .text(t, at, sz, bold, col, al, ang): return .text(t, at: p(at), size: sz, bold: bold, color: col, align: al, angle: ang)
        case let .textBox(t, r, sz, bold, col, al): return .textBox(t, b(r), size: sz, bold: bold, color: col, align: al)
        case let .photo(ph, r): return .photo(ph, b(r))
        case let .photoFill(ph, r): return .photoFill(ph, b(r))
        case let .runs(rs, at, col, al): return .runs(rs, at: p(at), color: col, align: al)
        case let .checkbox(r, on): return .checkbox(b(r), on: on)
        }
    }
}
