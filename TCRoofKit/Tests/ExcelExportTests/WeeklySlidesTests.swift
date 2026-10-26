import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// `WeeklySlides`: R3 as a .pptx in the customer's `Weekly Report Template`, 8 slides, built on `weekly_template.pptx`.
final class WeeklySlidesTests: XCTestCase {
    let cal = MasterSchedule.calendar

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    /// A small real JPEG (the IEC form's PWA logo, 220 × 222).
    func jpeg() throws -> Data { try XCTUnwrap(ZipArchive(IECExcel.template()).data("xl/media/image1.jpeg")) }

    /// MP 189's plan; the week of 8 มี.ค. 2569 (Sunday) with reports on Monday (signed, no photos), Tuesday (signed, the
    /// photos, a problem) and Wednesday (not signed), as of Saturday.
    func input(photos: [WeeklySlides.DayPhoto], wedSigned: Bool = false) -> WeeklySlides.Input {
        let plan = MasterSchedule.Input(installStart: day(2026, 2, 22), installEnd: day(2026, 4, 8), kickoff: day(2026, 1, 5),
                                        engineeringStart: day(2026, 1, 5), siteHandover: day(2026, 1, 12), over200kVA: false)
        var a = RoutineReport.Daily(date: day(2026, 3, 9))
        a.progress = [.init(task: .structure, description: "ติดตั้งโครงสร้าง", location: "โซน A", percent: 40)]
        a.weather[0] = .fine; a.weather[1] = .fine
        var b = RoutineReport.Daily(date: day(2026, 3, 10))
        b.progress = [.init(task: .structure, description: "ติดตั้งโครงสร้าง", location: "โซน A", percent: 60)]
        b.weather[8] = .rain
        b.problems = [.init(description: "ฝนตก <บ่าย> & ลมแรง", solution: "เลื่อนเป็นช่วงเช้า", since: day(2026, 3, 10))]
        var c = RoutineReport.Daily(date: day(2026, 3, 11))
        c.progress = [.init(task: .structure, description: "ติดตั้งโครงสร้าง", location: "โซน A", percent: 70)]
        let days: [WeeklySlides.Day] = [.init(report: a, photos: []), .init(report: b, photos: photos),
                                        .init(report: c, photos: [], signed: wedSigned)]
        return WeeklySlides.Input(stationName: "ทุ่งน้อย", mpNumber: 189, capacityKWp: 92.34, settings: RoutineReport.Settings(),
                                  week: day(2026, 3, 11), days: days, all: [a, b, c], schedule: (plan, MasterSchedule.Actual()),
                                  nextRequest: nil, installStart: day(2026, 2, 22), asOf: day(2026, 3, 14))
    }

    func slides(_ zip: ZipArchive) throws -> [String] {
        let pres = try XCTUnwrap(zip.string("ppt/presentation.xml"))
        let count = pres.components(separatedBy: "<p:sldId ").count - 1
        return try (1...max(count, 1)).map { try XCTUnwrap(zip.string("ppt/slides/slide\($0).xml"), "slide \($0)") }
    }

    /// Cover, AGENDA, progress, the day table, a photo slide per two photos, weather and problems.
    func testTheSlidesInTheCustomersOrder() throws {
        let photos = (0..<5).map { WeeklySlides.DayPhoto(id: UUID(), width: 220, height: 222, caption: "รูป \($0)") }
        let bytes = try jpeg()
        let zip = try ZipArchive(WeeklySlides.export(input(photos: photos), images: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, bytes) })))
        let s = try slides(zip)
        XCTAssertEqual(s.count, 4 + 3 + 2, "five photos: three photo slides")
        let types = try XCTUnwrap(zip.string("[Content_Types].xml")), rels = try XCTUnwrap(zip.string("ppt/_rels/presentation.xml.rels"))
        for n in 1...s.count {
            XCTAssertTrue(types.contains("/ppt/slides/slide\(n).xml"))
            XCTAssertTrue(rels.contains("Target=\"slides/slide\(n).xml\""))
            // every picture a slide names is in the package
            let r = try XCTUnwrap(zip.string("ppt/slides/_rels/slide\(n).xml.rels"))
            for part in r.components(separatedBy: "Target=\"../media/").dropFirst() {
                XCTAssertNotNil(zip.data("ppt/media/" + part.prefix { $0 != "\"" }), "slide \(n)")
            }
        }
        // the order: cover, AGENDA, progress, the day table, the photo slides, weather, problems
        XCTAssertTrue(s[0].contains("Weekly Report") && s[0].contains("สถานีผลิตน้ำทุ่งน้อย"))
        XCTAssertTrue(s[0].contains("ประจำวันที่ 8 มีนาคม 2569 ถึงวันที่ 14 มีนาคม 2569"))
        XCTAssertTrue(s[1].contains("AGENDA") && s[1].contains("CONSTRUCTION PROGRESS") && s[1].contains("Weather Report"))
        XCTAssertTrue(s[2].contains("ความก้าวหน้าของงาน") && s[2].contains("% WORK PROGRESS"))
        XCTAssertTrue(s[3].contains("การดำเนินงาน") && s[3].contains("-ติดตั้งโครงสร้าง | โซน A"), "done work starts with -")
        XCTAssertTrue(s[3].contains("สถานีผลิตน้ำทุ่งน้อย ดำเนินงาน 8–14 มีนาคม 2569"))
        XCTAssertTrue(s[2].contains("ช่วงระหว่างวันที่ 8 มีนาคม 2569 ถึง วันที่ 14 มีนาคม 2569"))
        XCTAssertTrue((4...6).allSatisfy { s[$0].contains("PROGRESS FOR THIS WEEK") })
        XCTAssertTrue(s[7].contains("2.Weather Report") && s[7].contains("ฝนตก") && s[7].contains("แจ่มใส"))
        XCTAssertTrue(s[7].contains(">MON<") && s[7].contains(">SUN<"))
        XCTAssertTrue(s[8].contains("ปัญหาและอุปสรรคระหว่างปฏิบัติงาน") && s[8].contains("แนวทางแก้ไข"))
        XCTAssertTrue(s[8].contains("ฝนตก &lt;บ่าย&gt; &amp; ลมแรง"), "text is escaped")
        XCTAssertTrue(s[8].contains("เลื่อนเป็นช่วงเช้า"))
        // two photos a slide, captioned with the work and the date
        XCTAssertTrue(s[4].contains("รูป 0 10/03/2569") && s[4].contains("รูป 1 10/03/2569") && !s[4].contains("รูป 2"))
        XCTAssertTrue(s[6].contains("รูป 4 10/03/2569"))
        XCTAssertEqual(s[6].components(separatedBy: "<p:pic>").count - 1, 1, "the last slide's single photo")
    }

    /// The template's pictures are in the package: the seal on the cover, AGENDA's three markers, the weather icons used.
    func testTheTemplatesPictures() throws {
        for name in ["logo-pea-seal", "agenda-hex-1", "agenda-hex-2", "agenda-hex-3", "weather-sunny", "weather-partly-cloudy", "weather-thunderstorm"] {
            XCTAssertNotNil(WeeklySlides.templatePicture(name), name)
        }
        let zip = try ZipArchive(WeeklySlides.export(input(photos: []), images: [:]))
        let seal = try XCTUnwrap(WeeklySlides.templatePicture("logo-pea-seal"))
        let media = (1...20).compactMap { zip.data("ppt/media/image\($0).png") }
        XCTAssertTrue(media.contains(seal))
        XCTAssertTrue(media.contains(try XCTUnwrap(WeeklySlides.templatePicture("agenda-hex-3"))))
        XCTAssertTrue(media.contains(try XCTUnwrap(WeeklySlides.templatePicture("weather-thunderstorm"))))
        XCTAssertEqual(try slides(zip)[0].components(separatedBy: "<p:pic>").count - 1, 1, "the seal")
        XCTAssertEqual(try slides(zip)[1].components(separatedBy: "<p:pic>").count - 1, 3, "the three markers")
        XCTAssertEqual(try slides(zip).count, 7, "no photos: one empty photo slide")
    }

    /// An unsigned working day waits: its row in the day table, and the day table, weather and problems in the outline.
    func testAWaitingDay() throws {
        let c = WeeklySlides.content(input(photos: []))
        XCTAssertEqual(c.waiting, ["พ 11/3", "พฤ 12/3", "ศ 13/3", "ส 14/3"], "unsigned, then working days with no report")
        XCTAssertEqual(c.rows.count, 7)
        XCTAssertEqual(c.rows[0].state, .off, "Sunday")
        XCTAssertEqual(c.rows[1].state, .done)
        XCTAssertEqual(c.rows[3].state, .waiting)
        XCTAssertEqual(c.rows[3].lines, ["รอเซ็นรายงานประจำวัน พ 11/3"])
        // Thursday to Saturday have no report: working days already past, so they wait too
        XCTAssertEqual(c.rows[4].lines, ["ยังไม่มีรายงานประจำวัน พฤ 12/3"])
        let o = WeeklySlides.outline(input(photos: []))
        XCTAssertEqual(o.map(\.label), ["ปก", "AGENDA", "ความก้าวหน้า", "งานรายวัน", "ภาพหน้างาน", "Weather Report", "ปัญหาและอุปสรรค"])
        XCTAssertEqual(o.map(\.number), Array(1...7))
        XCTAssertEqual(o.filter { !$0.ready }.map(\.number), [4, 5, 6, 7], "no photos either")
        let zip = try ZipArchive(WeeklySlides.export(input(photos: []), images: [:]))
        XCTAssertTrue(try slides(zip)[3].contains("รอเซ็นรายงานประจำวัน พ 11/3"))
        XCTAssertTrue(try slides(zip)[3].contains("i=\"1\""), "the waiting row in italic")
    }

    /// A week whose working days are all signed: every slide is ready.
    func testEverySignedDayIsReady() {
        var i = input(photos: [WeeklySlides.DayPhoto(id: UUID(), width: 1, height: 1, caption: "")], wedSigned: true)
        i.asOf = day(2026, 3, 11)
        let o = WeeklySlides.outline(i)
        XCTAssertTrue(o.allSatisfy(\.ready), o.filter { !$0.ready }.map(\.label).joined(separator: ", "))
        // Thursday onwards is still ahead
        XCTAssertEqual(WeeklySlides.content(i).rows[4].state, .ahead)
    }

    /// The week's photos day by day, two a slide, at most twenty.
    func testPhotosTwoASlide() {
        var i = input(photos: [])
        let p = (0..<3).map { n in (0..<9).map { k in WeeklySlides.DayPhoto(id: UUID(), width: 1, height: 1, caption: "d\(n)p\(k)") } }
        i.days = i.days.indices.map { d in WeeklySlides.Day(report: i.days[d].report, photos: p[d], signed: true) }
        let c = WeeklySlides.content(i)
        XCTAssertEqual(c.photos.count, WeeklySlides.maxPhotos)
        XCTAssertEqual(c.photos.prefix(3).map { String($0.caption.prefix(4)) }, ["d0p0", "d0p1", "d0p2"], "day by day")
        XCTAssertEqual(c.photoPages, 10)
        XCTAssertEqual(c.photos(page: 9).count, 2)
        XCTAssertEqual(c.photoCount, 27)
        let o = c.outline
        XCTAssertEqual(o.filter { $0.kind == .photos }.map(\.label).first, "ภาพหน้างาน 1/10")
        XCTAssertEqual(o.last?.number, 4 + 10 + 2)
    }

    /// Six weeks of plan and actual, the current one last, and the % box.
    func testProgressBars() {
        let c = WeeklySlides.content(input(photos: []))
        XCTAssertEqual(c.bars.count, 6)
        XCTAssertEqual(c.bars.last?.label, "W11")
        XCTAssertEqual(c.bars.filter(\.current).count, 1)
        XCTAssertEqual(c.bars.map(\.planned), c.bars.map(\.planned).sorted(), "cumulative")
        XCTAssertNotNil(c.status)
        var none = input(photos: [])
        none.schedule = nil
        let n = WeeklySlides.content(none)
        XCTAssertTrue(n.bars.isEmpty)
        XCTAssertFalse(n.outline[2].ready)
    }

    /// The customer's deck: text in TH SarabunPSK at its point sizes (band title 36 pt, cover title 54 pt, the day table in
    /// TH Sarabun New at 16 pt with an 18 pt header and 1 pt borders), the cover's lines in its grey.
    func testTheCustomersFontsAndSizes() throws {
        let s = try slides(ZipArchive(WeeklySlides.export(input(photos: []), images: [:])))
        XCTAssertTrue(s[0].contains("typeface=\"TH SarabunPSK\""))
        XCTAssertTrue(s[0].contains("sz=\"5400\" b=\"1\""), "Weekly Report 54 pt bold")
        XCTAssertTrue(s[0].contains("6E747A"), "the cover's grey")
        XCTAssertTrue(s[2].contains("sz=\"3600\""), "the band title")
        XCTAssertTrue(s[3].contains("typeface=\"TH Sarabun New\"") && s[3].contains("sz=\"1600\"") && s[3].contains("sz=\"1800\""))
        XCTAssertTrue(s[3].contains("w=\"12700\""), "1 pt borders")
    }

    func testFileName() {
        XCTAssertEqual(WeeklySlides.fileName(week: day(2026, 3, 11), station: "สถานีผลิตน้ำทุ่งน้อย"),
                       "2569-03-08 รายงานประจำสัปดาห์ สถานีผลิตน้ำทุ่งน้อย.pptx")
    }
}
