import Foundation
import TCRoofCore

/// รายงานประจำสัปดาห์ R3 as PowerPoint for the weekly meeting, in the customer's `Weekly Report Template`
/// (docs/ui/install-tracking-ipad-weekly-report §4.3): 16:9, 8 slides, every text and table editable: the cover, AGENDA,
/// the MP progress, the week's work a day a row, two slides of three site photos, the weather and the problems with their
/// fixes. The values are `content(_:images:)`'s, which the app's slide views draw too.
///
/// Built on `Resources/weekly_template.pptx` (the master, the blank layout and a theme in TH Sarabun New); this adds the
/// slides, their pictures (the template's from `Resources/WeeklyTemplate/`) and the entries that list them.
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
        /// Our engineer signed it; an unsigned day waits on slides 4, 7 and 8.
        public var signed: Bool
        public init(report: RoutineReport.Daily, photos: [DayPhoto], signed: Bool = true) {
            self.report = report; self.photos = photos; self.signed = signed
        }
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
        let deck = Deck(content: content(input, images: images), images: images)
        try package(&zip, deck.slides())
        return try zip.write()
    }

    // MARK: - Deck

    /// The template's 8 slides from the week's content, laid out on the board's 1920 × 1080 slide (`px`).
    struct Deck {
        let content: Content
        let images: [UUID: Data]

        func slides() -> [Slide] {
            content.outline.map { o -> Slide in
                var s = Slide()
                let k = o.kind
                if k == .cover { cover(&s) } else { frame(&s, k) }
                switch k {
                case .cover: break
                case .agenda: agenda(&s)
                case .progress: progress(&s)
                case .daily: daily(&s)
                case .photos: photos(&s, page: o.page)
                case .weather: weather(&s)
                case .problems: problems(&s)
                }
                // the page number, bottom right
                s.text(1386, 1003, 432, 58, ["\(o.number)"], size: 12.6, color: Tpl.pageInk, align: "r")
                return s
            }
        }

        /// The blue band, the cover's seal and its four lines.
        func cover(_ s: inout Slide) {
            s.rect(0, 80, 1920, 110, fill: Tpl.band)
            if let seal = templatePicture("logo-pea-seal") { s.picture(1608, 28, 228, 214, data: seal, descr: "ตราการไฟฟ้าส่วนภูมิภาค") }
            s.text(160, 283, 1600, 146, ["Weekly Report"], size: 75.6, bold: true, color: Tpl.title, align: "ctr", anchor: "ctr")
            // one paragraph that wraps, as the customer's cover
            s.text(170, 486, 1580, 305, [(content.project + [content.station]).joined(separator: " ")], size: 56, bold: true, color: Tpl.ink, align: "ctr", anchor: "ctr")
            s.text(99, 887, 1700, 102, [content.range], size: 50.4, bold: true, color: Tpl.ink, align: "ctr", anchor: "ctr")
        }

        /// Every slide but the cover: the band with its yellow title and the template's mark at its left.
        func frame(_ s: inout Slide, _ k: Kind) {
            s.rect(0, 49, 1920, 92, fill: Tpl.band)
            s.text(0, 42, 1920, 92, [k.bandTitle], size: k == .agenda || k == .weather ? 56 : 50.4, color: Tpl.bandTitle, align: "ctr", anchor: "ctr")
            s.rect(35, 6, 60, 156, fill: Tpl.markGrey, line: Tpl.markGreyLine, lineWidth: 10)
            s.rect(76, 15, 63, 83, fill: Tpl.markYellow, line: Tpl.markYellowLine, lineWidth: 10)
            s.shape("homePlate", 126, 49, 43, 56, fill: Tpl.markArrow, line: Tpl.markArrowLine, lineWidth: 10)
        }

        func agenda(_ s: inout Slide) {
            for (i, item) in ["CONSTRUCTION PROGRESS", "Weather Report", "ปัญหาและอุปสรรค"].enumerated() {
                let y = 205 + 150 * Double(i)
                if let hex = templatePicture("agenda-hex-\(i + 1)") { s.picture(118, y, 140, 120, data: hex, descr: "\(i + 1).") }
                s.text(300, y + 26, 1400, 68, [item], size: 39.2)
                s.line(258, y + 112, 1758, y + 112, color: Tpl.dots, width: 4, dash: "sysDot")
                s.shape("ellipse", 1752, y + 109, 10, 10, fill: Tpl.dot)
            }
        }

        func progress(_ s: inout Slide) {
            s.text(64, 168, 1000, 68, ["ความก้าวหน้าของงาน"], size: 39.2, bold: true)
            s.rect(64, 262, 1300, 668, fill: Tpl.chartBack, line: Tpl.chartLine, lineWidth: 2)
            // the legend
            s.rect(1050, 300, 22, 22, fill: Tpl.planBar); s.text(1078, 290, 80, 40, ["แผน"], size: 24)
            s.rect(1170, 300, 22, 22, fill: Tpl.band); s.text(1198, 290, 80, 40, ["จริง"], size: 24)
            let bars = content.bars
            guard !bars.isEmpty else {
                s.text(140, 560, 1180, 60, ["ยังไม่มีแผน MP"], size: 33.6, color: Tpl.pageInk, align: "ctr")
                return
            }
            // six weeks, plan and actual side by side; 60 % fills the chart until a week goes past it
            let top = max(60, bars.map { max($0.planned, $0.actual) }.max() ?? 0)
            let gap = 40.0, groupW = (1180 - gap * Double(bars.count - 1)) / Double(bars.count)
            let full = 476.0, base = 860.0, barW = (groupW - 8) / 2
            for (i, b) in bars.enumerated() {
                let x = 140 + Double(i) * (groupW + gap)
                let ph = full * b.planned / top, ah = full * b.actual / top
                s.rect(x, base - ph, barW, max(ph, 0.5), fill: Tpl.planBar)
                s.rect(x + barW + 8, base - ah, barW, max(ah, 0.5), fill: b.current ? Tpl.band : Tpl.actualBar)
                s.text(x, base - full - 48, groupW, 44, [Self.pct(b.actual) + "%"], size: 28, bold: true, align: "ctr")
                s.text(x, 870, groupW, 44, [b.label], size: 28, bold: b.current, align: "ctr")
            }
            s.line(140, base, 1320, base, color: Tpl.axis, width: 3)
            s.text(1366, 443, 478, 286, ["% WORK PROGRESS", "PLAN : \(Self.pct(content.planned ?? 0)) %",
                                         "ACTUAL : \(Self.pct(content.actual ?? 0)) %", "STATUS : \(content.status ?? "0") %"],
                   size: 39.2, color: Tpl.white, fill: Tpl.boxGrey, inset: 28)
            s.text(554, 960, 812, 58, [content.period], size: 25.2, align: "ctr", anchor: "ctr", line: Tpl.ink, dash: "sysDash")
        }

        static func pct(_ x: Double) -> String { String(Int(x.rounded())) }

        func daily(_ s: inout Slide) {
            // the customer's line under the band: the station and the week's dates
            s.text(109, 141, 1499, 69, [content.tableLine], size: 33.6, bold: true, color: Tpl.coverInk, anchor: "ctr")
            var rows: [[String]] = [["ลำดับ", "สัปดาห์ที่", "วันที่", "การดำเนินงาน"]]
            var fills: [[String?]] = [Array(repeating: Tpl.band, count: 4)]
            var inks: [[String?]] = [Array(repeating: Tpl.white, count: 4)]
            var italics: Set<Int> = []
            for r in content.rows {
                rows.append([String(r.number), String(content.weekNumber), r.dateText, r.lines.joined(separator: "\n")])
                let wait = r.state == .waiting
                fills.append([nil, nil, nil, wait ? Tpl.waitFill : nil])
                inks.append([nil, nil, nil, wait ? Tpl.waitInk : nil])
                if wait { italics.insert(rows.count - 1) }
            }
            s.table(116, 216, widths: [95, 126, 186, 1281], rows: rows, size: 22.4, headerSize: 25.2, rowH: 80, headerH: 50, fills: fills, inks: inks,
                    aligns: ["ctr", "ctr", "ctr", "l"], border: Tpl.tableLine, italicRows: italics)
        }

        /// Two photos side by side, each over its dashed caption (work and date); a last single photo centred.
        func photos(_ s: inout Slide, page: Int) {
            s.text(69, 165, 1200, 82, ["PROGRESS FOR THIS WEEK"], size: 39.2)
            let list = content.photos(page: page)
            for (i, p) in list.enumerated() {
                let x = list.count == 1 ? 504.0 : 40 + Double(i) * 936
                s.rect(x, 274, 911, 576, fill: Tpl.photoBack)
                if let bytes = images[p.id] { s.picture(x, 274, 911, 576, data: bytes, descr: p.caption) }
                s.text(x, 886, 911, 58, [p.caption], size: 25.2, align: "ctr", anchor: "ctr", line: Tpl.ink, dash: "sysDash")
            }
            if list.isEmpty { s.text(40, 540, 1840, 60, ["ไม่มีรูปในรายงานประจำวัน"], size: 33.6, color: Tpl.pageInk, align: "ctr") }
        }

        /// The customer's weather grid: a blue strip of day names, the icon, the words and the date, a column a day.
        func weather(_ s: inout Slide) {
            let w = 1320 / 7.0
            s.rect(353, 239, 1320, 110, gradient: [Tpl.white, Tpl.wxTop], line: Tpl.wxLine, lineWidth: 2)
            for (i, d) in content.weather.enumerated() {
                let x = 357 + Double(i) * w
                s.text(x, 258, w, 82, [d.name], size: 39.2, bold: true, color: d.colour, align: "ctr", anchor: "ctr")
                s.rect(x, 367, w, 241, fill: Tpl.wxIcon, line: Tpl.wxIconLine, lineWidth: 3)
                if let icon = d.icon, let png = templatePicture(icon.rawValue) {
                    s.picture(x + (w - 150) / 2, 412, 150, 150, data: png, descr: d.text)
                }
                s.text(x, 608, w, 215, [d.text], size: 33.6, align: "ctr", anchor: "ctr", gradient: [Tpl.wxTextTop, Tpl.wxTextBottom], line: Tpl.ink, lineWidth: 3)
                s.text(x, 823, w, 108, [d.date], size: 44.8, color: Tpl.dateInk, align: "ctr", anchor: "ctr", gradient: [Tpl.dateTop, Tpl.dateBottom], line: Tpl.ink, lineWidth: 3)
            }
        }

        func problems(_ s: inout Slide) {
            let bullets: ([String]) -> [(String, Bool)] = { list in
                list.isEmpty ? [("• ไม่มี", false)] : list.map { ("• " + $0, false) }
            }
            let lines = [("ปัญหาและอุปสรรคระหว่างปฏิบัติงาน", true)] + bullets(content.problems)
                + [("แนวทางแก้ไข", true)] + bullets(content.fixes)
            s.rich(195, 260, 1593, 720, lines, size: 37.1)
        }
    }

    // MARK: - Drawing

    /// The customer's template colours (a document, like the PDF: not the app's `Theme`).
    enum Tpl {
        static let band = "4472C4", bandTitle = "FFFF00", title = "002060", ink = "000000", white = "FFFFFF", pageInk = "898989", coverInk = "6E747A"
        static let markGrey = "808080", markGreyLine = "A6A6A6", markYellow = "FFC000", markYellowLine = "FFFF00"
        static let markArrow = "F4B183", markArrowLine = "C55A11"
        static let dots = "C0C0C0", dot = "A6A6A6"
        static let chartBack = "FAFBFD", chartLine = "D0D7E2", planBar = "BFC9D9", actualBar = "8FAADC", axis = "333333", boxGrey = "808080"
        static let tableLine = "1F4E79", waitFill = "FFF3E6", waitInk = "C55A11", photoBack = "F2F4F7"
        static let wxTop = "0070C0", wxMid = "DCE6F4", wxLine = "2F5597", wxIcon = "5B9BD5", wxIconLine = "002060"
        static let wxTextTop = "D9E2F3", wxTextBottom = "A9C7EA", dateInk = "FFC000", dateTop = "1F4E79", dateBottom = "002060"
    }

    /// Slide size in inches, and the board's 1920 px slide in inches.
    static let W = 13.333, H = 7.5
    static let px = W / 1920
    /// The customer's deck sets its text in TH SarabunPSK and its tables in TH Sarabun New.
    static let font = "TH SarabunPSK", tableFont = "TH Sarabun New"
    /// The board draws in Sarabun at 1.4 × the deck's point size (its 50.4 px band title is the deck's 36 pt).
    static let ptPerPx = 1 / 1.4

    static func emu(_ v: Double) -> String { String(Int((v * px * 914_400).rounded())) }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// One slide's shapes and pictures, in the board's px. A font size is the board's px, half of it in points.
    struct Slide {
        var shapes: [String] = []
        /// Picture bytes and extension, in the order of their relationship ids (rId2…).
        var images: [(data: Data, ext: String)] = []
        var nextID = 2

        mutating func id() -> Int { defer { nextID += 1 }; return nextID }

        static func run(_ text: String, size: Double, bold: Bool, italic: Bool = false, color: String, font: String = WeeklySlides.font) -> String {
            "<a:r><a:rPr lang=\"th-TH\" sz=\"\(Int((size * ptPerPx * 100).rounded()))\"\(bold ? " b=\"1\"" : "")\(italic ? " i=\"1\"" : "") dirty=\"0\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill>"
                + "<a:latin typeface=\"\(font)\"/><a:ea typeface=\"\(font)\"/><a:cs typeface=\"\(font)\"/></a:rPr><a:t>\(escape(text))</a:t></a:r>"
        }

        static func paragraphs(_ lines: [(String, Bool)], size: Double, italic: Bool = false, color: String, align: String,
                               font: String = WeeklySlides.font) -> String {
            lines.map { line, bold in
                "<a:p><a:pPr algn=\"\(align)\"/>" + (line.isEmpty ? "" : run(line, size: size, bold: bold, italic: italic, color: color, font: font))
                    + "<a:endParaRPr lang=\"th-TH\" sz=\"\(Int((size * ptPerPx * 100).rounded()))\"/></a:p>"
            }.joined()
        }

        static func frame(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> String {
            "<a:xfrm><a:off x=\"\(emu(x))\" y=\"\(emu(y))\"/><a:ext cx=\"\(emu(w))\" cy=\"\(emu(h))\"/></a:xfrm>"
        }

        /// A solid fill, a top-to-bottom gradient, or none.
        static func fill(_ color: String?, gradient: [String]? = nil) -> String {
            if let g = gradient, g.count > 1 {
                let stops = g.enumerated().map { i, c in "<a:gs pos=\"\(i * 100_000 / (g.count - 1))\"><a:srgbClr val=\"\(c)\"/></a:gs>" }.joined()
                return "<a:gradFill rotWithShape=\"1\"><a:gsLst>\(stops)</a:gsLst><a:lin ang=\"5400000\" scaled=\"0\"/></a:gradFill>"
            }
            return color.map { "<a:solidFill><a:srgbClr val=\"\($0)\"/></a:solidFill>" } ?? "<a:noFill/>"
        }

        static func outline(_ color: String?, width: Double, dash: String?) -> String {
            guard let color else { return "<a:ln><a:noFill/></a:ln>" }
            return "<a:ln w=\"\(Int(width * px * 914_400))\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill>"
                + (dash.map { "<a:prstDash val=\"\($0)\"/>" } ?? "") + "</a:ln>"
        }

        mutating func text(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ lines: [String], size: Double, bold: Bool = false,
                           color: String = Tpl.ink, align: String = "l", anchor: String = "t", fill: String? = nil, gradient: [String]? = nil,
                           line: String? = nil, lineWidth: Double = 2, dash: String? = nil, inset: Double = 6) {
            add(x, y, w, h, lines.map { ($0, bold) }, size: size, color: color, align: align, anchor: anchor, fill: fill, gradient: gradient,
                line: line, lineWidth: lineWidth, dash: dash, inset: inset)
        }

        /// Paragraphs each bold or not.
        mutating func rich(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ lines: [(String, Bool)], size: Double) {
            add(x, y, w, h, lines, size: size, color: Tpl.ink, align: "l", anchor: "t", fill: nil, gradient: nil, line: nil, lineWidth: 0, dash: nil, inset: 6)
        }

        private mutating func add(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ lines: [(String, Bool)], size: Double, color: String,
                                  align: String, anchor: String, fill: String?, gradient: [String]?, line: String?, lineWidth: Double,
                                  dash: String?, inset: Double) {
            let i = id(), ins = emu(inset)
            shapes.append("<p:sp><p:nvSpPr><p:cNvPr id=\"\(i)\" name=\"Text \(i)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr>"
                + "<p:spPr>\(Self.frame(x, y, w, h))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>\(Self.fill(fill, gradient: gradient))"
                + Self.outline(line, width: lineWidth, dash: dash) + "</p:spPr>"
                + "<p:txBody><a:bodyPr wrap=\"square\" lIns=\"\(ins)\" tIns=\"\(ins)\" rIns=\"\(ins)\" bIns=\"\(ins)\" anchor=\"\(anchor)\"><a:noAutofit/></a:bodyPr><a:lstStyle/>"
                + Self.paragraphs(lines, size: size, color: color, align: align) + "</p:txBody></p:sp>")
        }

        mutating func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, fill: String? = nil, gradient: [String]? = nil,
                           line: String? = nil, lineWidth: Double = 0) {
            shape("rect", x, y, w, h, fill: fill, gradient: gradient, line: line, lineWidth: lineWidth)
        }

        mutating func shape(_ prst: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, fill: String? = nil, gradient: [String]? = nil,
                            line: String? = nil, lineWidth: Double = 0) {
            let i = id()
            shapes.append("<p:sp><p:nvSpPr><p:cNvPr id=\"\(i)\" name=\"Shape \(i)\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
                + "<p:spPr>\(Self.frame(x, y, w, h))<a:prstGeom prst=\"\(prst)\"><a:avLst/></a:prstGeom>\(Self.fill(fill, gradient: gradient))"
                + Self.outline(line, width: lineWidth, dash: nil) + "</p:spPr></p:sp>")
        }

        /// A straight line from (x1, y1) to (x2, y2).
        mutating func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, color: String, width: Double, dash: String? = nil) {
            let i = id()
            shapes.append("<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"\(i)\" name=\"Line \(i)\"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>"
                + "<p:spPr>\(Self.frame(min(x1, x2), min(y1, y2), abs(x2 - x1), abs(y2 - y1)))<a:prstGeom prst=\"line\"><a:avLst/></a:prstGeom>"
                + Self.outline(color, width: width, dash: dash) + "</p:spPr></p:cxnSp>")
        }

        /// The picture fitted inside the box, centred.
        mutating func picture(_ x: Double, _ y: Double, _ w: Double, _ h: Double, data: Data, descr: String) {
            let size = IECWord.pixelSize(data) ?? (w: Int(w), h: Int(h))
            let pw = Double(max(size.w, 1)), ph = Double(max(size.h, 1)), k = min(w / pw, h / ph)
            let dw = pw * k, dh = ph * k
            let i = id()
            images.append((data, data.first == 0x89 ? "png" : "jpeg"))
            let rid = "rId\(images.count + 1)"
            shapes.append("<p:pic><p:nvPicPr><p:cNvPr id=\"\(i)\" name=\"Picture \(i)\" descr=\"\(escape(descr))\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"
                + "<p:blipFill><a:blip r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>"
                + "<p:spPr>\(Self.frame(x + (w - dw) / 2, y + (h - dh) / 2, dw, dh))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>")
        }

        /// A table: the first row is the header, cells bordered, text editable.
        mutating func table(_ x: Double, _ y: Double, widths: [Double], rows: [[String]], size: Double, headerSize: Double, rowH: Double, headerH: Double,
                            fills: [[String?]], inks: [[String?]], aligns: [String], border: String, italicRows: Set<Int>) {
            let i = id()
            let grid = widths.map { "<a:gridCol w=\"\(emu($0))\"/>" }.joined()
            let lines = ["lnL", "lnR", "lnT", "lnB"].map { "<a:\($0) w=\"12700\"><a:solidFill><a:srgbClr val=\"\(border)\"/></a:solidFill></a:\($0)>" }.joined()
            var trs = ""
            for (r, cells) in rows.enumerated() {
                var tcs = ""
                for (c, value) in cells.enumerated() where c < widths.count {
                    let head = r == 0
                    tcs += "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>"
                        + Self.paragraphs(value.components(separatedBy: "\n").map { ($0, false) }, size: head ? headerSize : size, italic: italicRows.contains(r),
                                          color: inks[safe: r]?[safe: c].flatMap { $0 } ?? Tpl.ink, align: head ? "ctr" : aligns[safe: c] ?? "l",
                                          font: tableFont)
                        + "</a:txBody><a:tcPr marL=\"\(emu(14))\" marR=\"\(emu(14))\" marT=\"\(emu(7))\" marB=\"\(emu(7))\" anchor=\"\(head ? "ctr" : "t")\">"
                        + lines + Self.fill(fills[safe: r]?[safe: c].flatMap { $0 }) + "</a:tcPr></a:tc>"
                }
                trs += "<a:tr h=\"\(emu(r == 0 ? headerH : rowH))\">\(tcs)</a:tr>"
            }
            let height = headerH + rowH * Double(rows.count - 1)
            shapes.append("<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(i)\" name=\"Table \(i)\"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>"
                + "<p:xfrm><a:off x=\"\(emu(x))\" y=\"\(emu(y))\"/><a:ext cx=\"\(emu(widths.reduce(0, +)))\" cy=\"\(emu(height))\"/></p:xfrm>"
                + "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl><a:tblPr firstRow=\"1\"/>"
                + "<a:tblGrid>\(grid)</a:tblGrid>\(trs)</a:tbl></a:graphicData></a:graphic></p:graphicFrame>")
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
    static func package(_ zip: inout ZipArchive, _ list: [Slide]) throws {
        guard var pres = zip.string("ppt/presentation.xml"), var rels = zip.string("ppt/_rels/presentation.xml.rels"),
              var types = zip.string("[Content_Types].xml") else { throw Failure.template }
        var next = (rels.components(separatedBy: "Id=\"rId").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }.max() ?? 0) + 1
        var ids = "", image = 1
        for (n, s) in list.enumerated().map({ ($0.offset + 1, $0.element) }) {
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
        // the template's pictures are PNG: make sure the package names the type
        if !types.contains("Extension=\"png\"") {
            types = types.replacingOccurrences(of: "</Types>", with: "<Default Extension=\"png\" ContentType=\"image/png\"/></Types>")
        }
        if !types.contains("Extension=\"jpeg\"") {
            types = types.replacingOccurrences(of: "</Types>", with: "<Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/></Types>")
        }
        pres = pres.replacingOccurrences(of: "</p:sldMasterIdLst>", with: "</p:sldMasterIdLst><p:sldIdLst>\(ids)</p:sldIdLst>")
        zip.set("ppt/presentation.xml", pres)
        zip.set("ppt/_rels/presentation.xml.rels", rels)
        zip.set("[Content_Types].xml", types)
    }
}
