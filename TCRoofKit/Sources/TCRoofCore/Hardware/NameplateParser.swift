import Foundation

/// Values read from the text of an equipment nameplate (docs/specs/hardware-assist-swift.md §H1): what Live Text
/// recognised on a transformer, breaker or meter label. Every value is a proposal the surveyor confirms.
public enum NameplateParser {
    public struct Reading: Equatable, Sendable {
        /// "630"
        public var kva: String?
        /// "4.5" (%Z / Uk)
        public var impedance: String?
        /// "Dyn11"
        public var vectorGroup: String?
        /// Highest and lowest voltage on the plate, in volts: 22000 / 400.
        public var hvVolts: Double?
        public var lvVolts: Double?
        /// Year of manufacture in B.E., as the form writes it: 2565.
        public var yearBE: Int?
        /// Breaker rated current In (AT), frame (AF) and breaking capacity Icu (kA).
        public var breakerAT: String?
        public var breakerAF: String?
        public var breakerKA: String?
        /// Meter number, digits and dashes: "1234-5678-90".
        public var meterNumber: String?
        public init() {}
    }

    /// The form fields Live Text can fill in phase 1.
    public enum Target: String, Sendable {
        case kva, breakerAT, meterNumber

        /// The proposal line: "630 kVA".
        public func display(_ value: String) -> String {
            switch self {
            case .kva: return "\(value) kVA"
            case .breakerAT: return "\(value) AT"
            case .meterNumber: return value
            }
        }
    }

    /// The value for one field, or nil when the text holds none.
    public static func value(_ target: Target, in text: String) -> String? {
        let r = read(text)
        switch target {
        case .kva: return r.kva
        case .breakerAT: return r.breakerAT
        case .meterNumber: return r.meterNumber
        }
    }

    public static func read(_ raw: String) -> Reading {
        let t = normalise(raw)
        var r = Reading()
        r.kva = first(#"(\d{2,5})\s*k\s*V\s*A\b"#, in: t)
        r.impedance = first(#"(?:%\s*Z|Z\s*%|U\s*k|IMPEDANCE)[^\d]{0,16}(\d{1,2}[.,]\d{1,2})"#, in: t)?.replacingOccurrences(of: ",", with: ".")
        if let m = match(#"\b([DY])(yn|zn|y|d)\s?(\d{1,2})\b"#, in: t) {
            r.vectorGroup = m[0].uppercased() + m[1].lowercased() + m[2]
        }
        let volts = all(#"(\d{1,6}(?:[.,]\d{1,3})?)\s*(k?)V\b(?!\s*A)"#, in: t).compactMap { m -> Double? in
            guard let v = Double(m[0].replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
            return m[1].lowercased() == "k" ? v * 1000 : v
        }
        if volts.count >= 2 { r.hvVolts = volts.max(); r.lvVolts = volts.min() }
        r.yearBE = year(t)
        r.breakerAT = first(#"\bI\s*n\s*=?\s*(\d{2,4})\s*A\b"#, in: t) ?? first(#"\b(\d{2,4})\s*AT\b"#, in: t)
        r.breakerAF = first(#"\b(\d{2,4})\s*AF\b"#, in: t)
        r.breakerKA = first(#"\bIcu\s*=?\s*(\d{1,3}(?:\.\d)?)\s*kA\b"#, in: t)
        r.meterNumber = meterNumber(t)
        return r
    }

    // MARK: pieces

    /// Thai digits to 0–9, "1,000" to "1000", one space between words.
    static func normalise(_ s: String) -> String {
        var out = String(s.unicodeScalars.map { u -> Character in
            (0x0E50...0x0E59).contains(u.value) ? Character(UnicodeScalar(u.value - 0x0E50 + 0x30)!) : Character(u)
        })
        out = out.replacingOccurrences(of: #"(\d),(\d{3})(?!\d)"#, with: "$1$2", options: .regularExpression)
        return out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Year of manufacture: after "Year" / "ปี" / "MFG" when written, else a lone 19xx / 20xx / 25xx that is no rating.
    static func year(_ t: String) -> Int? {
        let labelled = first(#"(?:YEAR|MFG|ปี(?:ที่ผลิต)?)\D{0,6}((?:19|20|25)\d{2})\b"#, in: t)
        let lone = first(#"\b((?:19|20|25)\d{2})\b(?!\s*(?:k?V|k?VA|AT|AF|A\b|kA|Hz|W|mm))"#, in: t)
        guard let s = labelled ?? lone, let y = Int(s) else { return nil }
        return y >= 2400 ? y : y + 543
    }

    /// The digit run (dashes allowed) of 8–12 characters after "No." / "เลขที่", else the longest one on the plate.
    static func meterNumber(_ t: String) -> String? {
        let run = #"(\d[\d-]{6,10}\d)"#
        if let s = first(#"(?:\bNo\.?|เลขที่|หมายเลข)\s*:?\s*"# + run, in: t) { return s }
        return all(#"(?<![\d.])"# + run + #"(?![\d.])"#, in: t).map { $0[0] }.max { $0.count < $1.count }
    }

    static func first(_ pattern: String, in t: String) -> String? { match(pattern, in: t)?.first }

    static func match(_ pattern: String, in t: String) -> [String]? { all(pattern, in: t).first }

    /// Capture groups of every match, case-insensitive.
    static func all(_ pattern: String, in t: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = t as NSString
        return re.matches(in: t, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }
}
