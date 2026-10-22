import XCTest
@testable import TCRoofCore

/// A manager's decision on the person's claim, announced once on their device (calendar-travel-expenses-swift.md §B5).
final class ClaimNotificationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_000_000)   // 2026-10
    func ms(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }

    func review(_ decision: TravelClaim.Decision, month: String = "2026-10", submitted: Int64 = 1_000, note: String = "",
                ago: TimeInterval = 600) -> TravelClaim.Review {
        TravelClaim.Review(ownerEmail: "a@tcroof.test", month: month, submittedAt: submitted, decision: decision, note: note,
                           total: 123_450, reviewedBy: "boss@tcroof.test", reviewerName: "คุณสมศรี", reviewedAt: ms(now) - Int64(ago * 1000))
    }

    func testThePlan() {
        let ok = ClaimNotification.plan(review(.approved, note: "เรียบร้อย"))
        XCTAssertEqual(ok.type, .claim)
        XCTAssertEqual(ok.title, "อนุมัติใบเบิกแล้ว")
        XCTAssertEqual(ok.body, "ใบเบิกเดือน ต.ค. 2569 | 1,234.50 บาท")
        XCTAssertEqual(ok.sub, "โดย คุณสมศรี | เรียบร้อย")
        let back = ClaimNotification.plan(review(.returned, note: " ใบเสร็จไม่ชัด "))
        XCTAssertEqual(back.title, "ใบเบิกถูกส่งกลับให้แก้")
        XCTAssertEqual(back.sub, "โดย คุณสมศรี | เหตุผล: ใบเสร็จไม่ชัด")
        XCTAssertNotEqual(ok.id, back.id)
        // a tap opens the claim screen on the month
        XCTAssertEqual(DeepLink.route(type: .claim, action: nil, info: ok.info), .claims(month: "2026-10"))
        XCTAssertEqual(ClaimNotification.link([:]), .home)
        XCTAssertEqual(ClaimNotification.link([NotificationInfo.month: "oops"]), .home)
        XCTAssertEqual(NotificationType.claim.group, .claim)
        XCTAssertEqual(NotificationGroup.claim.types, [.claim])
        XCTAssertEqual(NotificationType.claim.level, .active)
    }

    func testEachDecisionIsAnnouncedOnce() {
        let a = review(.approved), b = review(.returned, month: "2026-09")
        // the first run announces nothing
        XCTAssertTrue(ClaimNotification.fresh([a, b], seen: nil, now: now).isEmpty)
        let seen = Set([a, b].map(ClaimNotification.id))
        XCTAssertTrue(ClaimNotification.fresh([a, b], seen: seen, now: now).isEmpty)
        // a new decision, and a resubmission decided again, are new
        let c = review(.approved, month: "2026-09", submitted: 2_000)
        XCTAssertEqual(ClaimNotification.fresh([a, c], seen: seen, now: now).map(\.id), [ClaimNotification.id(c)])
        // an old one isn't announced
        let old = review(.approved, month: "2026-08", ago: ClaimNotification.maxAge + 60)
        XCTAssertTrue(ClaimNotification.fresh([old], seen: [], now: now).isEmpty)
    }

    func testMonthTitle() {
        XCTAssertEqual(ClaimNotification.monthTitle("2026-01"), "ม.ค. 2569")
        XCTAssertEqual(ClaimNotification.monthTitle("2027-12"), "ธ.ค. 2570")
        XCTAssertEqual(ClaimNotification.monthTitle("x"), "x")
    }
}
