import Foundation
import TCRoofCore

/// A picture bundled with `PDFReport` that a page names like a stored photo: the logos of the customer's forms.
/// `PDFRenderer` loads it from the package when the caller's photos don't have it.
public enum FormImage: String, CaseIterable, Sendable {
    case tcLogo = "form-logo-tc.png", pwaLogo = "form-logo-pwa.jpg", peaLogo = "form-logo-pea.png"

    static let prefix = "pdfreport-form:"

    /// Width / height of the bundled file.
    var aspect: Double {
        switch self {
        case .tcLogo: 500.0 / 116
        case .pwaLogo: 1
        case .peaLogo: 900.0 / 321
        }
    }

    public var photo: Photo {
        let ids: [FormImage: String] = [.tcLogo: "6E0C1F2A-0D5B-4E8A-9C1B-0000000000A1",
                                        .pwaLogo: "6E0C1F2A-0D5B-4E8A-9C1B-0000000000A2",
                                        .peaLogo: "6E0C1F2A-0D5B-4E8A-9C1B-0000000000A3"]
        return Photo(id: UUID(uuidString: ids[self]!)!, fileName: Self.prefix + rawValue,
                     width: Int(aspect * 1000), height: 1000, takenAt: .distantPast)
    }

    /// The bundled file a photo names, if it is one of these.
    public static func resource(_ p: Photo) -> String? {
        p.fileName.hasPrefix(prefix) ? String(p.fileName.dropFirst(prefix.count)) : nil
    }
}

/// R2 in the customer's DAILY REPORT form (docs/ui/daily-report-pdf): page 1 header, weather, manpower, tools and
/// materials; page 2 key plan, progress and problems; page 3 four photos and the signatures; then six photos per page.
/// Each page is drawn in the board's own pixels (816 × 1056, 96 dpi) and scaled once onto `dailyFormPage`.
extension RoutineReportPages {
    /// The form's paper: A4, as our other reports (the board is US Letter). The board's page scales to the width and
    /// centres down the page.
    public static let dailyFormPage = (w: ReportLayout.pageW, h: ReportLayout.pageH)

    // the board's page, frame and body, in px
    static let boardW = 816.0, boardH = 1056.0
    static let frameX0 = 41.5, frameX1 = 774.5, frameBottom = 1014.5
    static let bodyTop = 250.5
    /// Crew and tool rows, materials, progress and problems per page, as on the form.
    static let formRows = (crew: 17, materials: 8, progress: 6, problems: 5, firstPhotos: 4, morePhotos: 6)

    static let fineFill = RGBA(hex: 0xB7DEE8), cloudFill = RGBA(hex: 0xD9D9D9), rainFill = RGBA(hex: 0xFF0000)
    static let hint = RGBA(hex: 0x767676)

    /// The two title lines in the logo band: English (Helvetica bold) over Thai (Sarabun 15 bold).
    struct FormTitles {
        var en: String
        var enSize: Double
        var th: String
        static let daily = FormTitles(en: "DAILY REPORT", enSize: 14, th: "รายงานการทำงานประจำวัน")
    }

    /// What the header prints; nil fields draw the blank form's dotted lines.
    struct FormHeader {
        var contract: String
        var kWp: String?
        var date: String?
        var workingTime: String?
        var from: String
        var to: String
        var station: String?
        var titles = FormTitles.daily
        /// Sarabun after the date, as the weekly request's `(สัปดาห์ที่ 32)`.
        var dateNote: String? = nil
    }

    // MARK: - Report

    /// The daily report in the customer's form, every page numbered "n / N" within this report.
    public func dailyForm(_ e: DailyEntry, all: [RoutineReport.Daily], keyPlan: KeyPlan? = nil) -> [ReportLayout.Page] {
        let r = e.report, s = station.settings
        let header = FormHeader(contract: Self.contractText(s), kWp: String(format: "%.2f", station.capacityKWp),
                                date: Self.formDate(r.date), workingTime: Self.workingTime(r.workStart, r.workEnd),
                                from: s.contractor, to: s.employer, station: station.projectLine)

        // page 1, repeated while crew, tools or materials remain
        let crew = r.crew.filter { $0.count > 0 }, tools = r.tools.filter { $0.count > 0 }
        let n = Self.formRows
        let firstPages = max(1, Self.chunks(crew.count, n.crew), Self.chunks(tools.count, n.crew), Self.chunks(r.materials.count, n.materials))
        var bodies: [[DrawOp]] = (0..<firstPages).map { i in
            pageOne(weather: r.weather,
                    crew: Self.slice(crew, i, n.crew).map { ($0.offset + 1, $0.element.name, "\($0.element.count)") },
                    crewTotal: "\(r.crewTotal)",
                    tools: Self.slice(tools, i, n.crew).map { ($0.offset + 1, $0.element.name, "\($0.element.count)") },
                    toolTotal: "\(tools.reduce(0) { $0 + $1.count })",
                    materials: Self.slice(r.materials, i, n.materials).map { m in
                        [String(m.offset + 1), m.element.name, m.element.location, Self.num(m.element.qty), m.element.unit, m.element.remark]
                    },
                    rows: (n.crew, n.materials))
        }

        // page 2, repeated while progress lines or problems remain
        var progress: [[String]] = r.progress.enumerated().map { i, l in
            let delta = RoutineReport.todayDelta(l, on: r.date, in: all)
            return [String(i + 1), l.description.isEmpty ? (l.task?.title ?? "") : l.description, l.location, "1", "งาน",
                    RoutineReport.percent(delta), RoutineReport.percent(l.percent), ""]
        }
        if progress.isEmpty, !r.stopReason.isEmpty { progress = [["1", "หยุดงาน: " + r.stopReason, "", "", "", "", "", ""]] }
        let problems = r.problems.filter { !$0.description.isEmpty }.enumerated().map { i, p in
            [String(i + 1), p.description, p.solution, p.closed ? "แก้แล้ว" : "กำลังแก้"]
        }
        let secondPages = max(1, Self.chunks(progress.count, n.progress), Self.chunks(problems.count, n.problems))
        for i in 0..<secondPages {
            bodies.append(pageTwo(keyPlan: keyPlan, today: Set(r.progress.map(\.location)),
                                  progress: Self.slice(progress, i, n.progress).map(\.element),
                                  problems: Self.slice(problems, i, n.problems).map(\.element), rows: (n.progress, n.problems)))
        }

        // page 3 and the photo pages
        let captioned = e.photos.enumerated().map { i, p in (i + 1, Optional(p)) }
        let signed = (engineer: e.engineerSignedAt.map(Self.signDate), inspector: e.inspectorAckAt.map(Self.signDate))
        // page 3 keeps its four frames when the day has fewer photos
        let firstFour = (0..<n.firstPhotos).map { i in captioned[safe: i] ?? (i + 1, nil) }
        let drawn = (engineer: e.engineerSignedAt == nil ? nil : e.engineerSignature, inspector: e.inspectorAckAt == nil ? nil : e.inspectorSignature)
        bodies.append(pageThree(photos: firstFour, names: (s.siteEngineer, s.inspector), signed: signed, drawn: drawn, hints: false))
        var rest = Array(captioned.dropFirst(n.firstPhotos))
        while !rest.isEmpty {
            bodies.append(photoPage(Array(rest.prefix(n.morePhotos))))
            rest = Array(rest.dropFirst(n.morePhotos))
        }
        return finishForm(bodies, header: header)
    }

    // MARK: - Blank form

    /// The form's four pages blank, for printing and filling in by hand: dotted lines for the kWp, date, working time and
    /// station, numbered empty rows and photo slots 1–10.
    public static func dailyBlankForm(settings: RoutineReport.Settings = .init(), measure: TextMeasuring = ApproxMeasure()) -> [ReportLayout.Page] {
        let p = RoutineReportPages(station: .init(name: "", code: "", mpNumber: nil, capacityKWp: 0, settings: settings), measure: measure)
        let header = FormHeader(contract: contractText(settings), kWp: nil, date: nil, workingTime: nil,
                                from: settings.contractor, to: settings.employer, station: nil)
        let numbered = { (k: Int) in (1...k).map { ($0, "", "") } }
        let one = p.pageOne(weather: [], crew: numbered(15), crewTotal: "", tools: numbered(15), toolTotal: "",
                            materials: (1...7).map { [String($0), "", "", "", "", ""] }, rows: (15, 7))
        let two = p.pageTwo(keyPlan: nil, today: [], progress: (1...7).map { [String($0)] + Array(repeating: "", count: 7) },
                            problems: (1...5).map { [String($0), "", "", ""] }, rows: (7, 5), blank: true)
        let three = p.pageThree(photos: (1...4).map { ($0, nil) }, names: ("", ""), signed: (nil, nil))
        let four = p.photoPage((5...10).map { ($0, nil) })
        return p.finishForm([one, two, three, four], header: header)
    }

    // MARK: - Pages

    /// Page 1's body: weather, manpower and tools side by side, materials.
    func pageOne(weather: [RoutineReport.Weather?], crew: [(Int, String, String)], crewTotal: String,
                 tools: [(Int, String, String)], toolTotal: String, materials: [[String]], rows: (crew: Int, materials: Int)) -> [DrawOp] {
        let x0 = Self.frameX0 + 12, w = Self.frameX1 - 12 - x0
        let half = (w - 16) / 2
        let weatherH = 20 + 8 + 41.5
        let countH = 18 + 6 + 36 + Double(rows.crew) * 20 + 22 + 1.5
        let materialH = 18 + 6 + 36 + Double(rows.materials) * 20 + 1.5
        let ys = Self.spaced([weatherH, countH, materialH], top: Self.bodyTop + 12, bottom: Self.frameBottom - 12)
        var o = weatherSection(weather, x: x0, y: ys[0], w: w)
        o += countSection(("MANPOWER REPORT", "กำลังคน"), ("Qty.", "จำนวน"), "Total Man-Day", crew, total: crewTotal, rows: rows.crew,
                          x: x0, y: ys[1], w: half)
        o += countSection(("TOOL & MACHINERY REPORT", "เครื่องมือและเครื่องจักร"), ("Used", "ใช้งาน"), "Total Tool & Machinery", tools,
                          total: toolTotal, rows: rows.crew, x: x0 + half + 16, y: ys[1], w: half)
        o += sectionTitle("MATERIAL ON SITE", "วัสดุเข้าหน้างาน", x: x0, y: ys[2])
        let mw = [52.0, w - 52 - 140 - 66 - 66 - 96, 140, 66, 66, 96]
        let heads = [("Item", "ลำดับที่"), ("Description", "รายการ"), ("For use at LOCAL/LINE", "สถานที่"), ("Qty.", "จำนวน"),
                     ("Unit", "หน่วย"), ("Remark", "หมายเหตุ")]
        let aligns: [TextAlign] = [.center, .left, .center, .center, .center, .left]
        o += table(x: x0, y: ys[2] + 24, widths: mw, header: heads, rows: Self.padded(materials, rows.materials, columns: 6), aligns: aligns,
                   latin: [0])
        return o
    }

    /// Page 2's body: key plan, progress of work, problems.
    func pageTwo(keyPlan: KeyPlan?, today: Set<String>, progress: [[String]], problems: [[String]], rows: (progress: Int, problems: Int),
                 blank: Bool = false) -> [DrawOp] {
        let x0 = Self.frameX0 + 12, w = Self.frameX1 - 12 - x0
        let box = blank ? (w: 456.0, h: 292.0) : (w: 480.0, h: 333.0)
        let planH = 18 + 6 + box.h
        let progressH = 18 + 6 + 36 + Double(rows.progress) * 20 + 1.5
        let problemH = 18 + 6 + 36 + Double(rows.problems) * 20 + 1.5
        let ys = Self.spaced([planH, progressH, problemH], top: Self.bodyTop + 12, bottom: Self.frameBottom - 12)

        var o = sectionTitle("KEY PLAN", "ผังตำแหน่งงาน", x: x0, y: ys[0])
        let frame = Box(x0 + (w - box.w) / 2, ys[0] + 24, box.w, box.h)
        o.append(.rect(frame, stroke: .black, fill: nil, width: 1))
        if blank {
            o.append(.text("พื้นที่แนบผังตำแหน่งงาน (Key Plan)", at: Pt(frame.x + frame.w / 2, frame.y + frame.h / 2), size: 11,
                           color: Self.hint, align: .center))
        } else if let keyPlan {
            o += keyPlanPicture(keyPlan, today: today, in: frame.inset(1))
        }

        o += sectionTitle("PROGRESS OF WORK", "ความก้าวหน้าของงาน", x: x0, y: ys[1])
        o += progressTable(x: x0, y: ys[1] + 24, w: w, rows: Self.padded(progress, rows.progress, columns: 8))

        o += sectionTitle("PROBLEMS, OBSTRUCTIONS AND SOLUTIONS", "ปัญหาอุปสรรคและแนวทางการแก้ไข", x: x0, y: ys[2])
        let pw = [52.0, 300, w - 52 - 300 - 74, 74]
        o += table(x: x0, y: ys[2] + 24, widths: pw,
                   header: [("Item", "ลำดับที่"), ("Description", "รายการ"), ("Solutions", "แนวทางแก้ไข"), ("Status", "สถานะ")],
                   rows: Self.padded(problems, rows.problems, columns: 4), aligns: [.center, .left, .left, .center], latin: [0])
        return o
    }

    /// Page 3's body: four photos (nil = an empty slot) and the signature band.
    func pageThree(photos: [(Int, DayPhoto?)], names: (engineer: String, inspector: String),
                   signed: (engineer: String?, inspector: String?), drawn: (engineer: Photo?, inspector: Photo?) = (nil, nil),
                   hints: Bool = true) -> [DrawOp] {
        let band = Self.frameBottom - 144
        var o = photoGrid(photos, columns: 2, rows: 2, x: Self.frameX0 + 20, y: Self.bodyTop + 16,
                          w: Self.frameX1 - Self.frameX0 - 40, h: band - 16 - Self.bodyTop - 16, gap: (16, 20), hints: hints)
        o.append(.line(Pt(Self.frameX0, band + 0.75), Pt(Self.frameX1, band + 0.75), width: 1.5, color: .black))
        let mid = (Self.frameX0 + Self.frameX1) / 2
        o.append(.line(Pt(mid, band + 1.5), Pt(mid, Self.frameBottom), width: 1, color: .black))
        o += signature(("Please be informed accordingly / ", "จึงเรียนมาเพื่อทราบ"), name: names.engineer, date: signed.engineer,
                       drawn: drawn.engineer, role: "Site Engineer", x: Self.frameX0, w: mid - Self.frameX0, top: band)
        o += signature(("Acknowledge / ", "รับทราบ"), name: names.inspector, date: signed.inspector, drawn: drawn.inspector,
                       role: "Inspector", x: mid, w: Self.frameX1 - mid, top: band)
        return o
    }

    /// A continuation page: SITE PHOTOS (CONTINUED) and up to six photos.
    func photoPage(_ photos: [(Int, DayPhoto?)]) -> [DrawOp] {
        let x0 = Self.frameX0 + 20, top = Self.bodyTop + 12
        var o = sectionTitle("SITE PHOTOS (CONTINUED)", "ภาพถ่ายหน้างาน (ต่อ)", x: x0, y: top)
        o += photoGrid(photos, columns: 2, rows: 3, x: x0, y: top + 26, w: Self.frameX1 - Self.frameX0 - 40,
                       h: Self.frameBottom - 16 - top - 26, gap: (14, 20))
        return o
    }

    // MARK: - Header and page

    /// Frame, header and page number around each body, scaled onto the paper.
    func finishForm(_ bodies: [[DrawOp]], header: FormHeader) -> [ReportLayout.Page] {
        let page = Self.dailyFormPage, k = page.w / Self.boardW, dy = (page.h - Self.boardH * k) / 2
        return bodies.enumerated().map { i, body in
            var o: [DrawOp] = [.rect(Box(40.75, 40.75, 734.5, 974.5), stroke: .black, fill: nil, width: 1.5)]
            o += formHeader(header)
            o += body
            o.append(.runs([TextRun("\(i + 1) / \(bodies.count)", size: 18.23, face: .thSarabun)], at: Pt(Self.boardW / 2, 1034),
                           align: .center))
            let ops = Sketch(width: Self.boardW, height: Self.boardH, ops: o).translated(0, dy, scale: k)
            return ReportLayout.Page(ops: ops, width: page.w, height: page.h)
        }
    }

    /// The logo band and the info table shared by every page.
    func formHeader(_ h: FormHeader) -> [DrawOp] {
        let x0 = Self.frameX0, x1 = Self.frameX1
        var o: [DrawOp] = []
        // logo band, 76 px
        let mid = 41.5 + 38
        o.append(.photo(FormImage.tcLogo.photo, Box(x0 + 18, mid - 20, 40 * FormImage.tcLogo.aspect, 40)))
        o.append(.runs([TextRun(h.titles.en, size: h.titles.enSize, bold: true, face: .helvetica)], at: Pt(Self.boardW / 2, mid - 11), align: .center))
        o.append(.runs([TextRun(h.titles.th, size: 15, bold: true)], at: Pt(Self.boardW / 2, mid + 9), align: .center))
        let peaW = 36 * FormImage.peaLogo.aspect
        o.append(.photo(FormImage.peaLogo.photo, Box(x1 - 18 - peaW, mid - 18, peaW, 36)))
        o.append(.photo(FormImage.pwaLogo.photo, Box(x1 - 18 - peaW - 8 - 40, mid - 20, 40, 40)))
        o.append(.line(Pt(x0, 118.25), Pt(x1, 118.25), width: 1.5, color: .black))

        // info table: 92 / flex / 72 / 232 px; rows 60, 42, 28
        let c1 = x0 + 92, c3 = x1 - 232, c2 = c3 - 72
        let r1 = 119.0, r2 = 179.0, r3 = 221.0, r4 = 249.0
        for x in [c1, c2, c3] { o.append(.line(Pt(x, r1), Pt(x, r3), width: 1, color: .black)) }
        o.append(.line(Pt(x0, r2), Pt(x1, r2), width: 1, color: .black))
        o.append(.line(Pt(x0, r3), Pt(x1, r3), width: 1, color: .black))
        o.append(.line(Pt(x0, r4 + 0.75), Pt(x1, r4 + 0.75), width: 1.5, color: .black))

        let line1 = r1 + 12.5, line2 = line1 + 17, line3 = line2 + 17
        o.append(Self.latin("CONTRACT :", 10, bold: true, at: Pt(x0 + 8, line1)))
        o.append(Self.latin("PROJECT :", 10, bold: true, at: Pt(x0 + 8, line2)))
        o.append(.textBox(h.contract, Box(c1 + 8, r1 + 4, c2 - c1 - 16, 34), size: 11))
        if let kWp = h.kWp {
            o.append(.text("กำลังการผลิตติดตั้ง \(kWp) กิโลวัตต์", at: Pt(c1 + 8, line3), size: 11))
        } else {
            let lead = "กำลังการผลิตติดตั้ง ", lw = measure.width(lead, size: 11, bold: false)
            o.append(.text(lead, at: Pt(c1 + 8, line3), size: 11))
            o.append(Self.dotted(c1 + 8 + lw, line3 + 7, 54))
            o.append(.text(" กิโลวัตต์", at: Pt(c1 + 8 + lw + 54, line3), size: 11))
        }
        o.append(Self.latin("DATE :", 10, bold: true, at: Pt(c2 + 8, line1)))
        o.append(.text("วันที่", at: Pt(c2 + 8, line2), size: 11, bold: true))
        if let date = h.date, let note = h.dateNote {
            o.append(.runs([TextRun(date + " ", size: 12, bold: true, face: .helvetica), TextRun(note, size: 11)], at: Pt(c3 + 10, line1)))
        } else if let date = h.date {
            o.append(Self.latin(date, 12, bold: true, at: Pt(c3 + 10, line1)))
        } else {
            o.append(Self.dotted(c3 + 10, line1 + 7, 140))
        }
        if let wt = h.workingTime {
            o.append(Self.latin("Working Time: " + wt, 10, at: Pt(c3 + 10, line2)))
        } else {
            let label = [TextRun("Working Time:", size: 10, face: .helvetica)]
            o.append(.runs(label, at: Pt(c3 + 10, line2 + 3)))
            o.append(Self.dotted(c3 + 10 + measure.width(label) + 6, line2 + 10, 120))
        }

        let from = (r2 + r3) / 2
        o.append(Self.latin("FROM :", 10, bold: true, at: Pt(x0 + 8, from - 8)))
        o.append(.text("จาก", at: Pt(x0 + 8, from + 8), size: 11))
        o.append(line(h.from, Box(c1 + 8, from - 9, c2 - c1 - 16, 18), size: 11))
        o.append(Self.latin("TO :", 10, bold: true, at: Pt(c2 + 8, from - 8)))
        o.append(.text("ถึง", at: Pt(c2 + 8, from + 8), size: 11))
        o.append(line(h.to, Box(c3 + 10, from - 9, x1 - c3 - 18, 18), size: 11))

        let name = (r3 + r4) / 2
        let lead = "ชื่อโครงการ : "
        if let station = h.station {
            o.append(line(lead + station, Box(x0 + 8, name - 9, x1 - x0 - 16, 18), size: 12, bold: true))
        } else {
            o.append(.text(lead, at: Pt(x0 + 8, name), size: 12, bold: true))
            o.append(Self.dotted(x0 + 8 + measure.width(lead, size: 12, bold: true) + 4, name + 8, 560))
        }
        return o
    }

    // MARK: - Sections

    /// "WEATHER REPORT สภาพอากาศ", underlined.
    func sectionTitle(_ en: String, _ th: String, x: Double, y: Double) -> [DrawOp] {
        [.runs([TextRun(en + " ", size: 10, bold: true, face: .helvetica, underline: true),
                TextRun(th, size: 11, bold: true, underline: true)], at: Pt(x, y + 9))]
    }

    /// The title with the F / R legend, then the 15 hour cells (06:00–20:00) over the day's F / R.
    func weatherSection(_ weather: [RoutineReport.Weather?], x: Double, y: Double, w: Double) -> [DrawOp] {
        var o: [DrawOp] = [.runs([TextRun("WEATHER REPORT ", size: 10, bold: true, face: .helvetica, underline: true),
                                  TextRun("สภาพอากาศ", size: 11, bold: true, underline: true)], at: Pt(x, y + 10))]
        // legend, from the right edge
        var right = x + w
        for (mark, fill, en, th) in [("R", Self.rainFill, ": Raining ", "ฝนตก"), ("C", Self.cloudFill, ": Cloudy ", "เมฆครึ้ม"),
                                     ("F", Self.fineFill, ": Fine ", "ท้องฟ้าโปร่ง")] {
            let runs = [TextRun(en, size: 10, face: .helvetica), TextRun(th, size: 11)]
            let tw = measure.width(runs)
            o.append(.runs(runs, at: Pt(right, y + 10), align: .right))
            let bx = right - tw - 6 - 36
            o.append(.rect(Box(bx, y + 2, 36, 16), stroke: .black, fill: fill, width: 1))
            o.append(Self.latin(mark, 10, bold: true, at: Pt(bx + 18, y + 10), align: .center))
            right = bx - 18
        }
        let top = y + 28, cell = w / Double(RoutineReport.weatherHours.count)
        for (i, h) in RoutineReport.weatherHours.enumerated() {
            let cx = x + (Double(i) + 0.5) * cell
            o.append(Self.latin(String(format: "%02d:00", h), 10.5, at: Pt(cx, top + 10), align: .center))
            let mark: (String, RGBA)? = switch weather[safe: i] ?? nil {
            case .rain?: ("R", Self.rainFill)
            // the customer's form has F and R only; C is ours, grey, with its own legend entry
            case .cloudy?: ("C", Self.cloudFill)
            case .fine?: ("F", Self.fineFill)
            case nil: nil
            }
            if let mark {
                o.append(.rect(Box(x + Double(i) * cell, top + 20, cell, 20), stroke: nil, fill: mark.1))
                o.append(Self.latin(mark.0, 10.5, bold: true, at: Pt(cx, top + 30), align: .center))
            }
        }
        for i in 1..<RoutineReport.weatherHours.count {
            o.append(.line(Pt(x + Double(i) * cell, top), Pt(x + Double(i) * cell, top + 40), width: 1, color: .black))
        }
        o.append(.line(Pt(x, top + 20), Pt(x + w, top + 20), width: 1, color: .black))
        o.append(.rect(Box(x, top, w, 40), stroke: .black, fill: nil, width: 1.5))
        return o
    }

    /// Manpower or tools: Item / Description / Qty, fixed rows and the total.
    func countSection(_ title: (String, String), _ qty: (String, String), _ totalLabel: String, _ list: [(Int, String, String)],
                      total: String, rows: Int, x: Double, y: Double, w: Double) -> [DrawOp] {
        var o = sectionTitle(title.0, title.1, x: x, y: y)
        let widths = [52.0, w - 52 - 58, 58]
        let cells = Self.padded(list.map { [String($0.0), $0.1, $0.2] }, rows, columns: 3)
        o += table(x: x, y: y + 24, widths: widths, header: [("Item", "ลำดับที่"), ("Description", "รายการ"), qty], rows: cells,
                   aligns: [.center, .left, .center], latin: [0, 2], footer: 22)
        // the total row, under a 1.5 px rule
        let ty = y + 24 + 36 + Double(rows) * 20
        o.append(.line(Pt(x, ty), Pt(x + w, ty), width: 1.5, color: .black))
        o.append(Self.latin(totalLabel, 10, bold: true, at: Pt(x + widths[0] + widths[1] - 8, ty + 11), align: .right))
        o.append(Self.latin(total, 10, bold: true, at: Pt(x + w - widths[2] / 2, ty + 11), align: .center))
        return o
    }

    /// A form table: a 36 px two-line header (English over Thai), `rows` of 20 px, an optional empty `footer` row,
    /// 1 px rules inside and 1.5 px around and under the header. `latin` columns print in Helvetica.
    func table(x: Double, y: Double, widths: [Double], header: [(String, String)], rows: [[String]], aligns: [TextAlign],
               latin: Set<Int>, footer: Double = 0) -> [DrawOp] {
        let w = widths.reduce(0, +), h = 36 + Double(rows.count) * 20 + footer
        let xs = widths.indices.map { i in x + widths[..<i].reduce(0, +) }
        var o: [DrawOp] = []
        for (i, head) in header.enumerated() {
            o += headerCell(head.0, head.1, Box(xs[i], y, widths[i], 36))
        }
        for (r, cells) in rows.enumerated() {
            let cy = y + 36 + Double(r) * 20 + 10
            if r > 0 { o.append(.line(Pt(x, cy - 10), Pt(x + w, cy - 10), width: 1, color: .black)) }
            for (i, c) in cells.enumerated() where i < widths.count && !c.isEmpty {
                o.append(cell(c, Box(xs[i], cy - 10, widths[i], 20), align: aligns[i], latin: latin.contains(i)))
            }
        }
        if footer > 0, !rows.isEmpty { o.append(.line(Pt(x, y + h - footer), Pt(x + w, y + h - footer), width: 1, color: .black)) }
        for i in 1..<widths.count { o.append(.line(Pt(xs[i], y), Pt(xs[i], y + h), width: 1, color: .black)) }
        o.append(.line(Pt(x, y + 36), Pt(x + w, y + 36), width: 1.5, color: .black))
        o.append(.rect(Box(x, y, w, h), stroke: .black, fill: nil, width: 1.5))
        return o
    }

    /// PROGRESS OF WORK: Quantity (%) spans Today and Accumulated in a two-row header.
    func progressTable(x: Double, y: Double, w: Double, rows: [[String]]) -> [DrawOp] {
        let widths = [52.0, w - 52 - 100 - 46 - 46 - 50 - 74 - 62, 100, 46, 46, 50, 74, 62]
        let xs = widths.indices.map { i in x + widths[..<i].reduce(0, +) }
        var o: [DrawOp] = []
        let heads = [("Item", "ลำดับที่"), ("Description", "รายการ"), ("LOCAL/LINE", "ตำแหน่ง"), ("Qty.", "จำนวน"), ("Unit", "หน่วย")]
        for (i, head) in heads.enumerated() { o += headerCell(head.0, head.1, Box(xs[i], y, widths[i], 36)) }
        o += headerCell("Remark", "หมายเหตุ", Box(xs[7], y, widths[7], 36))
        o.append(Self.latin("Quantity (%)", 10, bold: true, at: Pt(xs[5] + (widths[5] + widths[6]) / 2, y + 9), align: .center))
        o.append(Self.latin("Today", 10, bold: true, at: Pt(xs[5] + widths[5] / 2, y + 27), align: .center))
        o.append(Self.latin("Accumulated", 10, bold: true, at: Pt(xs[6] + widths[6] / 2, y + 27), align: .center))
        o.append(.line(Pt(xs[5], y + 18), Pt(xs[7], y + 18), width: 1, color: .black))

        let aligns: [TextAlign] = [.center, .left, .center, .center, .center, .center, .center, .left]
        let latin: Set<Int> = [0, 3, 5, 6]
        let h = 36 + Double(rows.count) * 20
        for (r, cells) in rows.enumerated() {
            let top = y + 36 + Double(r) * 20
            if r > 0 { o.append(.line(Pt(x, top), Pt(x + w, top), width: 1, color: .black)) }
            for (i, c) in cells.enumerated() where i < widths.count && !c.isEmpty {
                o.append(cell(c, Box(xs[i], top, widths[i], 20), align: aligns[i], latin: latin.contains(i)))
            }
        }
        for i in 1..<widths.count {
            o.append(.line(Pt(xs[i], i == 6 ? y + 18 : y), Pt(xs[i], y + h), width: 1, color: .black))
        }
        o.append(.line(Pt(x, y + 36), Pt(x + w, y + 36), width: 1.5, color: .black))
        o.append(.rect(Box(x, y, w, h), stroke: .black, fill: nil, width: 1.5))
        return o
    }

    /// "Item" over "ลำดับที่", centred.
    func headerCell(_ en: String, _ th: String, _ b: Box) -> [DrawOp] {
        let cx = b.x + b.w / 2, cy = b.y + b.h / 2
        return [Self.latin(en, 10, bold: true, at: Pt(cx, cy - 7.5), align: .center),
                .text(th, at: Pt(cx, cy + 7.5), size: 11, bold: true, align: .center)]
    }

    /// One cell's text on one line, clipped to the cell: Helvetica 10 for numbers, Sarabun 11 otherwise.
    func cell(_ s: String, _ b: Box, align: TextAlign, latin: Bool) -> DrawOp {
        if latin { return Self.latin(s, 10, at: Pt(align == .center ? b.x + b.w / 2 : b.x + 8, b.y + b.h / 2), align: align) }
        let pad = align == .center ? 4.0 : 8
        return line(s, Box(b.x + pad, b.y, b.w - 2 * pad, b.h), size: 11, align: align)
    }

    /// One line of Sarabun centred down `b` and clipped to its width (a text box one line tall).
    func line(_ s: String, _ b: Box, size: Double, bold: Bool = false, align: TextAlign = .left) -> DrawOp {
        let h = measure.height("ก", width: 1000, size: size, bold: bold)
        return .textBox(s, Box(b.x, b.y + (b.h - h) / 2, b.w, h), size: size, bold: bold, align: align)
    }

    /// The station picture fitted in its box, with today's locations marked when it has them.
    func keyPlanPicture(_ k: KeyPlan, today: Set<String>, in box: Box) -> [DrawOp] {
        let f = box.fit(max(k.aspect, 0.01), 1)
        var o: [DrawOp] = [.photo(k.photo, f)]
        for p in k.points {
            let c = Pt(f.x + p.x * f.w, f.y + p.y * f.h), on = today.contains(p.name)
            o.append(.circle(c, r: on ? 7 : 5, stroke: on ? .white : Self.navy, fill: on ? Self.red : .white, width: 1.5))
            o.append(.rect(Box(c.x + 9, c.y - 7, measure.width(p.name, size: 9, bold: on) + 6, 14), stroke: nil, fill: RGBA(1, 1, 1, 0.85)))
            o.append(.text(p.name, at: Pt(c.x + 12, c.y), size: 9, bold: on, color: on ? Self.red : Self.navy))
        }
        return o
    }

    /// Photos in a grid: each a framed picture (a grey slot label when empty) over a 24 px caption box.
    func photoGrid(_ photos: [(Int, DayPhoto?)], columns: Int, rows: Int, x: Double, y: Double, w: Double, h: Double,
                   gap: (row: Double, column: Double), hints: Bool = true) -> [DrawOp] {
        let cw = (w - gap.column * Double(columns - 1)) / Double(columns)
        let ch = (h - gap.row * Double(rows - 1)) / Double(rows)
        var o: [DrawOp] = []
        for (i, item) in photos.prefix(columns * rows).enumerated() {
            let bx = x + Double(i % columns) * (cw + gap.column), by = y + Double(i / columns) * (ch + gap.row)
            let frame = Box(bx, by, cw, ch - 28)
            o.append(.rect(frame, stroke: .black, fill: nil, width: 1))
            let caption = Box(bx, by + ch - 24, cw, 24)
            o.append(.rect(caption, stroke: .black, fill: nil, width: 1))
            if let p = item.1 {
                o.append(.photoFill(p.photo, frame.inset(6)))
                o.append(line("รูปที่ \(item.0) \(p.caption)", Box(caption.x + 6, caption.y, caption.w - 12, 24), size: 10.5, align: .center))
            } else {
                if hints {
                    o.append(.text("พื้นที่ติดรูปที่ \(item.0)", at: Pt(frame.x + frame.w / 2, frame.y + frame.h / 2), size: 11,
                                   color: Self.hint, align: .center))
                }
                o.append(.text("รูปที่ \(item.0)", at: Pt(caption.x + 6, caption.y + 12), size: 10.5))
            }
        }
        return o
    }

    /// One half of the signature band: the drawn signature over the line, "( name )", the date and the role.
    func signature(_ label: (String, String), name: String, date: String?, drawn: Photo? = nil, role: String, x: Double, w: Double,
                   top: Double) -> [DrawOp] {
        let cx = x + w / 2
        // the 200 × 46 space above the line
        let sign: [DrawOp] = drawn.map { [.photo($0, Box(cx - 100, top + 33, 200, 44))] } ?? []
        return sign + [
            .runs([TextRun(label.0, size: 10, bold: true, face: .helvetica), TextRun(label.1, size: 11, bold: true)], at: Pt(x + 12, top + 22)),
            .line(Pt(cx - 100, top + 79), Pt(cx + 100, top + 79), width: 1, color: .black),
            .text("(", at: Pt(cx - 100, top + 90), size: 11),
            line(name, Box(cx - 92, top + 81, 184, 18), size: 11, align: .center),
            .text(")", at: Pt(cx + 100, top + 90), size: 11, align: .right),
            Self.latin("Date : " + (date ?? "......../......../........"), 10, at: Pt(cx - 100, top + 107)),
            Self.latin(role, 10, bold: true, at: Pt(cx, top + 122), align: .center),
        ]
    }

    // MARK: - Helpers

    static func latin(_ s: String, _ size: Double, bold: Bool = false, at: Pt, align: TextAlign = .left) -> DrawOp {
        .runs([TextRun(s, size: size, bold: bold, face: .helvetica)], at: at, align: align)
    }

    static func dotted(_ x: Double, _ y: Double, _ w: Double) -> DrawOp {
        .line(Pt(x, y), Pt(x + w, y), width: 1, color: hint, dash: [1, 2])
    }

    /// The contract sentence: the station's own when set, else the board's.
    static func contractText(_ s: RoutineReport.Settings) -> String {
        let own = s.contractName.trimmingCharacters(in: .whitespacesAndNewlines)
        return own.isEmpty ? "โครงการจัดการพลังงานไฟฟ้าจากระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์\nที่ติดตั้งบนหลังคา (Solar Rooftop) การประปาส่วนภูมิภาค" : own
    }

    /// "1-Jul-2025": English, Gregorian, Bangkok.
    static func formDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = RoutineReport.calendar.timeZone
        f.dateFormat = "d-MMM-yyyy"
        return f.string(from: d)
    }

    /// "1/7/2025" under a signature.
    static func signDate(_ d: Date) -> String {
        let c = RoutineReport.calendar.dateComponents([.year, .month, .day], from: d)
        let year = Calendar(identifier: .gregorian).component(.year, from: d)
        return "\(c.day ?? 0)/\(c.month ?? 0)/\(year)"
    }

    /// "08.00 AM - 18.00 PM", as the customer's form writes it (open question 2).
    static func workingTime(_ start: String, _ end: String) -> String {
        func one(_ t: String) -> String {
            let s = t.replacingOccurrences(of: ":", with: ".").trimmingCharacters(in: .whitespaces)
            guard let h = Int(s.prefix { $0.isNumber }) else { return s }
            return s + (h < 12 ? " AM" : " PM")
        }
        return one(start) + " - " + one(end)
    }

    /// Tops of blocks spread from `top` to `bottom`, the first at the top and the last at the bottom (CSS space-between).
    static func spaced(_ heights: [Double], top: Double, bottom: Double) -> [Double] {
        let gap = heights.count > 1 ? max(0, bottom - top - heights.reduce(0, +)) / Double(heights.count - 1) : 0
        var y = top, out: [Double] = []
        for h in heights { out.append(y); y += h + gap }
        return out
    }

    static func chunks(_ count: Int, _ size: Int) -> Int { (count + size - 1) / size }

    /// The `i`th page's share of a list, with each item's index in the whole list.
    static func slice<T>(_ list: [T], _ i: Int, _ size: Int) -> [(offset: Int, element: T)] {
        Array(list.enumerated()).dropFirst(i * size).prefix(size).map { ($0.offset, $0.element) }
    }

    static func padded(_ rows: [[String]], _ count: Int, columns: Int) -> [[String]] {
        rows + Array(repeating: Array(repeating: "", count: columns), count: max(0, count - rows.count))
    }
}
