import Foundation

/// Input rules of the iPhone new-customer sheet (docs/ui/tcroof-new-job-iphone §3, §5, §8).
public enum NewJobRules {
    // MARK: phone

    /// Digits only, at most 10.
    public static func phoneDigits(_ text: String) -> String { String(text.filter(\.isASCIIDigit).prefix(10)) }

    /// `081-234-5678` for 10 digits, `02-555-1234` for 9; fewer digits are grouped as far as they go.
    public static func formatPhone(_ text: String) -> String {
        let d = phoneDigits(text)
        let cuts = d.count == 9 || (d.hasPrefix("02") && d.count < 10) ? [2, 3] : [3, 3]
        var parts: [String] = [], rest = Substring(d)
        for n in cuts where !rest.isEmpty { parts.append(String(rest.prefix(n))); rest = rest.dropFirst(n) }
        if !rest.isEmpty { parts.append(String(rest)) }
        return parts.joined(separator: "-")
    }

    /// Valid when empty or 9–10 digits.
    public static func isValidPhone(_ text: String) -> Bool {
        let n = phoneDigits(text).count
        return n == 0 || (9...10).contains(n)
    }

    // MARK: system size

    public static let kWpRange = 1.0...100.0
    public static let kWpStep = 0.5
    public static let panelWatts = 570.0

    /// `~n แผง` of a 570 W panel; 0 when the size is unknown.
    public static func panelCount(kWp: Double) -> Int { kWp > 0 ? Int((kWp * 1000 / panelWatts).rounded()) : 0 }

    public enum KWpCheck: Equatable { case ok(Double), empty, tooHigh, tooLow, notStep }

    /// The custom kWp entry: 1–100 in steps of 0.5. `tooHigh` / `tooLow` carry the board's messages.
    public static func checkKWp(_ text: String) -> KWpCheck {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.isEmpty { return .empty }
        guard let v = Double(t) else { return .empty }
        if v > kWpRange.upperBound { return .tooHigh }
        if v < kWpRange.lowerBound { return .tooLow }
        return (v / kWpStep).rounded() == v / kWpStep ? .ok(v) : .notStep
    }

    public static func kWpMessage(_ c: KWpCheck) -> String? {
        switch c {
        case .tooHigh: "เกินค่าสูงสุด 100"
        case .tooLow: "ต่ำกว่าค่าต่ำสุด 1"
        case .notStep: "ใส่เป็นช่วง 0.5"
        case .ok, .empty: nil
        }
    }

    // MARK: dates

    /// `วันนี้`, `พรุ่งนี้`, otherwise `อีก n วัน`.
    public static func relativeDay(_ date: Date, from today: Date, calendar cal: Calendar = .current) -> String {
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: date)).day ?? 0
        return n == 0 ? "วันนี้" : n == 1 ? "พรุ่งนี้" : "อีก \(n) วัน"
    }

    /// The survey moment: `day` at `hour:minute`.
    public static func surveyDate(day: Date, hour: Int, minute: Int, calendar cal: Calendar = .current) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// `installStart` = the survey day plus `offsetDays`; the last install day is `days - 1` later.
    public static func installRange(survey: Date, offsetDays: Int, days: Int, calendar cal: Calendar = .current) -> (start: Date, end: Date) {
        let start = cal.date(byAdding: .day, value: offsetDays, to: cal.startOfDay(for: survey)) ?? survey
        return (start, cal.date(byAdding: .day, value: max(days, 1) - 1, to: start) ?? start)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
