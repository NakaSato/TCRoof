import XCTest
@testable import TCRoofCore

/// The WBS Dictionary's done criteria and rules of credit (CHA-84): a row with credit steps takes only those, 100 % of a
/// row whose dictionary lists documents needs a document number or a record, and a step books its share of the weight.
final class WBSDictionaryTests: XCTestCase {
    let dict = MasterSchedule.WBSDictionary.bundled
    let cal = MasterSchedule.calendar
    func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 12, day: d))! }

    // MARK: the bundled dictionary

    func testTheBundledDictionaryHasTheSheetsRows() throws {
        XCTAssertEqual(dict.revision, "REV 10")
        XCTAssertEqual(dict.entries.count, 124)
        let permit = try XCTUnwrap(dict.entry("1.4.3"))
        XCTAssertEqual(permit.steps, [.init(label: "ยื่น", percent: 50), .init(label: "ได้รับ", percent: 100)])
        XCTAssertEqual(permit.evidence, ["อ.1"])
        XCTAssertNotNil(permit.done)
        XCTAssertEqual(dict.percents("0.1.1"), [10, 50, 100])
        XCTAssertEqual(dict.entry("2.1.3")?.steps?.map(\.label), ["เริ่ม", "เสร็จ"])
        XCTAssertEqual(dict.percents("1.1.1"), [100], "0/100")
        XCTAssertEqual(dict.percents("9.9.9"), [100], "a row the dictionary doesn't have")
        XCTAssertEqual(dict.entry("2.3.5")?.byICL, true)
        // every step list ends at 100 and rises
        for (code, e) in dict.entries { if let s = e.steps { XCTAssertEqual(s.last?.percent, 100, code); XCTAssertEqual(s.map(\.percent), s.map(\.percent).sorted(), code) } }
    }

    // MARK: checks

    func testARowWithCreditStepsOnlyAcceptsThose() {
        let row = MasterSchedule.WorkItem(code: "1.4.3", title: "อ.1", weight: 2)
        XCTAssertNotNil(dict.problem(row, percent: 10, document: nil))
        XCTAssertNotNil(dict.problem(row, percent: 75, document: nil))
        XCTAssertNil(dict.problem(row, percent: 50, document: nil))
        let plain = MasterSchedule.WorkItem(code: "1.1.1", title: "บันทึกประชุม", weight: 1)
        XCTAssertNotNil(dict.problem(plain, percent: 50, document: nil), "0/100 has no half")
        XCTAssertNil(dict.problem(plain, percent: 100, document: nil))
    }

    func testARowWhoseEvidenceIsRequiredCantReach100WithoutIt() {
        let row = MasterSchedule.WorkItem(code: "1.4.3", title: "อ.1", weight: 2)
        XCTAssertEqual(dict.problem(row, percent: 100, document: nil), "ใส่เลขที่เอกสารก่อนนับ 100%: อ.1")
        XCTAssertNotNil(dict.problem(row, percent: 100, document: "  "))
        XCTAssertNil(dict.problem(row, percent: 100, document: "อ.1 เลขที่ 12/2569"))
    }

    // MARK: records

    func testApprovedPapersGiveTheCreditAndStandForTheEvidence() {
        var row = MasterSchedule.WorkItem(code: "1.4.3", title: "อ.1", weight: 2)
        row.note = "หลักฐาน: building_permit"
        XCTAssertNil(dict.credit(row, records: .init()))
        XCTAssertEqual(dict.credit(row, records: .init(papers: ["building_permit": .submitted]))?.percent, 50)
        XCTAssertNil(dict.credit(row, records: .init(papers: ["building_permit": .requested])))
        let approved = MasterSchedule.WBSDictionary.Records(papers: ["building_permit": .approved])
        XCTAssertEqual(dict.credit(row, records: approved)?.percent, 100)
        XCTAssertNil(dict.problem(row, percent: 100, document: nil, records: approved))
    }

    func testAllPapersCountTheLeastOne() {
        var row = MasterSchedule.WorkItem(code: "0.1.1", title: "PEP", weight: 1)
        row.note = "หลักฐาน: pep, baseline"
        XCTAssertEqual(dict.credit(row, records: .init(papers: ["pep": .approved, "baseline": .draft]))?.percent, 10)
        XCTAssertNil(dict.credit(row, records: .init(papers: ["pep": .approved])), "a paper without a state says nothing")
    }

    func testSignedICLSheetsGiveTheICLRow() {
        let row = MasterSchedule.WorkItem(code: "2.3.5", title: "ICL แผง + String", weight: 1)
        XCTAssertNil(dict.credit(row, records: .init(iclSigned: ["2.2"])))
        XCTAssertEqual(dict.credit(row, records: .init(iclSigned: ["2.3"]))?.percent, 100)
    }

    // MARK: booking

    func testAStepBooksItsShareAndMovingUpBooksTheRest() {
        var i = MasterSchedule.Input(installStart: day(5), installEnd: day(22), kickoff: day(1), engineeringStart: day(1),
                                     siteHandover: day(2), over200kVA: false)
        i.fixed = ["structure": .init(start: day(5), end: day(22), weight: 20)]
        let items: [MasterSchedule.WorkItem] = [.init(code: "2.1", title: "โครงสร้าง", weight: 20, level: 1),
                                                .init(code: "2.1.3", title: "ฐานยึด", weight: 8), .init(code: "2.1.4", title: "Rail", weight: 12)]
        var a = MasterSchedule.Actual()
        let started = MasterSchedule.WBSTick(by: "t@tcroof.test", at: day(7), percent: 50)
        XCTAssertFalse(started.isDone)
        MasterSchedule.bookWBS(&a, items: items, ticks: ["2.1.3": started], input: i)
        XCTAssertEqual(a.points["structure"]?.values.reduce(0, +), 4)
        XCTAssertNil(a.finished["structure"])

        let done = MasterSchedule.WBSTick(by: "t@tcroof.test", at: day(15), percent: 100)
        XCTAssertTrue(done.isDone)
        XCTAssertNil(done.percent, "100 is written as done")
        let ticks = ["2.1.3": done, "2.1.4": MasterSchedule.WBSTick(by: "t@tcroof.test", at: day(15))]
        MasterSchedule.bookWBS(&a, items: items, ticks: ticks, input: i)
        XCTAssertEqual(a.points["structure"], [MasterSchedule.Actual.key(day(15)): 20])
        XCTAssertEqual(a.finished["structure"], day(15))
        let once = a
        XCTAssertFalse(MasterSchedule.bookWBS(&a, items: items, ticks: ticks, input: i))
        XCTAssertEqual(a, once)
    }

    func testATickWithoutAStepKeepsItsJSON() throws {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        let done = String(data: try e.encode(MasterSchedule.WBSTick(by: "a", at: day(1))), encoding: .utf8)!
        XCTAssertFalse(done.contains("percent"))
        let half = MasterSchedule.WBSTick(by: "a", at: day(1), percent: 50)
        XCTAssertEqual(try JSONDecoder().decode(MasterSchedule.WBSTick.self, from: e.encode(half)).percent, 50)
    }
}
