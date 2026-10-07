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

// MARK: - Photo layouts of an attachment page

/// How the photos of one attachment page are arranged in its area (the PEA sample pages use these).
public enum PhotoLayout: String, Codable, CaseIterable, Sendable {
    /// By the number of photos: 1 full, 2 stacked, 3 big top + 2, 4 a 2 × 2 grid, 5–6 a 2 × 3 grid.
    case auto
    case single
    case stack2
    case side2
    case stack3
    case top1bottom2
    case top2bottom1
    case grid4
    case grid6

    public var title: String {
        switch self {
        case .auto: "อัตโนมัติ"
        case .single: "1 รูปเต็มหน้า"
        case .stack2: "2 รูป บน–ล่าง"
        case .side2: "2 รูป ซ้าย–ขวา"
        case .stack3: "3 รูป เรียงลง"
        case .top1bottom2: "ใหญ่บน + 2 ล่าง"
        case .top2bottom1: "2 บน + ใหญ่ล่าง"
        case .grid4: "ตาราง 2 × 2"
        case .grid6: "ตาราง 2 × 3"
        }
    }

    /// Photos the layout places; more are left off the page.
    public var capacity: Int {
        switch self {
        case .auto, .grid6: 6
        case .single: 1
        case .stack2, .side2: 2
        case .stack3, .top1bottom2, .top2bottom1: 3
        case .grid4: 4
        }
    }

    /// The layout `auto` uses for `count` photos.
    public static func automatic(_ count: Int) -> PhotoLayout {
        switch count {
        case ...1: .single
        case 2: .stack2
        case 3: .top1bottom2
        case 4: .grid4
        default: .grid6
        }
    }

    public func resolved(_ count: Int) -> PhotoLayout { self == .auto ? Self.automatic(count) : self }

    /// Cells as fractions of the area, [x, y, w, h], in photo order (left to right, top to bottom).
    public var unitCells: [[Double]] {
        switch self {
        case .auto: Self.automatic(6).unitCells
        case .single: [[0, 0, 1, 1]]
        case .stack2: [[0, 0, 1, 0.5], [0, 0.5, 1, 0.5]]
        case .side2: [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]]
        case .stack3: (0..<3).map { [0, Double($0) / 3, 1, 1.0 / 3] }
        case .top1bottom2: [[0, 0, 1, 0.55], [0, 0.55, 0.5, 0.45], [0.5, 0.55, 0.5, 0.45]]
        case .top2bottom1: [[0, 0, 0.5, 0.45], [0.5, 0, 0.5, 0.45], [0, 0.45, 1, 0.55]]
        case .grid4: (0..<4).map { [Double($0 % 2) / 2, Double($0 / 2) / 2, 0.5, 0.5] }
        case .grid6: (0..<6).map { [Double($0 % 2) / 2, Double($0 / 2) / 3, 0.5, 1.0 / 3] }
        }
    }

    /// Cells in page points inside `area` ([x, y, w, h]), `gap` apart, for `count` photos (at most `capacity`).
    public func cells(in area: [Double], count: Int, gap: Double = 8) -> [[Double]] {
        let layout = resolved(count)
        return layout.unitCells.prefix(min(count, layout.capacity)).map { u in
            // a cell keeps half a gap from each inner edge, none at the area's edges
            let x0 = area[0] + u[0] * area[2] + (u[0] > 0 ? gap / 2 : 0)
            let y0 = area[1] + u[1] * area[3] + (u[1] > 0 ? gap / 2 : 0)
            let x1 = area[0] + (u[0] + u[2]) * area[2] - (u[0] + u[2] < 0.999 ? gap / 2 : 0)
            let y1 = area[1] + (u[1] + u[3]) * area[3] - (u[1] + u[3] < 0.999 ? gap / 2 : 0)
            return [x0, y0, x1 - x0, y1 - y0]
        }
    }
}

// MARK: - One photo on an attachment page

/// How one attachment photo is shown: its caption, crop, turn and red marks.
public struct AttachmentPhotoInfo: Codable, Equatable, Sendable {
    public enum Fit: String, Codable, CaseIterable, Sendable {
        /// Fills its cell, cropped to the cell's shape (site and equipment photos).
        case fill
        /// Whole photo inside its cell (documents: กว., bills).
        case fit
        public var title: String { self == .fill ? "เต็มกรอบ" : "ทั้งภาพ" }
    }

    public var caption = ""
    /// Nil = the attachment's default (`SelfCertification.defaultFit`).
    public var fit: Fit?
    /// Clockwise quarter turns, 0…3.
    public var quarterTurns = 0
    /// Red boxes pointing at what PEA checks (S/N, settings, ratings): [x, y, w, h] as fractions of the turned photo.
    public var highlights: [[Double]] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        fit = try c.decodeIfPresent(Fit.self, forKey: .fit)
        quarterTurns = try c.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0
        highlights = try c.decodeIfPresent([[Double]].self, forKey: .highlights) ?? []
    }
    private enum CodingKeys: String, CodingKey { case caption, fit, quarterTurns, highlights }
}

/// Geometry of a photo cell: the picture above a caption line, and where the picture is drawn.
public enum PhotoFrame {
    /// Caption line under each picture (pt).
    public static let captionHeight = 14.0
    /// Caption text size (pt): a step under the form's 16 pt TH Sarabun body, like a figure caption.
    public static let captionFontSize = 9.5

    /// The picture's box in `cell` ([x, y, w, h]), leaving the caption line when `caption` is on.
    public static func pictureBox(cell: [Double], caption: Bool) -> [Double] {
        caption ? [cell[0], cell[1], cell[2], max(cell[3] - captionHeight, 1)] : cell
    }

    /// The caption line under the picture box.
    public static func captionBox(cell: [Double]) -> [Double] {
        [cell[0], cell[1] + cell[3] - captionHeight, cell[2], captionHeight]
    }

    /// Where an image of `size` ([w, h]) is drawn for `fit` in `box`, centred. `fill` covers the box and
    /// overflows it (clip to the box); `fit` sits inside it.
    public static func placement(size: [Double], in box: [Double], fit: AttachmentPhotoInfo.Fit) -> [Double] {
        guard size[0] > 0, size[1] > 0 else { return box }
        let sx = box[2] / size[0], sy = box[3] / size[1]
        let s = fit == .fill ? max(sx, sy) : min(sx, sy)
        let w = size[0] * s, h = size[1] * s
        return [box[0] + (box[2] - w) / 2, box[1] + (box[3] - h) / 2, w, h]
    }

    /// A highlight ([x, y, w, h] fractions of the photo) on the page, for a photo drawn at `drawn`.
    public static func highlight(_ h: [Double], drawn: [Double]) -> [Double] {
        [drawn[0] + h[0] * drawn[2], drawn[1] + h[1] * drawn[3], h[2] * drawn[2], h[3] * drawn[3]]
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
    /// Photos kept per attachment (the largest layout prints 6).
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
    /// Layout per attachment 1…10 (index 0 = attachment 1).
    public var layouts: [PhotoLayout] = Array(repeating: .auto, count: 10)
    /// Caption, crop, turn and marks per photo file name.
    public var photoInfo: [String: AttachmentPhotoInfo] = [:]
    /// Caption lines under the photos, per attachment.
    public var showCaptions: [Bool] = Array(repeating: true, count: 10)

    /// Documents (9 กว., 10 bill) show whole; site and equipment photos fill their cells.
    public static func defaultFit(_ attachment: Int) -> AttachmentPhotoInfo.Fit { attachment >= 9 ? .fit : .fill }

    /// Caption ideas per attachment, from what the PEA sample pages show.
    public static let captionSuggestions: [[String]] = [
        ["ภาพหน้าบ้าน", "ภาพมุมสูงหลังคา", "ภาพแผนที่ตำแหน่งติดตั้ง", "ภาพแผงบนหลังคา"],
        ["ตู้ควบคุมกันย้อน", "Export Limiter", "CT ตรวจวัด", "ค่าตั้งจำกัดการส่งออก"],
        ["แผงบนหลังคา", "ป้ายแผง (Nameplate)", "จำนวนแผง"],
        ["อินเวอร์เตอร์", "ป้ายอินเวอร์เตอร์ (Nameplate)", "S/N อินเวอร์เตอร์"],
        ["Grid code", "ค่าป้องกัน (Protection)", "S/N ในแอป", "ค่าตั้งเครื่องที่ 2"],
        ["ตู้ AC", "อุปกรณ์ป้องกัน (RCBO/RCD)", "ป้ายพิกัดอุปกรณ์"],
        ["AC SPD", "ป้ายพิกัด SPD"],
        ["จุดเชื่อมต่อใต้เบรกเกอร์ประธาน", "ตู้ MDB", "สายเชื่อมต่อ"],
        ["บัตร กว.", "หนังสือรับรองสภาวิศวกร"],
        ["ใบแจ้งค่าไฟฟ้า"],
    ]

    public func info(_ file: String) -> AttachmentPhotoInfo { photoInfo[file] ?? AttachmentPhotoInfo() }

    public func fit(_ file: String, attachment: Int) -> AttachmentPhotoInfo.Fit { info(file).fit ?? Self.defaultFit(attachment) }

    public func captionsOn(_ attachment: Int) -> Bool { showCaptions.indices.contains(attachment - 1) ? showCaptions[attachment - 1] : true }

    /// `รูปที่ 4.2 ป้ายอินเวอร์เตอร์ (Nameplate)` — numbered by attachment and place on the page.
    public func caption(attachment: Int, index: Int) -> String {
        let list = photos[attachment - 1]
        let text = list.indices.contains(index) ? info(list[index]).caption.trimmingCharacters(in: .whitespaces) : ""
        return "รูปที่ \(attachment).\(index + 1)" + (text.isEmpty ? "" : " " + text)
    }

    public init() {}

    public func layout(_ attachment: Int) -> PhotoLayout { layouts.indices.contains(attachment - 1) ? layouts[attachment - 1] : .auto }

    /// Photos that land on the page, in order; the rest are kept but not printed.
    public func printedPhotos(_ attachment: Int) -> [String] {
        let list = photos[attachment - 1]
        return Array(list.prefix(layout(attachment).resolved(list.count).capacity))
    }

    /// Moves a photo one place earlier (`by: -1`) or later (`by: 1`) on its page.
    public mutating func movePhoto(attachment: Int, from index: Int, by step: Int) {
        let i = attachment - 1, j = index + step
        guard photos[i].indices.contains(index), photos[i].indices.contains(j) else { return }
        photos[i].swapAt(index, j)
    }

    private enum CodingKeys: String, CodingKey {
        case producerName, ppimSuffix, contractNo, contractDate, caNo, phone, email, address, pvKWp, inverterKW, sellKW,
             phase, latitude, longitude, overcurrent, engineerName, producerSignDate, engineerSignDate, photos, layouts,
             photoInfo, showCaptions
    }

    /// Every key is optional so forms saved by older builds still open.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ k: CodingKeys) throws -> String { try c.decodeIfPresent(String.self, forKey: k) ?? "" }
        producerName = try text(.producerName); ppimSuffix = try text(.ppimSuffix)
        contractNo = try text(.contractNo); contractDate = try text(.contractDate)
        caNo = try text(.caNo); phone = try text(.phone); email = try text(.email); address = try text(.address)
        pvKWp = try text(.pvKWp); inverterKW = try text(.inverterKW); sellKW = try text(.sellKW)
        phase = try c.decodeIfPresent(Phase.self, forKey: .phase)
        latitude = try text(.latitude); longitude = try text(.longitude)
        overcurrent = try c.decodeIfPresent(Int.self, forKey: .overcurrent)
        engineerName = try text(.engineerName)
        producerSignDate = try c.decodeIfPresent(Date.self, forKey: .producerSignDate)
        engineerSignDate = try c.decodeIfPresent(Date.self, forKey: .engineerSignDate)
        let saved = try c.decodeIfPresent([[String]].self, forKey: .photos) ?? []
        photos = (0..<10).map { saved.indices.contains($0) ? saved[$0] : [] }
        let savedLayouts = try c.decodeIfPresent([PhotoLayout].self, forKey: .layouts) ?? []
        layouts = (0..<10).map { savedLayouts.indices.contains($0) ? savedLayouts[$0] : .auto }
        photoInfo = try c.decodeIfPresent([String: AttachmentPhotoInfo].self, forKey: .photoInfo) ?? [:]
        let savedCaptions = try c.decodeIfPresent([Bool].self, forKey: .showCaptions) ?? []
        showCaptions = (0..<10).map { savedCaptions.indices.contains($0) ? savedCaptions[$0] : true }
    }

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
