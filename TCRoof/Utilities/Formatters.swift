import Foundation

enum ThaiFormat {
    static let locale = Locale(identifier: "th_TH")

    private static func make(_ format: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = locale
        df.calendar = Calendar(identifier: .buddhist)
        df.dateFormat = format
        return df
    }

    static let long = make("d MMMM yyyy")
    static let longTime = make("d MMMM yyyy HH:mm")
    static let short = make("d MMM yy")
    static let monthYear = make("MMMM yyyy")
    static let year = make("yyyy")
    /// "30/9/2569"
    static let numericDate = make("d/M/yyyy")
    /// "วันพุธ"
    static let weekday = make("EEEE")
    /// "29/9"
    static let dayMonth = make("d/M")
    /// "พุธ 30 กันยายน 2569"
    static let longDate = make("EEE d MMMM yyyy")
    /// "พุธ 30 ก.ย."
    static let weekdayShort = make("EEE d MMM")
    /// "1 ต.ค."
    static let dayMonthShort = make("d MMM")
    /// "29/9 16:42"
    static let dayMonthTime = make("d/M HH:mm")
    /// "09:30"
    static let time = make("HH:mm")
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var endOfDay: Date { Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay)! }
    var startOfMonth: Date { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))! }
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isWeekend: Bool { Calendar.current.isDateInWeekend(self) }

    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self)! }
    func adding(months: Int) -> Date { Calendar.current.date(byAdding: .month, value: months, to: self)! }

    var thaiLong: String { ThaiFormat.long.string(from: self) }
    var thaiLongTime: String { ThaiFormat.longTime.string(from: self) }
    var thaiShort: String { ThaiFormat.short.string(from: self) }
    var thaiMonthYear: String { ThaiFormat.monthYear.string(from: self) }
}

extension Double {
    var kw: String { "\(formatted(.number.precision(.fractionLength(0...2)))) kW" }
    var plain: String { formatted(.number.precision(.fractionLength(0...2))) }
}

/// Queue filter used by every job list ("คิว…ใน 7 วัน / 30 วัน / ทั้งหมด").
enum DateWindow: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, all = 0

    var id: Int { rawValue }

    func label(_ prefix: String) -> String {
        switch self {
        case .week: "\(prefix)ใน 7 วัน"
        case .month: "\(prefix)ใน 30 วัน"
        case .all: "\(prefix)ทั้งหมด"
        }
    }

    func overlaps(_ range: ClosedRange<Date>) -> Bool {
        guard self != .all else { return true }
        let start = Date().startOfDay
        let end = start.adding(days: rawValue)
        return range.upperBound >= start && range.lowerBound < end
    }
}
