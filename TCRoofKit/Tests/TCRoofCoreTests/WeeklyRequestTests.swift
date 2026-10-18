import XCTest
@testable import TCRoofCore

/// The weekly request R1 a contractor sends (docs/ui/user-admin-iphone, change A3).
final class WeeklyRequestTests: XCTestCase {
    private let cal = RoutineReport.calendar
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day))! }
    private func week(_ day: Int, crew: Int = 0) -> RoutineReport.WeeklyRequest {
        var r = RoutineReport.WeeklyRequest(weekStart: d(day))
        r.crew = [.init(name: "ช่าง", count: crew)]
        return r
    }

    func testOldJSONDecodesWithoutSending() throws {
        let json = #"{"weekStart": 813974400, "approvedBy": "", "engineerSignedAt": 813974400}"#
        let r = try JSONDecoder().decode(RoutineReport.WeeklyRequest.self, from: Data(json.utf8))
        XCTAssertNil(r.sentAt)
        XCTAssertEqual(r.sentBy, "")
        XCTAssertEqual(r.status, .sent, "a request our engineer signed before sentAt still reads as sent")
        let draft = try JSONDecoder().decode(RoutineReport.WeeklyRequest.self, from: Data(#"{"weekStart": 813974400}"#.utf8))
        XCTAssertEqual(draft.status, .draft)
        var sent = draft
        sent.send(by: "foreman@contractor.co", signs: false, at: d(14))
        let round = try JSONDecoder().decode(RoutineReport.WeeklyRequest.self, from: JSONEncoder().encode(sent))
        XCTAssertEqual(round.sentAt, d(14))
        XCTAssertEqual(round.sentBy, "foreman@contractor.co")
    }

    func testContractorSendsTeamSendsBackOrApproves() {
        var r = week(18)
        XCTAssertTrue(r.isEditable(external: true))
        r.send(by: "foreman@contractor.co", signs: false, at: d(14))
        XCTAssertEqual(r.status, .sent)
        XCTAssertNil(r.engineerSignedAt, "a contractor's send doesn't sign for our engineer")
        XCTAssertFalse(r.isEditable(external: true), "sent: read only for the contractor")
        XCTAssertTrue(r.isEditable(external: false), "the team still corrects it")
        r.sendBack()
        XCTAssertEqual(r.status, .draft)
        XCTAssertTrue(r.isEditable(external: true))
        r.send(by: "foreman@contractor.co", signs: false, at: d(15))
        r.approve(by: "วิศวกร", at: d(16))
        XCTAssertEqual(r.status, .approved)
        XCTAssertFalse(r.isEditable(external: true))
        XCTAssertFalse(r.isEditable(external: false), "approved: read only for everyone until reopened")
        r.reopen()
        XCTAssertEqual(r.status, .sent)
        XCTAssertTrue(r.isEditable(external: false))
        // our engineer's send signs it, as before
        var ours = week(25)
        ours.send(by: "eng@tcroof.co", signs: true, at: d(20))
        XCTAssertEqual(ours.engineerSignedAt, d(20))
    }

    func testTeamDevicesDropAContractorsChangeToASentOrApprovedWeek() {
        var sent = week(4, crew: 3); sent.send(by: "foreman@contractor.co", signs: false, at: d(1))
        var approved = week(11, crew: 4); approved.send(by: "foreman@contractor.co", signs: false, at: d(8)); approved.approve(by: "วิศวกร", at: d(9))
        let draft = week(18, crew: 1)
        let local = [sent, approved, draft]

        // the contractor rewrites everything, approves the draft and adds a new approved week
        var sent2 = sent; sent2.crew[0].count = 9
        var approved2 = approved; approved2.sendBack(); approved2.reopen()
        var draft2 = draft; draft2.crew[0].count = 5; draft2.send(by: "foreman@contractor.co", signs: true, at: d(15)); draft2.approve(by: "ฉันเอง", at: d(15))
        var new = week(25, crew: 2); new.approve(by: "ฉันเอง", at: d(15))
        let incoming = [sent2, approved2, draft2, new]

        let kept = RoutineReport.WeeklyRequest.trusting(incoming, local: local, byContractor: true)
        XCTAssertEqual(kept.map(\.id), [sent, approved, draft, new].map(\.id))
        XCTAssertEqual(kept[0], sent, "a sent week stays as the team holds it")
        XCTAssertEqual(kept[1], approved, "an approved week stays approved")
        XCTAssertEqual(kept[2].crew[0].count, 5, "a draft takes the contractor's values")
        XCTAssertEqual(kept[2].status, .sent, "and their send")
        XCTAssertNil(kept[2].approvedAt, "but not an approval")
        XCTAssertNil(kept[2].engineerSignedAt, "nor our engineer's signature")
        XCTAssertNil(kept[3].approvedAt)

        // a contractor deleting a sent week doesn't remove it; a draft they delete goes
        let deleted = RoutineReport.WeeklyRequest.trusting([], local: local, byContractor: true)
        XCTAssertEqual(deleted.map(\.id), [sent.id, approved.id])

        // the team's own write is taken as it is
        XCTAssertEqual(RoutineReport.WeeklyRequest.trusting(incoming, local: local, byContractor: false), incoming)
    }
}
