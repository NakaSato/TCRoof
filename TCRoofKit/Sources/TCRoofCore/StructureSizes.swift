import Foundation

/// Pick lists for the roof-structure table ("รายละเอียด (ขนาด @ระยะห่าง)"), e.g. "C-100x50x20x3.2 @1.00M".
/// The value stays a plain string, so anything not in the list can still be typed.
public enum StructureSizes {
    public static let sections: [(group: String, items: [String])] = [
        ("เหล็กตัวซี (C)", ["C-75x45x15x2.3", "C-100x50x20x2.3", "C-100x50x20x3.2", "C-125x50x20x3.2", "C-150x50x20x2.3", "C-150x50x20x3.2", "C-150x65x20x3.2", "C-200x75x25x3.2"]),
        ("ตัวซีคู่ (2C)", ["2C-100x50x20x3.2", "2C-125x50x20x3.2", "2C-150x50x20x2.3", "2C-150x50x20x3.2", "2C-200x75x25x3.2"]),
        ("เหล็กกล่อง (□)", ["□-50x50x2.3", "□-75x75x3.2", "□-100x100x3.2", "□-100x50x2.3", "□-125x75x3.2", "□-150x50x3.2"]),
        ("เหล็ก H / I", ["H-100x100x6x8", "H-125x125x6.5x9", "H-150x150x7x10", "H-200x100x5.5x8", "H-200x200x8x12", "I-150x75x5.5x9.5", "I-200x100x7x10"]),
        ("เหล็กฉาก (L)", ["L-40x40x4", "L-50x50x5", "L-65x65x6"]),
        ("ท่อกลม (Ø)", ["Ø-60.5x2.3", "Ø-76.3x3.2", "Ø-101.6x3.2"]),
        ("ไม้", ["ไม้ 1.5\"x3\"", "ไม้ 2\"x4\"", "ไม้ 2\"x6\"", "ไม้ 2\"x8\"", "ไม้ 1\"x8\""]),
        ("คอนกรีตเสริมเหล็ก", ["ค.ส.ล 0.20x0.30", "ค.ส.ล 0.20x0.40", "ค.ส.ล 0.25x0.50"]),
    ]
    public static let spacings = ["@0.60M", "@0.80M", "@1.00M", "@1.20M", "@1.50M", "@2.00M", "@2.50M", "@3.00M", "@4.00M", "@5.00M", "@6.00M"]

    /// C2 roof form: member sizes as "g x f x h" in centimetres, with the section type in front.
    public static let sectionsCm: [(group: String, items: [String])] = [
        ("เหล็กตัวซี (C) ซม.", ["C 7.5x4.5x1.5", "C 10x5x2", "C 12.5x5x2", "C 15x5x2", "C 15x6.5x2", "C 20x7.5x2.5"]),
        ("ตัวซีคู่ (2C) ซม.", ["2C 10x5x2", "2C 12.5x5x2", "2C 15x5x2", "2C 20x7.5x2.5"]),
        ("เหล็กกล่อง (□) ซม.", ["□ 5x5", "□ 7.5x7.5", "□ 10x10", "□ 10x5", "□ 15x5"]),
        ("เหล็ก H / I ซม.", ["H 10x10", "H 12.5x12.5", "H 15x15", "H 20x10", "I 15x7.5", "I 20x10"]),
        ("เหล็กฉาก (L) ซม.", ["L 4x4", "L 5x5", "L 6.5x6.5"]),
        ("ไม้ ซม.", ["ไม้ 3.8x7.5", "ไม้ 5x10", "ไม้ 5x15", "ไม้ 5x20", "ไม้ 2.5x20"]),
        ("คอนกรีต ซม.", ["ค.ส.ล 20x30", "ค.ส.ล 20x40", "ค.ส.ล 25x50"]),
    ]
    /// C2 spacing, centimetres.
    public static let spacingsCm = ["60", "80", "100", "120", "150", "200", "250", "300", "400", "500", "600"]

    /// Usual sizes for each component 1…7 (แป จันทัน อเส ขื่อ ค้ำยัน เชิงชาย ดั้ง), shown first.
    public static func recommended(_ component: Int) -> [String] {
        switch component {
        case 1: return ["C-100x50x20x2.3", "C-100x50x20x3.2", "C-125x50x20x3.2", "C-75x45x15x2.3", "□-50x50x2.3"]
        case 2: return ["C-150x50x20x3.2", "2C-150x50x20x2.3", "2C-150x50x20x3.2", "H-150x150x7x10"]
        case 3: return ["C-150x50x20x3.2", "2C-150x50x20x2.3", "ไม้ 2\"x8\""]
        case 4: return ["2C-150x50x20x3.2", "H-200x100x5.5x8", "ค.ส.ล 0.20x0.40"]
        case 5: return ["L-50x50x5", "□-75x75x3.2", "C-100x50x20x3.2"]
        case 6: return ["ไม้ 1\"x8\"", "C-150x50x20x2.3"]
        case 7: return ["□-100x100x3.2", "2C-150x50x20x2.3", "H-150x150x7x10"]
        default: return []
        }
    }
    /// Usual spacing: purlins about 1 m, rafters about 4 m.
    public static func defaultSpacing(_ component: Int) -> String? {
        switch component { case 1: return "@1.00M"; case 2: return "@4.00M"; default: return nil }
    }

    /// "C-100x50x20x3.2 @1.00M" → ("C-100x50x20x3.2", "@1.00M")
    public static func split(_ value: String) -> (size: String, spacing: String) {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard let r = v.range(of: "@") else { return (v, "") }
        return (String(v[..<r.lowerBound]).trimmingCharacters(in: .whitespaces), String(v[r.lowerBound...]).replacingOccurrences(of: " ", with: ""))
    }
    public static func join(size: String, spacing: String) -> String {
        let s = size.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "-" { return s }
        return spacing.isEmpty ? s : s + " " + spacing
    }
}
