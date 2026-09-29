import Foundation

/// Clean-up for typed numbers, so "1,200", "50 ซม." or Thai digits still read as numbers.
public enum NumberInput {
    /// Keeps the first number in `s`: Thai digits become 0–9, commas and spaces are dropped,
    /// and anything after the first letter (a unit such as "cm" or "ซม.") is cut off.
    public static func clean(_ s: String) -> String {
        var out = ""
        var dot = false
        for ch in s {
            var c = ch
            if ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value, (0x0E50...0x0E59).contains(v),
               let ascii = UnicodeScalar(v - 0x0E50 + 0x30) {
                c = Character(ascii)
            }
            if c.isASCII && c.isWholeNumber {
                out.append(c)
            } else if c == "." && !dot {
                dot = true
                out.append(c)
            } else if c == "-" && out.isEmpty {
                out.append(c)
            } else if c.isLetter && out.contains(where: \.isWholeNumber) {
                break
            }
        }
        return out
    }

    /// Empty, or text `Double` can read.
    public static func isValid(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || Double(t) != nil
    }
}

public enum GPSCheck: Equatable, Sendable {
    case empty, ok, outsideThailand, invalid
    /// Latitude and longitude typed the wrong way round; carries the corrected text.
    case swapped(String)
}

/// "lat, lon" text as stored in the `gps` field.
public enum GPS {
    public static func parse(_ s: String) -> (lat: Double, lon: Double)? {
        let parts = s.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" || $0 == "\n" })
            .map { NumberInput.clean(String($0)) }
            .filter { !$0.isEmpty }
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) else { return nil }
        return (a, b)
    }

    static func inThailand(_ lat: Double, _ lon: Double) -> Bool { (5.0...21.0).contains(lat) && (97.0...106.0).contains(lon) }

    public static func format(_ lat: Double, _ lon: Double) -> String { String(format: "%.6f, %.6f", lat, lon) }

    public static func check(_ s: String) -> GPSCheck {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .empty }
        guard let p = parse(t) else { return .invalid }
        if inThailand(p.lat, p.lon) { return .ok }
        if inThailand(p.lon, p.lat) { return .swapped(format(p.lon, p.lat)) }
        return (-90.0...90.0).contains(p.lat) && (-180.0...180.0).contains(p.lon) ? .outsideThailand : .invalid
    }
}

/// Required answers still missing (or unreadable) in one page of the editor.
public struct MissingGroup: Identifiable, Sendable {
    public enum Target: Hashable, Sendable { case info, site, electrical, flood, module(UUID), final }
    public let target: Target
    public let title: String
    public let items: [String]
    public var id: Target { target }
}

public extension FieldSpec {
    /// The label without the "**" marks the paper form uses.
    var plainLabel: String { label.trimmingCharacters(in: CharacterSet(charactersIn: "* ")) }
}

public extension GroupSpec {
    /// Visible number fields whose text isn't a number (e.g. typed before input clean-up existed).
    func badNumbers(_ v: Values) -> [FieldSpec] {
        fields.filter { f in
            guard f.isVisible(v), case .number = f.kind else { return false }
            return !NumberInput.isValid(v.text(f.id))
        }
    }
}

public extension Job {
    /// Everything still to fill or fix, grouped by the editor page it is on.
    var missingGroups: [MissingGroup] {
        func items(_ g: GroupSpec, _ v: Values, skipTransformerFields: Bool = false) -> [String] {
            g.missing(v).filter { !skipTransformerFields || !$0.id.hasPrefix("tr") || $0.id == "trafos" }.map(\.plainLabel)
                + g.badNumbers(v).map { "ตัวเลขไม่ถูกต้อง: " + $0.plainLabel }
        }
        var info = items(Schema.info, values)
        switch GPS.check(values.text("gps")) {
        case .invalid: info.append("พิกัด GPS รูปแบบไม่ถูกต้อง")
        case .swapped: info.append("พิกัด GPS สลับละติจูด/ลองจิจูด")
        case .outsideThailand: info.append("พิกัด GPS อยู่นอกประเทศไทย")
        case .empty, .ok: break
        }
        let date = values.text("date")
        if !date.isEmpty && ISODate.date(date) == nil { info.append("วันที่รูปแบบไม่ถูกต้อง") }

        var out: [MissingGroup] = []
        func add(_ t: MissingGroup.Target, _ title: String, _ list: [String]) {
            if !list.isEmpty { out.append(MissingGroup(target: t, title: title, items: list)) }
        }
        add(.info, "A1 ข้อมูลโครงการ", info)
        add(.site, "A2 ภาพสถานที่ติดตั้ง", items(Schema.site, values))
        add(.electrical, "A3 มิเตอร์ หม้อแปลง และตู้ MDB", transformerGaps + items(Schema.electrical, values, skipTransformerFields: true))
        add(.flood, "A4 ประวัติน้ำท่วม", items(Schema.flood, values))
        let numbered = sectionsByCategory.flatMap(\.sections)
        for m in modules {
            let title = numbered.first { $0.id == m.id }?.title ?? (m.spec.code + " " + m.title)
            add(.module(m.id), title, m.spec.groups.flatMap { items($0, m.values) })
        }
        add(.final, "E1 สรุปผลและลงนาม", items(Schema.final, values))
        return out
    }

    var missingCount: Int { missingGroups.reduce(0) { $0 + $1.items.count } }
}
