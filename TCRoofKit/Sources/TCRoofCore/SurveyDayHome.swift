import Foundation

/// The iPhone survey home's header greeting (docs/ui/tcroof-survey-home-iphone), by the local hour.
public enum SurveyGreeting {
    public static func text(hour: Int) -> String {
        switch hour {
        case ..<12: "สวัสดีตอนเช้า"
        case 12..<17: "สวัสดีตอนบ่าย"
        default: "สวัสดีตอนเย็น"
        }
    }
}

/// The week strip, next appointment, agenda and list order of the iPhone survey home, on plain appointment dates.
/// Functions that pick appointments return indices into `dates`, so the caller keeps its own job values.
public enum SurveyDayHome {
    /// `อา จ อ พ พฤ ศ ส`, by `Calendar` weekday (1 = Sunday).
    public static let weekdayLabels = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]

    /// One day of the strip, `offset` days after today.
    public struct Day: Equatable, Sendable {
        public let offset: Int
        public let date: Date
        /// `วันนี้` for today, else the short weekday.
        public let label: String
        public let number: Int
        /// Appointments on this day.
        public let count: Int
        public var isToday: Bool { offset == 0 }
        public var hasAppointments: Bool { count > 0 }
    }

    /// Seven days rolling from today (not Monday to Sunday).
    public static func week(now: Date, dates: [Date], calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: now)
        let offsets = dates.map { RelativeDay.days(from: now, to: $0, calendar: calendar) }
        return (0..<7).map { k in
            let date = calendar.date(byAdding: .day, value: k, to: today) ?? today
            return Day(offset: k, date: date,
                       label: k == 0 ? "วันนี้" : weekdayLabels[calendar.component(.weekday, from: date) - 1],
                       number: calendar.component(.day, from: date),
                       count: offsets.filter { $0 == k }.count)
        }
    }

    /// The earliest appointment that is still ahead (`>= now`); on the same time, the first in `dates`.
    public static func next(dates: [Date], now: Date) -> Int? {
        dates.indices.filter { dates[$0] >= now }.min { dates[$0] < dates[$1] }
    }

    /// The appointments `offset` days after today, without `excluding` (the next appointment), by time.
    public static func agenda(dates: [Date], offset: Int, now: Date, excluding: Int? = nil, calendar: Calendar = .current) -> [Int] {
        dates.indices
            .filter { $0 != excluding && RelativeDay.days(from: now, to: dates[$0], calendar: calendar) == offset }
            .sorted { dates[$0] < dates[$1] }
    }

    /// Nearest day to today first, past or future; on the same distance, the earlier date.
    public static func listOrder(dates: [Date], now: Date, calendar: Calendar = .current) -> [Int] {
        let away = dates.map { abs(RelativeDay.days(from: now, to: $0, calendar: calendar)) }
        return dates.indices.sorted { away[$0] != away[$1] ? away[$0] < away[$1] : dates[$0] < dates[$1] }
    }

    /// How many of `keys` are each value (the status chips' counts over the search result).
    public static func counts<Key: Hashable>(_ keys: [Key]) -> [Key: Int] {
        keys.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// The avatar letter: the first character of the name after a leading `คุณ`, `บริษัท`, `ร้าน`, `โรงงาน` or `หอพัก`; `?` if none.
    public static func initial(of name: String) -> String {
        var rest = name.trimmingCharacters(in: .whitespaces)
        if let prefix = ["คุณ", "บริษัท", "ร้าน", "โรงงาน", "หอพัก"].first(where: rest.hasPrefix) {
            rest = String(rest.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        // the first scalar, not the first character: the consonant without the vowel or tone mark over it
        return rest.unicodeScalars.first.map { String($0) } ?? "?"
    }

    /// `อีก 1 ชม. 20 นาที` or `อีก 20 นาที` on the same day, `อีก 3 วัน` on a later one.
    public static func until(now: Date, date: Date, calendar: Calendar = .current) -> String {
        let days = RelativeDay.days(from: now, to: date, calendar: calendar)
        if days > 0 { return "อีก \(days) วัน" }
        let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded(.down)))
        return minutes < 60 ? "อีก \(minutes) นาที" : "อีก \(minutes / 60) ชม. \(minutes % 60) นาที"
    }

    /// `12 กม. - ขับ 25 นาที` (`1 ชม. 5 นาที` from an hour), from a route's length and expected travel time.
    public static func drive(meters: Double, seconds: Double) -> String {
        let km = meters / 1000
        let distance = km < 10 ? String(format: "%.1f", km).replacingOccurrences(of: ".0", with: "") : String(Int(km.rounded()))
        let minutes = max(1, Int((seconds / 60).rounded()))
        let time = minutes < 60 ? "\(minutes) นาที" : "\(minutes / 60) ชม. \(minutes % 60) นาที"
        return "\(distance) กม. - ขับ \(time)"
    }
}
