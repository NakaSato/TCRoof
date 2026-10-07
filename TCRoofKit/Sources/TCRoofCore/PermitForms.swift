import Foundation

// PEA permit forms of the Solar Rooftop ภาคประชาชน 2569 programme (บ้านอยู่อาศัย).
//
// The printed page is the original PEA PDF, untouched; the app only writes the answers on top of it at the
// positions in `Resources/PermitForms/<template>.json` (PDF points, origin top-left, measured from the original).
// That keeps the font and layout identical to the form PEA issued.

// MARK: - Overlay map

/// Where answers go on one PEA form (`Resources/PermitForms/<template>.json`).
public struct PermitFormMap: Decodable, Sendable {
    /// A blank line: the value is drawn between `x0` and `x1`, sitting on `baseline`.
    public struct Field: Decodable, Sendable {
        public enum Align: String, Decodable, Sendable { case left, center }
        public let key: String
        public let page: Int
        public let x0: Double
        public let x1: Double
        public let baseline: Double
        public let align: Align
    }
    /// A printed check box; the app draws ✓ or – inside `rect` ([x, y, w, h]).
    public struct Check: Decodable, Sendable {
        public let key: String
        public let page: Int
        public let rect: [Double]
    }
    /// A photo area on an attachment page ([x, y, w, h]).
    public struct Area: Decodable, Sendable {
        public let key: String
        public let page: Int
        public let rect: [Double]
    }

    public let title: String
    public let template: String
    public let pageSize: [Double]
    public let pages: Int
    public let fontSize: Double
    public let fields: [Field]
    public let checks: [Check]
    public let areas: [Area]

    public static let powerOfAttorney = "pea-poa-2569"
    public static let selfCertification = "pea-selfcert-2569"

    static var folder: URL? { Bundle.module.url(forResource: "PermitForms", withExtension: nil) }

    /// The original PEA PDF the answers are drawn on.
    public static func templateURL(_ template: String) -> URL? {
        folder?.appendingPathComponent(template + ".pdf")
    }

    public static func load(_ template: String) -> PermitFormMap? {
        guard let url = folder?.appendingPathComponent(template + ".json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PermitFormMap.self, from: data)
    }
}

/// A check box answer: ✓ (do) or – (do not), as the forms' notes ask.
public enum PermitMark: String, Codable, Sendable, Equatable {
    case yes
    case no
}

// MARK: - Thai ID and dates

public enum ThaiID {
    /// Digits only (Thai digits count too), at most 13.
    public static func digits(_ s: String) -> String {
        String(s.compactMap { $0.wholeNumberValue.map { Character(String($0)) } }.prefix(13))
    }

    /// 13 digits with a correct check digit.
    public static func isValid(_ s: String) -> Bool {
        let d = digits(s).compactMap(\.wholeNumberValue)
        guard d.count == 13 else { return false }
        let sum = (0..<12).reduce(0) { $0 + d[$1] * (13 - $1) }
        return (11 - sum % 11) % 10 == d[12]
    }

    /// `x-xxxx-xxxxx-xx-x` as far as typed.
    public static func formatted(_ s: String) -> String {
        let d = Array(digits(s))
        var parts: [String] = []
        var i = 0
        for n in [1, 4, 5, 2, 1] where i < d.count {
            parts.append(String(d[i..<min(i + n, d.count)]))
            i += n
        }
        return parts.joined(separator: "-")
    }
}

public enum PermitDate {
    public static let months = ["มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
                                "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"]

    /// Day, month and Buddhist-era year of `date` in Thai time.
    public static func parts(_ date: Date) -> (day: Int, month: Int, year: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        let c = cal.dateComponents([.day, .month, .year], from: date)
        return (c.day ?? 1, c.month ?? 1, (c.year ?? 2026) + 543)
    }

    /// `7/10/2569`.
    public static func short(_ date: Date) -> String {
        let p = parts(date)
        return "\(p.day)/\(p.month)/\(p.year)"
    }
}

// MARK: - หนังสือมอบอำนาจ

/// แบบฟอร์ม กฟภ. "หนังสือมอบอำนาจ โครงการผลิตไฟฟ้าจากพลังงานแสงอาทิตย์ที่ติดตั้งบนหลังคา สำหรับภาคประชาชนประเภทบ้านที่อยู่อาศัย".
public struct PowerOfAttorney: Codable, Equatable, Sendable {
    public struct Person: Codable, Equatable, Sendable {
        public var name = ""
        public var age = ""
        /// Digits only.
        public var nationalID = ""
        public var ethnicity = "ไทย"
        public var nationality = "ไทย"
        public var houseNo = ""
        public var moo = ""
        public var subdistrict = ""
        public var district = ""
        public var province = ""
        public var phone = ""
        public var email = ""
        public init() {}
    }

    /// The seven powers, as printed.
    public static let powers = [
        "ยื่นแบบคำขอขายไฟฟ้า และเอกสารประกอบที่เกี่ยวข้องทั้งหมด",
        "ลงนามและยื่นแบบคำขอขายไฟฟ้า และเอกสารประกอบที่เกี่ยวข้องทั้งหมด",
        "ติดต่อประสานงาน ให้ถ้อยคำต่างๆ กับเจ้าหน้าที่ของการไฟฟ้าฝ่ายจำหน่าย",
        "ติดต่อ จัดส่งเอกสารและลงนามสัญญาซื้อขายไฟฟ้ากับการไฟฟ้าฝ่ายจำหน่าย หากได้รับการคัดเลือก",
        "ลงนามและยื่นขออนุญาตเชื่อมต่อระบบโครงข่ายไฟฟ้า และเอกสารประกอบที่เกี่ยวข้อง หากได้รับการคัดเลือก กับการไฟฟ้าฝ่ายจำหน่าย",
        "แก้ไข ตกเติม และรับรองเอกสารที่เกี่ยวข้องในข้อ…",
        "อื่นๆ (ระบุ)",
    ]

    public enum Preset: CaseIterable, Sendable {
        /// ✓ 1–5, – 6–7: the installer files everything for a seller.
        case sellAll
        /// ✓ 3 and 5 only: the grid connection without selling.
        case connectOnly
        case clear
    }

    public var writtenAt = ""
    public var date = Date()
    public var grantor = Person()
    public var grantee = Person()
    /// Items 1…7; nil = not marked yet.
    public var powers: [PermitMark?] = Array(repeating: nil, count: 7)
    public var item6Ref = ""
    public var item7Other = ""
    public var witness1 = ""
    public var witness2 = ""

    public init() {}

    public mutating func apply(_ preset: Preset) {
        switch preset {
        case .sellAll: powers = [.yes, .yes, .yes, .yes, .yes, .no, .no]
        case .connectOnly: powers = [.no, .no, .yes, .no, .yes, .no, .no]
        case .clear: powers = Array(repeating: nil, count: 7)
        }
    }

    /// Answers by field key of `pea-poa-2569.json`.
    public var values: [String: String] {
        let d = PermitDate.parts(date)
        var v: [String: String] = [
            "written_at": writtenAt, "day": "\(d.day)", "month": PermitDate.months[d.month - 1], "year": "\(d.year)",
            "item6_ref": powers[5] == .yes ? item6Ref : "",
            "item7_other": powers[6] == .yes ? item7Other : "",
            "grantor.print": grantor.name, "grantee.print": grantee.name,
            "witness_1": witness1, "witness_2": witness2,
        ]
        for (key, p) in [("grantor", grantor), ("grantee", grantee)] {
            v["\(key).name"] = p.name
            v["\(key).age"] = p.age
            v["\(key).national_id"] = ThaiID.formatted(p.nationalID)
            v["\(key).ethnicity"] = p.ethnicity
            v["\(key).nationality"] = p.nationality
            v["\(key).house_no"] = p.houseNo
            v["\(key).moo"] = p.moo
            v["\(key).subdistrict"] = p.subdistrict
            v["\(key).district"] = p.district
            v["\(key).province"] = p.province
            v["\(key).phone"] = p.phone
            v["\(key).email"] = p.email
        }
        return v
    }

    public var marks: [String: PermitMark] {
        var m: [String: PermitMark] = [:]
        for (i, p) in powers.enumerated() { if let p { m["power_\(i + 1)"] = p } }
        return m
    }

    /// What is still missing or wrong, in the order of the form; empty when ready to print.
    public var issues: [String] {
        var out: [String] = []
        if writtenAt.isBlank { out.append("เขียนที่") }
        for (label, p) in [("ผู้มอบ", grantor), ("ผู้รับมอบ", grantee)] {
            if p.name.isBlank { out.append("\(label): ชื่อ") }
            if p.age.isBlank { out.append("\(label): อายุ") }
            if !ThaiID.isValid(p.nationalID) {
                out.append(p.nationalID.isEmpty ? "\(label): เลขบัตรประชาชน" : "\(label): เลขบัตรประชาชนไม่ถูกต้อง")
            }
            if p.ethnicity.isBlank || p.nationality.isBlank { out.append("\(label): เชื้อชาติ/สัญชาติ") }
            if p.houseNo.isBlank || p.subdistrict.isBlank || p.district.isBlank || p.province.isBlank { out.append("\(label): ที่อยู่") }
            if p.phone.isBlank { out.append("\(label): เบอร์โทรศัพท์") }
        }
        if !grantor.nationalID.isEmpty && ThaiID.digits(grantor.nationalID) == ThaiID.digits(grantee.nationalID) {
            out.append("ผู้มอบและผู้รับมอบเป็นคนเดียวกัน")
        }
        if powers.prefix(5).contains(where: { $0 == nil }) { out.append("ทำเครื่องหมาย ✓ หรือ – ให้ครบข้อ 1–5") }
        if powers[5] == .yes && item6Ref.isBlank { out.append("ข้อ 6: ระบุเลขข้อ") }
        if powers[6] == .yes && item7Other.isBlank { out.append("ข้อ 7: ระบุอำนาจ") }
        if witness1.isBlank || witness2.isBlank { out.append("พยาน 2 คน") }
        return out
    }
}

// MARK: - แบบฟอร์มรับรองตนเอง (VSPP)

/// แบบฟอร์ม กฟภ. "แบบฟอร์มรับรองตนเองการติดตั้งอุปกรณ์และการเชื่อมต่อระบบผลิตไฟฟ้าจากพลังงานแสงอาทิตย์ (VSPP) พ.ศ. 2569",
/// with its attachments 1–10.
public struct SelfCertification: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, CaseIterable, Sendable {
        case single
        case multi
        public var title: String { self == .single ? "เฟสเดียว" : "มากกว่าหนึ่งเฟส" }
    }

    /// Attachment 2's three boxes.
    public enum ExportLimiter: String, Sendable {
        case singleOver7
        case multiOver10
        case notRequired
    }

    /// Attachment 6's three choices of overcurrent device.
    public static let overcurrentOptions = [
        "Circuit Breaker ประเภทที่มีฟังก์ชัน Overcurrent และ Ground Fault Protection",
        "เครื่องตัดไฟรั่ว (Residual Current Device, RCD) ประเภทที่มีฟังก์ชัน Overcurrent Protection",
        "Circuit Breaker ติดตั้งร่วมกับ RCD หรือรีเลย์ 50/51N",
    ]

    /// Attachment titles, as printed after `หัวข้อที่ n`.
    public static let attachments = [
        "สถานที่ติดตั้งระบบผลิตไฟฟ้า",
        "อุปกรณ์ควบคุมหรือป้องกันการจ่ายกระแสไหลย้อน (Export Limiting Device)",
        "แผงโฟโตโวลเตอิค (PV)",
        "อินเวอร์เตอร์ (Inverter)",
        "การตั้งค่าอินเวอร์เตอร์ (Inverter Setting)",
        "อุปกรณ์ป้องกันระบบผลิตไฟฟ้าจากพลังงานแสงอาทิตย์",
        "อุปกรณ์ AC Surge Protection Device (AC SPD)",
        "จุดเชื่อมต่อระบบผลิตไฟฟ้าจากพลังงานแสงอาทิตย์",
        "สำเนา กว. และหนังสือรับรองสภาวิศวกร ของวิศวกรที่ลงนาม",
        "สำเนาใบแจ้งค่าไฟฟ้าเดือนล่าสุด",
    ]
    public static let maxPhotos = 6

    public var producerName = ""
    /// The part after `PPIM1A6`.
    public var ppimSuffix = ""
    public var contractNo = ""
    public var contractDate = ""
    public var caNo = ""
    public var phone = ""
    public var email = ""
    public var address = ""
    public var pvKWp = ""
    public var inverterKW = ""
    public var sellKW = ""
    public var phase: Phase?
    public var latitude = ""
    public var longitude = ""
    /// 1…3 of `overcurrentOptions`.
    public var overcurrent: Int?
    public var engineerName = ""
    public var producerSignDate: Date?
    public var engineerSignDate: Date?
    /// Photo file names per attachment 1…10 (index 0 = attachment 1).
    public var photos: [[String]] = Array(repeating: [], count: 10)

    public init() {}

    static func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }

    /// The form's rule (item 2): a limiter only when the inverters exceed the power sold and
    /// one phase is over 7 kW or more than one phase is over 10 kW. Nil until the numbers and phase are in.
    public var exportLimiter: ExportLimiter? {
        guard let inv = Self.number(inverterKW), let sell = Self.number(sellKW), let phase else { return nil }
        if inv > sell && phase == .single && inv > 7 { return .singleOver7 }
        if inv > sell && phase == .multi && inv > 10 { return .multiOver10 }
        return .notRequired
    }

    /// Attachments that need photos (2 drops out when no limiter is needed).
    public var requiredAttachments: [Int] {
        (1...10).filter { $0 != 2 || exportLimiter != .notRequired }
    }

    public var coordinatesValid: Bool {
        guard let lat = Self.number(latitude), let lng = Self.number(longitude) else { return false }
        return (5...21).contains(lat) && (97...106).contains(lng)
    }

    public var values: [String: String] {
        var v: [String: String] = [
            "producer_name": producerName, "ppim_suffix": ppimSuffix, "contract_no": contractNo, "contract_date": contractDate,
            "ca_no": caNo, "phone": phone, "email": email, "address": address,
            "pv_kwp": pvKWp, "inverter_kw": inverterKW, "sell_kw": sellKW,
            "producer.print": producerName, "engineer.print": engineerName,
            "latlng": (latitude.isBlank && longitude.isBlank) ? "" : "\(latitude), \(longitude)",
        ]
        for (key, date) in [("producer", producerSignDate), ("engineer", engineerSignDate)] {
            guard let date else { continue }
            let p = PermitDate.parts(date)
            v["\(key).day"] = "\(p.day)"; v["\(key).month"] = "\(p.month)"; v["\(key).year"] = "\(p.year)"
        }
        return v
    }

    public var marks: [String: PermitMark] {
        var m: [String: PermitMark] = [:]
        switch exportLimiter {
        case .singleOver7: m["el_single"] = .yes
        case .multiOver10: m["el_multi"] = .yes
        case .notRequired: m["el_na"] = .yes
        case nil: break
        }
        if let overcurrent { m["ocd_\(overcurrent)"] = .yes }
        return m
    }

    public var issues: [String] {
        var out: [String] = []
        let need: [(String, String)] = [(producerName, "ชื่อผู้ผลิตไฟฟ้า"), (ppimSuffix, "เลขที่คำขอ PPIM"), (contractNo, "เลขที่สัญญา"),
                                        (contractDate, "วันที่สัญญา"), (caNo, "หมายเลขผู้ใช้ไฟฟ้า"), (phone, "เบอร์โทรศัพท์"),
                                        (email, "อีเมล"), (address, "สถานที่ติดตั้ง"), (pvKWp, "ขนาดแผง PV"),
                                        (inverterKW, "ขนาด Inverter"), (sellKW, "ปริมาณเสนอขาย")]
        out += need.filter { $0.0.isBlank }.map { $0.1 }
        if phase == nil { out.append("จำนวนเฟสที่เชื่อมต่อ") }
        if let sell = Self.number(sellKW), sell > 5 { out.append("ปริมาณเสนอขายเกิน 5 kW") }
        if !coordinatesValid { out.append("แนบ 1: พิกัด") }
        if overcurrent == nil { out.append("แนบ 6: เลือกอุปกรณ์ป้องกัน") }
        for n in requiredAttachments where photos[n - 1].isEmpty { out.append("แนบ \(n): ยังไม่มีรูป") }
        if engineerName.isBlank { out.append("ชื่อวิศวกร") }
        return out
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
