import Foundation

public enum FieldKind: Sendable {
    case text(placeholder: String = "")
    /// Roof-structure member "size @spacing" with pick lists (component 1…7); stored as text.
    case member(component: Int)
    /// Text with a pick list (C2 sizes in cm, spacing in cm); typing is still allowed.
    case pick(list: PickList, unit: String)
    case number(unit: String)
    case textarea
    case choice([String], other: Bool = false)
    case checks([String])
    case photo
    case photos(max: Int)
    case signature
    case obstacles
    case transformers
    /// Symbols placed on the photo of another field (PEA meter, transformer, MDB …).
    case marks(photoField: String)
    /// Dimensioned plan drawn from the spans and obstacles of the same section.
    case plan(tank: Bool)
    /// Roof-frame diagram with components 1–7.
    case diagram
    case note(String)
}

public enum PickList: String, Sendable {
    case roofSizeCm, spacingCm
    public var groups: [(group: String, items: [String])] {
        switch self {
        case .roofSizeCm: return StructureSizes.sectionsCm
        case .spacingCm: return [("ระยะห่าง (ซม.)", StructureSizes.spacingsCm)]
        }
    }
}

public struct FieldSpec: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let kind: FieldKind
    public let optional: Bool
    public let visibleWhen: (@Sendable (Values) -> Bool)?
    public init(_ id: String, _ label: String, _ kind: FieldKind, optional: Bool = false, when: (@Sendable (Values) -> Bool)? = nil) {
        self.id = id; self.label = label; self.kind = kind; self.optional = optional; self.visibleWhen = when
    }
    public func isVisible(_ v: Values) -> Bool { visibleWhen?(v) ?? true }
    /// Counted in the progress of a section.
    public var countable: Bool {
        switch kind { case .plan, .diagram, .note: return false; default: return true }
    }
    public func isFilled(_ v: Values) -> Bool {
        guard let val = v[id] else { return false }
        switch val {
        case .text(let s): return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .choice(let s, _): return !s.isEmpty
        case .multi(let a): return !a.isEmpty
        case .photo: return true
        case .photos(let a): return !a.isEmpty
        case .obstacles(let a): return !a.isEmpty
        case .transformers(let a): return a.contains { !$0.kva.trimmingCharacters(in: .whitespaces).isEmpty }
        case .marks(let a): return !a.isEmpty
        case .shapes(let a): return !a.isEmpty
        }
    }
    /// Required for completeness: counted, not optional, and currently shown.
    public func isRequired(_ v: Values) -> Bool { countable && !optional && isVisible(v) }
}

public struct GroupSpec: Identifiable, Sendable {
    public let no: String?
    public let title: String?
    public let fields: [FieldSpec]
    public var id: String { (no ?? "") + "|" + (title ?? "") + "|" + (fields.first?.id ?? "") }
    public init(no: String? = nil, _ title: String? = nil, _ fields: [FieldSpec]) { self.no = no; self.title = title; self.fields = fields }
}

public struct ModuleSpec: Sendable {
    public let type: ModuleType
    /// Name of the workbook sheet this section fills.
    public let sheet: String
    public let label: String
    public let short: String
    /// Title printed on the form / report box.
    public let reportTitle: String
    public let namePlaceholder: String
    public let groups: [GroupSpec]
    public var fields: [FieldSpec] { groups.flatMap(\.fields) }
    /// Section code in the app: B1…B5 electrical, C1…C3 roof & structure, D1…D2 water works.
    public var code: String { type.code }
    public var category: SectionCategory { type.category }
}

/// How sections are grouped and numbered in the app (Excel sheets and the PDF keep the company form's titles).
public enum SectionCategory: String, CaseIterable, Identifiable, Sendable {
    case general = "A", electrical = "B", roof = "C", water = "D", summary = "E"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .general: return "ข้อมูลทั่วไป"
        case .electrical: return "ระบบไฟฟ้า"
        case .roof: return "หลังคาและโครงสร้าง"
        case .water: return "งานระบบน้ำ"
        case .summary: return "สรุปผลและลงนาม"
        }
    }
    /// "B  ระบบไฟฟ้า"
    public var heading: String { rawValue + "  " + title }
}

public extension ModuleType {
    var code: String {
        switch self {
        case .panel: return "B1"
        case .inverter: return "B2"
        case .water: return "B3"
        case .backfeed: return "B4"
        case .fts: return "B5"
        case .roof: return "C1"
        case .roofForm: return "C2"
        case .house: return "C3"
        case .tank: return "D1"
        case .sed: return "D2"
        }
    }
    var category: SectionCategory { SectionCategory(rawValue: String(code.prefix(1))) ?? .general }
    /// All section types in code order.
    static var byCode: [ModuleType] { allCases.sorted { $0.code < $1.code } }
}

// MARK: - option lists (as printed on the forms)

public enum Options {
    public static let list = ["ตำแหน่งติดตั้งแผง", "ตำแหน่งติดตั้งห้องอินเวอร์เตอร์", "ตำแหน่งติดตั้ง Site Office", "ตำแหน่งติดตั้งกันย้อน", "ตำแหน่งติดตั้งบันได",
                              "แนวรางและสายไฟ AC/DC (Underground/Pipe Rack)", "ตำแหน่งติดตั้งตู้ SMDB ในห้อง MDB", "ตำแหน่งมิเตอร์ PEA", "ตำแหน่งหม้อแปลง", "รูปถ่ายป้ายหน้าโครงการ",
                              "GPS สถานี", "ที่อยู่สถานี", "ประเภทที่ดิน"]
    /// Who owns the station's land (A2 LIST "ประเภทที่ดิน").
    public static let landType = ["ที่ดิน กปภ.", "ที่ราชพัสดุ", "ที่สาธารณประโยชน์", "ที่ดินเช่า", "อื่นๆ"]
    public static let roofShape = ["หลังคาทรงจั่ว", "หลังคาทรงปั้นหยา", "หลังคาคอนกรีต (ดาดฟ้า)", "หลังคาทรงโค้ง", "หลังคาเพิงหมาแหงน", "อื่นๆ"]
    public static let roofMaterial = ["กระเบื้องซีแพค", "กระเบื้องลอนคู่/เดี่ยว", "เมทัลชีท", "คอนกรีตเสริมเหล็ก", "อื่นๆ"]
    public static let facing = ["เหนือ", "ใต้", "ตะวันออก", "ตะวันตก", "ตะวันตกเฉียงใต้", "ตะวันออกเฉียงเหนือ", "อื่นๆ"]
    public static let components = ["แป", "จันทัน", "อเส", "ขื่อ", "ค้ำยัน", "เชิงชาย", "ดั้ง"]
    public static let structure = ["ไม้", "โครงเหล็ก"]
    public static let structMaterial = ["โครงสร้างไม้", "โครงสร้างเหล็ก"]
    public static let yesNo = ["มี", "ไม่มี"]
    public static let noYes = ["ไม่มี", "มี"]
    public static let sedDims: [(String, String)] = [("A", "ความยาวบ่อ"), ("B", "ความกว้างบ่อ"), ("C", "ความกว้างของทางเดิน"), ("D", "ความกว้างของขอบบ่อ"),
        ("E", "ความกว้างของช่องย่อย"), ("F", "ความยาวบ่อน้ำวน"), ("G", "ความยาวของช่องย่อย 1"), ("H", "ความยาวของช่องย่อย 2"),
        ("I", "ความยาวของช่องย่อย 3"), ("J", "ความกว้างบันไดทางเดิน"), ("K", "ความสูงราวกันตก")]
    public static let verdict = ["ติดตั้งได้", "ติดตั้งได้ (มีเงื่อนไข)", "ไม่แนะนำให้ติดตั้ง"]
}

// MARK: - the schema

public enum Schema {
    private static func P(_ id: String, _ l: String, optional: Bool = false) -> FieldSpec { FieldSpec(id, l, .photo, optional: optional) }
    private static func N(_ id: String, _ l: String, _ u: String, optional: Bool = false, when: (@Sendable (Values) -> Bool)? = nil) -> FieldSpec { FieldSpec(id, l, .number(unit: u), optional: optional, when: when) }
    private static func T(_ id: String, _ l: String, _ ph: String = "", optional: Bool = false, when: (@Sendable (Values) -> Bool)? = nil) -> FieldSpec { FieldSpec(id, l, .text(placeholder: ph), optional: optional, when: when) }
    private static func C(_ id: String, _ l: String, _ o: [String], other: Bool = false, optional: Bool = false, when: (@Sendable (Values) -> Bool)? = nil) -> FieldSpec { FieldSpec(id, l, .choice(o, other: other), optional: optional, when: when) }
    private static func detail() -> FieldSpec { FieldSpec("detail", "รายละเอียดเพิ่มเติม", .textarea, optional: true) }
    @Sendable private static func isWood(_ v: Values) -> Bool { v.choice("structMaterial") == "โครงสร้างไม้" }
    @Sendable private static func isSteel(_ v: Values) -> Bool { v.choice("structMaterial") == "โครงสร้างเหล็ก" }

    // job-level pages
    public static let info = GroupSpec("ข้อมูลโครงการ", [
        T("docNo", "เลขที่", "215"), FieldSpec("date", "วันที่", .text()), T("engineer", "วิศวกรผู้สำรวจงาน"), T("rev", "REV.", "00", optional: true),
        T("projectName", "ชื่อโครงการ / สถานี"), T("coordinator", "ชื่อผู้ประสานงาน"), T("phone", "เบอร์โทร"),
        T("address", "ที่อยู่สถานี / สถานที่ติดตั้ง"), T("officeAddress", "ที่อยู่สำนักงาน/สาขา", optional: true),
        T("gps", "**พิกัดดาวเทียม Google Map", "17.0062, 99.8235"), C("internet", "สัญญาณอินเตอร์เน็ต", Options.yesNo),
        N("capacity", "ขนาดที่ต้องการติดตั้ง / กำลังการผลิตติดตั้ง", "kWp")])
    public static let site = GroupSpec("ภาพสถานที่ติดตั้ง", [
        P("siteMap", "ภาพสถานที่ติดตั้ง (โดรน/ดาวเทียม ระบุตำแหน่งแผง อินเวอร์เตอร์ MDB มิเตอร์ หม้อแปลง)"),
        FieldSpec("siteMarks", "สัญลักษณ์บนภาพ — PEA METER, TRANSFORMER, MDB, INVERTER STATION, WATER CONNECTION POINT, SITE OFFICE", .marks(photoField: "siteMap"), optional: true),
        C("north", "ทิศเหนือของภาพอยู่", ["ด้านบน", "ด้านขวา", "ด้านล่าง", "ด้านซ้าย"]),
        FieldSpec("siteList", "LIST — รายการที่ระบุในภาพ", .checks(Options.list), optional: true),
        // added with the A2 card page; optional, so A2's completion counts as before
        P("projectSignPhoto", "รูปถ่ายป้ายหน้าโครงการ", optional: true),
        C("landType", "ประเภทที่ดิน", Options.landType, optional: true),
        FieldSpec("siteNote", "หมายเหตุหน้างาน", .textarea, optional: true),
        // A2 v2 building models (`SiteModels`): optional and not shown on the form page, so completion counts as before
        T(SiteModels.key, "โมเดลอาคารบนภาพ", optional: true, when: { _ in false }),
        T(SiteModels.lockKey, "ล็อกโมเดลอาคารทั้งหมด", optional: true, when: { _ in false })])
    /// Photos every transformer must have (all sides, nameplate, wide view) — keys "tr0_front" … as in the web version.
    public static let transformerAngles: [(key: String, label: String)] = [
        ("front", "ด้านหน้า"), ("back", "ด้านหลัง"), ("left", "ด้านซ้าย"), ("right", "ด้านขวา"),
        ("plate", "ป้ายพิกัด (Nameplate)"), ("wide", "มุมกว้าง / ตำแหน่งติดตั้ง")]
    public static func transformerPresent(_ v: Values, _ i: Int) -> Bool {
        guard let t = v.transformers("trafos")[safe: i] else { return false }
        return !t.kva.trimmingCharacters(in: .whitespaces).isEmpty || t.mdb.contains { !$0.isEmpty }
    }
    /// Per-transformer fields: 6 required photos, the MDB it feeds (required) and where that MDB is.
    public static let transformerFields: [FieldSpec] = (0..<5).flatMap { i -> [FieldSpec] in
        let on: @Sendable (Values) -> Bool = { transformerPresent($0, i) }
        return transformerAngles.map { FieldSpec("tr\(i)_\($0.key)", "TR\(i + 1) ภาพ\($0.label)", .photo, when: on) }
            + [FieldSpec("tr\(i)_feed", "TR\(i + 1) ตู้ MDB ปลายสาย", .text(placeholder: "MDB1"), when: on),
               FieldSpec("tr\(i)_feedLoc", "TR\(i + 1) ตำแหน่งตู้ MDB ปลายสาย", .text(placeholder: "เช่น ห้องไฟฟ้า อาคารสูบน้ำ"), optional: true, when: on),
               FieldSpec("tr\(i)_feedPhoto", "TR\(i + 1) ภาพตู้ MDB ปลายสาย", .photo, optional: true, when: on),
               // A3 wide page: the other main-board photos. Only the solar-CB space is required, as on the design.
               FieldSpec("tr\(i)_mdbOpen", "TR\(i + 1) ภาพเปิดตู้ MDB ภายใน", .photo, optional: true, when: on),
               FieldSpec("tr\(i)_mdbBreaker", "TR\(i + 1) ภาพเมนเบรกเกอร์ MDB", .photo, optional: true, when: on),
               FieldSpec("tr\(i)_mdbSpace", "TR\(i + 1) ภาพที่ว่างติดตั้ง CB โซลาร์", .photo, when: on)]
    }
    public static let electrical = GroupSpec("มิเตอร์ / หม้อแปลง / ตู้ MDB", [
        T("meterNo", "หมายเลขมิเตอร์ไฟฟ้า"), FieldSpec("trafos", "หม้อแปลงไฟฟ้าและตู้ MDB (สูงสุด 5 × 6)", .transformers)] + transformerFields
        // A3 wide page: meter details, all optional (caNo / userType / meterPhoto of the C3 form live in that section's answers, so these are separate)
        + [C("meterKV", "แรงดันที่รับไฟ (kV)", meterKV, optional: true), C("meterPhase", "ระบบไฟ", meterPhases, optional: true),
           T("meterCA", "เลขผู้ใช้ไฟ (CA)", optional: true), T("meterRate", "ประเภทผู้ใช้ไฟ / อัตรา", optional: true),
           T("meterCT", "ขนาดมิเตอร์ / CT (A)", "400/5", optional: true), P("meterPic", "ภาพมิเตอร์", optional: true)])
    public static let meterKV = ["0.4", "22", "33"]
    public static let meterPhases = ["1 เฟส", "3 เฟส"]
    /// A4 flood history — sets how high inverters, SMDB/backfeed boxes and cable routes must be mounted.
    public static let tankTypes = ["ค.ส.ล.", "เหล็ก", "FRP", "อื่นๆ"]
    public static let tankPositions = ["บนดิน", "ฝังดิน", "กึ่งฝัง"]
    public static let shadeSources = ["ต้นไม้", "อาคาร", "หอถังสูง", "อื่นๆ"]
    public static let shadeDirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    /// D1 shading — only asks what/which side when something does shade the tank.
    @Sendable public static func shaded(_ v: Values) -> Bool { v.choice("shade") == "มี" }
    /// "ชนิด ค.ส.ล. · บนดิน" — nil when neither is filled.
    public static func tankKind(_ v: Values) -> String? {
        let t = v.choice("tankType").map { $0 == "อื่นๆ" ? v.other("tankType") : $0 } ?? "", p = v.choice("tankPos") ?? ""
        let parts = [t.isEmpty ? "" : "ถัง " + t, p].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    /// "เงาบัง: ต้นไม้, อาคาร ทิศ S, SW (สูง ~8 ม.)" / "ไม่มีเงาบัง" / nil when not answered.
    public static func shadeText(_ v: Values) -> String? {
        switch v.choice("shade") {
        case "ไม่มี"?: return "ไม่มีเงาบัง"
        case "มี"?:
            let from = v.multi("shadeFrom").joined(separator: ", "), dir = v.multi("shadeDir").joined(separator: ", ")
            let note = v.text("shadeNote").trimmingCharacters(in: .whitespaces)
            return "เงาบัง" + (from.isEmpty ? "" : ": " + from) + (dir.isEmpty ? "" : " ทิศ " + dir) + (note.isEmpty ? "" : " (\(note))")
        default: return nil
        }
    }
    @Sendable public static func flooded(_ v: Values) -> Bool { v.choice("floodHistory") == "เคย" }
    public static let floodRefs = ["ดินเดิม", "พื้นถนน", "พื้นห้อง MDB"]
    public static let floodInfoSources = ["เจ้าหน้าที่", "คราบน้ำ"]
    public static let floodSources = ["ฝนตกหนัก / ระบายน้ำไม่ทัน", "แม่น้ำ / คลองล้นตลิ่ง", "น้ำทะเลหนุน", "น้ำป่า / น้ำหลาก", "อื่นๆ"]
    public static let floodHits = ["ห้อง MDB / ตู้ไฟฟ้า", "หม้อแปลง", "ห้องเครื่องสูบน้ำ", "อาคาร / พื้นที่ติดตั้งอินเวอร์เตอร์", "ถนนทางเข้า"]
    public static let flood = GroupSpec("ประวัติน้ำท่วม", [
        C("floodHistory", "พื้นที่เคยมีน้ำท่วมหรือไม่", ["ไม่เคย", "เคย", "ไม่ทราบ"]),
        T("floodYear", "ปีที่ท่วมล่าสุด (พ.ศ.)", "เช่น 2554", when: flooded),
        N("floodDepth", "ระดับน้ำสูงสุดจากพื้นดิน", "ซม.", when: flooded),
        N("floodDays", "ระยะเวลาน้ำท่วมขัง", "วัน", optional: true, when: flooded),
        C("floodFreq", "ความถี่", ["ทุกปี", "2–5 ปีครั้ง", "นานกว่า 5 ปี"], optional: true, when: flooded),
        C("floodSource", "สาเหตุ", floodSources, other: true, optional: true, when: flooded),
        FieldSpec("floodHit", "จุดที่เคยได้รับผลกระทบ", .checks(floodHits), optional: true, when: flooded),
        FieldSpec("floodPhoto", "ภาพคราบระดับน้ำ / หลักฐานน้ำท่วม", .photo, optional: true, when: flooded),
        // A4 wide page: everything below is optional, so jobs saved before it decode and count as before.
        C("floodRef", "วัดความสูงจาก", floodRefs, optional: true, when: flooded),
        C("floodInfoSource", "ที่มาข้อมูล", floodInfoSources, optional: true, when: flooded),
        // evidence photos after the first (`floodPhoto` stays the first, so old jobs and the PDF still work)
        FieldSpec("floodPhotos", "ภาพหลักฐานน้ำท่วมเพิ่มเติม", .photos(max: 12), optional: true, when: flooded),
        // the stored GISTDA lookup (JSON); shown by the wide page and the PDF, never as a form row
        FieldSpec("floodGistda", "ข้อมูลน้ำท่วมจาก GISTDA", .text(placeholder: ""), optional: true, when: { _ in false }),
        N("invFloorCm", "ความสูงพื้นห้อง Inverter จากพื้นดิน", "ซม.", optional: true, when: flooded),
        N("invMountCm", "ความสูงติดตั้ง Inverter / SMDB จากพื้นห้อง", "ซม.", optional: true, when: flooded),
        N("emgMountCm", "ความสูงติดตั้งปุ่ม Emergency", "ซม.", optional: true, when: flooded),
        N("equipHeight", "ระดับติดตั้งอุปกรณ์ที่แนะนำ (สูงจากพื้นดิน)", "ซม.", optional: true, when: flooded),
        FieldSpec("floodNote", "หมายเหตุ", .textarea, optional: true)])
    /// Water level + 50 cm, rounded up to 10 cm — for a flood the surveyor reported, or a GISTDA estimate (`FloodCheck.level`).
    /// nil when there is no water level.
    public static func recommendedEquipHeight(_ v: Values) -> Int? {
        FloodCheck.level(v) > 0 ? FloodCheck.minCm(v) : nil
    }
    public static let final = GroupSpec("สรุปผลการสำรวจและลงนาม", [
        C("verdict", "ผลการประเมินความเหมาะสมในการติดตั้ง", Options.verdict),
        FieldSpec("remarks", "ความเห็น / เงื่อนไข / สิ่งที่ต้องแก้ไขก่อนติดตั้ง", .textarea, optional: true),
        FieldSpec("surveyorSign", "ลายเซ็นวิศวกรผู้สำรวจ", .signature), T("reviewer", "ผู้ตรวจสอบ", optional: true),
        T("customerName", "ชื่อผู้ประสานงาน / เจ้าของสถานที่"), FieldSpec("customerSign", "ลายเซ็นผู้ประสานงาน / เจ้าของสถานที่", .signature)])
    public static let jobGroups = [info, site, electrical, flood, final]

    private static func planFields(tank: Bool) -> [FieldSpec] {
        [N("panelsBefore", "จำนวนแผงก่อนเข้าสำรวจ", "แผง"), N("panelsCut", "จำนวนแผงที่ตัดออกหลังสำรวจ", "แผง", optional: true),
         T("spansX", "ระยะช่วงเสาแนวนอน (ม. คั่นด้วย ,)", tank ? "4,4,4,4" : "1.5,4,4,4,4,1.5"),
         T("spansY", "ระยะช่วงเสาแนวตั้ง (ม. คั่นด้วย ,)", tank ? "4,4,4,4" : "1.5,4.5,4,4.5,1.5")]
        + (tank ? [] : [C("sheetDir", "แนวลอนหลังคาในแปลน", ["แนวนอน", "แนวตั้ง"], optional: true)])
        + [FieldSpec("obst", tank ? "สิ่งกีดขวางบนถัง (ปล่องระบาย ช่องเซอร์วิส ท่อ เสาสัญญาณ)" : "สิ่งกีดขวางบนหลังคา", .obstacles, optional: true),
           FieldSpec("plan", "แปลน", .plan(tank: tank)), P("planPhoto", "แบบร่างที่วาดเอง (ใช้แทนแปลนอัตโนมัติ)", optional: true)]
    }

    public static let modules: [ModuleType: ModuleSpec] = [
        .panel: ModuleSpec(type: .panel, sheet: "ระบบไฟฟ้า", label: "ตู้ไฟฟ้าอาคาร", short: "ตู้ไฟฟ้าอาคาร", reportTitle: "ภาพตู้ไฟฟ้าของอาคาร", namePlaceholder: "ชื่ออาคาร เช่น โรงสูบน้ำ", groups: [
            GroupSpec(nil, [P("photoBreaker", "ภาพถ่ายเบรกเกอร์เมนของตู้ไฟฟ้า"), P("photoWide", "ภาพถ่ายมุมกว้างของตู้ไฟฟ้า (เพื่อพิจารณาจุดเชื่อมต่อระบบโซล่าเซลล์)"),
                            N("breakerAT", "ขนาดเบรกเกอร์เมน", "AT"), N("loadKW", "ปริมาณการใช้ไฟ", "kW"), T("loadTime", "เวลา", "10 น."), detail()]
                            // B1 wide page (docs/ui/survey-b1): optional and not shown on the form page, so completion counts as before
                            + buildingPanelFields)]),
        .inverter: ModuleSpec(type: .inverter, sheet: "ระบบไฟฟ้า", label: "พื้นที่ติดตั้งอินเวอร์เตอร์", short: "พื้นที่ติดตั้งอินเวอร์เตอร์", reportTitle: "ภาพตำแหน่งติดตั้ง Inverter station", namePlaceholder: "ชื่ออาคาร (ถ้ามี)", groups: [
            GroupSpec(nil, [P("photoArea", "ภาพถ่ายพื้นที่ติดตั้ง Inverter Station"), P("photoDetail", "รายละเอียด (ภาพระบุขอบเขตพื้นที่)", optional: true),
                            T("sizeLWH", "ขนาดพื้นที่ติดตั้ง Inverter station (ก x ย x ส)", "6x2"), N("inverterCount", "จำนวนอินเวอร์เตอร์", "เครื่อง"),
                            FieldSpec("invNote", "", .note("**ขนาดพื้นที่ที่ต้องการในการติดตั้ง Inverter Station ยาว = (1.5 × จำนวนอินเวอร์เตอร์) + 1.5 เมตร กว้าง 2 เมตร")), detail()]
                            // B2 wide page (docs/ui/survey-b2): optional and not shown on the form page, so completion counts as before;
                            // the page keeps `sizeLWH` and `inverterCount` in step with them (`InverterStation`)
                            + inverterStationFields)]),
        .water: ModuleSpec(type: .water, sheet: "ระบบไฟฟ้า", label: "ระบบน้ำล้างแผง", short: "ระบบน้ำล้างแผง", reportTitle: "ภาพตำแหน่งระบบน้ำล้างแผง", namePlaceholder: "ชื่ออาคาร (ถ้ามี)", groups: [
            GroupSpec(nil, [P("photoArea", "ภาพถ่ายพื้นที่ติดตั้ง"), P("photoWide", "ภาพถ่ายมุมกว้างของพื้นที่ติดตั้ง"),
                            C("waterMode", "รูปแบบระบบน้ำ", ["ติดตั้งระบบน้ำใหม่", "ติดตั้งร่วมกับระบบน้ำเดิม"]), detail()])]),
        .backfeed: ModuleSpec(type: .backfeed, sheet: "ระบบไฟฟ้า", label: "ระบบกันย้อน", short: "ระบบกันย้อน", reportTitle: "ภาพตำแหน่งติดตั้งระบบกันย้อน", namePlaceholder: "ชื่ออาคาร (ถ้ามี)", groups: [
            GroupSpec(nil, [P("photoArea", "ภาพถ่ายพื้นที่ติดตั้ง"), P("photoDetail", "รายละเอียด (ภาพ)", optional: true),
                            C("level", "ตำแหน่งกันย้อน", ["กันย้อนที่แรงต่ำ", "กันย้อนที่แรงสูง"]),
                            C("pole", "เสา", ["เสาเดิม", "เสาใหม่"], when: { $0.choice("level") == "กันย้อนที่แรงสูง" }), detail()])]),
        .fts: ModuleSpec(type: .fts, sheet: "ระบบไฟฟ้า", label: "ตู้ FTS และปุ่มฉุกเฉิน", short: "ตู้ FTS และปุ่มฉุกเฉิน", reportTitle: "ภาพตำแหน่งติดตั้งตู้ FTS และปุ่ม Emergency", namePlaceholder: "ชื่ออาคาร (ถ้ามี)", groups: [
            // the owner no longer records the FTS cabinet's place (docs/ui/survey-b5): its photo stays for old jobs, Excel and
            // the PDF but is optional, so B5 needs only the Emergency button photo; `emgPlace` is B5 wide page's place text
            GroupSpec(nil, [P("photoFTS", "ภาพถ่ายพื้นที่ติดตั้งตู้ FTS", optional: true), P("photoEmg", "ภาพถ่ายพื้นที่ติดตั้งปุ่ม Emergency"),
                            T("emgPlace", "ตำแหน่งปุ่ม Emergency", optional: true, when: { _ in false })])]),
        .roof: ModuleSpec(type: .roof, sheet: "หลังคาทั่วไป R", label: "หลังคา (แปลนและโครงสร้าง)", short: "หลังคา", reportTitle: "หลังคาทั่วไป", namePlaceholder: "เช่น 1 โรงกรอง", groups: [
            GroupSpec("แปลนหลังคา", planFields(tank: false)),
            GroupSpec("โครงสร้าง", [FieldSpec("diag", "แนะนำองค์ประกอบของหลังคา", .diagram)] + Options.components.enumerated().map { FieldSpec("comp\($0.offset + 1)", "\($0.offset + 1). \($0.element)", .member(component: $0.offset + 1)) }
                                    // the C1 wide page's own answers (docs/ui/survey-c1, `Roof`); hidden, so completion is unchanged
                                    + [("frameType", "ชนิดโครงหลังคา"), ("ridgeDir", "แนวสันหลังคา"), ("trussBays", "ช่องโครงถักต่อข้าง"), ("postGrid", "เสาที่แก้ในแปลน"),
                                       ("pvOrientation", "แนวแผงในแปลนจัดแผง"), ("roofShots", "มุมภาพหลังคา"), ("eaveOverhang", "ชายคา (ม.)"), ("clearHeight", "ความสูงใต้ขื่อ (ม.)"),
                                       ("purlinSpacing", "ระยะแป (ม.)"), ("roofStd", "หลังคามาตรฐาน"), ("pvRows", "แถวต่อชุด"), ("pvPerTable", "แผงต่อชุด"),
                                       ("pvGap", "ระยะห่างระหว่างชุด (ม.)")]
                                        .map { T($0.0, $0.1, optional: true, when: { _ in false }) }),
            GroupSpec("รูปแบบหลังคา", [C("roofShape", "**1. รูปแบบหลังคา", Options.roofShape, other: true), C("roofMaterial", "**2. วัสดุมุงหลังคา", Options.roofMaterial, other: true),
                                     C("roofStructure", "**3. ชนิดโครงสร้างหลังคา", Options.structure)]),
            GroupSpec("ภาพถ่าย", [P("aerialPhoto", "ภาพมุมสูง / ภาพโดรน (ระบุตำแหน่งหลังคา)"), FieldSpec("generalPhotos", "ภาพหลังคาทั่วไป", .photos(max: 3), optional: true),
                                FieldSpec("structPhotos", "ภาพโครงสร้าง (ใต้หลังคา)", .photos(max: 4))])]),
        .tank: ModuleSpec(type: .tank, sheet: "บ่อน้ำใส", label: "ถังน้ำใส", short: "ถังน้ำใส", reportTitle: "ถังน้ำใส", namePlaceholder: "เช่น 1 (ใหม่)", groups: [
            GroupSpec("แปลนถัง", planFields(tank: true)),
            GroupSpec("ข้อมูลถัง", [C("tankType", "ชนิดถัง", tankTypes, other: true), C("tankPos", "ตำแหน่งถัง", tankPositions),
                                  N("tankHeight", "ความสูงของถังน้ำใส", "M"), T("surface", "ผิวของถังน้ำใส", "คอนกรีต"), N("soilDepth", "กรณีมีดินกลบ ชั้นดินลึก", "M", optional: true)]
                                  // the D1 wide page's own answers (docs/ui/survey-d1-size, `Tank`); hidden, so completion is unchanged
                                  + [N(Tank.Key.exposed, "ส่วนพ้นดิน", "M", optional: true, when: { _ in false })]
                                  + [(Tank.Key.azimuth, "ทิศของถัง"), (Tank.Key.azimuthAt, "เวลาวัดทิศของถัง"), (Tank.Key.azimuthSrc, "ที่มาทิศของถัง"),
                                     (Tank.Key.azimuthAcc, "ความแม่นยำทิศของถัง")].map { T($0.0, $0.1, optional: true, when: { _ in false }) }),
            GroupSpec("เงาบัง", [C("shade", "มีเงาบังพื้นที่ติดตั้งหรือไม่", ["ไม่มี", "มี"]),
                               FieldSpec("shadeFrom", "สิ่งที่บัง", .checks(shadeSources), when: shaded),
                               FieldSpec("shadeDir", "ทิศที่เงาบัง", .checks(shadeDirs), when: shaded),
                               T("shadeNote", "รายละเอียด (ระยะห่าง / ความสูงโดยประมาณ)", "เช่น ต้นไม้สูง ~8 ม. ห่าง 5 ม.", optional: true, when: shaded)]),
            GroupSpec("ภาพถ่าย", [FieldSpec("obstPhotos", "ภาพสิ่งกีดขวาง (ภาพแรกลงกรอบใหญ่ \"สำหรับวาดขนาดของสิ่งกีดขวาง\")", .photos(max: 5)),
                                P("aerialPhoto", "รูปมุมสูง / รูปโดรน"), FieldSpec("sidePhotos", "รูปข้างถัง (สำหรับทางเดินรางสายไฟ)", .photos(max: 3))])]),
        .sed: ModuleSpec(type: .sed, sheet: "บ่อตกตะกอน", label: "บ่อตกตะกอน", short: "บ่อตกตะกอน", reportTitle: "บ่อตกตะกอน", namePlaceholder: "เช่น บ่อ 1", groups: [
            GroupSpec("ภาพบ่อตกตะกอน (Google Earth/Google Map)", [FieldSpec("sitePhotos", "ภาพบ่อตกตะกอน", .photos(max: 6))]),
            GroupSpec("โครงสร้างบ่อตกตะกอน", [P("drawing", "*เขียนแบบบ่อพอสังเขป (ระบุจุด A–K)")] + Options.sedDims.map { N("dist\($0.0)", "\($0.0) — \($0.1)", "ซม.", optional: $0.0 > "F") }),
            GroupSpec("ภาพถ่าย", [P("aerialPhoto", "ภาพถ่ายมุมสูงของพื้นที่ติดตั้ง"), P("pFront", "ด้านหน้า"), P("pBack", "ด้านหลัง"), P("pLeft", "ด้านซ้าย"), P("pRight", "ด้านขวา"),
                                P("obstPhoto", "ภาพสิ่งกีดขวางหรือบริเวณที่ไม่สามารถติดตั้งระบบได้", optional: true)])]),
        .house: ModuleSpec(type: .house, sheet: "ระบบไฟฟ้า 2", label: "บ้าน / อาคารขนาดเล็ก", short: "บ้าน / อาคารขนาดเล็ก", reportTitle: "บ้าน/อาคาร", namePlaceholder: "ชื่ออาคาร (ถ้ามี)", groups: [
            GroupSpec(no: "1", "รูปแบบบ้าน/อาคาร", [C("buildingType", "ประเภท", ["คอนกรีตเสริมเหล็ก", "ไม้", "อื่นๆ"], other: true), N("floors", "บ้านสูง", "ชั้น"),
                                                 N("buildingWidth", "ความกว้าง", "ซม."), N("buildingLength", "ความยาว", "ซม.")]),
            GroupSpec(no: "2", "รูปแบบหลังคา", [C("roofShape", "รูปแบบหลังคา", Options.roofShape, other: true)]),
            GroupSpec(no: "3", "วัสดุมุงหลังคา", [C("roofMaterial", "วัสดุมุงหลังคา", Options.roofMaterial, other: true)]),
            GroupSpec(no: "4", "ชนิดโครงสร้างหลังคา", [C("roofStructure", "ชนิดโครงสร้าง", Options.structure)]),
            GroupSpec(no: "5", "พื้นที่หลังคาติดตั้งแผง", [N("panelAreaWidth", "กว้าง", "ซม."), N("panelAreaLength", "ยาว", "ซม.")]),
            GroupSpec(no: "6", "หันหน้าแผงที่จะติดตั้ง", [C("facing", "ทิศ", Options.facing, other: true)]),
            GroupSpec(no: "7", "สิ่งกีดขวางและอุปสรรคบนหลังคา", [C("obstacle", "มีหรือไม่", Options.noYes), T("obstacleDetail", "ได้แก่", when: { $0.choice("obstacle") == "มี" })]),
            GroupSpec(no: "8", "แบบก่อสร้างของบ้านที่จะติดตั้ง", [C("hasConstructionDrawing", "มีหรือไม่", Options.yesNo)]),
            GroupSpec(no: "9", "แบบระบบไฟฟ้าของบ้านที่ติดตั้ง", [C("hasElectricalDrawing", "มีหรือไม่", Options.yesNo)]),
            GroupSpec(no: "10", "ตู้ควบคุมไฟฟ้าหลัก", [N("mainBreaker", "ตู้ควบคุมไฟฟ้าขนาดเมนเบรกเกอร์", "แอมป์"), C("hasCutout", "คัทเอาท์/สะพานไฟ", Options.yesNo)]),
            GroupSpec(no: "11", "ระบบไฟฟ้าแบบ", [N("busbarAmp", "Busbar", "A"), N("spareAmp", "Spare", "A"), N("spaceSlots", "Space", "ช่อง")]),
            GroupSpec(no: "12", "ระบบกราวด์หลักดิน", [C("hasGround", "มีหรือไม่", Options.yesNo), N("groundValue", "ค่ากราวด์เดิม", "โอห์ม", when: { $0.choice("hasGround") == "มี" })]),
            GroupSpec(no: "13", "องค์ประกอบของหลังคาและการวัด", [
                P("purlinPhotoF", "ภาพถ่ายการวัดแป — ด้านกว้าง f"), P("purlinPhotoG", "ภาพถ่ายการวัดแป — ด้านยาว g"), P("purlinPhotoS", "ภาพถ่ายระยะห่างแป"),
                P("rafterPhotoF", "ภาพถ่ายการวัดจันทัน — ด้านกว้าง f"), P("rafterPhotoG", "ภาพถ่ายการวัดจันทัน — ด้านยาว g"), P("rafterPhotoS", "ภาพถ่ายระยะห่างจันทัน"),
                FieldSpec("diag", "แนะนำองค์ประกอบของหลังคา", .diagram),
                FieldSpec("abNote", "", .note("ค่า a–e ลงในแบบของทรงหลังคาที่เลือกในข้อ 2 (จั่ว / เพิงหมาแหงน / ปั้นหยา) โดยอัตโนมัติ")),
                N("measA", "a: ระยะห่างของจันทัน (a1 → a2)", "ซม."), N("measB", "b: ระยะความยาวของจันทัน (b1 → b2)", "ซม."), N("measC", "c: ระยะห่างของแป (c1 → c2)", "ซม."),
                N("measD", "d: ระยะความยาวของเชิงชาย (d1 → d2)", "ซม."), N("measE", "e: ระยะความสูงของดั้ง (e1 → e2)", "ซม."),
                C("structMaterial", "ลักษณะวัสดุโครงสร้างหลังคา", Options.structMaterial),
                N("woodRafterF", "จันทันไม้ กว้าง f", "ซม.", when: isWood), N("woodRafterG", "จันทันไม้ ยาว g", "ซม.", when: isWood),
                N("woodPurlinF", "แปไม้ กว้าง f", "ซม.", when: isWood), N("woodPurlinG", "แปไม้ ยาว g", "ซม.", when: isWood),
                T("steelRafterType", "จันทันเหล็กประเภท", "C / กล่อง / กลม", when: isSteel), N("steelRafterF", "จันทันเหล็ก กว้าง f", "ซม.", when: isSteel),
                N("steelRafterG", "จันทันเหล็ก ยาว g", "ซม.", when: isSteel), N("steelRafterH", "จันทันเหล็ก ความยาวปีก h", "ซม.", when: isSteel),
                T("steelPurlinType", "แปเหล็กประเภท", "C / กล่อง / กลม", when: isSteel), N("steelPurlinF", "แปเหล็ก กว้าง f", "ซม.", when: isSteel),
                N("steelPurlinG", "แปเหล็ก ยาว g", "ซม.", when: isSteel), N("steelPurlinH", "แปเหล็ก ความยาวปีก h", "ซม.", when: isSteel),
                N("prefabRafterLength", "แปสำเร็จรูป — ความยาวจันทัน", "ซม.", optional: true),
                N("measH", "8. h: ระยะแนวระนาบจากปลายจันทันถึงเสา", "ซม."), N("measI1", "10. i1: จากพื้นดินถึงสันหลังคา", "ซม."),
                N("measI2", "11. i2: จากพื้นดินถึงเชิงชายหลังคา", "ซม."), N("roofAngle", "12. มุมเอียงของหลังคา", "องศา")]),
            GroupSpec(no: "14", "ร่างแบบหลังคาบ้านและตำแหน่งการวางแผง", [P("sketchPhoto", "ภาพร่าง")]),
            GroupSpec(no: "15", "ภาพถ่ายใต้หลังคา (เปิดฝ้า) หรือแบบแปลนหลังคา", [P("underRoofPhoto", "ภาพใต้หลังคา")]),
            GroupSpec(no: "16", "ภาพถ่ายมุมสูง / ภาพถ่ายดาวเทียม", [P("aerialPhoto", "ภาพมุมสูง")]),
            GroupSpec(no: "17", "ภาพถ่ายสถานที่ติดตั้ง", [P("photoFront", "17.1 ด้านหน้า"), P("photoBack", "17.2 ด้านหลัง"), P("photoLeft", "17.3 ด้านซ้าย"), P("photoRight", "17.4 ด้านขวา")]),
            GroupSpec(no: "18", "ภาพตำแหน่งติดตั้ง Inverter", [N("inverterCount", "จำนวนอินเวอร์เตอร์", "เครื่อง", optional: true),
                FieldSpec("invNote", "", .note("*ต้องมีพื้นที่ ยาว = (1.5 × จำนวนอินเวอร์เตอร์) + 1.5 เมตร · กว้าง = 2 เมตร")),
                P("inverterWidePhoto", "18 มุมกว้าง"), P("inverterClosePhoto", "18.1 ภาพใกล้")]),
            GroupSpec(no: "19", "ภาพถ่ายตู้ควบคุมไฟฟ้าหลัก", [P("mainPanelWide", "19 มุมกว้าง"), P("mainPanelOpen", "19.1 เปิดฝาตู้")]),
            GroupSpec(no: "20", "ภาพถ่ายเมนเบรกเกอร์", [P("breakerPhoto", "ภาพเมนเบรกเกอร์ (ขนาดจากข้อ 10)")]),
            GroupSpec(no: "21", "ภาพถ่ายมิเตอร์วัดหน่วยไฟฟ้า", [P("meterPhoto", "ภาพมิเตอร์")]),
            GroupSpec(no: "22", "ภาพถ่ายวัสดุมุงหลังคา", [P("roofMatPhoto", "ภาพวัสดุมุงหลังคา")]),
            GroupSpec(no: "23", "ภาพถ่ายบิลค่าไฟฟ้า", [T("userType", "ผู้ใช้ไฟประเภท"), T("caNo", "23.1 หมายเลขผู้ใช้ไฟฟ้า"), T("meterCode", "23.2 รหัสเครื่องวัด"), P("billPhoto", "ภาพบิลค่าไฟฟ้า")]),
            GroupSpec(no: "24", "ภาพถ่ายตำแหน่งกราวด์หลักดิน", [P("groundPhoto", "ภาพกราวด์หลักดิน (ถ้าถ่ายได้)", optional: true)])]),
        .roofForm: ModuleSpec(type: .roofForm, sheet: "หลังคาทั่วไป", label: "หลังคาอาคาร (แบบละเอียด)", short: "หลังคาอาคาร", reportTitle: "หลังคาอาคาร", namePlaceholder: "ชื่ออาคาร (ถ้ามี)", groups: [
            GroupSpec("อาคาร", [N("floors", "อาคารสูง", "ชั้น"), N("buildingWidth", "ความกว้าง", "ซม."), N("buildingLength", "ความยาว", "ซม.")]),
            GroupSpec(no: "1", "รูปแบบหลังคา", [C("roofShape", "รูปแบบหลังคา", Options.roofShape, other: true)]),
            GroupSpec(no: "2", "วัสดุมุงหลังคา", [C("roofMaterial", "วัสดุมุงหลังคา", Options.roofMaterial, other: true)]),
            GroupSpec(no: "4", "ชนิดโครงสร้างหลังคา", [C("roofStructure", "ชนิดโครงสร้าง", Options.structure)]),
            GroupSpec(no: "5", "พื้นที่หลังคาติดตั้งแผง", [N("panelAreaWidth", "กว้าง", "ซม."), N("panelAreaLength", "ยาว", "ซม.")]),
            GroupSpec(no: "6", "หลังคาหันไปทางทิศ", [C("facing", "ทิศ", Options.facing, other: true)]),
            GroupSpec(no: "7", "สิ่งกีดขวางและอุปสรรคบนหลังคา", [C("obstacle", "มีหรือไม่", Options.noYes), T("obstacleDetail", "ได้แก่", when: { $0.choice("obstacle") == "มี" })]),
            GroupSpec(no: "8", "แบบก่อสร้างของอาคาร", [C("hasConstructionDrawing", "มีหรือไม่", Options.yesNo)]),
            GroupSpec("ภาพหลังคา (Google Earth/Google Map)", [P("roofPhoto", "ภาพหลังคา")]),
            GroupSpec("โครงสร้างหลังคา", [P("sketchPhoto", "*เขียนแบบโครงสร้างหลังคาพอสังเขป"), FieldSpec("diag", "แนะนำองค์ประกอบของหลังคา", .diagram)]
                      + Options.components.enumerated().flatMap { i, c in [FieldSpec("size\(i + 1)", "\(c) — ขนาด g x f x h (ซม.)", .pick(list: .roofSizeCm, unit: "ซม."), optional: true),
                                                                        FieldSpec("space\(i + 1)", "\(c) — ระยะห่าง", .pick(list: .spacingCm, unit: "ซม."), optional: true)] }
                      + [C("structMaterial", "ลักษณะวัสดุโครงสร้างหลังคา", Options.structMaterial)]),
            GroupSpec("ภาพถ่าย", [P("underRoofPhoto", "ภาพถ่ายใต้หลังคา (เปิดฝ้า)"), P("aerialPhoto", "ภาพถ่ายมุมสูง / ดาวเทียม"),
                                P("photoFront", "ด้านหน้า"), P("photoBack", "ด้านหลัง"), P("photoLeft", "ด้านซ้าย"), P("photoRight", "ด้านขวา")])]),
    ]
    public static func spec(_ t: ModuleType) -> ModuleSpec { modules[t]! }

    /// B1 wide page answers: the A3 breaker feeding the panel, the PV connection point on `photoWide` and the spare slots.
    static let buildingPanelFields: [FieldSpec] = {
        let hidden: @Sendable (Values) -> Bool = { _ in false }
        return [T("a3Breaker", "ตู้นี้ในผัง A3", optional: true, when: hidden),
                FieldSpec("pvPoint", "จุดเชื่อมต่อ PV บนภาพ", .text(), optional: true, when: hidden),
                N("spareSlots", "ช่องว่างในตู้", "ช่อง", optional: true, when: hidden),
                // A2 building model of this building (`SiteModels`)
                N("bldW", "ความกว้างอาคาร (ก)", "ม.", optional: true, when: hidden), N("bldL", "ความยาวอาคาร (ย)", "ม.", optional: true, when: hidden)]
    }()

    /// B2 wide page answers: the measured area, the boundary on `photoDetail`, the site, the inverter sizes and the user's spans / tray / ladder.
    static let inverterStationFields: [FieldSpec] = {
        let hidden: @Sendable (Values) -> Bool = { _ in false }
        return [N("invAreaW", "ความกว้างพื้นที่ (ก)", "ม.", optional: true, when: hidden), N("invAreaL", "ความยาวพื้นที่ (ย)", "ม.", optional: true, when: hidden),
                N("invAreaH", "ความสูงพื้นที่ (ส)", "ม.", optional: true, when: hidden),
                FieldSpec("invBoundary", "ขอบเขตบนภาพ", .text(), optional: true, when: hidden),
                C("invSite", "ตำแหน่งติดตั้ง", InverterStation.Site.allCases.map(\.label), optional: true, when: hidden),
                T("invSizes", "ขนาดอินเวอร์เตอร์ (kW คั่นด้วย ,)", "60,60", optional: true, when: hidden),
                T("invSpans", "ระยะช่วงเสา (ม. คั่นด้วย ,)", optional: true, when: hidden),
                N("invTrayW", "Tray อินเวอร์เตอร์ → AC-DB", "มม.", optional: true, when: hidden), N("invLadderW", "Ladder ออกจาก AC-DB", "มม.", optional: true, when: hidden)]
    }()

    /// Starting slots on the station sheet, used to warn when a sheet copy will be added.
    public static let stationSlots: [ModuleType: Int] = [.panel: 3, .inverter: 3, .water: 4, .backfeed: 2, .fts: 4]
}
