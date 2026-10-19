import UIKit
import TCRoofCore

/// `-claimReviewDemo YES` (DEBUG): three team members' months for `ตรวจใบเบิกของทีม` (one waiting, one sent back, one
/// approved) and one of the signed-in manager's own, dated this month; decisions stay in memory.
@MainActor
struct ClaimReviewDemo {
    let monthKey = TravelClaim.monthKey(.now)
    private let me = MemberRole.shared.permissions.email

    private func day(_ n: Int) -> Date {
        let start = TravelClaim.monthStart(monthKey) ?? .now
        return TravelClaim.calendar.date(byAdding: .hour, value: 9 + 24 * (n - 1), to: start) ?? start
    }
    private var submitted: Int64 { day(2).millis }

    var claims: [String: ClaimMonth.Record] {
        var out: [String: ClaimMonth.Record] = [:]
        for (i, owner) in ["somchai@tcroof.test", "suda@tcroof.test", "anan@tcroof.test", me].enumerated() {
            let r = ClaimMonth.Record(ownerEmail: owner, month: monthKey, log: "ยื่นเบิก \(ClaimExport.stamp(Date(millis: submitted + Int64(i) * 3_600_000)))",
                                      submittedAt: submitted + Int64(i) * 3_600_000, pdfDrive: nil, excelDrive: nil,
                                      driveFolderURL: nil)
            out[TravelClaim.Review.id(owner: owner, month: monthKey)] = r
        }
        return out
    }

    var reviews: [String: TravelClaim.Review] {
        let back = TravelClaim.Review(ownerEmail: "suda@tcroof.test", month: monthKey, submittedAt: submitted + 3_600_000, decision: .returned,
                                      note: "ใบเสร็จค่าที่พักวันที่ 2 ไม่ชัด ถ่ายใหม่", total: 186_000, reviewedBy: "boss@tcroof.test",
                                      reviewerName: "ผู้จัดการ", reviewedAt: submitted + 7_200_000)
        let ok = TravelClaim.Review(ownerEmail: "anan@tcroof.test", month: monthKey, submittedAt: submitted + 7_200_000, decision: .approved,
                                    total: 94_000, reviewedBy: "boss@tcroof.test", reviewerName: "ผู้จัดการ", reviewedAt: submitted + 10_800_000)
        return [back.id: back, ok.id: ok]
    }

    func month(_ owner: String) -> ClaimReviewModel.Month {
        let stop = { (label: String, km: Double) in TravelClaim.Stop(jobID: nil, label: label, legKm: km) }
        let days = [
            TravelClaim.Day(id: "d1", date: day(1), vehicle: .personal, plate: "1กข 2345", startPlace: "สำนักงาน",
                            stops: [stop("MP 189 สถานีผลิตน้ำบางไทร", 42.5)], backKm: 42.5),
            TravelClaim.Day(id: "d2", date: day(2), vehicle: .personal, plate: "1กข 2345", startPlace: "สำนักงาน",
                            stops: [stop("MP 190 สถานีแพรกหนามแดง", 61.2), stop("MP 191", 18.0)], backKm: 70.4,
                            odoStart: 10200, odoEnd: 10420, odoReason: "อ้อมถนนปิด"),
        ]
        let items = [
            TravelClaim.Item(id: "x1", date: day(1), category: .toll, amount: 6_000, vendor: "กทพ.", hasReceipt: true),
            TravelClaim.Item(id: "x2", date: day(2), category: .lodging, amount: 80_000, vendor: "โรงแรมริมน้ำ", hasReceipt: true),
            TravelClaim.Item(id: "x3", date: day(2), category: .perDiem, amount: 24_000, note: "เบี้ยเลี้ยง"),
        ]
        return ClaimReviewModel.Month(summary: TravelClaim.Summary(days: days, items: items), receipts: ["x1": "demo-x1", "x2": "demo-x2"])
    }

    /// A drawn receipt.
    func receipt(_ id: String) -> UIImage? {
        guard id.hasPrefix("demo-") else { return nil }
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 34, weight: .semibold)]
            ("ใบเสร็จรับเงิน\n" + (id == "demo-x1" ? "ทางด่วน 60.00" : "ที่พัก 800.00") as NSString).draw(at: CGPoint(x: 50, y: 80), withAttributes: a)
        }
    }

    /// The directory's names for the demo's people.
    static func name(_ owner: String) -> String? {
        ["somchai@tcroof.test": "สมชาย ใจดี", "suda@tcroof.test": "สุดา รักงาน", "anan@tcroof.test": "อนันต์ มั่นคง"][owner]
    }
}
