import Foundation

/// A manager's decision on the person's expense claim (docs/specs/calendar-travel-expenses-swift.md §B5), announced on
/// the claimant's device once sync brings it in: `อนุมัติใบเบิกแล้ว`, or `ใบเบิกถูกส่งกลับ` with the reason. A tap opens
/// เดินทางและเบิกค่าใช้จ่าย on that month. Each decision is announced once (`fresh`), never on the first run after
/// sign-in or install (they are old news then), and never when older than `maxAge`.
public enum ClaimNotification {
    /// One per decision: a decision on a new submission, or a changed one, is announced again.
    public static func id(_ r: TravelClaim.Review) -> String { "claim-\(r.month)-\(r.submittedAt)-\(r.decision.rawValue)" }

    /// A decision older than this when it arrives isn't announced (the bell still lists it).
    public static let maxAge: TimeInterval = 3 * 86_400

    public static func title(_ r: TravelClaim.Review) -> String {
        r.decision == .approved ? "อนุมัติใบเบิกแล้ว" : "ใบเบิกถูกส่งกลับให้แก้"
    }

    /// `ใบเบิกเดือน ต.ค. 2569 | 1,234.50 บาท`.
    public static func body(_ r: TravelClaim.Review) -> String {
        "ใบเบิกเดือน \(monthTitle(r.month)) | \(TravelClaim.baht(r.total)) บาท"
    }

    /// `โดย คุณสมศรี | เหตุผล: ใบเสร็จค่าน้ำมันไม่ชัด`.
    public static func sub(_ r: TravelClaim.Review) -> String {
        let note = r.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return "โดย \(r.who)" + (note.isEmpty ? "" : (r.decision == .returned ? " | เหตุผล: " : " | ") + note)
    }

    public static func plan(_ r: TravelClaim.Review, fire: NotificationPlan.Fire = .after(1)) -> NotificationPlan {
        NotificationPlan(id: id(r), type: .claim, title: title(r), body: body(r), sub: sub(r), fire: fire,
                         info: [NotificationInfo.month: r.month])
    }

    /// The decisions to announce now: not in `seen` and decided within `maxAge`. `seen` nil (nothing kept yet: the first
    /// run on this device or account) announces nothing. Keep every id of `reviews` as the next `seen`.
    public static func fresh(_ reviews: [TravelClaim.Review], seen: Set<String>?, now: Date) -> [NotificationPlan] {
        guard let seen else { return [] }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000), limit = Int64(maxAge * 1000)
        return reviews.filter { !seen.contains(id($0)) && nowMs - $0.reviewedAt <= limit }
            .sorted { $0.reviewedAt < $1.reviewedAt }
            .map { plan($0) }
    }

    /// The claim screen on the decision's month.
    public static func link(_ info: [String: String]) -> DeepLink {
        guard let m = info[NotificationInfo.month], TravelClaim.monthStart(m) != nil else { return .home }
        return .claims(month: m)
    }

    static let monthNames = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."]

    /// "2026-10" → "ต.ค. 2569"; the key itself when it doesn't read.
    public static func monthTitle(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return key }
        return "\(monthNames[parts[1] - 1]) \(parts[0] + 543)"
    }
}
