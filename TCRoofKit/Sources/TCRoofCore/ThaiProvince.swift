import Foundation

/// The 77 Thai provinces for the new-customer sheet (docs/ui/tcroof-new-job-iphone §7). `Job.province` stays a plain string.
public enum ThaiProvince {
    public static let all: [String] = [
        "กระบี่",
        "กรุงเทพมหานคร",
        "กาญจนบุรี",
        "กาฬสินธุ์",
        "กำแพงเพชร",
        "ขอนแก่น",
        "จันทบุรี",
        "ฉะเชิงเทรา",
        "ชลบุรี",
        "ชัยนาท",
        "ชัยภูมิ",
        "ชุมพร",
        "เชียงราย",
        "เชียงใหม่",
        "ตรัง",
        "ตราด",
        "ตาก",
        "นครนายก",
        "นครปฐม",
        "นครพนม",
        "นครราชสีมา",
        "นครศรีธรรมราช",
        "นครสวรรค์",
        "นนทบุรี",
        "นราธิวาส",
        "น่าน",
        "บึงกาฬ",
        "บุรีรัมย์",
        "ปทุมธานี",
        "ประจวบคีรีขันธ์",
        "ปราจีนบุรี",
        "ปัตตานี",
        "พระนครศรีอยุธยา",
        "พะเยา",
        "พังงา",
        "พัทลุง",
        "พิจิตร",
        "พิษณุโลก",
        "เพชรบุรี",
        "เพชรบูรณ์",
        "แพร่",
        "ภูเก็ต",
        "มหาสารคาม",
        "มุกดาหาร",
        "แม่ฮ่องสอน",
        "ยโสธร",
        "ยะลา",
        "ร้อยเอ็ด",
        "ระนอง",
        "ระยอง",
        "ราชบุรี",
        "ลพบุรี",
        "ลำปาง",
        "ลำพูน",
        "เลย",
        "ศรีสะเกษ",
        "สกลนคร",
        "สงขลา",
        "สตูล",
        "สมุทรปราการ",
        "สมุทรสงคราม",
        "สมุทรสาคร",
        "สระแก้ว",
        "สระบุรี",
        "สิงห์บุรี",
        "สุโขทัย",
        "สุพรรณบุรี",
        "สุราษฎร์ธานี",
        "สุรินทร์",
        "หนองคาย",
        "หนองบัวลำภู",
        "อ่างทอง",
        "อำนาจเจริญ",
        "อุดรธานี",
        "อุตรดิตถ์",
        "อุทัยธานี",
        "อุบลราชธานี"
    ]

    /// The chips under `ใช้บ่อย`: Bangkok and its metro area, and the east.
    public static let frequent = ["กรุงเทพมหานคร", "นนทบุรี", "ปทุมธานี", "สมุทรปราการ", "ชลบุรี", "ระยอง"]

    public static let defaultName = "กรุงเทพมหานคร"

    /// The first consonant, skipping a leading vowel เ แ โ ใ ไ (`เชียงใหม่` groups under `ช`).
    public static func groupKey(_ name: String) -> String {
        let lead: Set<Unicode.Scalar> = ["เ", "แ", "โ", "ใ", "ไ"]
        guard let c = name.unicodeScalars.first(where: { !lead.contains($0) }) else { return "" }
        return String(c)
    }

    /// Provinces whose name contains `query` (whitespace trimmed); everything when the query is empty.
    public static func search(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.contains(q) }
    }

    /// `search` split by `groupKey`, in Thai alphabet order. The names inside a group keep the order of `all`.
    public static func grouped(_ query: String = "") -> [(key: String, names: [String])] {
        let found = search(query)
        var order: [String] = [], byKey: [String: [String]] = [:]
        for n in found {
            let k = groupKey(n)
            if byKey[k] == nil { order.append(k) }
            byKey[k, default: []].append(n)
        }
        return order.sorted { $0.compare($1, locale: Locale(identifier: "th_TH")) == .orderedAscending }
            .map { (key: $0, names: byKey[$0] ?? []) }
    }
}
