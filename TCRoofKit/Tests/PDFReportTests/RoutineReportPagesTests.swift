import XCTest
@testable import PDFReport
@testable import TCRoofCore

final class RoutineReportPagesTests: XCTestCase {
    private let cal = RoutineReport.calendar
    private func d(_ day: Int, _ m: Int = 7) -> Date { cal.date(from: DateComponents(year: 2025, month: m, day: day))! }

    private var pages: RoutineReportPages {
        var s = RoutineReport.Settings()
        s.siteEngineer = "วิศวกร ทดสอบ"; s.inspector = "ผู้ตรวจ ทดสอบ"
        return RoutineReportPages(station: .init(name: "สถานีผลิตน้ำโชคชัย", code: "J-1", mpNumber: 189, capacityKWp: 92.34, settings: s))
    }

    private func texts(_ p: [ReportLayout.Page]) -> [String] {
        p.flatMap(\.ops).compactMap {
            switch $0 {
            case let .text(t, _, _, _, _, _, _), let .textBox(t, _, _, _, _, _): t
            case let .runs(rs, _, _, _): rs.map(\.text).joined()
            default: nil
            }
        }
    }

    private func report(_ day: Int, _ pct: Double, lines: Int = 1) -> RoutineReport.Daily {
        var r = RoutineReport.Daily(date: d(day))
        r.crew = [.init(name: "ผู้ปฏิบัติงาน", count: 7), .init(name: "หัวหน้างาน", count: 1)]
        r.crewConfirmed = true
        r.weather = RoutineReport.weatherHours.map { $0 < 9 ? .rain : .fine }
        r.progress = (0..<lines).map { .init(task: .structure, description: "ติดตั้งราง", location: "หลังคา \($0 + 1)", percent: pct) }
        return r
    }

    private func entry(_ r: RoutineReport.Daily, photos: Int = 0, signed: Date? = nil, ack: Date? = nil) -> RoutineReportPages.DailyEntry {
        .init(report: r, photos: (0..<photos).map { .init(photo: Photo(fileName: "p\($0).jpg", width: 4, height: 3), date: r.date, caption: "ภาพ \($0 + 1)") },
              engineerSignedAt: signed, inspectorAckAt: ack)
    }

    /// Runs and plain texts with their anchor x, for checking where a mark lands.
    private func placed(_ page: ReportLayout.Page) -> [(String, Double)] {
        page.ops.compactMap {
            switch $0 {
            case let .runs(rs, at, _, _): (rs.map(\.text).joined(), at.x)
            case let .text(t, at, _, _, _, _, _): (t, at.x)
            default: nil
            }
        }
    }

    func testFourPhotosGiveThreePagesAndNineGiveFour() {
        let r = report(1, 20)
        let three = pages.daily(entry(r, photos: 4), all: [r])
        XCTAssertEqual(three.count, 3)
        XCTAssertTrue(texts(three).contains("3 / 3"))
        XCTAssertEqual(three.map(\.width), Array(repeating: RoutineReportPages.dailyFormPage.w, count: 3))
        let four = pages.daily(entry(r, photos: 9), all: [r])
        XCTAssertEqual(four.count, 4)
        XCTAssertTrue(texts([four[3]]).contains("SITE PHOTOS (CONTINUED) ภาพถ่ายหน้างาน (ต่อ)"))
        XCTAssertTrue(texts([four[3]]).contains("รูปที่ 9 ภาพ 9"))
        XCTAssertEqual(four[3].ops.filter { if case .photoFill = $0 { true } else { false } }.count, 5)
        // eleven photos still fit on one more page
        XCTAssertEqual(pages.daily(entry(r, photos: 10), all: [r]).count, 4)
        XCTAssertEqual(pages.daily(entry(r, photos: 11), all: [r]).count, 5)
    }

    func testTwentyCrewLinesGiveAnExtraFirstPage() {
        var r = report(1, 20)
        r.crew = (1...20).map { .init(name: "ช่าง \($0)", count: 1) }
        let p = pages.daily(entry(r), all: [r])
        XCTAssertEqual(p.count, 4)
        XCTAssertTrue(texts([p[0]]).contains("ช่าง 17"))
        XCTAssertFalse(texts([p[0]]).contains("ช่าง 18"))
        XCTAssertTrue(texts([p[1]]).contains("ช่าง 18"))
        XCTAssertTrue(texts([p[1]]).contains("18"))                      // the numbering carries on
        XCTAssertTrue(texts([p[1]]).contains("MANPOWER REPORT กำลังคน"))  // with the header and title
        XCTAssertTrue(texts([p[1]]).contains("DAILY REPORT"))
        XCTAssertEqual(texts([p[1]]).filter { $0 == "20" }.count, 2)      // row 20 and Total Man-Day
    }

    func testWeatherMarksLandInTheirHourCells() {
        var r = report(1, 20)
        r.weather = RoutineReport.weatherHours.map { $0 >= 14 && $0 <= 17 ? .rain : $0 == 8 ? .cloudy : $0 == 20 ? nil : .fine }
        let page = pages.daily(entry(r), all: [r])[0]
        let items = placed(page)
        for (h, want) in [(6, "F"), (8, "C"), (13, "F"), (14, "R"), (17, "R"), (18, "F")] {
            let x = items.first { $0.0 == String(format: "%02d:00", h) }!.1
            XCTAssertTrue(items.contains { $0.0 == want && abs($0.1 - x) < 0.01 }, "\(h):00 should be \(want)")
        }
        let x20 = items.first { $0.0 == "20:00" }!.1
        XCTAssertFalse(items.contains { ["F", "C", "R"].contains($0.0) && abs($0.1 - x20) < 0.01 })   // not filled
        let rain = page.ops.filter { if case let .rect(_, _, f?, _) = $0 { f == RoutineReportPages.rainFill } else { false } }
        XCTAssertEqual(rain.count, 4 + 1)   // four hours and the legend
        XCTAssertTrue(texts([page]).contains(": Cloudy เมฆครึ้ม"))
    }

    func testHeaderReadsTheDateInEnglishAndTheStation() {
        let r = report(1, 20)
        let t = texts([pages.daily(entry(r), all: [r])[0]])
        XCTAssertTrue(t.contains("1-Jul-2025"))
        XCTAssertTrue(t.contains("Working Time: 08.00 AM - 18.00 PM"))
        XCTAssertTrue(t.contains("กำลังการผลิตติดตั้ง 92.34 กิโลวัตต์"))
        XCTAssertTrue(t.contains("ชื่อโครงการ : สถานีผลิตน้ำโชคชัย"))
        XCTAssertTrue(t.contains("บริษัท ทีซี รีนิวอะเบิ้ล เอ็นเนอร์ยี่ จำกัด"))
        XCTAssertTrue(t.contains("Total Man-Day"))
        XCTAssertEqual(RoutineReportPages.formDate(d(23, 12)), "23-Dec-2025")
        var st = RoutineReportPages.Station(name: "สถานีผลิตน้ำโชคชัย", code: "", mpNumber: nil, capacityKWp: 0, settings: .init(), branch: "สาขาโชคชัย")
        XCTAssertEqual(st.projectLine, "สถานีผลิตน้ำโชคชัย การประปาส่วนภูมิภาคสาขาโชคชัย")
        st.branch = "โชคชัย"
        XCTAssertEqual(st.projectLine, "สถานีผลิตน้ำโชคชัย การประปาส่วนภูมิภาคสาขาโชคชัย")
    }

    func testProgressShowsTodayAndAccumulated() {
        let all = [report(1, 20), report(2, 45)]
        let t = texts(pages.daily(entry(all[1]), all: all))
        XCTAssertTrue(t.contains("ติดตั้งราง"))
        XCTAssertTrue(t.contains("25%"))
        XCTAssertTrue(t.contains("45%"))
        XCTAssertTrue(t.contains("งาน"))
        var stopped = RoutineReport.Daily(date: d(3))
        stopped.stopReason = "ฝนตกทั้งวัน"
        XCTAssertTrue(texts(pages.daily(entry(stopped), all: [stopped])).contains("หยุดงาน: ฝนตกทั้งวัน"))
    }

    func testASignedReportPrintsTheSignDates() {
        let r = report(2, 45)
        let t = texts(pages.daily(entry(r, signed: d(2), ack: d(3)), all: [r]))
        XCTAssertTrue(t.contains("Date : 2/7/2025"))
        XCTAssertTrue(t.contains("Date : 3/7/2025"))
        XCTAssertTrue(t.contains("วิศวกร ทดสอบ"))
        XCTAssertTrue(t.contains("ผู้ตรวจ ทดสอบ"))
        let unsigned = texts(pages.daily(entry(r), all: [r]))
        XCTAssertEqual(unsigned.filter { $0 == "Date : ......../......../........" }.count, 2)
    }

    func testDrawnSignaturesPrintOnlyWhileSigned() {
        let r = report(2, 45)
        let eng = Photo(fileName: "eng.png", width: 400, height: 90), insp = Photo(fileName: "insp.png", width: 400, height: 90)
        func drawn(_ e: RoutineReportPages.DailyEntry) -> [String] {
            pages.daily(e, all: [r])[2].ops.compactMap { if case let .photo(p, _) = $0, p.fileName.hasSuffix(".png") { p.fileName } else { nil } }
        }
        let both = RoutineReportPages.DailyEntry(report: r, photos: [], engineerSignedAt: d(2), inspectorAckAt: d(3),
                                                 engineerSignature: eng, inspectorSignature: insp)
        XCTAssertEqual(drawn(both).filter { $0 != "pdfreport-form:form-logo-tc.png" && $0 != "pdfreport-form:form-logo-pea.png" }, ["eng.png", "insp.png"])
        var unacked = both; unacked.inspectorAckAt = nil
        XCTAssertFalse(drawn(unacked).contains("insp.png"))   // a signature whose acknowledgement was taken off
    }

    func testKeyPlanMarksTodaysLocations() {
        let r = report(1, 20)   // หลังคา 1
        let k = RoutineReportPages.KeyPlan(photo: Photo(fileName: "site.jpg", width: 1600, height: 900), aspect: 16 / 9,
                                          points: [("หลังคา 1", 0.2, 0.3), ("ถังน้ำใส 1", 0.7, 0.6)])
        let p = pages.daily(entry(r), all: [r], keyPlan: k)
        XCTAssertTrue(texts([p[1]]).contains("KEY PLAN ผังตำแหน่งงาน"))
        let fills = p[1].ops.compactMap { op -> RGBA? in if case let .circle(_, _, _, f?, _) = op { f } else { nil } }
        XCTAssertEqual(fills, [RoutineReportPages.red, .white])
        XCTAssertTrue(p[1].ops.contains { if case let .photo(ph, _) = $0 { ph.fileName == "site.jpg" } else { false } })
    }

    func testEverythingStaysInsideThePage() {
        var r = report(1, 10, lines: 14)
        r.materials = (1...12).map { .init(name: "วัสดุ \($0)", location: "หลังคา", qty: 2, unit: "ชุด") }
        r.problems = (1...7).map { .init(description: "ปัญหา \($0)", since: d(1)) }
        let p = pages.daily(entry(r, photos: 7), all: [r])
        XCTAssertEqual(p.count, 2 + 3 + 1 + 1)   // materials, progress and photos each overflow
        XCTAssertTrue(texts(p).contains("วัสดุ 12"))
        XCTAssertTrue(texts(p).contains("ปัญหา 7"))
        let size = RoutineReportPages.dailyFormPage
        for page in p {
            for op in page.ops {
                if case let .rect(b, _, _, _) = op { XCTAssertLessThanOrEqual(b.maxY, size.h); XCTAssertLessThanOrEqual(b.maxX, size.w) }
            }
        }
    }

    func testTheBlankFormHasFourPages() {
        let p = RoutineReportPages.dailyBlankForm()
        XCTAssertEqual(p.count, 4)
        let t = texts(p)
        XCTAssertTrue(t.contains("4 / 4"))
        XCTAssertTrue(t.contains("15"))
        XCTAssertTrue(t.contains("พื้นที่แนบผังตำแหน่งงาน (Key Plan)"))
        XCTAssertTrue(t.contains("พื้นที่ติดรูปที่ 10"))
        XCTAssertFalse(t.contains { $0.hasPrefix("ชื่อโครงการ : ส") })
        let dotted = p[0].ops.filter { if case let .line(_, _, _, _, dash) = $0 { !dash.isEmpty } else { false } }
        XCTAssertEqual(dotted.count, 4)   // kWp, date, working time, station
    }

    func testWeeklyListsWorkDoneManDaysAndMissingDays() {
        let all = [report(7, 10), report(8, 30), report(10, 30)]
        let entries = all.map { RoutineReportPages.DailyEntry(report: $0, photos: [], engineerSignedAt: nil, inspectorAckAt: nil) }
        let t = texts(pages.weekly(week: d(9), entries: entries, all: all, schedule: nil, nextRequest: nil, installStart: d(1)))
        XCTAssertTrue(t.contains { $0.contains("+20%") })
        XCTAssertTrue(t.contains("24"))                      // 3 days × 8 people
        XCTAssertTrue(t.contains { $0.contains("9 ก.ค. 2568") && $0.contains("ไม่มีรายงาน") })
        XCTAssertTrue(t.contains("ฝนตกรวม 9 ชั่วโมง ใน 3 วัน"))
    }

    func testMonthlyPlanStopsAtTodayForTheRunningMonth() {
        let input = MasterSchedule.Input(installStart: d(1), installEnd: d(31), kickoff: d(1, 5), engineeringStart: d(1, 5),
                                         siteHandover: d(1, 6), over200kVA: false)
        let all = [report(8, 10)]
        let e = all.map { RoutineReportPages.DailyEntry(report: $0, photos: [], engineerSignedAt: nil, inspectorAckAt: nil) }
        func planned(asOf: Date) -> String? {
            let t = texts(pages.monthly(month: d(15), entries: e, all: all, schedule: .init(input: input, actual: .init()),
                                        installStart: d(1), asOf: asOf))
            return t.firstIndex(of: "แผนสะสม").map { t[$0 + 1] }
        }
        let midMonth = planned(asOf: d(8)), monthEnd = planned(asOf: d(31))
        XCTAssertNotNil(midMonth)
        XCTAssertNotEqual(midMonth, monthEnd)
        XCTAssertEqual(planned(asOf: d(1, 9)), monthEnd)     // a finished month reports the whole month
    }

    func testMonthlyTitleTurnsToCompleteAt100Percent() {
        let input = MasterSchedule.Input(installStart: d(1), installEnd: d(31), kickoff: d(1, 5), engineeringStart: d(1, 5),
                                         siteHandover: d(1, 6), over200kVA: false)
        var a = MasterSchedule.Actual()
        for t in MasterSchedule.Task.allCases { a.setPercent(100, task: t, week: d(20), over200kVA: false) }
        let all = [report(20, 100)]
        let e = all.map { RoutineReportPages.DailyEntry(report: $0, photos: [], engineerSignedAt: nil, inspectorAckAt: nil) }
        let done = texts(pages.monthly(month: d(15), entries: e, all: all, schedule: .init(input: input, actual: a), installStart: d(1)))
        XCTAssertTrue(done.contains("รายงานผลการติดตั้งแล้วเสร็จ 100%"))
        let partial = texts(pages.monthly(month: d(15), entries: e, all: all, schedule: .init(input: input, actual: .init()), installStart: d(1)))
        XCTAssertTrue(partial.contains("รายงานผลความก้าวหน้าประจำเดือน"))
        XCTAssertTrue(partial.contains("ส่วนที่ 4 สรุปแรงงาน"))
        XCTAssertTrue(partial.contains("สถานะการยื่นขออนุญาต"))
        XCTAssertTrue(partial.contains("ยื่นขอขนานไฟ"))
    }

    // MARK: R1 in the WORK REQUEST form (docs/ui/weekly-request-pdf)

    private func request(work: Int = 3) -> RoutineReport.WeeklyRequest {
        // the week of Monday 14 to Sunday 20 July 2025
        var r = RoutineReport.WeeklyRequest(weekStart: d(13))
        r.crew = [.init(name: "ผู้ควบคุมงาน", count: 1), .init(name: "หัวหน้างาน", count: 1), .init(name: "ผู้ปฏิบัติงาน", count: 5),
                  .init(name: "ช่างไฟฟ้า", count: 0)]
        r.tools = [.init(name: "สว่านไฟฟ้า", count: 2), .init(name: "บันได", count: 1)]
        r.work = (0..<work).map { .init(task: .panels, description: "ติดตั้งแผง \($0 + 1)", location: "หลังคา 1", qty: 1, unit: "งาน") }
        r.risks = [.init(description: "งานบนที่สูง", level: .high, prevention: "สวมเข็มขัดนิรภัย")]
        return r
    }

    func testRequestFormFitsOnePageWithItsTitlesAndTotals() {
        var r = request()
        r.engineerSignedAt = d(11)
        r.approvedAt = d(12); r.approvedBy = "นาย ก"
        let sig = Photo(fileName: "sig.png", width: 240, height: 70)
        let p = pages.request(r, signature: sig)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].width, RoutineReportPages.dailyFormPage.w)
        let t = texts(p)
        XCTAssertTrue(t.contains("WORK REQUEST CIVIL-ELECTRICAL"))
        XCTAssertTrue(t.contains("คำขอปฏิบัติงานรายสัปดาห์ (Weekly Request)"))
        XCTAssertFalse(t.contains("DAILY REPORT"))
        XCTAssertTrue(t.contains("14–20 July 2025 (สัปดาห์ที่ 29)"), "Monday to Sunday with the week number")
        XCTAssertTrue(t.contains("MANPOWER PLAN แผนกำลังคน"))
        XCTAssertTrue(t.contains("RISK ASSESSMENT ประเมินความเสี่ยง"))
        XCTAssertTrue(t.contains("สูง") && t.contains("สวมเข็มขัดนิรภัย"))
        XCTAssertTrue(t.contains("1 / 1"))
        // the totals: people 1 + 1 + 5 (a role at 0 is left out), tools 2 + 1
        let placed = placed(p[0])
        let manTotal = placed.firstIndex { $0.0 == "Total Man-Day" }.map { placed[$0 + 1].0 }
        let toolTotal = placed.firstIndex { $0.0 == "Total Tool & Machinery" }.map { placed[$0 + 1].0 }
        XCTAssertEqual(manTotal, "7")
        XCTAssertEqual(toolTotal, "3")
        XCTAssertFalse(t.contains("ช่างไฟฟ้า"))
        // the signatures: the engineer's drawn one, the approver's name and date
        XCTAssertTrue(t.contains("นาย ก"))
        XCTAssertTrue(t.contains("Date : 11/7/2025") && t.contains("Date : 12/7/2025"))
        XCTAssertTrue(p[0].ops.contains { if case .photo(let ph, _) = $0 { return ph.id == sig.id } else { return false } })
    }

    func testRequestFormContinuesWithTheSignaturesOnTheLastPage() {
        let p = pages.request(request(work: 9))
        XCTAssertEqual(p.count, 2, "9 work lines are more than the form's 7")
        XCTAssertTrue(texts([p[1]]).contains("2 / 2"))
        XCTAssertFalse(texts([p[0]]).contains("Site Engineer"), "no signatures before the last page")
        XCTAssertTrue(texts([p[1]]).contains("Site Engineer") && texts([p[1]]).contains("Inspector"))
        XCTAssertTrue(texts([p[1]]).contains("ติดตั้งแผง 9"))
        XCTAssertTrue(texts([p[1]]).contains("9"), "the numbering goes on")
        XCTAssertTrue(texts([p[1]]).contains("WORK REQUEST CIVIL-ELECTRICAL"), "the header repeats")
        let second = placed(p[1])
        XCTAssertEqual(second.firstIndex { $0.0 == "Total Man-Day" }.map { second[$0 + 1].0 }, "", "no total under a page without crew rows")
    }

    func testRequestBlankFormHasTheBoardsRows() {
        let p = RoutineReportPages.requestBlankForm()
        XCTAssertEqual(p.count, 1)
        let t = texts(p)
        XCTAssertTrue(t.contains("WORK REQUEST CIVIL-ELECTRICAL"))
        XCTAssertTrue(t.contains("MANPOWER PLAN") && t.contains("WORK PLAN") && t.contains("ประเมินความเสี่ยง"))
        XCTAssertFalse(t.contains("MANPOWER PLAN แผนกำลังคน"), "the blank form's titles are English only")
        // numbered rows 11 / 11 / 10 / 4: "11" twice, "10" three times, "5" three times
        XCTAssertEqual(t.filter { $0 == "11" }.count, 2)
        XCTAssertEqual(t.filter { $0 == "10" }.count, 3)
        XCTAssertEqual(t.filter { $0 == "5" }.count, 3)
        XCTAssertEqual(t.filter { $0 == "4" }.count, 4)
        XCTAssertFalse(t.contains("12"))
        XCTAssertTrue(t.contains("Site Engineer") && t.contains("1 / 1"))
    }

    func testDailyFormKeepsItsTitles() {
        let r = report(1, 20)
        let t = texts(pages.daily(entry(r), all: [r]))
        XCTAssertTrue(t.contains("DAILY REPORT") && t.contains("รายงานการทำงานประจำวัน"))
        XCTAssertFalse(t.contains("WORK REQUEST CIVIL-ELECTRICAL"))
    }
}
