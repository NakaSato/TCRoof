import Foundation

/// A manager's decision on a submitted month (docs/specs/calendar-travel-expenses-swift.md §B5): approved, or sent back
/// with a note. Kept apart from the claim (Firestore `claimReviews`), which only its owner writes, so a claimant can't
/// approve their own month and a manager can't change the claim. A decision belongs to one submission (`submittedAt`):
/// once the person withdraws and submits again it no longer counts, and the month waits for a new one.
extension TravelClaim {
    public enum Decision: String, Codable, Sendable { case approved, returned }

    public struct Review: Codable, Equatable, Sendable {
        public var ownerEmail: String
        /// "2026-10".
        public var month: String
        /// The submission decided on (ms since 1970), as `ClaimMonth.submittedAt`.
        public var submittedAt: Int64
        public var decision: Decision
        /// Why it was sent back (required then), or a remark on an approval.
        public var note: String
        /// The total the manager saw (satang).
        public var total: Int
        public var reviewedBy: String
        public var reviewerName: String
        public var reviewedAt: Int64

        public init(ownerEmail: String, month: String, submittedAt: Int64, decision: Decision, note: String = "", total: Int,
                    reviewedBy: String, reviewerName: String = "", reviewedAt: Int64) {
            self.ownerEmail = ownerEmail; self.month = month; self.submittedAt = submittedAt; self.decision = decision
            self.note = note; self.total = total; self.reviewedBy = reviewedBy; self.reviewerName = reviewerName
            self.reviewedAt = reviewedAt
        }

        /// The document id: one decision per person and month, replaced by the next.
        public var id: String { Self.id(owner: ownerEmail, month: month) }
        public static func id(owner: String, month: String) -> String { "\(owner.lowercased())_\(month)" }
        public var who: String { reviewerName.isEmpty ? reviewedBy : reviewerName }
    }

    /// Where a month stands.
    public enum Status: Equatable, Sendable {
        case open
        case submitted
        case approved(Review)
        case returned(Review)

        public var isApproved: Bool { if case .approved = self { true } else { false } }
        public var title: String {
            switch self {
            case .open: "ยังไม่ยื่นเบิก"
            case .submitted: "ยื่นเบิกแล้ว | รออนุมัติ"
            case .approved: "อนุมัติแล้ว"
            case .returned: "ส่งกลับให้แก้"
            }
        }
    }

    /// The month's status: a decision counts only for the submission it was made on.
    public static func status(submittedAt: Int64?, review: Review?) -> Status {
        guard let s = submittedAt else { return .open }
        guard let r = review, r.submittedAt == s else { return .submitted }
        return r.decision == .approved ? .approved(r) : .returned(r)
    }

    /// Why a manager can't decide on this claim now; nil when they can. A note is required to send it back.
    public static func reviewRefusal(reviewer: String, owner: String, submitted: Bool, decision: Decision, note: String) -> String? {
        if reviewer.lowercased() == owner.lowercased() { return "อนุมัติใบเบิกของตัวเองไม่ได้" }
        if !submitted { return "ใบเบิกนี้ถูกถอนการยื่นแล้ว" }
        if decision == .returned, note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "ใส่เหตุผลที่ส่งกลับ" }
        return nil
    }
}
