import Foundation

/// The document library of a กปภ. (PWA) station job: which papers exist, who makes and signs them, which
/// submission each belongs to, and where each one stands. Catalog from the Project's `forms/pwa/catalog/`
/// (38 kinds, plus 6 from the PPA phase 3–4 tracking file) and the ERC พค.2 check list (23 items, `erc-pk2-checklist.json`).
///
/// Papers that are the same for every station (the PWA act, the engineer's license…) are kept once in the
/// device library and shown on every job; site papers belong to the job. Files themselves stay in the job's
/// documents (แฟ้มเอกสาร) or the library folder; this file only holds kinds, rules and states.
public enum StationDocs {

    // MARK: Kinds

    /// Who is the source of a paper, which decides what the app can do with it.
    public enum Origin: String, Codable, Sendable, CaseIterable {
        /// We make it and it ends with us (app, engineer, contractor).
        case internalDoc = "internal"
        /// We draft it, PWA signs, numbers or approves it.
        case signoff = "internal_signoff"
        /// We have to ask PWA, a government office or a maker for it; the app tracks and keeps the file.
        case external

        public var title: String {
            switch self {
            case .internalDoc: "ทีมเราทำ"
            case .signoff: "เราร่าง กปภ. ลงนาม"
            case .external: "ขอจากภายนอก"
            }
        }
    }

    /// How widely one file is reused.
    public enum Scope: String, Codable, Sendable, CaseIterable {
        case org, contractor, project, branch, site

        public var title: String {
            switch self {
            case .org: "ใช้ทั้ง กปภ."
            case .contractor: "ของบริษัท"
            case .project: "ใช้ทั้งโครงการ"
            case .branch: "ต่อ กปภ.สาขา"
            case .site: "ต่อสถานี"
            }
        }

        /// Kept once in the device library instead of per job.
        public var isShared: Bool { self != .site }
    }

    /// The submission (ชุดยื่น) a paper goes into.
    public enum Package: String, Codable, Sendable, CaseIterable, Identifiable {
        case gridConnection = "grid_connection", pk2, building, commissioning, handover

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .gridConnection: "ขนานไฟ"
            case .pk2: "พค.2"
            case .building: "อาคาร (อ.1 / แจ้งเทศบาล)"
            case .commissioning: "ทดสอบระบบ"
            case .handover: "ส่งมอบงาน"
            }
        }
    }

    /// When a kind applies only to some stations.
    public enum Condition: String, Codable, Sendable {
        case buildingPermit, buildingNotify, over200kVA
    }

    public struct Kind: Sendable, Identifiable, Equatable {
        public let id: String
        public let name: String
        public let origin: Origin
        public let scope: Scope
        public let packages: [Package]
        /// Who signs (internal papers) or must sign (sign-off papers).
        public let signBy: String?
        /// Where to ask for it (external papers).
        public let obtainFrom: String?
        public let expires: Bool
        public let condition: Condition?
        /// A short how-to shown under the name (privacy, reuse, what the app makes it from).
        public let note: String?

        init(_ id: String, _ name: String, _ origin: Origin, _ scope: Scope, _ packages: [Package],
             signBy: String? = nil, obtainFrom: String? = nil, expires: Bool = false,
             condition: Condition? = nil, note: String? = nil) {
            self.id = id; self.name = name; self.origin = origin; self.scope = scope; self.packages = packages
            self.signBy = signBy; self.obtainFrom = obtainFrom; self.expires = expires
            self.condition = condition; self.note = note
        }
    }

    public static let kinds: [Kind] = [
        // ภายใน — ทีมเราทำ
        Kind("site_map", "แผนผังแสดงที่ตั้ง / แผนที่ Google Map", .internalDoc, .site, [.gridConnection, .pk2],
             note: "ไฟล์เดียวใช้ทั้งขนานไฟและ พค.2 · ทำจากพิกัดในแบบสำรวจ"),
        Kind("layout_plan", "แผนผังบริเวณ (Layout) วิศวกรรับรอง", .internalDoc, .site, [.pk2], signBy: "วิศวกรไฟฟ้า"),
        Kind("route_line", "แผนผังรวมแปลงโฉนด (Route Line)", .internalDoc, .site, [.pk2], signBy: "วิศวกรไฟฟ้า"),
        Kind("sld", "Single Line Diagram + เอกสารวิศวกรไฟฟ้า", .internalDoc, .site, [.gridConnection, .pk2],
             signBy: "วิศวกรไฟฟ้า", note: "ไฟล์เดียวใช้ทั้งขนานไฟและ พค.2"),
        Kind("engineer_license", "สำเนาใบ กว. + หนังสือรับรองผู้ตรวจสอบ ตพค.", .internalDoc, .contractor,
             [.gridConnection, .pk2, .building], expires: true, note: "ต้องไม่หมดอายุ ณ วันยื่น"),
        Kind("elec_calc", "รายการคำนวณทางไฟฟ้า", .internalDoc, .site, [.handover]),
        Kind("asbuilt", "แบบ As-Built Drawing", .internalDoc, .site, [.handover, .pk2]),
        Kind("structural_plan", "แบบแปลนโครงสร้างรองรับ", .internalDoc, .site, [.building], signBy: "วิศวกรโยธา"),
        Kind("structural_calc", "รายการคำนวณโยธา", .internalDoc, .site, [.building], signBy: "วิศวกรโยธา"),
        Kind("spec_summary", "พิกัดขนาดติดตั้ง (Specification)", .internalDoc, .site, [.pk2],
             note: "ทำจากรายการอุปกรณ์ของสถานี"),
        Kind("install_photo_report", "รายงานภาพถ่ายติดตั้งระบบผลิตไฟฟ้า", .internalDoc, .site,
             [.gridConnection, .pk2, .handover], note: "ไฟล์เดียวใช้ทั้งขนานไฟ พค.2 และส่งมอบ"),
        Kind("iec62446_report", "ตารางตรวจสอบก่อน / หลังเชื่อมต่อ (IEC 62446)", .internalDoc, .site, [.commissioning, .handover]),
        Kind("iv_photo_report", "รายงานภาพถ่ายตรวจสอบก่อน / หลังเชื่อมต่อ", .internalDoc, .site, [.commissioning, .handover]),
        Kind("thermal_report", "ภาพถ่ายความร้อน", .internalDoc, .site, [.commissioning, .handover]),
        Kind("om_manual", "คู่มือการใช้งานและบำรุงรักษา", .internalDoc, .project, [.handover],
             note: "แยกตามภาค เลือกตามจังหวัดของสถานี"),
        Kind("pk_inspection_form", "แบบตรวจสอบระบบผลิตพลังงานควบคุม ส่วนที่ 1–3", .internalDoc, .site, [.pk2],
             signBy: "ผู้ตรวจสอบ ตพค.", condition: .over200kVA, note: "รูปหน้างานเติมช่องรูปในส่วนที่ 2 ได้"),
        Kind("vat_pp20", "ภพ.20", .internalDoc, .contractor, [.pk2]),
        Kind("erc_checklist", "Check list เอกสารประกอบคำขอ พค.2", .internalDoc, .site, [.pk2],
             condition: .over200kVA, note: "แอปติ๊กให้จากสถานะเอกสาร"),
        Kind("install_inspection_report", "รายงานตรวจสอบการติดตั้ง (ประกอบขนานไฟ)", .internalDoc, .site,
             [.gridConnection, .handover]),
        Kind("outage_letter", "หนังสือแจ้งดับไฟ (เลขที่ TC-PML-…)", .internalDoc, .site, [.gridConnection],
             note: "ใช้เมื่อต้องดับไฟเพื่อเชื่อมต่อ ถ้าไม่ต้องดับไฟ ตั้งเป็น “ไม่ใช้กับสถานีนี้”"),
        // ภายใน → ภายนอก — เราร่าง กปภ. ลงนาม
        Kind("poa_letter", "หนังสือมอบอำนาจ (ติดอากร)", .signoff, .site, [.building, .pk2], signBy: "ผจก. กปภ.สาขา"),
        Kind("building_permit_request", "คำขออนุญาตดัดแปลงอาคาร (ข.1) + หนังสือนำส่งเทศบาล", .signoff, .site,
             [.building], signBy: "ผจก. กปภ.สาขา", condition: .buildingPermit),
        Kind("building_exempt_notice", "หนังสือแจ้งเทศบาลติดตั้งตามกฎกระทรวงยกเว้น + สำเนา กว.", .signoff, .site,
             [.building], signBy: "ผจก. กปภ.สาขา", condition: .buildingNotify),
        Kind("punch_list", "Punch List Inspection Report", .signoff, .site, [.handover], signBy: "ผู้ว่าจ้าง"),
        Kind("pk2_readiness_letter", "หนังสือแจ้งความพร้อมให้เข้าตรวจ (นำส่ง กกพ.)", .signoff, .site, [.pk2],
             signBy: "ผจก. กปภ.สาขา", condition: .over200kVA, note: "ร่างจากข้อมูลสถานี ให้ กปภ. ออกเลขและลงนาม"),
        Kind("pk1_form", "คำขออนุญาต แบบ พค.1", .signoff, .site, [.pk2], signBy: "ผจก. กปภ.สาขา", condition: .over200kVA),
        Kind("anti_bribery", "หนังสือแสดงความมุ่งมั่นป้องกันสินบน", .signoff, .site, [.pk2],
             signBy: "ผจก. กปภ.สาขา", condition: .over200kVA),
        Kind("owner_signoff", "เอกสารเจ้าของพื้นที่ (ส่งผู้มีอำนาจ กปภ. ลงนาม)", .signoff, .site, [.gridConnection, .pk2],
             signBy: "ผู้มีอำนาจ กปภ."),
        Kind("self_cert_vspp", "หนังสือรับรองตนเอง (แบบ VSPP ของ กฟภ.)", .signoff, .site, [.gridConnection, .handover],
             signBy: "ผู้มีอำนาจ กปภ. · วิศวกรเซ็นรับรอง"),
        Kind("self_cert_k1", "หนังสือรับรองตนเอง ก.1", .signoff, .site, [.gridConnection], signBy: "ผู้มีอำนาจ กปภ."),
        // ภายนอก — ขอจาก กปภ. หน่วยงานรัฐ ผู้ผลิต
        Kind("pwa_act", "พ.ร.บ. การประปาส่วนภูมิภาค", .external, .org, [.gridConnection, .pk2], obtainFrom: "กปภ. ส่วนกลาง"),
        Kind("pwa_poa_order", "คำสั่ง กปภ. (มอบอำนาจ)", .external, .org, [.gridConnection, .pk2], obtainFrom: "กปภ. ส่วนกลาง",
             expires: true, note: "เปลี่ยนเมื่อมีคำสั่งฉบับใหม่"),
        Kind("grantor_docs", "เอกสารผู้มอบอำนาจ (บัตร / ทะเบียนบ้าน)", .external, .org, [.gridConnection, .pk2, .building],
             obtainFrom: "กปภ. ส่วนกลาง", note: "ปิดศาสนา กรุ๊ปเลือด วันเกิด ก่อนยื่น"),
        Kind("grantee_docs", "เอกสารผู้รับมอบอำนาจ (บัตร ผจก.สาขา)", .external, .branch, [.gridConnection, .pk2, .building],
             obtainFrom: "กปภ.สาขา", note: "ปิดศาสนา กรุ๊ปเลือด วันเกิด ก่อนยื่น"),
        Kind("electric_bill", "ใบแจ้งค่าไฟฟ้า (สำเนา)", .external, .site, [.gridConnection, .pk2], obtainFrom: "กปภ.สาขา",
             note: "ไฟล์เดียวใช้ทั้งขนานไฟและ พค.2"),
        Kind("land_deed", "สำเนาโฉนด / เอกสารสิทธิ์ที่ดิน", .external, .site, [.pk2, .building], obtainFrom: "กปภ.สาขา"),
        Kind("house_reg", "สำเนาทะเบียนบ้านของสถานที่ติดตั้ง", .external, .site, [.building, .pk2], obtainFrom: "กปภ.สาขา"),
        Kind("building_permit_o1", "ใบอนุญาตดัดแปลงอาคาร (อ.1) ที่ได้รับ", .external, .site, [.pk2, .building],
             obtainFrom: "เทศบาล / อบต.", condition: .buildingPermit),
        Kind("pv_datasheet", "Datasheet แผงเซลล์แสงอาทิตย์", .external, .project, [.gridConnection], obtainFrom: "ผู้ผลิตแผง"),
        Kind("inverter_datasheet", "Datasheet อินเวอร์เตอร์", .external, .project, [.gridConnection], obtainFrom: "ผู้ผลิตอินเวอร์เตอร์"),
        Kind("other_equipment", "Datasheet อุปกรณ์อื่น (ตู้ AC/DC, Zero Export, PQM, SPD)", .external, .project,
             [.gridConnection], obtainFrom: "ผู้ผลิตอุปกรณ์"),
        Kind("contract_mou", "MOU และใบสั่งจ้าง", .external, .project, [.pk2], obtainFrom: "กปภ. ส่วนกลาง"),
        Kind("erc_qr", "QR Code คำขอ (ระบบ กกพ.)", .external, .site, [.pk2], obtainFrom: "สำนักงาน กกพ.",
             condition: .over200kVA),
        Kind("outage_attachment", "เอกสารแนบหนังสือแจ้งดับไฟ", .external, .site, [.gridConnection],
             note: "ขอตามที่การไฟฟ้ากำหนด · ใช้คู่กับหนังสือแจ้งดับไฟ"),
    ]

    public static func kind(_ id: String) -> Kind? { kinds.first { $0.id == id } }

    // MARK: Station

    /// How the building side is handled; the เทศบาล decides.
    public enum BuildingRoute: String, Codable, Sendable, CaseIterable {
        case unknown, permit, notify

        public var title: String {
            switch self {
            case .unknown: "ยังไม่รู้"
            case .permit: "ขออนุญาต (อ.1)"
            case .notify: "แจ้งยกเว้น"
            }
        }
    }

    /// What kind of พค.2 request this is (check list items 2–4 and 20).
    public enum RequestType: String, Codable, Sendable, CaseIterable {
        case new, renew, renewLate, change

        public var title: String {
            switch self {
            case .new: "รายใหม่"
            case .renew: "ต่ออายุ"
            case .renewLate: "ต่ออายุล่าช้า"
            case .change: "ขยาย / เปลี่ยนแปลง"
            }
        }
    }

    /// Where a paper stands.
    public enum Status: String, Codable, Sendable, CaseIterable {
        case missing, requested, draft, signed, submitted, approved, notNeeded

        public var title: String {
            switch self {
            case .missing: "ยังไม่มี"
            case .requested: "ขอแล้ว รอรับ"
            case .draft: "ร่างแล้ว"
            case .signed: "ลงนามแล้ว"
            case .submitted: "ยื่นแล้ว"
            case .approved: "อนุมัติแล้ว"
            case .notNeeded: "ไม่ใช้กับสถานีนี้"
            }
        }

        /// Ready to go into a submission.
        public var isReady: Bool { self == .signed || self == .submitted || self == .approved }

        /// The states a kind can take: internal papers aren't "requested", external ones aren't "drafted".
        public static func choices(for origin: Origin) -> [Status] {
            switch origin {
            case .internalDoc: [.missing, .draft, .signed, .submitted, .approved, .notNeeded]
            case .signoff: [.missing, .draft, .requested, .signed, .submitted, .approved, .notNeeded]
            case .external: [.missing, .requested, .signed, .submitted, .approved, .notNeeded]
            }
        }
    }

    /// One paper's state. `fileName` names the file in the job's documents (site papers) or in the library.
    public struct DocState: Codable, Equatable, Sendable {
        public var status: Status
        public var fileName: String?
        public var expiresAt: Date?
        public var note: String
        public var updatedAt: Date?

        public init(status: Status = .missing, fileName: String? = nil, expiresAt: Date? = nil, note: String = "",
                    updatedAt: Date? = nil) {
            self.status = status; self.fileName = fileName; self.expiresAt = expiresAt; self.note = note
            self.updatedAt = updatedAt
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? .missing
            fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
            expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        }
    }

    /// A station's papers (site scope) and the facts that decide which papers it needs. Stored on the job.
    public struct Station: Codable, Equatable, Sendable {
        /// Inverters total 200 kVA or more: the station needs พค.2. Nil = take it from the job's inverter size.
        public var over200kVA: Bool?
        public var buildingRoute: BuildingRoute
        public var requestType: RequestType
        public var sellsPower: Bool
        /// SRT project (check list item 15 asks for the contract / purchase order).
        public var srtProject: Bool
        public var docs: [String: DocState]
        /// Package raw value → the day its papers are due, `yyyy-MM-dd` (Bangkok), where the team set one. A package
        /// without an entry is due on its task's planned start in the MP plan.
        public var dueDates: [String: String]

        public init(over200kVA: Bool? = nil, buildingRoute: BuildingRoute = .unknown, requestType: RequestType = .new,
                    sellsPower: Bool = false, srtProject: Bool = true, docs: [String: DocState] = [:], dueDates: [String: String] = [:]) {
            self.over200kVA = over200kVA; self.buildingRoute = buildingRoute; self.requestType = requestType
            self.sellsPower = sellsPower; self.srtProject = srtProject; self.docs = docs; self.dueDates = dueDates
        }

        /// The day the team set for a package's submission.
        public func due(_ package: Package) -> Date? {
            guard let n = dueDates[package.rawValue]?.split(separator: "-").compactMap({ Int($0) }), n.count == 3 else { return nil }
            return MasterSchedule.calendar.date(from: DateComponents(year: n[0], month: n[1], day: n[2]))
        }

        /// Sets a package's due day, or clears it with nil.
        public mutating func setDue(_ date: Date?, for package: Package) {
            dueDates[package.rawValue] = date.map {
                let c = MasterSchedule.calendar.dateComponents([.year, .month, .day], from: $0)
                return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            }
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            over200kVA = try c.decodeIfPresent(Bool.self, forKey: .over200kVA)
            buildingRoute = (try? c.decodeIfPresent(BuildingRoute.self, forKey: .buildingRoute)) ?? .unknown
            requestType = (try? c.decodeIfPresent(RequestType.self, forKey: .requestType)) ?? .new
            sellsPower = try c.decodeIfPresent(Bool.self, forKey: .sellsPower) ?? false
            srtProject = try c.decodeIfPresent(Bool.self, forKey: .srtProject) ?? true
            docs = try c.decodeIfPresent([String: DocState].self, forKey: .docs) ?? [:]
            dueDates = try c.decodeIfPresent([String: String].self, forKey: .dueDates) ?? [:]
        }

        public static func decode(_ json: String?) -> Station {
            guard let json, let data = json.data(using: .utf8),
                  let s = try? JSONDecoder().decode(Station.self, from: data) else { return Station() }
            return s
        }

        public var json: String? {
            guard let data = try? JSONEncoder().encode(self) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    /// The papers kept once on the device and shared by every station (org, branch, project and company scope).
    public struct Library: Codable, Equatable, Sendable {
        public var docs: [String: DocState]
        public init(docs: [String: DocState] = [:]) { self.docs = docs }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            docs = try c.decodeIfPresent([String: DocState].self, forKey: .docs) ?? [:]
        }
    }

    /// Station facts after filling in what wasn't set by hand.
    public struct Context: Equatable, Sendable {
        public var over200kVA: Bool
        public var buildingRoute: BuildingRoute
        public var requestType: RequestType
        public var sellsPower: Bool
        public var srtProject: Bool

        public init(_ station: Station, inverterKW: Double?) {
            over200kVA = station.over200kVA ?? ((inverterKW ?? 0) >= 200)
            buildingRoute = station.buildingRoute
            requestType = station.requestType
            sellsPower = station.sellsPower
            srtProject = station.srtProject
        }
    }

    /// Whether a station needs this paper at all.
    public static func applies(_ kind: Kind, _ ctx: Context) -> Bool {
        switch kind.condition {
        case nil: true
        case .over200kVA: ctx.over200kVA
        // until the เทศบาล has decided, both building papers stay on the list
        case .buildingPermit: ctx.buildingRoute != .notify
        case .buildingNotify: ctx.buildingRoute != .permit
        }
    }

    /// Packages a station takes part in: no พค.2 without 200 kVA.
    public static func packages(_ ctx: Context) -> [Package] {
        Package.allCases.filter { $0 != .pk2 || ctx.over200kVA }
    }

    /// The state of a paper for this station: shared papers come from the library.
    public static func state(_ kind: Kind, station: Station, library: Library) -> DocState {
        (kind.scope.isShared ? library.docs[kind.id] : station.docs[kind.id]) ?? DocState()
    }

    /// Papers of one package that this station needs, in catalog order (a paper used only for พค.2 is
    /// skipped when the station is under 200 kVA).
    public static func papers(in package: Package, _ ctx: Context) -> [Kind] {
        kinds.filter { $0.packages.contains(package) && applies($0, ctx) }
    }

    public struct Progress: Equatable, Sendable {
        public let ready: Int
        public let total: Int
        public var isComplete: Bool { total > 0 && ready == total }
    }

    /// Ready papers of a package. A paper marked "not needed" counts as neither.
    public static func progress(_ package: Package, station: Station, library: Library, _ ctx: Context) -> Progress {
        let states = papers(in: package, ctx).map { state($0, station: station, library: library) }
            .filter { $0.status != .notNeeded }
        return Progress(ready: states.filter(\.status.isReady).count, total: states.count)
    }

    // MARK: Expiry

    public enum Expiry: Equatable, Sendable {
        case expired, soon(days: Int)
    }

    /// Expired or expiring within `warnDays` (default 30), for kinds that expire.
    public static func expiry(_ kind: Kind, _ state: DocState, on date: Date = .now, warnDays: Int = 30,
                              calendar: Calendar = .current) -> Expiry? {
        guard kind.expires, let end = state.expiresAt else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: end)).day ?? 0
        if days < 0 { return .expired }
        return days <= warnDays ? .soon(days: days) : nil
    }

    // MARK: พค.2 check list

    /// One line of the ERC check list (form updated ต.ค. 2565), with the papers that satisfy it.
    public struct CheckItem: Sendable, Identifiable, Equatable {
        public let number: Int
        public let text: String
        public let docs: [String]
        public let when: CheckCondition?
        public var id: Int { number }

        init(_ number: Int, _ text: String, _ docs: [String] = [], when: CheckCondition? = nil) {
            self.number = number; self.text = text; self.docs = docs; self.when = when
        }
    }

    /// Check list lines that apply only to some requests.
    public enum CheckCondition: Sendable, Equatable {
        case request(RequestType), sellsPower, srtProject

        public func holds(_ ctx: Context) -> Bool {
            switch self {
            case .request(let t): ctx.requestType == t
            case .sellsPower: ctx.sellsPower
            case .srtProject: ctx.srtProject
            }
        }
    }

    public static let pk2Checklist: [CheckItem] = [
        CheckItem(1, "หนังสือแจ้งความพร้อมให้เข้าตรวจสถานประกอบกิจการ", ["pk2_readiness_letter"]),
        CheckItem(2, "ต่ออายุ: สำเนา พค.2 เดิม + รับรองข้อมูลขนาดกำลังผลิต", when: .request(.renew)),
        CheckItem(3, "ต่ออายุล่าช้า: แบบรายงานการผลิตพลังงานควบคุม", when: .request(.renewLate)),
        CheckItem(4, "ขยาย / เปลี่ยนแปลง: สำเนา พค.2 เดิม", when: .request(.change)),
        CheckItem(5, "คำขออนุญาต แบบ พค.1", ["pk1_form"]),
        CheckItem(6, "หน่วยงานรัฐ: หนังสือแสดงวัตถุประสงค์การจัดตั้ง", ["pwa_act"]),
        CheckItem(7, "มอบอำนาจ: หนังสือมอบอำนาจ ทะเบียนบ้าน บัตรผู้มอบ / ผู้รับ (ปิดข้อมูลอ่อนไหว)",
                  ["pwa_poa_order", "grantor_docs", "grantee_docs"]),
        CheckItem(8, "แผนผังบริเวณ (Layout) วิศวกรรับรอง", ["layout_plan"]),
        CheckItem(9, "แผนที่ (Google Map)", ["site_map"]),
        CheckItem(10, "Single Line Diagram วิศวกรรับรอง", ["sld"]),
        CheckItem(11, "สำเนาใบอนุญาตวิศวกรรมควบคุม", ["engineer_license"]),
        CheckItem(12, "พิกัดขนาดติดตั้ง (Specification)", ["spec_summary"]),
        CheckItem(13, "แบบตรวจสอบระบบผลิตพลังงานควบคุม (ประกาศ พพ. 31 ส.ค. 2565)", ["pk_inspection_form"]),
        CheckItem(14, "จำหน่ายไฟฟ้า: สัญญาซื้อขายไฟฟ้า", when: .sellsPower),
        CheckItem(15, "โครงการ SRT: สัญญา / ใบสั่งจ้าง", ["contract_mou"], when: .srtProject),
        CheckItem(16, "สำเนาทะเบียนบ้านของที่ตั้ง", ["house_reg"]),
        CheckItem(17, "สำเนาใบแจ้งค่าไฟฟ้า", ["electric_bill"]),
        CheckItem(18, "สำเนาโฉนด + หนังสือยินยอม (ถ้าที่ดินคนอื่น)", ["land_deed"]),
        CheckItem(19, "แผนผังรวมแปลงโฉนด (Route Line) วิศวกรรับรอง", ["route_line"]),
        CheckItem(20, "รายใหม่: Solar Rooftop ได้ยกเว้นผังเมือง", when: .request(.new)),
        CheckItem(21, "หนังสือมุ่งมั่นป้องกันสินบน", ["anti_bribery"]),
        CheckItem(22, "ไฟล์คำขอ + เอกสารประกอบ (ถ้ามี)"),
        CheckItem(23, "อื่นๆ: อ.1 · ภพ.20 · รายงานภาพถ่ายติดตั้ง",
                  ["building_permit_o1", "vat_pp20", "install_photo_report"]),
    ]

    public enum CheckState: Equatable, Sendable {
        /// Every paper is ready.
        case done
        /// Some papers aren't ready yet (names of the missing ones).
        case missing([String])
        /// Nothing in the app answers it; the team ticks it on the form.
        case manual
        /// Doesn't apply to this station.
        case notApplicable
    }

    /// The check list as the app would tick it: an item is done when every paper it needs is ready.
    /// A paper that doesn't apply (อ.1 when the เทศบาล only wants a notice) or is marked not needed is skipped.
    public static func check(_ item: CheckItem, station: Station, library: Library, _ ctx: Context) -> CheckState {
        if let when = item.when, !when.holds(ctx) { return .notApplicable }
        let needed = item.docs.compactMap(kind).filter { applies($0, ctx) }
            .filter { state($0, station: station, library: library).status != .notNeeded }
        if item.docs.isEmpty { return .manual }
        if needed.isEmpty { return .notApplicable }
        let missing = needed.filter { !state($0, station: station, library: library).status.isReady }
        return missing.isEmpty ? .done : .missing(missing.map(\.name))
    }
}
