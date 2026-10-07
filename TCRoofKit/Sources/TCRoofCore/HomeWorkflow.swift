import Foundation

// งานบ้าน: a residential Solar Rooftop job (PEA area, ผู้ใช้ไฟประเภท 1) from survey to handover, in one place.
// Two routes: selling the surplus (โครงการภาคประชาชน 2569) or self-use (ขอเชื่อมต่อ ไม่ขายไฟ).
// The document list follows PEA's forms and the PPIM upload screens (non-sell part 4 slots confirmed from the screen).

public enum HomeStage: String, Codable, CaseIterable, Sendable {
    case survey, design, apply, install, connect, handover

    public var title: String {
        switch self {
        case .survey: "สำรวจหน้างาน"
        case .design: "ออกแบบ"
        case .apply: "ยื่นขออนุญาต"
        case .install: "ติดตั้ง"
        case .connect: "ขอเชื่อมต่อ / ขนานไฟ"
        case .handover: "ส่งมอบ"
        }
    }
}

/// Who brings a document.
public enum HomeProvider: String, Codable, Sendable {
    case customer, team, engineer, pea, local

    public var title: String {
        switch self {
        case .customer: "ลูกค้า"
        case .team: "ทีมเรา"
        case .engineer: "วิศวกร"
        case .pea: "PEA"
        case .local: "เทศบาล/อบต."
        }
    }
}

public enum HomeDocStatus: String, Codable, CaseIterable, Sendable {
    case missing, received, submitted, approved

    public var title: String {
        switch self {
        case .missing: "ยังไม่มี"
        case .received: "ได้แล้ว"
        case .submitted: "ยื่นแล้ว"
        case .approved: "ผ่าน"
        }
    }
    public var isDone: Bool { self != .missing }
}

/// A screen of the app that produces the document instead of an upload.
public enum HomeFormLink: String, Codable, Sendable {
    case powerOfAttorney, selfCertification, roofWeight, surveyForm, installLog, inspection
}

/// One document of the job: what it is, at which stage, who brings it, and its PPIM upload slot.
public struct HomeDocSpec: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let stage: HomeStage
    public let provider: HomeProvider
    public var note: String?
    public var form: HomeFormLink?
    /// PPIM part 4 slot of the self-use request (1…9), and its file name and size limit.
    public var ppimSlot: Int?
    public var ppimFile: String?
    public var maxMB: Int?
    /// Optional documents never block a stage.
    public var optional = false
    public var when: @Sendable (HomeJob) -> Bool = { _ in true }
}

public struct HomeDocument: Codable, Equatable, Sendable {
    public var status: HomeDocStatus = .missing
    /// File names in the job's permit folder.
    public var files: [String] = []
    public var note = ""
    public var updatedAt: Date?
    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(HomeDocStatus.self, forKey: .status) ?? .missing
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
    private enum CodingKeys: String, CodingKey { case status, files, note, updatedAt }
}

/// The residential job's answers that decide which documents apply.
public struct HomeJob: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case sell, selfUse
        public var title: String { self == .sell ? "ขายไฟส่วนเกิน (ภาคประชาชน 2569)" : "ผลิตใช้เอง ไม่ขายไฟ" }
    }

    /// Confirmed as a home: ผู้ใช้ไฟประเภท 1 in a PEA area. The module is for homes only.
    public var residentialConfirmed = false
    public var caRateCode = ""
    public var mode: Mode = .selfUse
    /// The team files for the owner (needs a power of attorney).
    public var teamFiles = true
    public var wantsTaxDeduction = true
    public var pvKWp = ""
    public var inverterKW = ""
    public var sellKW = ""
    public var phase: SelfCertification.Phase?
    /// From the roof weight calculator (กฎกระทรวง ฉบับที่ 72 พ.ศ. 2568).
    public var roofKgPerM2: Double?
    public var ppimRequestNo = ""
    public var documents: [String: HomeDocument] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        residentialConfirmed = try c.decodeIfPresent(Bool.self, forKey: .residentialConfirmed) ?? false
        caRateCode = try c.decodeIfPresent(String.self, forKey: .caRateCode) ?? ""
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .selfUse
        teamFiles = try c.decodeIfPresent(Bool.self, forKey: .teamFiles) ?? true
        wantsTaxDeduction = try c.decodeIfPresent(Bool.self, forKey: .wantsTaxDeduction) ?? true
        pvKWp = try c.decodeIfPresent(String.self, forKey: .pvKWp) ?? ""
        inverterKW = try c.decodeIfPresent(String.self, forKey: .inverterKW) ?? ""
        sellKW = try c.decodeIfPresent(String.self, forKey: .sellKW) ?? ""
        phase = try c.decodeIfPresent(SelfCertification.Phase.self, forKey: .phase)
        roofKgPerM2 = try c.decodeIfPresent(Double.self, forKey: .roofKgPerM2)
        ppimRequestNo = try c.decodeIfPresent(String.self, forKey: .ppimRequestNo) ?? ""
        documents = try c.decodeIfPresent([String: HomeDocument].self, forKey: .documents) ?? [:]
    }
    private enum CodingKeys: String, CodingKey {
        case residentialConfirmed, caRateCode, mode, teamFiles, wantsTaxDeduction, pvKWp, inverterKW, sellKW, phase,
             roofKgPerM2, ppimRequestNo, documents
    }

    static func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }

    /// CA rate code starts with 1 (บ้านอยู่อาศัย). Nil until typed.
    public var rateCodeIsResidential: Bool? {
        let d = caRateCode.trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? nil : d.hasPrefix("1")
    }

    /// Over 20 kg/m² needs a building permit (ข.1 → อ.1); nil until weighed.
    public var needsBuildingPermit: Bool? { roofKgPerM2.map { $0 > 20 } }

    public var taxEligible: Bool {
        guard wantsTaxDeduction, let kwp = Self.number(pvKWp) else { return false }
        return kwp <= 10
    }

    /// The form's limiter rule (item 2): inverters above the power sold, and one phase > 7 kW or more phases > 10 kW.
    /// Self-use always needs zero export.
    public var needsExportLimiter: Bool? {
        if mode == .selfUse { return true }
        guard let inv = Self.number(inverterKW), let sell = Self.number(sellKW), let phase else { return nil }
        return inv > sell && (phase == .single ? inv > 7 : inv > 10)
    }

    public var issues: [String] {
        var out: [String] = []
        if !residentialConfirmed { out.append("ยืนยันว่าเป็นบ้านอยู่อาศัย") }
        if rateCodeIsResidential == false { out.append("CA ไม่ได้ขึ้นต้นด้วย 1 — ไม่ใช่บ้านอยู่อาศัย") }
        if mode == .sell, let sell = Self.number(sellKW), sell > 5 { out.append("เสนอขายเกิน 5 kW") }
        return out
    }

    public func document(_ id: String) -> HomeDocument { documents[id] ?? HomeDocument() }

    /// Documents that apply to this job, in stage order.
    public var checklist: [HomeDocSpec] { HomeCatalog.all.filter { $0.when(self) } }

    public func missing(in stage: HomeStage) -> [HomeDocSpec] {
        checklist.filter { $0.stage == stage && !$0.optional && !document($0.id).status.isDone }
    }

    /// Done / required of a stage.
    public func progress(_ stage: HomeStage) -> (done: Int, total: Int) {
        let req = checklist.filter { $0.stage == stage && !$0.optional }
        return (req.filter { document($0.id).status.isDone }.count, req.count)
    }

    /// The first stage with something missing; nil when the job is complete.
    public var currentStage: HomeStage? { HomeStage.allCases.first { !missing(in: $0).isEmpty } }

    /// PPIM part 4 slots of the self-use request that apply, in slot order.
    public var ppimSlots: [HomeDocSpec] {
        checklist.filter { $0.ppimSlot != nil }.sorted { ($0.ppimSlot ?? 0) < ($1.ppimSlot ?? 0) }
    }
}

public enum HomeCatalog {
    static let sell: @Sendable (HomeJob) -> Bool = { $0.mode == .sell }
    static let selfUse: @Sendable (HomeJob) -> Bool = { $0.mode == .selfUse }

    public static let all: [HomeDocSpec] = [
        // สำรวจ
        HomeDocSpec(id: "survey", title: "แบบสำรวจหน้างาน (หลังคา ตู้ MDB มิเตอร์ ทิศ เงา)", stage: .survey, provider: .team, form: .surveyForm),
        HomeDocSpec(id: "bill", title: "ใบแจ้งค่าไฟฟ้าของเครื่องวัด เดือนล่าสุดหรือย้อนหลังไม่เกิน 3 เดือน", stage: .survey, provider: .customer,
                    note: "ชื่อต้องตรงผู้ยื่น · CA ขึ้นต้นด้วย 1", ppimSlot: 1, ppimFile: "1. ใบแจ้งค่าไฟฟ้า.pdf", maxMB: 5),
        HomeDocSpec(id: "idCard", title: "สำเนาบัตรประชาชนเจ้าของเครื่องวัด (รับรองสำเนา)", stage: .survey, provider: .customer,
                    ppimSlot: 2, ppimFile: "2. สำเนาบัตรประชาชน.pdf", maxMB: 5),
        HomeDocSpec(id: "houseReg", title: "สำเนาทะเบียนบ้านหน้าแรก (ที่อยู่ตรงบิล)", stage: .survey, provider: .customer, when: sell),
        HomeDocSpec(id: "sitePlan", title: "แผนผังแสดงที่ตั้งเครื่องกำเนิดไฟฟ้า พร้อมพิกัด Latitude / Longitude", stage: .survey, provider: .team,
                    ppimSlot: 3, ppimFile: "3. แผนผังแสดงที่ติดตั้ง.pdf", maxMB: 5),
        HomeDocSpec(id: "sitePhotos", title: "รูปถ่ายหน้าบ้าน / สถานที่ตั้งระบบ", stage: .survey, provider: .team,
                    note: "หลังติดตั้งเปลี่ยนเป็นรูประบบที่ติดตั้งแล้ว", ppimSlot: 4, ppimFile: "4. ภาพถ่ายติดตั้งระบบผลิตไฟฟ้า.pdf", maxMB: 5),
        HomeDocSpec(id: "roofWeight", title: "ใบคำนวณน้ำหนักบนหลังคา (กก./ตร.ม.)", stage: .survey, provider: .engineer,
                    note: "≤ 20 กก./ตร.ม. ไม่ต้องขออนุญาตดัดแปลงอาคาร (กฎกระทรวง ฉบับที่ 72 พ.ศ. 2568)", form: .roofWeight),

        // ออกแบบ
        HomeDocSpec(id: "sld", title: "Single Line Diagram วิศวกรลงนามทุกแผ่น + สำเนา กว. + หนังสือรับรองสภาวิศวกร", stage: .design, provider: .engineer,
                    note: "ผลิตใช้เอง: แสดงอุปกรณ์กันไหลย้อน (zero export)", ppimSlot: 6, ppimFile: "6. Single Line Diagram + เอกสารวิศวกรไฟฟ้า.pdf", maxMB: 50),
        HomeDocSpec(id: "equipment", title: "รายละเอียดอุปกรณ์ที่ใช้เชื่อมต่อ: อุปกรณ์กันไหลย้อน + CT, เบรกเกอร์/RCBO, AC SPD", stage: .design, provider: .team,
                    ppimSlot: 5, ppimFile: "5. อุปกรณ์อื่นๆที่เกี่ยวข้อง.pdf", maxMB: 50),
        HomeDocSpec(id: "pvSpec", title: "Datasheet แผงโซลาร์ (ระบุมาตรฐาน มอก./IEC)", stage: .design, provider: .team,
                    ppimSlot: 8, ppimFile: "8. แผงเซลล์แสงอาทิตย์.pdf", maxMB: 5),
        HomeDocSpec(id: "inverterSpec", title: "Datasheet อินเวอร์เตอร์ / ผลทดสอบและรับรองผลิตภัณฑ์", stage: .design, provider: .team,
                    note: "รุ่นต้องอยู่ใน smartlist.pea.co.th", ppimSlot: 9, ppimFile: "9. เครื่องแปลงไฟฟ้า.pdf", maxMB: 25),
        HomeDocSpec(id: "buildingPermit", title: "ขออนุญาตดัดแปลงอาคาร ข.1 → อ.1 (แบบและรายการคำนวณโยธา + โฉนด)", stage: .design, provider: .local,
                    note: "เฉพาะน้ำหนักเกิน 20 กก./ตร.ม. · ต้องได้ อ.1 ก่อนติดตั้ง", when: { $0.needsBuildingPermit == true }),

        // ยื่นขออนุญาต
        HomeDocSpec(id: "poa", title: "หนังสือมอบอำนาจ เซ็นสด + อากร 30 บาท + สำเนาบัตรผู้มอบและผู้รับมอบ", stage: .apply, provider: .customer,
                    form: .powerOfAttorney, when: { $0.teamFiles }),
        HomeDocSpec(id: "ppimRequest", title: "ยื่นคำขอใน PPIM และบันทึกเลขคำขอ", stage: .apply, provider: .team,
                    note: "ผลิตใช้เอง: PEA แจ้งผลภายใน 45 วันนับจากเอกสารครบ"),
        HomeDocSpec(id: "peaApproval", title: "PEA อนุมัติคำขอ / ประกาศรายชื่อ", stage: .apply, provider: .pea),
        HomeDocSpec(id: "feeReceipt", title: "ใบเสร็จค่าตรวจสอบการเชื่อมต่อ 2,140 บาท", stage: .apply, provider: .customer,
                    note: "ภายใน 30 วันนับจากประกาศ", when: sell),
        HomeDocSpec(id: "contract", title: "ส่งเอกสารสัญญา 2 ชุด และลงนามสัญญาซื้อขายไฟฟ้า", stage: .apply, provider: .customer,
                    note: "ภายใน 30 วันนับจากประกาศ ไม่ลงนาม = ยกเลิก", when: sell),

        // ติดตั้ง
        HomeDocSpec(id: "installLog", title: "บันทึกงานติดตั้งและรูประหว่างติดตั้ง", stage: .install, provider: .team, form: .installLog),
        HomeDocSpec(id: "exportLimiter", title: "ติดตั้งและตั้งค่าอุปกรณ์กันไหลย้อน (Export Limiter / zero export) + CT", stage: .install, provider: .team,
                    when: { $0.needsExportLimiter == true }),
        HomeDocSpec(id: "eTax", title: "e-Tax Invoice ในชื่อลูกค้า", stage: .install, provider: .team,
                    note: "ลดหย่อนภาษีสูงสุด 200,000 บาท แผงไม่เกิน 10 kWp", when: { $0.taxEligible }),
        HomeDocSpec(id: "icl", title: "ใบตรวจรับงาน (ICL)", stage: .install, provider: .team, form: .inspection),

        // ขอเชื่อมต่อ
        HomeDocSpec(id: "selfCert", title: "แบบฟอร์มรับรองตนเอง VSPP + เอกสารแนบ 1–10 (วิศวกรเซ็นทุกแผ่น)", stage: .connect, provider: .engineer,
                    form: .selfCertification, when: sell),
        HomeDocSpec(id: "installCert", title: "แบบรับรองการติดตั้ง + รูปหน้างาน (วิศวกรเซ็น)", stage: .connect, provider: .engineer,
                    note: "ฉบับที่ PEA ใช้กับสายผลิตใช้เองยังไม่ยืนยัน — ใช้แบบรับรองตนเองเป็นโครง", form: .selfCertification, when: selfUse),
        HomeDocSpec(id: "ercNotice", title: "แจ้ง กกพ. การผลิตไฟฟ้าที่ได้รับยกเว้นใบอนุญาต (inverter < 1,000 kW)", stage: .connect, provider: .team,
                    note: "ผลิตใช้เอง: ยังไม่ยืนยันว่าต้องแจ้ง", optional: false, when: sell),
        HomeDocSpec(id: "ercNoticeSelfUse", title: "แจ้ง กกพ. (ถ้า PEA เขตขอ)", stage: .connect, provider: .team,
                    note: "ยังไม่ยืนยันว่าสายผลิตใช้เองต้องแจ้ง", optional: true, when: selfUse),
        HomeDocSpec(id: "peaInspection", title: "PEA ตรวจระบบ / ทดสอบขนาน (First Sync, Anti-islanding, กันไหลย้อน)", stage: .connect, provider: .pea,
                    note: "PEA ตรวจภายใน 30 วันนับจากแจ้งขอตรวจ"),

        // ส่งมอบ
        HomeDocSpec(id: "connectionDate", title: "หนังสือ PEA แจ้งวันเริ่มต้นเชื่อมต่อ / วัน COD", stage: .handover, provider: .pea),
        HomeDocSpec(id: "eBill", title: "ลงทะเบียน e-bill และบัญชีรับเงิน ภายในเดือนที่ COD", stage: .handover, provider: .customer, when: sell),
        HomeDocSpec(id: "taxPack", title: "ส่งชุดเอกสารลดหย่อนภาษีให้ลูกค้า (e-Tax Invoice + หนังสือ PEA)", stage: .handover, provider: .team,
                    when: { $0.taxEligible }),
        HomeDocSpec(id: "handoverPack", title: "ส่งมอบคู่มือ รูปติดตั้ง และ SLD ให้ลูกค้า", stage: .handover, provider: .team),
    ]

    public static func spec(_ id: String) -> HomeDocSpec? { all.first { $0.id == id } }
}

/// Roof weight per m² for the building-permit rule: everything on the roof over the area the panels cover.
public enum RoofWeight {
    public static func kgPerM2(panelKg: Double, panelAreaM2: Double, panelCount: Int, mountingKg: Double, otherKg: Double) -> Double? {
        let area = panelAreaM2 * Double(panelCount)
        guard area > 0 else { return nil }
        return (panelKg * Double(panelCount) + mountingKg + otherKg) / area
    }
}
