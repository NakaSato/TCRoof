import XCTest
@testable import ExcelExport
@testable import TCRoofCore

/// `WeeklySlides`: R3 as a .pptx built on `weekly_template.pptx`.
final class WeeklySlidesTests: XCTestCase {
    let cal = MasterSchedule.calendar

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    /// A small real JPEG (the IEC form's PWA logo, 220 × 222).
    func jpeg() throws -> Data { try XCTUnwrap(ZipArchive(IECExcel.template()).data("xl/media/image1.jpeg")) }

    /// MP 189's plan; the week of 8 มี.ค. 2569 with two daily reports, the second with 5 photos and a problem.
    func input(photos: [WeeklySlides.DayPhoto]) -> WeeklySlides.Input {
        let plan = MasterSchedule.Input(installStart: day(2026, 2, 22), installEnd: day(2026, 4, 8), kickoff: day(2026, 1, 5),
                                        engineeringStart: day(2026, 1, 5), siteHandover: day(2026, 1, 12), over200kVA: false)
        var a = RoutineReport.Daily(date: day(2026, 3, 9))
        a.progress = [.init(task: .structure, description: "ติดตั้งโครงสร้าง", location: "โซน A", percent: 40)]
        a.crew = [.init(name: "ช่างติดตั้ง", count: 4)]; a.crewConfirmed = true
        a.weather[0] = .fine; a.weather[8] = .rain
        var b = RoutineReport.Daily(date: day(2026, 3, 10))
        b.progress = [.init(task: .structure, description: "ติดตั้งโครงสร้าง", location: "โซน A", percent: 60)]
        b.crew = [.init(name: "ช่างติดตั้ง", count: 5)]
        b.problems = [.init(description: "ฝนตก <บ่าย> & ลมแรง", solution: "เลื่อนเป็นช่วงเช้า", since: day(2026, 3, 10))]
        var next = RoutineReport.WeeklyRequest(weekStart: day(2026, 3, 15))
        next.work = [.init(task: .dcSide, description: "เดินสาย DC", location: "โซน A")]
        var settings = RoutineReport.Settings()
        settings.contractName = "Solar Rooftop กปภ."
        return WeeklySlides.Input(stationName: "สถานีผลิตน้ำทุ่งน้อย", mpNumber: 189, capacityKWp: 92.34, settings: settings,
                                  week: day(2026, 3, 11), days: [.init(report: a, photos: []), .init(report: b, photos: photos)],
                                  all: [a, b], schedule: (plan, MasterSchedule.Actual()), nextRequest: next,
                                  installStart: day(2026, 2, 22), asOf: day(2026, 3, 14))
    }

    func testBuildsTheDeck() throws {
        let photos = (0..<5).map { WeeklySlides.DayPhoto(id: UUID(), width: 220, height: 222, caption: $0 == 4 ? "" : "รูป \($0)") }
        let bytes = try jpeg()
        let data = try WeeklySlides.export(input(photos: photos), images: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, bytes) }))
        let zip = try ZipArchive(data)

        let pres = try XCTUnwrap(zip.string("ppt/presentation.xml"))
        let count = pres.components(separatedBy: "<p:sldId ").count - 1
        // cover, progress (2: the plan's weighted tasks are more than 14), 2 days, weather, labour, problems, next week
        let weighted = MasterSchedule.plan(input(photos: []).schedule!.input).filter { $0.weight > 0 }.count
        XCTAssertEqual(count, 1 + (weighted + 13) / 14 + 2 + 1 + 1 + 1 + 1)
        let types = try XCTUnwrap(zip.string("[Content_Types].xml")), rels = try XCTUnwrap(zip.string("ppt/_rels/presentation.xml.rels"))
        for n in 1...count {
            XCTAssertNotNil(zip.string("ppt/slides/slide\(n).xml"), "slide \(n)")
            XCTAssertTrue(types.contains("/ppt/slides/slide\(n).xml"))
            XCTAssertTrue(rels.contains("Target=\"slides/slide\(n).xml\""))
            // every picture a slide names is in the package
            let r = try XCTUnwrap(zip.string("ppt/slides/_rels/slide\(n).xml.rels"))
            for part in r.components(separatedBy: "Target=\"../media/").dropFirst() {
                XCTAssertNotNil(zip.data("ppt/media/" + part.prefix { $0 != "\"" }))
            }
        }

        let all = (1...count).compactMap { zip.string("ppt/slides/slide\($0).xml") }.joined()
        XCTAssertTrue(all.contains("รายงานประจำสัปดาห์ (Weekly Report)"))
        XCTAssertTrue(all.contains("MP 189 | สถานีผลิตน้ำทุ่งน้อย | 92.34 kWp"))
        XCTAssertTrue(all.contains("ติดตั้งโครงสร้าง | โซน A  +20%"), "the day's delta from the day before")
        XCTAssertTrue(all.contains("ฝนตก &lt;บ่าย&gt; &amp; ลมแรง"), "text is escaped")
        XCTAssertTrue(all.contains("เดินสาย DC"))
        XCTAssertTrue(all.contains("* 1 วันใช้กำลังคนจากวันก่อนโดยไม่ได้ยืนยัน"))
        // the 4 captioned photos of the second day, not the fifth
        XCTAssertEqual(all.components(separatedBy: "<p:pic>").count - 1, 4)
        XCTAssertEqual(zip.data("ppt/media/image1.jpeg"), bytes)
    }

    func testAWeekWithNothing() throws {
        var i = input(photos: [])
        i.days = []; i.all = []; i.schedule = nil; i.nextRequest = nil
        let zip = try ZipArchive(WeeklySlides.export(i, images: [:]))
        let pres = try XCTUnwrap(zip.string("ppt/presentation.xml"))
        // cover, weather, labour, problems, next week
        XCTAssertEqual(pres.components(separatedBy: "<p:sldId ").count - 1, 5)
        let all = (1...5).compactMap { zip.string("ppt/slides/slide\($0).xml") }.joined()
        XCTAssertTrue(all.contains("ยังไม่มีคำขอปฏิบัติงานสัปดาห์ถัดไป"))
        XCTAssertTrue(all.contains("วันทำงานที่ไม่มีรายงานประจำวัน"))
    }

    func testFileName() {
        XCTAssertEqual(WeeklySlides.fileName(week: day(2026, 3, 11), station: "สถานีผลิตน้ำทุ่งน้อย"),
                       "2569-03-08 รายงานประจำสัปดาห์ สถานีผลิตน้ำทุ่งน้อย.pptx")
    }
}
