import Foundation
import TCRoofCore

/// รายงานประจำสัปดาห์ R3 as PowerPoint for the weekly meeting (docs/specs/routine-reports-swift.md §4.4): the same content
/// as the PDF (`RoutineReportPages.weekly`), 16:9, every text and table editable. Slides: the cover, the MP progress, one
/// slide per daily report with its work and up to 4 photos, the weather, labour and tools, problems (with the working
/// days that have no report), and next week's plan. Long tables continue on another slide.
///
/// Built on `Resources/weekly_template.pptx` (the master, the blank layout and a theme in TH Sarabun New); this adds the
/// slides, their pictures and the entries that list them.
public enum WeeklySlides {
    public enum Failure: Error, Equatable { case template }

    /// A photo of the day: the id `images` holds its bytes under, its pixel size and what it shows.
    public struct DayPhoto: Sendable {
        public var id: UUID
        public var width: Int
        public var height: Int
        public var caption: String
        public init(id: UUID, width: Int, height: Int, caption: String) {
            self.id = id; self.width = width; self.height = height; self.caption = caption
        }
    }

    public struct Day: Sendable {
        public var report: RoutineReport.Daily
        public var photos: [DayPhoto]
        public init(report: RoutineReport.Daily, photos: [DayPhoto]) { self.report = report; self.photos = photos }
    }

    public struct Input: Sendable {
        public var stationName: String
        public var mpNumber: Int?
        public var capacityKWp: Double
        public var settings: RoutineReport.Settings
        /// Any day of the week.
        public var week: Date
        /// The station's daily reports with their photos; the week's are taken.
        public var days: [Day]
        /// Every report of the station, for the "วันนี้" deltas.
        public var all: [RoutineReport.Daily]
        public var schedule: (input: MasterSchedule.Input, actual: MasterSchedule.Actual)?
        public var nextRequest: RoutineReport.WeeklyRequest?
        public var installStart: Date?
        public var asOf: Date

        public init(stationName: String, mpNumber: Int?, capacityKWp: Double, settings: RoutineReport.Settings, week: Date,
                    days: [Day], all: [RoutineReport.Daily], schedule: (input: MasterSchedule.Input, actual: MasterSchedule.Actual)?,
                    nextRequest: RoutineReport.WeeklyRequest?, installStart: Date?, asOf: Date = Date()) {
            self.stationName = stationName; self.mpNumber = mpNumber; self.capacityKWp = capacityKWp; self.settings = settings
            self.week = week; self.days = days; self.all = all; self.schedule = schedule; self.nextRequest = nextRequest
            self.installStart = installStart; self.asOf = asOf
        }
    }

    /// `2568-07-06 รายงานประจำสัปดาห์ <สถานี>.pptx`, the PDF's name with its own extension.
    public static func fileName(week: Date, station: String) -> String {
        let pdf = RoutineReport.fileName(.weekly, date: MasterSchedule.weekStart(week), station: station)
        return String(pdf.dropLast(4)) + ".pptx"
    }

    /// The deck; `images` holds each photo's JPEG or PNG bytes by its id (a photo without them is left out).
    public static func export(_ input: Input, images: [UUID: Data]) throws -> Data {
        guard let url = Bundle.module.url(forResource: "weekly_template", withExtension: "pptx")
                ?? Bundle.module.url(forResource: "weekly_template", withExtension: "pptx", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), var zip = try? ZipArchive(data) else { throw Failure.template }
        let deck = Deck(input, images: images)
        try package(&zip, deck.slides(), subtitle: deck.subtitle)
        return try zip.write()
    }

    // MARK: - Content

    struct Deck {
        let input: Input
        let images: [UUID: Data]
        let range: ClosedRange<Date>
        let days: [Day]
        let reports: [RoutineReport.Daily]
        let subtitle: String

        init(_ input: Input, images: [UUID: Data]) {
            self.input = input; self.images = images
            let range = RoutineReport.week(of: input.week)
            let cal = RoutineReport.calendar
            self.range = range
            days = input.days.filter { range.contains(cal.startOfDay(for: $0.report.date)) }.sorted { $0.report.date < $1.report.date }
            reports = days.map(\.report)
            var weekNo = ""
            if let s = input.schedule {
                let first = MasterSchedule.plan(s.input).compactMap(\.start).min() ?? range.lowerBound
                if let i = MasterSchedule.weeks(from: first, to: range.lowerBound).firstIndex(of: range.lowerBound) { weekNo = "สัปดาห์ที่ \(i + 1) | " }
            }
            let station = [input.mpNumber.map { "MP \($0)" }, input.stationName,
                           input.capacityKWp > 0 ? String(format: "%.2f kWp", input.capacityKWp) : nil].compactMap { $0 }.joined(separator: " | ")
            subtitle = station + " | " + weekNo + RoutineReport.thaiDate(range.lowerBound) + " – " + RoutineReport.thaiDate(range.upperBound)
        }

        func slides() -> [Slide] {
            var out = [cover()]
            out += progress()
            out += days.map(day)
            out.append(weather())
            out += labour()
            out += problems()
            out += nextWeek()
            return out
        }

        func cover() -> Slide {
            var s = Slide(title: nil)
            s.rect(0, 0, W, 2.6, fill: navy)
            s.text(M, 0.7, W - 2 * M, 0.9, ["รายงานประจำสัปดาห์ (Weekly Report)"], size: 44, bold: true, color: white)
            s.text(M, 1.55, W - 2 * M, 0.6, [subtitle], size: 22, color: white)
            let set = input.settings
            let rows = [["โครงการ", set.contractName.isEmpty ? input.stationName : set.contractName], ["สถานี", input.stationName],
                        ["ผู้ว่าจ้าง", set.employer], ["ผู้รับจ้าง", set.contractor], ["รายงานประจำวัน", "\(reports.count) วัน"]]
            s.table(M, 3.1, widths: [2.6, 9.7], rows: rows, size: 18, rowH: 0.5, header: false,
                    fills: rows.map { _ in [soft, nil] })
            return s
        }

        func progress() -> [Slide] {
            guard let sch = input.schedule else { return [] }
            let plan = MasterSchedule.plan(sch.input)
            let st = MasterSchedule.status(plan: plan, actual: sch.actual, through: min(range.upperBound, input.asOf))
            let v = st.variance
            let gap = v < -0.05 ? "ช้ากว่าแผน " + RoutineReport.percent(-v) : v > 0.05 ? "เร็วกว่าแผน " + RoutineReport.percent(v) : "ตามแผน"
            let rows = plan.filter { $0.weight > 0 }.map { p in
                [p.task.code, p.task.title, RoutineReport.percent(p.weight),
                 RoutineReport.percent(st.plannedByTask[p.task] ?? 0), RoutineReport.percent(st.actualByTask[p.task] ?? 0)]
            }
            return Self.chunks(rows, 14).enumerated().map { i, part in
                var s = Slide(title: "ความก้าวหน้าตามแผน MP" + (i > 0 ? " (ต่อ)" : ""))
                let figures: [(String, String, String)] = [("แผนสะสม", RoutineReport.percent(st.planned), navy),
                                                           ("ทำได้สะสม", RoutineReport.percent(st.actual), navy),
                                                           ("ผลต่าง", gap, v < -0.05 ? red : v > 0.05 ? green : navy)]
                for (k, f) in figures.enumerated() {
                    s.text(M, 1.6 + Double(k) * 1.15, 3.3, 0.4, [f.0], size: 18, color: muted)
                    s.text(M, 1.95 + Double(k) * 1.15, 3.3, 0.7, [f.1], size: k < 2 ? 32 : 24, bold: true, color: f.2)
                }
                s.table(4.2, 1.6, widths: [0.8, 5.1, 0.9, 0.9, 0.9], rows: [["ข้อ", "งาน", "น้ำหนัก", "แผน", "ทำได้"]] + part,
                        size: 14, rowH: 0.35, aligns: ["ctr", "l", "r", "r", "r"])
                return s
            }
        }

        func day(_ d: Day) -> Slide {
            let r = d.report
            var s = Slide(title: "งานวันที่ " + RoutineReport.thaiDate(r.date))
            let done = RoutineReport.workDone(r, in: input.all)
            let lines = done.isEmpty
                ? [r.stopReason.isEmpty ? "ไม่มีความก้าวหน้า" : "หยุดงาน: " + r.stopReason]
                : done.map { "• \($0.line.title)  +\(RoutineReport.percent($0.delta)) (สะสม \(RoutineReport.percent($0.line.percent)))" }
            // only pictures PowerPoint can show: a JPEG or PNG whose size can be read
            let usable = d.photos.filter { p in images[p.id].flatMap { IECWord.pixelSize($0) } != nil }
            let tagged = usable.filter { !$0.caption.isEmpty }
            let pick = Array((tagged.isEmpty ? usable : tagged).prefix(4))
            s.text(M, 1.6, pick.isEmpty ? W - 2 * M : 4.6, 5.2, lines, size: 18)
            for (k, p) in pick.enumerated() {
                let x = 5.4 + Double(k % 2) * 3.75, y = 1.6 + Double(k / 2) * 2.7
                guard let bytes = images[p.id] else { continue }
                s.rect(x, y, 3.6, 2.25, fill: photoBack)
                s.picture(x, y, 3.6, 2.25, data: bytes, pixels: (p.width, p.height), descr: p.caption)
                s.text(x, y + 2.27, 3.6, 0.38, [p.caption.isEmpty ? RoutineReport.thaiDate(r.date) : p.caption],
                       size: 14, color: navy, align: "ctr")
            }
            return s
        }

        func weather() -> Slide {
            var s = Slide(title: "สภาพอากาศ")
            let cal = RoutineReport.calendar, hours = RoutineReport.weatherHours
            var rows = [["วัน"] + hours.map { String(format: "%02d", $0) }]
            var fills: [[String?]] = [Array(repeating: nil, count: hours.count + 1)]
            for i in 0..<7 {
                let d = cal.date(byAdding: .day, value: i, to: range.lowerBound)!
                let slots = reports.first { RoutineReport.dayKey($0.date) == RoutineReport.dayKey(d) }?.weather
                    ?? Array(repeating: nil, count: hours.count)
                rows.append([RoutineReport.thaiDate(d)] + hours.indices.map { slots[safe: $0]??.rawValue ?? "" })
                fills.append([nil] + hours.indices.map { i -> String? in
                    switch slots[safe: i] ?? nil { case .fine?: sun; case .cloudy?: cloud; case .rain?: rain; case nil: nil }
                })
            }
            s.table(M, 1.6, widths: [1.8] + Array(repeating: 0.69, count: hours.count), rows: rows, size: 14, rowH: 0.42,
                    fills: fills, aligns: ["l"] + Array(repeating: "ctr", count: hours.count))
            s.text(M, 5.15, W - 2 * M, 0.8, ["F = ท้องฟ้าโปร่ง   C = เมฆครึ้ม   R = ฝนตก",
                                             "ฝนตกรวม \(RoutineReport.rainHours(reports)) ชั่วโมง ใน \(RoutineReport.rainDays(reports)) วัน"],
                   size: 16, color: muted)
            return s
        }

        func labour() -> [Slide] {
            let men = RoutineReport.manDays(reports), tools = RoutineReport.toolDays(reports)
            // typed and split: one long untyped expression can be too slow for the type checker
            let total = men.reduce(0) { $0 + $1.days }
            var menRows: [[String]] = men.map { [$0.name, String($0.days)] }
            if !men.isEmpty { menRows.append(["รวม", String(total)]) }
            let toolRows: [[String]] = tools.map { [$0.name, String($0.days)] }
            let parts = max(Self.chunks(menRows, 10).count, Self.chunks(toolRows, 10).count, 1)
            let unconfirmed = reports.filter { !$0.crewConfirmed && $0.crewTotal > 0 }.count
            return (0..<parts).map { i in
                var s = Slide(title: "แรงงานและเครื่องมือ" + (i > 0 ? " (ต่อ)" : ""))
                if men.isEmpty, tools.isEmpty { s.text(M, 1.6, 6, 0.5, ["ไม่มี"], size: 18, color: muted) }
                if let part = Self.chunks(menRows, 10)[safe: i] {
                    let bold: Set<Int> = i == Self.chunks(menRows, 10).count - 1 ? [part.count] : []
                    s.table(M, 1.6, widths: [4.0, 2.0], rows: [["ตำแหน่ง", "แรงงาน (คน-วัน)"]] + part, size: 16, rowH: 0.42,
                            aligns: ["l", "ctr"], boldRows: bold)
                }
                if let part = Self.chunks(toolRows, 10)[safe: i] {
                    s.table(6.9, 1.6, widths: [4.0, 2.0], rows: [["เครื่องมือ", "เครื่อง-วัน"]] + part, size: 16, rowH: 0.42, aligns: ["l", "ctr"])
                }
                if i == 0, unconfirmed > 0 {
                    s.text(M, 6.45, W - 2 * M, 0.45, ["* \(unconfirmed) วันใช้กำลังคนจากวันก่อนโดยไม่ได้ยืนยัน"], size: 14, color: red)
                }
                return s
            }
        }

        func problems() -> [Slide] {
            let p = RoutineReport.problems(reports)
            let rows = p.open.map { [$0.description, $0.solution, "ยังเปิด"] } + p.closed.map { [$0.description, $0.solution, "ปิดแล้ว"] }
            let from = max(range.lowerBound, input.installStart ?? range.lowerBound), to = min(range.upperBound, input.asOf)
            let missing = from <= to
                ? RoutineReport.missingDays(reported: reports.map(\.date), settings: input.settings, from: from, to: to) : []
            let parts = Self.chunks(rows, 9)
            return (parts.isEmpty ? [[]] : parts).enumerated().map { i, part in
                var s = Slide(title: "ปัญหา / อุปสรรค" + (i > 0 ? " (ต่อ)" : ""))
                if part.isEmpty { s.text(M, 1.6, 6, 0.5, ["ไม่มี"], size: 18, color: muted) } else {
                    s.table(M, 1.6, widths: [4.8, 5.4, 2.1], rows: [["ปัญหา", "แนวทางแก้ไข", "สถานะ"]] + part, size: 16, rowH: 0.45,
                            aligns: ["l", "l", "ctr"])
                }
                if i == 0, !missing.isEmpty {
                    s.text(M, 6.2, W - 2 * M, 0.7, ["วันทำงานที่ไม่มีรายงานประจำวัน: " + missing.map(RoutineReport.thaiDate).joined(separator: ", ")],
                           size: 14, color: red)
                }
                return s
            }
        }

        func nextWeek() -> [Slide] {
            let rows = (input.nextRequest?.work ?? []).map { [$0.task?.code ?? "อื่น", $0.description, $0.location] }
            let parts = Self.chunks(rows, 11)
            return (parts.isEmpty ? [[]] : parts).enumerated().map { i, part in
                var s = Slide(title: "แผนงานสัปดาห์ถัดไป" + (i > 0 ? " (ต่อ)" : ""))
                if part.isEmpty { s.text(M, 1.6, 8, 0.5, ["ยังไม่มีคำขอปฏิบัติงานสัปดาห์ถัดไป"], size: 18, color: muted) } else {
                    s.table(M, 1.6, widths: [1.2, 7.4, 3.7], rows: [["งาน MP", "รายละเอียด", "ตำแหน่ง"]] + part, size: 16, rowH: 0.42,
                            aligns: ["ctr", "l", "l"])
                }
                return s
            }
        }

        static func chunks<T>(_ list: [T], _ n: Int) -> [[T]] {
            stride(from: 0, to: list.count, by: n).map { Array(list[$0..<min($0 + n, list.count)]) }
        }
    }

    // MARK: - Drawing

    /// Slide size and margin in inches; colours as the PDF's.
    static let W = 13.333, H = 7.5, M = 0.5
    static let navy = "16325C", primary = "1F6FB5", muted = "6B7A90", soft = "E3EEF8", line = "C9D3DF"
    static let red = "B42318", green = "2E7D32", sun = "FCE7A6", cloud = "D5DCE5", rain = "9CC3E8"
    static let white = "FFFFFF", photoBack = "F2F4F7", black = "000000"
    static let font = "TH Sarabun New"

    static func emu(_ inches: Double) -> String { String(Int((inches * 914_400).rounded())) }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// One slide's shapes and pictures; the header and footer are added when the deck is packed.
    struct Slide {
        /// nil for the cover, which has its own header.
        var title: String?
        var shapes: [String] = []
        /// Picture bytes and extension, in the order of their relationship ids (rId2…).
        var images: [(data: Data, ext: String)] = []
        var nextID = 2

        init(title: String?) { self.title = title }

        mutating func id() -> Int { defer { nextID += 1 }; return nextID }

        static func run(_ text: String, size: Double, bold: Bool, color: String) -> String {
            "<a:r><a:rPr lang=\"th-TH\" sz=\"\(Int(size * 100))\"\(bold ? " b=\"1\"" : "") dirty=\"0\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill>"
                + "<a:latin typeface=\"\(font)\"/><a:cs typeface=\"\(font)\"/></a:rPr><a:t>\(escape(text))</a:t></a:r>"
        }

        static func paragraphs(_ lines: [String], size: Double, bold: Bool, color: String, align: String) -> String {
            lines.map { line in
                "<a:p><a:pPr algn=\"\(align)\"/>" + (line.isEmpty ? "" : run(line, size: size, bold: bold, color: color))
                    + "<a:endParaRPr lang=\"th-TH\" sz=\"\(Int(size * 100))\"/></a:p>"
            }.joined()
        }

        static func frame(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> String {
            "<a:xfrm><a:off x=\"\(emu(x))\" y=\"\(emu(y))\"/><a:ext cx=\"\(emu(w))\" cy=\"\(emu(h))\"/></a:xfrm>"
        }

        static func solid(_ color: String?) -> String {
            color.map { "<a:solidFill><a:srgbClr val=\"\($0)\"/></a:solidFill>" } ?? "<a:noFill/>"
        }

        mutating func text(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ lines: [String], size: Double, bold: Bool = false,
                           color: String = black, align: String = "l") {
            let i = id()
            shapes.append("<p:sp><p:nvSpPr><p:cNvPr id=\"\(i)\" name=\"Text \(i)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr>"
                + "<p:spPr>\(Self.frame(x, y, w, h))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>"
                + "<p:txBody><a:bodyPr wrap=\"square\" lIns=\"45720\" tIns=\"27432\" rIns=\"45720\" bIns=\"27432\" anchor=\"t\"><a:noAutofit/></a:bodyPr><a:lstStyle/>"
                + Self.paragraphs(lines, size: size, bold: bold, color: color, align: align) + "</p:txBody></p:sp>")
        }

        mutating func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, fill: String) {
            let i = id()
            shapes.append("<p:sp><p:nvSpPr><p:cNvPr id=\"\(i)\" name=\"Shape \(i)\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
                + "<p:spPr>\(Self.frame(x, y, w, h))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>\(Self.solid(fill))<a:ln><a:noFill/></a:ln></p:spPr></p:sp>")
        }

        /// The picture fitted inside the box, centred.
        mutating func picture(_ x: Double, _ y: Double, _ w: Double, _ h: Double, data: Data, pixels: (Int, Int), descr: String) {
            let size: (Int, Int) = IECWord.pixelSize(data).map { ($0.w, $0.h) } ?? pixels
            let pw = Double(max(size.0, 1)), ph = Double(max(size.1, 1)), k = min(w / pw, h / ph)
            let dw = pw * k, dh = ph * k
            let i = id()
            images.append((data, data.first == 0x89 ? "png" : "jpeg"))
            let rid = "rId\(images.count + 1)"
            shapes.append("<p:pic><p:nvPicPr><p:cNvPr id=\"\(i)\" name=\"Picture \(i)\" descr=\"\(escape(descr))\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"
                + "<p:blipFill><a:blip r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>"
                + "<p:spPr>\(Self.frame(x + (w - dw) / 2, y + (h - dh) / 2, dw, dh))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>")
        }

        /// A table: the first row is the header (unless `header` is false), cells bordered, text editable.
        mutating func table(_ x: Double, _ y: Double, widths: [Double], rows: [[String]], size: Double, rowH: Double, header: Bool = true,
                            fills: [[String?]]? = nil, aligns: [String]? = nil, boldRows: Set<Int> = []) {
            let i = id()
            let grid = widths.map { "<a:gridCol w=\"\(emu($0))\"/>" }.joined()
            let border = ["lnL", "lnR", "lnT", "lnB"].map { "<a:\($0) w=\"6350\"><a:solidFill><a:srgbClr val=\"\(line)\"/></a:solidFill></a:\($0)>" }.joined()
            var trs = ""
            for (r, cells) in rows.enumerated() {
                var tcs = ""
                for (c, value) in cells.enumerated() where c < widths.count {
                    let head = header && r == 0
                    let fill = head ? soft : fills?[safe: r]?[safe: c] ?? nil
                    let align = head ? "ctr" : aligns?[safe: c] ?? "l"
                    tcs += "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>"
                        + Self.paragraphs(value.components(separatedBy: "\n"), size: size, bold: head || boldRows.contains(r),
                                          color: head ? navy : black, align: align)
                        + "</a:txBody><a:tcPr marL=\"45720\" marR=\"45720\" marT=\"22860\" marB=\"22860\" anchor=\"ctr\">\(border)\(Self.solid(fill))</a:tcPr></a:tc>"
                }
                trs += "<a:tr h=\"\(emu(rowH))\">\(tcs)</a:tr>"
            }
            shapes.append("<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(i)\" name=\"Table \(i)\"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>"
                + "<p:xfrm><a:off x=\"\(emu(x))\" y=\"\(emu(y))\"/><a:ext cx=\"\(emu(widths.reduce(0, +)))\" cy=\"\(emu(rowH * Double(rows.count)))\"/></p:xfrm>"
                + "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl><a:tblPr firstRow=\"\(header ? 1 : 0)\"/>"
                + "<a:tblGrid>\(grid)</a:tblGrid>\(trs)</a:tbl></a:graphicData></a:graphic></p:graphicFrame>")
        }

        /// The title, the station line and the page number; the cover has only its footer.
        mutating func addFrame(subtitle: String, page: Int, pages: Int) {
            if let title {
                text(M, 0.3, W - 2 * M, 0.62, [title], size: 30, bold: true, color: navy)
                text(M, 0.88, W - 2 * M, 0.42, [subtitle], size: 18, color: muted)
                rect(M, 1.34, W - 2 * M, 0.03, fill: primary)
                text(W - M - 2, 7.0, 2, 0.36, ["\(page)/\(pages)"], size: 12, color: muted, align: "r")
            }
            text(M, 7.0, 6, 0.36, ["สร้างจาก TCRoof"], size: 12, color: muted)
        }

        static let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
            + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
            + "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""

        var xml: String {
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sld \(Self.ns)><p:cSld><p:spTree>"
                + "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
                + "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
                + shapes.joined() + "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"
        }
    }

    // MARK: - Package

    static let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let slideType = "application/vnd.openxmlformats-officedocument.presentationml.slide+xml"

    /// Adds the slides to the template: each slide's part and relationships (the blank layout, its pictures), the
    /// pictures, the presentation's slide list and the content types.
    static func package(_ zip: inout ZipArchive, _ list: [Slide], subtitle: String) throws {
        guard var pres = zip.string("ppt/presentation.xml"), var rels = zip.string("ppt/_rels/presentation.xml.rels"),
              var types = zip.string("[Content_Types].xml") else { throw Failure.template }
        var next = (rels.components(separatedBy: "Id=\"rId").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }.max() ?? 0) + 1
        var ids = "", image = 1
        for (n, var s) in list.enumerated().map({ ($0.offset + 1, $0.element) }) {
            s.addFrame(subtitle: subtitle, page: n, pages: list.count)
            zip.set("ppt/slides/slide\(n).xml", s.xml)
            var r = "<Relationship Id=\"rId1\" Type=\"\(rel)/slideLayout\" Target=\"../slideLayouts/slideLayout7.xml\"/>"
            for (k, img) in s.images.enumerated() {
                let path = "media/image\(image + k).\(img.ext)"
                zip.set("ppt/" + path, img.data)
                r += "<Relationship Id=\"rId\(k + 2)\" Type=\"\(rel)/image\" Target=\"../\(path)\"/>"
            }
            image += s.images.count
            zip.set("ppt/slides/_rels/slide\(n).xml.rels",
                    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(r)</Relationships>")
            let rid = "rId\(next)"; next += 1
            rels = rels.replacingOccurrences(of: "</Relationships>",
                                             with: "<Relationship Id=\"\(rid)\" Type=\"\(rel)/slide\" Target=\"slides/slide\(n).xml\"/></Relationships>")
            ids += "<p:sldId id=\"\(255 + n)\" r:id=\"\(rid)\"/>"
            types = types.replacingOccurrences(of: "</Types>", with: "<Override PartName=\"/ppt/slides/slide\(n).xml\" ContentType=\"\(slideType)\"/></Types>")
        }
        pres = pres.replacingOccurrences(of: "</p:sldMasterIdLst>", with: "</p:sldMasterIdLst><p:sldIdLst>\(ids)</p:sldIdLst>")
        zip.set("ppt/presentation.xml", pres)
        zip.set("ppt/_rels/presentation.xml.rels", rels)
        zip.set("[Content_Types].xml", types)
    }
}
