import Foundation
import FirebaseFirestore
import TCRoofCore

/// Managers' decisions on submitted months (Firestore `claimReviews`, `TravelClaim.Review`). The claimant's own come in
/// through `CloudSync` and are kept on the device, so the claim screen shows them offline; a manager's review screen
/// reads every claim and decision while it is open (`ClaimReviewScreen`), without keeping other people's records.
@MainActor
@Observable
final class ClaimReviews {
    static let shared = ClaimReviews()
    static let collection = "claimReviews"
    private static let cacheKey = "travel.reviews"
    /// The decisions already announced (`ClaimNotification.id`, one per line); absent until the first snapshot after
    /// sign-in, so the decisions already there then aren't announced.
    private static let seenKey = "notifications.claim.seen"

    /// The signed-in person's decisions, by month.
    private(set) var mine: [String: TravelClaim.Review] = [:]
    private var owner = ""

    /// The month's status for the signed-in person.
    func status(month: String, submittedAt: Date?) -> TravelClaim.Status {
        TravelClaim.status(submittedAt: submittedAt?.millis, review: mine[month])
    }

    // MARK: the claimant's (from CloudSync)

    func start(owner email: String) {
        owner = Permissions.normalized(email)
        let all = (UserDefaults.standard.data(forKey: Self.cacheKey)).flatMap { try? JSONDecoder().decode([TravelClaim.Review].self, from: $0) } ?? []
        mine = Dictionary(all.filter { $0.ownerEmail.lowercased() == owner }.map { ($0.month, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func receive(_ documents: [QueryDocumentSnapshot]) {
        let got = documents.compactMap { try? $0.data(as: TravelClaim.Review.self) }.filter { $0.ownerEmail.lowercased() == owner }
        mine = Dictionary(got.map { ($0.month, $0) }, uniquingKeysWith: { a, b in a.reviewedAt >= b.reviewedAt ? a : b })
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(mine.values)), forKey: Self.cacheKey)
        announce(Array(mine.values))
    }

    /// `อนุมัติใบเบิกแล้ว` / `ใบเบิกถูกส่งกลับให้แก้` for a decision not seen before (`ClaimNotification.fresh`).
    private func announce(_ reviews: [TravelClaim.Review]) {
        let d = UserDefaults.standard
        let seen = d.string(forKey: Self.seenKey).map { Set($0.split(separator: "\n").map(String.init)) }
        let fresh = ClaimNotification.fresh(reviews, seen: seen, now: .now)
        d.set((seen ?? []).union(reviews.map(ClaimNotification.id)).sorted().joined(separator: "\n"), forKey: Self.seenKey)
        fresh.forEach(NotificationService.shared.post)
    }

    /// The bell's rows: decisions of the last 7 days, newest first.
    var recent: [TravelClaim.Review] {
        let weekAgo = Int64(Date.now.adding(days: -7).timeIntervalSince1970 * 1000)
        return mine.values.filter { $0.reviewedAt >= weekAgo }.sorted { $0.reviewedAt > $1.reviewedAt }
    }

    /// Another account signs in on this device.
    func clear() {
        mine = [:]; owner = ""
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.seenKey)
    }

    // MARK: a manager's decision

    /// Writes the decision; the rules check the manager signs it with their own email and isn't the claimant.
    static func decide(_ review: TravelClaim.Review) async throws {
        try Firestore.firestore().collection(collection).document(review.id).setData(from: review)
    }
}
