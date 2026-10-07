import Foundation

// งานบ้าน: a residential Solar Rooftop job (PEA area, ผู้ใช้ไฟประเภท 1) from survey to handover, in one place.
// Two routes: selling the surplus (โครงการภาคประชาชน 2569) or self-use (ขอเชื่อมต่อ ไม่ขายไฟ).
// The document list follows PEA's forms and the PPIM upload screens. The self-use part 4 slots, their titles, limits and
// what goes in each file are confirmed from a filed request (slots 1–6 เอกสารหลัก, 8–9 พลังงานแสงอาทิตย์; there is no 7
// for solar).

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
    case powerOfAttorney, selfCertification, roofWeight, surveyForm, installLog, inspection, photoReport, boq, site
}

/// One upload slot of PPIM part 4 (self-use request), as the screen shows it. Several documents of the job can go
/// into one slot's file (slot 2: ID card and house registration; slot 6: the drawings and the engineer's papers).
public struct PPIMSlotSpec: Sendable, Equatable, Identifiable {
    public let number: Int
    /// PPIM's heading over the slot: เอกสารหลัก (1–6) or พลังงานแสงอาทิตย์ (8–9).
    public let group: String
    /// The slot's title on the screen.
    public let title: String
    /// File name to upload, numbered as the screen.
    public let file: String
    public let maxMB: Int
    public var id: Int { number }
}

/// The documents that go into one slot's file, in file order.
public struct PPIMUpload: Sendable, Identifiable {
    public let slot: PPIMSlotSpec
    public let documents: [HomeDocSpec]
    public var id: Int { slot.number }
}

/// One document of the job: what it is, at which stage, who brings it, and its PPIM upload slot.
public struct HomeDocSpec: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let stage: HomeStage
    public let provider: HomeProvider
    public var note: String?
    public var form: HomeFormLink?
    /// PPIM part 4 slot of the self-use request (1…9); the file name and size limit come from `HomeCatalog.ppimSlots`.
    public var ppimSlot: Int?
    /// Optional documents never block a stage.
    public var optional = false
    public var when: @Sendable (HomeJob) -> Bool = { _ in true }
    /// Optional on some routes only.
    public var optionalWhen: (@Sendable (HomeJob) -> Bool)? = nil

    public var ppim: PPIMSlotSpec? { ppimSlot.flatMap(HomeCatalog.slot) }
    public func isOptional(for job: HomeJob) -> Bool { optional || optionalWhen?(job) == true }
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
    /// What to type into PPIM parts 3 (meter, location, panels, inverters).
    public var ppim = PPIMEntry()
    /// Slot 4's photo pages.
    public var photoReport = PhotoReport()
    /// หนังสือรับรองสภาวิศวกร for slot 6; valid 120 days from this date.
    public var coeCertIssued: Date?
    /// Selling route: the second PPIM request (ขออนุญาตเชื่อมต่อ, after the contract). `ppimRequestNo` is the first.
    public var connectRequestNo = ""
    /// Selling route: sizes filed in the sell request. The connection request can't go above them.
    public var offer: HomeOffer?
    /// Selling route: PEA's list announcement, the contract's SCOD and the COD PEA gives.
    public var announcedOn: Date?
    public var scod: Date?
    public var cod: Date?
    /// Document id → `HomeLibrary.Item` id attached to this job (engineer papers, datasheets); "" = don't use the library.
    public var libraryPicks: [String: String] = [:]
    /// Installed by a contractor (work order, delivery, acceptance) rather than the team's own crew.
    public var usesContractor = true
    /// Work order, materials, changes and punch list with the installer.
    public var site = HomeSite()

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
        ppim = try c.decodeIfPresent(PPIMEntry.self, forKey: .ppim) ?? PPIMEntry()
        photoReport = try c.decodeIfPresent(PhotoReport.self, forKey: .photoReport) ?? PhotoReport()
        coeCertIssued = try c.decodeIfPresent(Date.self, forKey: .coeCertIssued)
        connectRequestNo = try c.decodeIfPresent(String.self, forKey: .connectRequestNo) ?? ""
        offer = try c.decodeIfPresent(HomeOffer.self, forKey: .offer)
        announcedOn = try c.decodeIfPresent(Date.self, forKey: .announcedOn)
        scod = try c.decodeIfPresent(Date.self, forKey: .scod)
        cod = try c.decodeIfPresent(Date.self, forKey: .cod)
        libraryPicks = try c.decodeIfPresent([String: String].self, forKey: .libraryPicks) ?? [:]
        usesContractor = try c.decodeIfPresent(Bool.self, forKey: .usesContractor) ?? true
        site = try c.decodeIfPresent(HomeSite.self, forKey: .site) ?? HomeSite()
    }
    private enum CodingKeys: String, CodingKey {
        case residentialConfirmed, caRateCode, mode, teamFiles, wantsTaxDeduction, pvKWp, inverterKW, sellKW, phase,
             roofKgPerM2, ppimRequestNo, documents, ppim, photoReport, coeCertIssued,
             connectRequestNo, offer, announcedOn, scod, cod, libraryPicks, usesContractor, site
    }

    /// The council's certificate is valid 120 days from its date (printed on it). Nil until the date is set.
    public static let coeCertValidDays = 120
    public func coeCertDaysLeft(on date: Date = Date()) -> Int? {
        guard let issued = coeCertIssued else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: issued), to: cal.startOfDay(for: date)).day ?? 0
        return Self.coeCertValidDays - days
    }

    public static func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }

    /// CA rate code starts with 1 (บ้านอยู่อาศัย). Nil until typed.
    public var rateCodeIsResidential: Bool? {
        let d = caRateCode.trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? nil : d.hasPrefix("1")
    }

    /// Fourth digit 5: below 400 V, the only voltage the 2569 programme takes. Nil until 4 digits are typed.
    public var rateCodeIsLowVoltage: Bool? {
        let d = caRateCode.trimmingCharacters(in: .whitespaces)
        guard d.count >= 4 else { return nil }
        return Array(d)[3] == "5"
    }

    /// PPIM takes sell requests from 1 Jul 2569 08:00 to 30 Nov 2570 17:00 (Bangkok), or until the quota is full.
    public static let sellWindow: ClosedRange<Date> = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let from = cal.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 8))!
        let to = cal.date(from: DateComponents(year: 2027, month: 11, day: 30, hour: 17))!
        return from...to
    }()
    public static func sellWindowOpen(on date: Date) -> Bool { sellWindow.contains(date) }

    /// Days PEA gives after the announcement to pay, send the contract papers and sign.
    public static let announcementDays = 30

    /// Selling route deadlines that have a start date, in order.
    public var sellDeadlines: [HomeDeadline] {
        guard mode == .sell else { return [] }
        var out: [HomeDeadline] = []
        if let a = announcedOn, let due = Calendar(identifier: .gregorian).date(byAdding: .day, value: Self.announcementDays, to: a) {
            out.append(HomeDeadline(id: "fee", title: "ชำระค่าตรวจสอบการเชื่อมต่อ 2,140 บาท", due: due, done: document("feeReceipt").status.isDone))
            out.append(HomeDeadline(id: "contract", title: "ส่งเอกสารสัญญา 2 ชุด และลงนามสัญญา", due: due, done: document("contract").status.isDone))
        }
        if let s = scod {
            out.append(HomeDeadline(id: "scod", title: "จ่ายไฟเข้าระบบ (COD) ภายใน SCOD", due: s, done: cod != nil))
        }
        return out
    }

    /// Sizes now that are above what the sell request filed.
    public var offerIssues: [String] {
        guard mode == .sell, let offer else { return [] }
        var out: [String] = []
        func over(_ now: Double?, _ filed: Double?, _ what: String) {
            if let now, let filed, now > filed + 0.0001 { out.append("\(what) เกินที่ยื่นขอขายไฟ (\(HomeOffer.text(now)) > \(HomeOffer.text(filed)))") }
        }
        over(Self.number(pvKWp), offer.pvKWp, "แผง kWp")
        over(Self.number(inverterKW), offer.inverterKW, "อินเวอร์เตอร์ kW")
        over(Self.number(sellKW), offer.sellKW, "ปริมาณเสนอขาย kW")
        return out
    }

    /// Records the sizes of the sell request; false when a size isn't a number yet.
    @discardableResult
    public mutating func lockOffer(on date: Date = Date()) -> Bool {
        guard let pv = Self.number(pvKWp), let inv = Self.number(inverterKW), let sell = Self.number(sellKW) else { return false }
        offer = HomeOffer(pvKWp: pv, inverterKW: inv, sellKW: sell, phase: phase, lockedAt: date)
        return true
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

    public var issues: [String] { issues(on: Date()) }

    public func issues(on now: Date) -> [String] {
        var out: [String] = []
        if !residentialConfirmed { out.append("ยืนยันว่าเป็นบ้านอยู่อาศัย") }
        if rateCodeIsResidential == false { out.append("CA ไม่ได้ขึ้นต้นด้วย 1 — ไม่ใช่บ้านอยู่อาศัย") }
        if mode == .sell, let sell = Self.number(sellKW), sell > 5 { out.append("เสนอขายเกิน 5 kW") }
        if !site.pendingChanges.isEmpty { out.append("ใบขอเปลี่ยนแปลงรออนุมัติ \(site.pendingChanges.count) ใบ") }
        let late = site.punches.filter { $0.isLate(on: now) }.count
        if late > 0 { out.append("Punch list เลยกำหนด \(late) รายการ") }
        if let left = coeCertDaysLeft(), left < 0 { out.append("หนังสือรับรองสภาวิศวกรหมดอายุ (เกิน 120 วัน) ขอฉบับใหม่ก่อนยื่น") }
        if mode == .sell {
            if rateCodeIsLowVoltage == false { out.append("Rate code หลักที่ 4 ไม่ใช่ 5 — แรงดันตั้งแต่ 400 V ขึ้นไป ไม่เข้าโครงการภาคประชาชน") }
            if ppimRequestNo.trimmingCharacters(in: .whitespaces).isEmpty, !Self.sellWindowOpen(on: now) {
                out.append("อยู่นอกช่วงเปิดรับคำขอขายไฟ (1 ก.ค. 2569 – 30 พ.ย. 2570)")
            }
            out += offerIssues
            out += sellDeadlines.filter { !$0.done && $0.daysLeft(on: now) < 0 }.map { "เลยกำหนด: \($0.title)" }
        }
        return out
    }

    public func document(_ id: String) -> HomeDocument { documents[id] ?? HomeDocument() }

    /// Documents that apply to this job, in stage order.
    public var checklist: [HomeDocSpec] { HomeCatalog.all.filter { $0.when(self) } }

    public func missing(in stage: HomeStage) -> [HomeDocSpec] {
        checklist.filter { $0.stage == stage && !$0.isOptional(for: self) && !document($0.id).status.isDone }
    }

    /// Done / required of a stage.
    public func progress(_ stage: HomeStage) -> (done: Int, total: Int) {
        let req = checklist.filter { $0.stage == stage && !$0.isOptional(for: self) }
        return (req.filter { document($0.id).status.isDone }.count, req.count)
    }

    /// The first stage with something missing; nil when the job is complete.
    public var currentStage: HomeStage? { HomeStage.allCases.first { !missing(in: $0).isEmpty } }

    /// PPIM part 4 slots of the self-use request, in slot order, each with the job's documents that go into its file.
    public var ppimSlots: [PPIMUpload] {
        let docs = checklist
        return HomeCatalog.ppimSlots.map { slot in PPIMUpload(slot: slot, documents: docs.filter { $0.ppimSlot == slot.number }) }
    }
}

/// Sizes filed in the sell request.
public struct HomeOffer: Codable, Equatable, Sendable {
    public var pvKWp: Double?
    public var inverterKW: Double?
    public var sellKW: Double?
    public var phase: SelfCertification.Phase?
    public var lockedAt: Date?

    public static func text(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

/// A date PEA holds the job to.
public struct HomeDeadline: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let due: Date
    public let done: Bool

    public func daysLeft(on date: Date = Date()) -> Int {
        let cal = Calendar(identifier: .gregorian)
        return cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: due)).day ?? 0
    }
}

public enum HomeCatalog {
    static let sell: @Sendable (HomeJob) -> Bool = { $0.mode == .sell }
    static let selfUse: @Sendable (HomeJob) -> Bool = { $0.mode == .selfUse }

    /// PPIM part 4 of the self-use request, as on the screen. Slot 7 isn't shown for solar.
    public static let ppimSlots: [PPIMSlotSpec] = [
        PPIMSlotSpec(number: 1, group: "เอกสารหลัก",
                     title: "ใบแจ้งค่าไฟฟ้าของเครื่องวัดหน่วยไฟฟ้าเดือนล่าสุดหรือย้อนหลังไม่เกิน 3 เดือนล่าสุด",
                     file: "1. ใบแจ้งค่าไฟฟ้า.pdf", maxMB: 5),
        PPIMSlotSpec(number: 2, group: "เอกสารหลัก",
                     title: "สำเนาบัตรประชาชน/สำเนาหนังสือรับรองนิติบุคคลของเจ้าของเครื่องวัด/เจ้าของเครื่องกำเนิดไฟฟ้า",
                     file: "2. เอกสารเจ้าของเครื่องวัด.pdf", maxMB: 5),
        PPIMSlotSpec(number: 3, group: "เอกสารหลัก",
                     title: "แผนผังแสดงที่ตั้งเครื่องกำเนิดไฟฟ้าพร้อมระบุพิกัด Latitude และ Longitude",
                     file: "3. แผนผังแสดงที่ติดตั้ง.pdf", maxMB: 5),
        PPIMSlotSpec(number: 4, group: "เอกสารหลัก",
                     title: "รูปถ่าย/ภาพถ่ายของระบบผลิตไฟฟ้าที่ขอเชื่อมต่อฯ หรือสถานที่ตั้งของโครงการที่จะติดตั้งระบบผลิตไฟฟ้า",
                     file: "4. ภาพถ่ายติดตั้งระบบผลิตไฟฟ้า.pdf", maxMB: 5),
        PPIMSlotSpec(number: 5, group: "เอกสารหลัก",
                     title: "เอกสารแสดงรายละเอียดคุณสมบัติของระบบไฟฟ้าและหรืออุปกรณ์ที่ใช้ในการเชื่อมต่อส่วนระบบผลิตไฟฟ้า",
                     file: "5. อุปกรณ์อื่นๆที่เกี่ยวข้อง.pdf", maxMB: 50),
        PPIMSlotSpec(number: 6, group: "เอกสารหลัก",
                     title: "แผนภูมิระบบไฟฟ้า (Single Line Diagram) พร้อมวิศวกรลงนามรับรองทุกแผ่นและใบอนุญาตและหนังสือรับรอง",
                     file: "6. แบบแปลน + เอกสารวิศวกรไฟฟ้า.pdf", maxMB: 50),
        PPIMSlotSpec(number: 8, group: "พลังงานแสงอาทิตย์",
                     title: "เอกสารแสดงรายละเอียดคุณสมบัติของแผงพลังงานแสงอาทิตย์",
                     file: "8. แผงเซลล์แสงอาทิตย์.pdf", maxMB: 5),
        PPIMSlotSpec(number: 9, group: "พลังงานแสงอาทิตย์",
                     title: "เอกสารแสดงรายละเอียดคุณสมบัติของอินเวอร์เตอร์ / ผลการทดสอบและรับรองผลิตภัณฑ์",
                     file: "9. เครื่องแปลงไฟฟ้า.pdf", maxMB: 25),
    ]

    public static func slot(_ number: Int) -> PPIMSlotSpec? { ppimSlots.first { $0.number == number } }

    public static let all: [HomeDocSpec] = [
        // สำรวจ
        HomeDocSpec(id: "survey", title: "แบบสำรวจหน้างาน (หลังคา ตู้ MDB มิเตอร์ ทิศ เงา)", stage: .survey, provider: .team, form: .surveyForm),
        HomeDocSpec(id: "bill", title: "ใบแจ้งค่าไฟฟ้าของเครื่องวัด เดือนล่าสุดหรือย้อนหลังไม่เกิน 3 เดือน", stage: .survey, provider: .customer,
                    note: "ชื่อต้องตรงผู้ยื่น · CA ขึ้นต้นด้วย 1", ppimSlot: 1),
        HomeDocSpec(id: "idCard", title: "สำเนาบัตรประชาชนเจ้าของเครื่องวัด (เซ็นรับรองสำเนา)", stage: .survey, provider: .customer,
                    ppimSlot: 2),
        HomeDocSpec(id: "houseReg", title: "สำเนาทะเบียนบ้าน (หน้ารายการเกี่ยวกับบ้าน + หน้าเจ้าของ)", stage: .survey, provider: .customer,
                    note: "ผลิตใช้เอง: รวมไว้ในไฟล์ช่อง 2 ต่อจากบัตรประชาชน", ppimSlot: 2, optionalWhen: selfUse),
        HomeDocSpec(id: "sitePlan", title: "แผนผังแสดงที่ตั้งเครื่องกำเนิดไฟฟ้า พร้อมพิกัด Latitude / Longitude", stage: .survey, provider: .team,
                    note: "ภาพถ่ายทางอากาศ วางตำแหน่งแผง อินเวอร์เตอร์ แนวสาย DC และตารางข้อมูลโครงการพร้อมพิกัด · ใช้แผ่นผังแผงจากชุดแบบได้",
                    ppimSlot: 3),
        HomeDocSpec(id: "sitePhotos", title: "ภาพถ่ายระบบผลิตไฟฟ้า (ชุดรูปมาตรฐาน 9 หัวข้อ)", stage: .survey, provider: .team,
                    note: "ก่อนติดตั้งใช้รูปสถานที่ตั้งได้ · ยื่นหลังติดตั้งใช้ชุดรูประบบ หน้าละ 2 หัวข้อ มีหัวโครงการ ที่อยู่ และขนาดกำลังผลิต",
                    form: .photoReport, ppimSlot: 4),
        HomeDocSpec(id: "roofWeight", title: "ใบคำนวณน้ำหนักบนหลังคา (กก./ตร.ม.)", stage: .survey, provider: .engineer,
                    note: "≤ 20 กก./ตร.ม. ไม่ต้องขออนุญาตดัดแปลงอาคาร (กฎกระทรวง ฉบับที่ 72 พ.ศ. 2568)", form: .roofWeight),

        // ออกแบบ
        HomeDocSpec(id: "sld", title: "ชุดแบบไฟฟ้า วิศวกรลงนามทุกแผ่น: ปก · ผังติดตั้งแผง · Single Line Diagram · โครงสร้างหลังคา · รายละเอียดการยึดแผง",
                    stage: .design, provider: .engineer,
                    note: "SLD แสดงมิเตอร์กันไหลย้อน (zero export) + สายสื่อสาร และตารางสเปกแผง/อินเวอร์เตอร์ · ปกระบุชื่อโครงการ ขนาด kWp และพิกัด GPS",
                    ppimSlot: 6),
        HomeDocSpec(id: "engineerDocs", title: "เอกสารวิศวกรไฟฟ้า: สำเนาบัตรประชาชน + สำเนาใบอนุญาต กว. + หนังสือรับรองสภาวิศวกร",
                    stage: .design, provider: .engineer,
                    note: "สำเนาเซ็นรับรองและเขียนกำกับว่าใช้กับโครงการนี้ · ไฟฟ้ากำลัง ภาคีวิศวกรขึ้นไป · หนังสือรับรองใช้ได้ 120 วันนับจากวันออก · ต่อท้ายชุดแบบในไฟล์ช่อง 6",
                    ppimSlot: 6),
        HomeDocSpec(id: "equipment", title: "Datasheet อุปกรณ์เชื่อมต่อ: มิเตอร์กันไหลย้อน (smart power sensor) · RCBO/เบรกเกอร์ AC · AC SPD · DC fuse · DC SPD · DC breaker",
                    stage: .design, provider: .team,
                    note: "รวมเป็นไฟล์เดียวตามลำดับใน SLD", ppimSlot: 5),
        HomeDocSpec(id: "pvSpec", title: "Datasheet แผงโซลาร์ (ระบุมาตรฐาน มอก./IEC)", stage: .design, provider: .team,
                    ppimSlot: 8),
        HomeDocSpec(id: "inverterSpec", title: "Datasheet อินเวอร์เตอร์ / ผลทดสอบและรับรองผลิตภัณฑ์", stage: .design, provider: .team,
                    note: "รุ่นต้องอยู่ใน smartlist.pea.co.th", ppimSlot: 9),
        HomeDocSpec(id: "boq", title: "BOQ (Bill of quantities) จากแบบ", stage: .design, provider: .engineer,
                    note: "ร่างจากตารางแผง/อินเวอร์เตอร์ · ราคาจำจากงานก่อน · พิมพ์ฉบับต้นทุนและฉบับส่งลูกค้า", form: .boq),
        HomeDocSpec(id: "buildingPermit", title: "ขออนุญาตดัดแปลงอาคาร ข.1 → อ.1 (แบบและรายการคำนวณโยธา + โฉนด)", stage: .design, provider: .local,
                    note: "เฉพาะน้ำหนักเกิน 20 กก./ตร.ม. · ต้องได้ อ.1 ก่อนติดตั้ง", when: { $0.needsBuildingPermit == true }),

        // ยื่นขออนุญาต
        HomeDocSpec(id: "poa", title: "หนังสือมอบอำนาจ เซ็นสด + อากร 30 บาท + สำเนาบัตรผู้มอบและผู้รับมอบ", stage: .apply, provider: .customer,
                    form: .powerOfAttorney, when: { $0.teamFiles }),
        HomeDocSpec(id: "ppimRequest", title: "ยื่นคำขอใน PPIM และบันทึกเลขคำขอ", stage: .apply, provider: .team,
                    note: "แนบภาพหน้าจอส่วนที่ 1–5 และหน้าสถานะคำขอเก็บไว้ · ผลิตใช้เอง: PEA แจ้งผลภายใน 45 วันนับจากเอกสารครบ", when: selfUse),
        HomeDocSpec(id: "sellRequest", title: "ยื่นคำขอขายไฟใน PPIM และบันทึกเลขคำขอ (ล็อกขนาดที่เสนอ)", stage: .apply, provider: .team,
                    note: "เลข D… ระหว่างรออัปโหลด เปลี่ยนเป็น PPIM1A6… เมื่อเอกสารครบ · แผงไม่เกิน 10 kWp ยินยอมส่งข้อมูลให้สรรพากร", when: sell),
        HomeDocSpec(id: "peaApproval", title: "PEA อนุมัติคำขอ / ประกาศรายชื่อ", stage: .apply, provider: .pea,
                    note: "ขายไฟ: ประกาศภายใน 30 วันนับจากคำขอครบ · บันทึกวันประกาศเพื่อนับเส้นตาย 30 วัน"),
        HomeDocSpec(id: "feeReceipt", title: "ใบเสร็จค่าตรวจสอบการเชื่อมต่อ 2,140 บาท", stage: .apply, provider: .customer,
                    note: "ภายใน 30 วันนับจากประกาศ", when: sell),
        HomeDocSpec(id: "contract", title: "ส่งเอกสารสัญญา 2 ชุด และลงนามสัญญาซื้อขายไฟฟ้า", stage: .apply, provider: .customer,
                    note: "ภายใน 30 วันนับจากประกาศ ไม่ลงนาม = ยกเลิก", when: sell),

        // ติดตั้ง
        HomeDocSpec(id: "workOrder", title: "ใบสั่งงานผู้รับเหมา (ขอบเขต ค่าแรง วันเข้างาน) ผู้รับเหมาเซ็นรับ", stage: .install, provider: .team,
                    note: "ค่าแรงตั้งต้นจาก BOQ · ชุดแบบ Rev. ล่าสุด", form: .site, when: { $0.usesContractor }),
        HomeDocSpec(id: "delivery", title: "ใบส่งของ/รับวัสดุหน้างาน ตาม BOQ + S/N อินเวอร์เตอร์", stage: .install, provider: .team,
                    note: "นับจำนวนจริงเทียบ BOQ · ผู้รับเหมาเซ็นรับ", form: .site, when: { $0.usesContractor }),
        HomeDocSpec(id: "installLog", title: "บันทึกงานติดตั้งและรูประหว่างติดตั้ง", stage: .install, provider: .team, form: .installLog),
        HomeDocSpec(id: "exportLimiter", title: "ติดตั้งและตั้งค่าอุปกรณ์กันไหลย้อน (Export Limiter / zero export) + CT", stage: .install, provider: .team,
                    when: { $0.needsExportLimiter == true }),
        HomeDocSpec(id: "eTax", title: "e-Tax Invoice ในชื่อลูกค้า", stage: .install, provider: .team,
                    note: "ลดหย่อนภาษีสูงสุด 200,000 บาท แผงไม่เกิน 10 kWp", when: { $0.taxEligible }),
        HomeDocSpec(id: "icl", title: "ใบตรวจรับงาน (ICL)", stage: .install, provider: .team, form: .inspection),
        HomeDocSpec(id: "contractorAccept", title: "ปิด Punch list และตรวจรับงานผู้รับเหมา (ใช้วางบิลค่าแรง)", stage: .install, provider: .team,
                    note: "ค่าแรงตามใบสั่งงาน + ใบขอเปลี่ยนแปลงที่อนุมัติ − รายการหัก", form: .site, when: { $0.usesContractor }),

        // ขอเชื่อมต่อ
        HomeDocSpec(id: "selfCert", title: "แบบฟอร์มรับรองตนเอง VSPP + เอกสารแนบ 1–10 (วิศวกรเซ็นทุกแผ่น)", stage: .connect, provider: .engineer,
                    form: .selfCertification, when: sell),
        HomeDocSpec(id: "connectRequest", title: "ยื่นขออนุญาตเชื่อมต่อใน PPIM และบันทึกเลขคำขอ", stage: .connect, provider: .team,
                    note: "เลือกยืนยันข้อมูลเดิม หรือแก้ไขไม่เกินที่ยื่นขอขายไฟ (แนบแผง/อินเวอร์เตอร์/SLD ที่แก้)", when: sell),
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
