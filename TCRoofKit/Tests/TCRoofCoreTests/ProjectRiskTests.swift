import XCTest
@testable import TCRoofCore

/// CHA-81: the Master Plan's project risk register, as the sheet writes it into `config/risks`.
final class ProjectRiskTests: XCTestCase {
    /// What `Core.riskRegister` writes (tools/master-plan-sheet/core.test.js checks the same shape).
    let json = """
    {"risks":[
     {"id":"R03","title":"ผรม. S กำลังติดตั้งไม่พอ","category":"ผรม.","cause":"","scope":"ผรม. S","wbs":"2.x","kri":"สถานีที่ COD ช้า",
      "kriValue":12,"kriThreshold":10,"warn":true,"probability":4,"impact":5,"score":20,"level":"สูง","impactDays":30,
      "reserveDays":21,"strategy":"ลด","response":"ย้ายสถานี","owner":"PM","status":"เปิด","reviewed":"2026-11-01","jobs":["job-1"]},
     {"id":"R01","title":"กฟภ. ตรวจเต็ม 30 วันทำการ","scope":"ทั้งเฟส","score":16,"level":"สูง","status":"เฝ้าระวัง","kriValue":null},
     {"id":"R06","title":"ฝน","scope":"ทั้งเฟส","score":6,"level":"ต่ำ","status":"เปิด"},
     {"id":"R09","title":"รายงานส่งช้า","scope":"ทุก ผรม.","score":12,"level":"กลาง","status":"เปิด","warn":true},
     {"id":"R12","title":"ค่าธรรมเนียม","scope":"รายสถานี","score":20,"level":"สูง","status":"ปิด"},
     {"title":"no id"}
    ]}
    """

    func testDecodesTheSheetsJSONSkippingARowWithoutAnId() throws {
        let r = try XCTUnwrap(RiskRegister.decode(json))
        XCTAssertEqual(r.risks.map(\.id), ["R03", "R01", "R06", "R09", "R12"])
        let r03 = r.risks[0]
        XCTAssertEqual(r03.kriValue, 12)
        XCTAssertEqual(r03.probability, 4)
        XCTAssertEqual(r03.jobs, ["job-1"])
        XCTAssertTrue(r03.warn)
        XCTAssertNil(r.risks[1].kriValue)
        XCTAssertNil(r.risks[1].jobs, "every station")
        XCTAssertNil(RiskRegister.decode("not json"))
    }

    func testOpenHighRisksForAStation() throws {
        let r = try XCTUnwrap(RiskRegister.decode(json))
        XCTAssertEqual(r.open(for: "job-1", highOnly: true).map(\.id), ["R03", "R01"], "high first by score; R12 is closed")
        XCTAssertEqual(r.open(for: "job-2", highOnly: true).map(\.id), ["R01"], "R03 is contractor S's stations only")
        XCTAssertEqual(r.open(for: "job-2").map(\.id), ["R01", "R09", "R06"])
    }

    func testABlankLevelFallsBackToTheScore() {
        XCTAssertTrue(ProjectRisk(id: "R20", title: "x", score: 15).isHigh)
        XCTAssertFalse(ProjectRisk(id: "R21", title: "x", score: 14).isHigh)
        XCTAssertFalse(ProjectRisk(id: "R22", title: "x", score: 20, level: "กลาง").isHigh, "the sheet's level wins")
        XCTAssertTrue(ProjectRisk(id: "R23", title: "x", status: "").isOpen, "no status yet is open")
    }

    func testLookAheadGivesOpenHighRisksAndKRIWarnings() throws {
        let r = try XCTUnwrap(RiskRegister.decode(json))
        var job = Assistant.Job(id: "job-2", station: "บ้านโป่ง", input: nil, canEdit: false)
        XCTAssertNil(job.riskBriefs)
        job.risks = r.open(for: "job-2")
        let briefs = try XCTUnwrap(job.riskBriefs)
        XCTAssertEqual(briefs.map(\.id), ["R01", "R09"], "R06 is low with no warning")
        XCTAssertTrue(briefs[1].kriWarning)
        XCTAssertEqual(briefs[0].level, "สูง")
    }
}
