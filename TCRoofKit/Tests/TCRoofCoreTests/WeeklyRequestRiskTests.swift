import XCTest
@testable import TCRoofCore

/// The weekly request's working time and its 5 × 5 risk scores (docs/ui/weekly-request-ipad-map §5 items 1 and 2).
final class WeeklyRequestRiskTests: XCTestCase {
    typealias R = RoutineReport

    // MARK: working time

    func testOlderRequestHasNoWorkingTimeAndASetOneRoundTrips() throws {
        let json = #"{"weekStart":0,"crew":[],"tools":[],"work":[],"risks":[],"approvedBy":"","sentBy":""}"#
        var r = try JSONDecoder().decode(R.WeeklyRequest.self, from: Data(json.utf8))
        XCTAssertNil(r.workStart)
        XCTAssertNil(r.workEnd)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(r), as: UTF8.self).contains("workStart"), "nothing new while unset")
        r.workStart = 8 * 60; r.workEnd = 18 * 60
        let back = try JSONDecoder().decode(R.WeeklyRequest.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.workStart, 480)
        XCTAssertEqual(back.workEnd, 1080)
        XCTAssertEqual(back, r)
    }

    func testTheDraftLeavesTheWorkingTimeUnset() {
        let r = R.requestDraft(weekStart: .now, plan: nil, actual: MasterSchedule.Actual(), latest: nil, settings: R.Settings())
        XCTAssertNil(r.workStart)
        XCTAssertNil(r.workEnd)
    }

    // MARK: bands and levels

    func testBandsAtTheirEdges() {
        XCTAssertEqual(R.RiskBand(score: 4), .low)
        XCTAssertEqual(R.RiskBand(score: 5), .medium)
        XCTAssertEqual(R.RiskBand(score: 9), .medium)
        XCTAssertEqual(R.RiskBand(score: 10), .high)
        XCTAssertEqual(R.RiskBand(score: 16), .high)
        XCTAssertEqual(R.RiskBand(score: 20), .veryHigh)
        XCTAssertEqual(R.RiskBand(score: 25).title, "สูงมาก")
    }

    func testAScoreWritesTheLevel() {
        var risk = R.Risk(description: "x")
        risk.assess(likelihood: 2, severity: 2)
        XCTAssertEqual(risk.level, .low)
        risk.assess(likelihood: 3, severity: 3)
        XCTAssertEqual(risk.level, .medium)
        risk.assess(likelihood: 3, severity: 5)
        XCTAssertEqual(risk.level, .high)
        XCTAssertEqual(risk.score, 15)
        XCTAssertEqual(risk.band, .high)
    }

    func testOlderRiskJSONDecodesUnscored() throws {
        let json = #"{"id":"\#(UUID())","description":"งานบนที่สูง","level":"high","prevention":"ราวกันตก"}"#
        let risk = try JSONDecoder().decode(R.Risk.self, from: Data(json.utf8))
        XCTAssertEqual(risk.level, .high)
        XCTAssertNil(risk.likelihood)
        XCTAssertNil(risk.score)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(risk), as: UTF8.self).contains("likelihood"))
        // a scored one keeps its scores
        var scored = risk
        scored.assess(likelihood: 4, severity: 5)
        XCTAssertEqual(try JSONDecoder().decode(R.Risk.self, from: JSONEncoder().encode(scored)), scored)
    }

    // MARK: hazards

    func line(_ description: String, at place: String) -> R.PlanLine { R.PlanLine(task: nil, description: description, location: place) }
    func hazard(_ rule: R.Hazard.Rule) -> R.Hazard { R.hazards.first { $0.rule == rule }! }

    func testEachHazardsRule() {
        XCTAssertTrue(hazard(.height).applies(to: line("ติดตั้งรางเก็บสายไฟกระแสตรง", at: "หลังคา 1")))
        XCTAssertTrue(hazard(.height).applies(to: line("ติดตั้งตู้ Fire Fighter Switch", at: "ถังน้ำใส 1")))
        XCTAssertFalse(hazard(.height).applies(to: line("ติดตั้งรางเก็บสายไฟกระแสสลับ", at: "ห้องอินเวอร์เตอร์")))

        XCTAssertTrue(hazard(.electrical).applies(to: line("ติดตั้งรางเก็บสายไฟกระแสสลับ", at: "ห้องอินเวอร์เตอร์")))
        XCTAssertTrue(hazard(.electrical).applies(to: line("ติดตั้งตู้ Fire Fighter Switch", at: "ถังน้ำใส 1")))
        XCTAssertFalse(hazard(.electrical).applies(to: line("ติดตั้งโครงสร้างราง", at: "หลังคา 1")))

        XCTAssertTrue(hazard(.droppedObjects).applies(to: line("ติดตั้งแผงโซลาร์", at: "หลังคา 2")))
        XCTAssertFalse(hazard(.droppedObjects).applies(to: line("ติดตั้งแผงโซลาร์", at: "ลานจอดรถ")), "not on a roof")

        for rule in [R.Hazard.Rule.byHand] {
            for h in R.hazards where h.rule == rule {
                XCTAssertFalse(h.applies(to: line("ติดตั้งแผงโซลาร์", at: "หลังคา 1")), "\(h.name) is added by hand")
            }
        }
        XCTAssertEqual(R.hazards.count, 5)
    }

    func testANewDraftStartsAssessedAtTheDefaults() {
        var r = R.WeeklyRequest(weekStart: .now)
        r.work = [line("ติดตั้งรางเก็บสายไฟกระแสตรง", at: "หลังคา 1"), line("ทาสี", at: "สำนักงาน")]
        XCTAssertEqual(r.firstUnassessedLine, 0)
        r.assessDefaults()
        XCTAssertEqual(Set(r.risks.map(\.description)),
                       Set([hazard(.height), hazard(.electrical), hazard(.droppedObjects)].map(\.name)))
        XCTAssertEqual(r.risk(for: hazard(.height))?.score, 15)
        XCTAssertEqual(r.risk(for: hazard(.height))?.level, .high)
        XCTAssertNil(r.firstUnassessedLine)
        r.removeAssessment(hazard(.height))
        XCTAssertEqual(r.firstUnassessedLine, 0)
    }
}
