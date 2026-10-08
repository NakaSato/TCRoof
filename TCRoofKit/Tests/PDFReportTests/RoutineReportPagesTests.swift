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

    func testDailyShowsTodayDeltaAndSignatures() {
        let all = [report(1, 20), report(2, 45)]
        let e = RoutineReportPages.DailyEntry(report: all[1], photos: [], engineerSignedAt: d(2), inspectorAckAt: nil)
        let t = texts(pages.daily(e, all: all))
        XCTAssertTrue(t.contains("+25%"))
        XCTAssertTrue(t.contains("45%"))
        XCTAssertTrue(t.contains("ลงนาม 2 ก.ค. 2568"))
        XCTAssertTrue(t.contains("(ผู้ตรวจ ทดสอบ)"))
        XCTAssertTrue(t.contains("ไม่มี"))                  // empty materials / problems
        XCTAssertTrue(t.contains("หน้า 1/1"))
    }

    func testKeyPlanHighlightsTodaysLocations() {
        let r = report(1, 20)   // หลังคา 1
        let k = RoutineReportPages.KeyPlan(photo: Photo(fileName: "site.jpg", width: 1600, height: 900), aspect: 16 / 9,
                                          points: [("หลังคา 1", 0.2, 0.3), ("ถังน้ำใส 1", 0.7, 0.6)])
        let p = pages.daily(.init(report: r, photos: [], engineerSignedAt: nil, inspectorAckAt: nil), all: [r], keyPlan: k)
        XCTAssertTrue(texts(p).contains("ผังตำแหน่งงานวันนี้ (Key plan)"))
        let fills = p.flatMap(\.ops).compactMap { op -> RGBA? in if case let .circle(_, _, _, f?, _) = op { f } else { nil } }
        XCTAssertEqual(fills, [RoutineReportPages.red, .white])
        XCTAssertTrue(p.flatMap(\.ops).contains { if case .photo = $0 { true } else { false } })
        // the heading lands on the page that has the picture
        let withHeading = p.first { $0.ops.contains { if case let .text(t, _, _, _, _, _, _) = $0 { t == "ผังตำแหน่งงานวันนี้ (Key plan)" } else { false } } }
        XCTAssertTrue(withHeading?.ops.contains { if case .photo = $0 { true } else { false } } ?? false)
        // a long day pushes the key plan to the next page with its heading
        let long = report(1, 20, lines: 14)
        let q = pages.daily(.init(report: long, photos: [], engineerSignedAt: nil, inspectorAckAt: nil), all: [long], keyPlan: k)
        let page = q.first { $0.ops.contains { if case .photo = $0 { true } else { false } } }
        XCTAssertTrue(page?.ops.contains { if case let .text(t, _, _, _, _, _, _) = $0 { t == "ผังตำแหน่งงานวันนี้ (Key plan)" } else { false } } ?? false)
    }

    func testLongTablesContinueOnNextPageWithTheHeader() {
        let r = report(1, 10, lines: 60)
        let p = pages.daily(.init(report: r, photos: [], engineerSignedAt: nil, inspectorAckAt: nil), all: [r])
        XCTAssertGreaterThan(p.count, 1)
        XCTAssertGreaterThan(texts(p).filter { $0 == "รายละเอียด" }.count, 1)
        for page in p {
            for op in page.ops {
                if case let .rect(b, _, _, _) = op { XCTAssertLessThanOrEqual(b.maxY, ReportLayout.pageH - 20) }
            }
        }
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

    func testRequestShowsApprovalAndRisks() {
        var r = RoutineReport.WeeklyRequest(weekStart: d(13))
        r.work = [.init(task: .panels, description: "ติดตั้งแผง", location: "หลังคา 1")]
        r.risks = [.init(description: "งานบนที่สูง", level: .high, prevention: "สวมเข็มขัดนิรภัย")]
        r.approvedAt = d(12); r.approvedBy = "นาย ก"
        let t = texts(pages.request(r))
        XCTAssertTrue(t.contains("สูง"))
        XCTAssertTrue(t.contains("อนุมัติ 12 ก.ค. 2568"))
        XCTAssertTrue(t.contains("(นาย ก)"))
        XCTAssertTrue(t.contains { $0.contains("13 ก.ค. 2568 – 19 ก.ค. 2568") })
    }
}
