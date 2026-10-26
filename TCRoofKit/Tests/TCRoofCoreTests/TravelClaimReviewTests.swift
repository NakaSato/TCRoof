import XCTest
@testable import TCRoofCore

/// A manager's decision on a submitted month (calendar-travel-expenses-swift.md §B5).
final class TravelClaimReviewTests: XCTestCase {
    func review(_ d: TravelClaim.Decision, on s: Int64, note: String = "") -> TravelClaim.Review {
        TravelClaim.Review(ownerEmail: "A@tcroof.test", month: "2026-10", submittedAt: s, decision: d, note: note, total: 12_000,
                           reviewedBy: "boss@tcroof.test", reviewedAt: s + 1000)
    }

    func testADecisionCountsOnlyForTheSubmissionItWasMadeOn() {
        XCTAssertEqual(TravelClaim.status(submittedAt: nil, review: nil), .open)
        XCTAssertEqual(TravelClaim.status(submittedAt: 100, review: nil), .submitted)
        let ok = review(.approved, on: 100)
        XCTAssertEqual(TravelClaim.status(submittedAt: 100, review: ok), .approved(ok))
        XCTAssertTrue(TravelClaim.status(submittedAt: 100, review: ok).isApproved)
        let back = review(.returned, on: 100, note: "ใบเสร็จวันที่ 3 ไม่ชัด")
        XCTAssertEqual(TravelClaim.status(submittedAt: 100, review: back), .returned(back))
        // withdrawn and submitted again: the old decision no longer counts
        XCTAssertEqual(TravelClaim.status(submittedAt: 200, review: back), .submitted)
        XCTAssertEqual(TravelClaim.status(submittedAt: nil, review: ok), .open)
    }

    func testOneDocumentPerPersonAndMonth() {
        XCTAssertEqual(review(.approved, on: 1).id, "a@tcroof.test_2026-10")
        XCTAssertEqual(TravelClaim.Review.id(owner: "a@tcroof.test", month: "2026-10"), review(.returned, on: 2).id)
        XCTAssertEqual(review(.approved, on: 1).who, "boss@tcroof.test")
    }

    func testWhoMayDecide() {
        XCTAssertEqual(TravelClaim.reviewRefusal(reviewer: "a@tcroof.test", owner: "A@tcroof.test", submitted: true, decision: .approved, note: ""),
                       "อนุมัติใบเบิกของตัวเองไม่ได้")
        XCTAssertEqual(TravelClaim.reviewRefusal(reviewer: "b@x", owner: "a@x", submitted: false, decision: .approved, note: ""), "ใบเบิกนี้ถูกถอนการยื่นแล้ว")
        XCTAssertEqual(TravelClaim.reviewRefusal(reviewer: "b@x", owner: "a@x", submitted: true, decision: .returned, note: "  "), "ใส่เหตุผลที่ส่งกลับ")
        XCTAssertNil(TravelClaim.reviewRefusal(reviewer: "b@x", owner: "a@x", submitted: true, decision: .returned, note: "แก้ยอด"))
        XCTAssertNil(TravelClaim.reviewRefusal(reviewer: "b@x", owner: "a@x", submitted: true, decision: .approved, note: ""))
    }

    func testTheRecordRoundTrips() throws {
        let r = review(.returned, on: 5, note: "x")
        let back = try JSONDecoder().decode(TravelClaim.Review.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
        let json = String(data: try JSONEncoder().encode(r), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"decision\":\"returned\""))
    }
}
