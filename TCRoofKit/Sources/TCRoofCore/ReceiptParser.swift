import Foundation

/// Proposes an expense's values from a receipt's recognised text (docs/specs/calendar-travel-expenses-swift.md §B4):
/// the amount, the date, the seller's tax ID, a category and the vendor. Nothing is filled until the person accepts.
public struct ReceiptParser {
    public struct Proposal: Equatable, Sendable {
        /// Satang.
        public var amount: Int?
        public var date: Date?
        public var taxID: String?
        public var category: TravelClaim.Category?
        public var vendor: String?
        public init(amount: Int? = nil, date: Date? = nil, taxID: String? = nil, category: TravelClaim.Category? = nil, vendor: String? = nil) {
            self.amount = amount; self.date = date; self.taxID = taxID; self.category = category; self.vendor = vendor
        }
        public var isEmpty: Bool { amount == nil && date == nil && taxID == nil && category == nil && vendor == nil }
    }

    /// Words before the amount paid, strongest first: a line with one of these wins over the largest number.
    static let totalWords = ["รวมทั้งสิ้น", "ยอดสุทธิ", "ยอดรวม", "จำนวนเงินรวม", "grand total", "net total", "total", "รวมเงิน",
                             "จำนวนเงิน", "amount", "รวม"]
    /// Lines that hold money but not the amount paid.
    static let notTotalWords = ["เงินทอน", "change", "รับเงิน", "cash", "เงินสด", "ภาษีมูลค่าเพิ่ม", "vat", "ส่วนลด", "discount",
                                "ก่อนภาษี", "before"]
    static let categoryWords: [(TravelClaim.Category, [String])] = [
        (.fuel, ["น้ำมัน", "ดีเซล", "แก๊สโซฮอล์", "แก๊สโซฮอล", "เบนซิน", "diesel", "gasohol", "benzine", "ptt", "บางจาก", "bangchak",
                 "shell", "เชลล์", "caltex", "คาลเท็กซ์", "esso", "เอสโซ่", "พีที", "susco", "ซัสโก้", "e20", "b7", "ลิตร", "litre", "liter"]),
        (.toll, ["ทางด่วน", "ทางพิเศษ", "มอเตอร์เวย์", "motorway", "expressway", "easy pass", "m-flow", "ด่าน", "toll"]),
        (.parking, ["จอดรถ", "parking", "ค่าจอด"]),
        (.lodging, ["โรงแรม", "รีสอร์ท", "รีสอร์ต", "hotel", "resort", "ห้องพัก", "ที่พัก", "เกสต์เฮาส์", "guest house", "อพาร์ทเม้นท์"]),
    ]

    public init() {}

    public func parse(_ text: String) -> Proposal {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Proposal(amount: amount(lines), date: date(lines), taxID: taxID(lines), category: category(text), vendor: vendor(lines))
    }

    // MARK: amount

    /// Money-looking numbers in a line: "1,234.50", "1234.50", "350.00", "฿ 85". A number glued to letters (a code)
    /// and a 13-digit tax ID are not money.
    static func money(in line: String) -> [Int] {
        let pattern = #"(?<![\d.,])(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?(?![\d,]|\.\d)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = line as NSString
        return re.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let whole = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
            guard whole.count <= 7 else { return nil }
            let fraction = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            // a bare whole number without a decimal or thousands separator is often a quantity or a code: only with a ฿ / บาท
            let hasMoneyShape = !fraction.isEmpty || ns.substring(with: m.range(at: 1)).contains(",")
                || line.contains("฿") || line.contains("บาท") || line.lowercased().contains("thb")
            guard hasMoneyShape, let baht = Int(whole) else { return nil }
            let satang = fraction.isEmpty ? 0 : Int(fraction.count == 1 ? fraction + "0" : fraction) ?? 0
            return baht * 100 + satang
        }
    }

    func amount(_ lines: [String]) -> Int? {
        for word in Self.totalWords {
            for (i, line) in lines.enumerated() {
                let lower = line.lowercased()
                guard lower.contains(word), !Self.notTotalWords.contains(where: { lower.contains($0) }) else { continue }
                // the amount on the same line, else on the next (receipts often put it under the label)
                if let v = Self.money(in: line).last, v > 0 { return v }
                if i + 1 < lines.count, let v = Self.money(in: lines[i + 1]).last, v > 0 { return v }
            }
        }
        return lines.flatMap { line -> [Int] in
            let lower = line.lowercased()
            return Self.notTotalWords.contains(where: { lower.contains($0) }) ? [] : Self.money(in: line)
        }.max()
    }

    // MARK: date

    /// The first `dd/mm/yy`, `dd/mm/yyyy` (also with - or .) or `dd <Thai month> yy(yy)` date; Buddhist years (> 2400)
    /// and two-digit Buddhist years (60–99 → 25xx) are converted.
    func date(_ lines: [String]) -> Date? {
        let numeric = #"(?<!\d)(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})(?!\d)"#
        if let re = try? NSRegularExpression(pattern: numeric) {
            for line in lines {
                let ns = line as NSString
                for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    let d = Int(ns.substring(with: m.range(at: 1))) ?? 0
                    let mo = Int(ns.substring(with: m.range(at: 2))) ?? 0
                    let y = Int(ns.substring(with: m.range(at: 3))) ?? 0
                    if let date = Self.make(day: d, month: mo, year: y) { return date }
                }
            }
        }
        let months = RoutineReport.thaiMonthsShort.map { $0.replacingOccurrences(of: ".", with: "") }
        let full = RoutineReport.thaiMonths
        for line in lines {
            let plain = line.replacingOccurrences(of: ".", with: "")
            for (i, names) in zip(months.indices, zip(months, full)) {
                for name in [names.1, names.0] where plain.contains(name) {
                    let pattern = #"(\d{1,2})\s*"# + NSRegularExpression.escapedPattern(for: name) + #"\s*(\d{2,4})"#
                    guard let re = try? NSRegularExpression(pattern: pattern),
                          let m = re.firstMatch(in: plain, range: NSRange(location: 0, length: (plain as NSString).length)) else { continue }
                    let ns = plain as NSString
                    if let date = Self.make(day: Int(ns.substring(with: m.range(at: 1))) ?? 0, month: i + 1,
                                            year: Int(ns.substring(with: m.range(at: 2))) ?? 0) { return date }
                }
            }
        }
        return nil
    }

    static func make(day: Int, month: Int, year raw: Int) -> Date? {
        var year = raw
        if year < 100 { year += year >= 60 ? 2500 : 2000 }
        if year > 2400 { year -= 543 }
        guard (1...12).contains(month), (1...31).contains(day), (2000...2100).contains(year) else { return nil }
        let cal = TravelClaim.calendar
        guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)),
              cal.component(.day, from: date) == day else { return nil }
        return date
    }

    // MARK: tax ID, category, vendor

    /// A 13-digit run (spaces and dashes between groups allowed), preferring one on or after a tax-ID label.
    func taxID(_ lines: [String]) -> String? {
        let labels = ["เลขประจำตัวผู้เสียภาษี", "เลขที่ผู้เสียภาษี", "tax id", "taxid", "tax no", "เลขประจำตัว"]
        func digits(_ line: String) -> String? {
            let pattern = #"(?<!\d)(\d[\d\s\-]{11,20}\d)(?!\d)"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            let ns = line as NSString
            for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let d = ns.substring(with: m.range(at: 1)).filter(\.isNumber)
                if d.count == 13 { return d }
            }
            return nil
        }
        for (i, line) in lines.enumerated() where labels.contains(where: { line.lowercased().contains($0) }) {
            if let d = digits(line) { return d }
            if i + 1 < lines.count, let d = digits(lines[i + 1]) { return d }
        }
        return lines.lazy.compactMap(digits).first
    }

    func category(_ text: String) -> TravelClaim.Category? {
        let lower = text.lowercased()
        return Self.categoryWords.first { $0.1.contains { lower.contains($0) } }?.0
    }

    /// The first line with letters that isn't a receipt heading.
    func vendor(_ lines: [String]) -> String? {
        let skip = ["ใบเสร็จ", "receipt", "ใบกำกับ", "tax invoice", "สำเนา", "copy", "abb", "pos"]
        return lines.first { line in
            let lower = line.lowercased()
            return line.contains(where: \.isLetter) && line.count >= 3 && !skip.contains(where: { lower.contains($0) })
        }
    }

    // MARK: odometer

    /// The odometer reading in a photo's text: the longest run of 4 to 7 digits (a trip meter or the clock is shorter).
    public static func odometer(_ text: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: #"(?<![\d.])(\d[\d,\s]{2,8}\d)(?![\d.])"#) else { return nil }
        let ns = text as NSString
        let runs = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m -> String? in
            let d = ns.substring(with: m.range(at: 1)).filter(\.isNumber)
            return (4...7).contains(d.count) ? d : nil
        }
        return runs.max { $0.count < $1.count }.flatMap { Int($0) }
    }
}
