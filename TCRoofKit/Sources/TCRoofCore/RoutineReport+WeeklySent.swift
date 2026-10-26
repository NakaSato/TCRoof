import Foundation

extension RoutineReport {
    /// A Weekly Report (R3) sent from the iPad install page (docs/ui/install-tracking-ipad-weekly-report §4.5): the week,
    /// when, by whom and to which of the page's recipient groups. The job keeps one per week sent (`Job.weeklySentJSON`).
    public struct WeeklySent: Codable, Equatable, Sendable {
        /// The Sunday of the week (`MasterSchedule.weekStart`).
        public var weekStart: Date
        public var sentAt: Date
        /// The sender's email.
        public var sentBy: String
        /// The recipient groups picked: `เจ้าของงาน กปภ.`, `ผู้ตรวจ กฟภ.`, `ทีมภายใน`.
        public var recipients: [String]

        public init(weekStart: Date, sentAt: Date, sentBy: String, recipients: [String]) {
            self.weekStart = weekStart; self.sentAt = sentAt; self.sentBy = sentBy; self.recipients = recipients
        }

        enum CodingKeys: String, CodingKey { case weekStart, sentAt, sentBy, recipients }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            weekStart = try c.decodeIfPresent(Date.self, forKey: .weekStart) ?? .distantPast
            sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt) ?? .distantPast
            sentBy = try c.decodeIfPresent(String.self, forKey: .sentBy) ?? ""
            recipients = try c.decodeIfPresent([String].self, forKey: .recipients) ?? []
        }

        /// The page's recipient groups, in order.
        public static let groups = ["เจ้าของงาน กปภ.", "ผู้ตรวจ กฟภ.", "ทีมภายใน"]
        /// Picked until the person changes them.
        public static let defaultRecipients = ["เจ้าของงาน กปภ.", "ทีมภายใน"]

        /// `list` with `sent` in place of an earlier send of its week, oldest week first.
        public static func recording(_ sent: WeeklySent, in list: [WeeklySent]) -> [WeeklySent] {
            let key = dayKey(sent.weekStart)
            return (list.filter { dayKey($0.weekStart) != key } + [sent]).sorted { $0.weekStart < $1.weekStart }
        }
    }
}
