import Foundation

// Working with the installer (ผู้รับเหมา) on a home job: the work order they sign, the materials they receive, the
// changes they ask for, the punch list they close and the acceptance that releases their labour payment.
// Signatures are taken on the team's device; files (signatures, photos) live in the job's permit folder.

/// One signature: who, when, and the PNG file of the strokes.
public struct HomeSignature: Codable, Equatable, Sendable {
    public var name: String
    public var file: String
    public var at: Date
    public init(name: String, file: String, at: Date = Date()) { self.name = name; self.file = file; self.at = at }
}

public struct HomeWorkOrder: Codable, Equatable, Sendable {
    public var number = ""
    public var contractor = ""
    public var contractorPhone = ""
    /// Who lets the crew in at the house.
    public var siteContact = ""
    public var start: Date?
    public var finish: Date?
    /// Agreed labour for the whole job, baht. Starts at the BOQ's labour total.
    public var labor: Double = 0
    /// What the crew does, one item a line.
    public var scope: [String] = []
    /// BOQ / drawing revision the crew works to.
    public var revision = 1
    public var notes = ""
    public var issued: Date?
    public var accepted: HomeSignature?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        contractor = try c.decodeIfPresent(String.self, forKey: .contractor) ?? ""
        contractorPhone = try c.decodeIfPresent(String.self, forKey: .contractorPhone) ?? ""
        siteContact = try c.decodeIfPresent(String.self, forKey: .siteContact) ?? ""
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        finish = try c.decodeIfPresent(Date.self, forKey: .finish)
        labor = try c.decodeIfPresent(Double.self, forKey: .labor) ?? 0
        scope = try c.decodeIfPresent([String].self, forKey: .scope) ?? []
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        issued = try c.decodeIfPresent(Date.self, forKey: .issued)
        accepted = try c.decodeIfPresent(HomeSignature.self, forKey: .accepted)
    }
    private enum CodingKeys: String, CodingKey {
        case number, contractor, contractorPhone, siteContact, start, finish, labor, scope, revision, notes, issued, accepted
    }

    /// The standard scope of a home rooftop job; the export-control line only when the job needs it.
    public static func standardScope(_ job: HomeJob) -> [String] {
        var s = ["ติดตั้งโครงยึดและแผงตามผังแผง Rev. ล่าสุด", "เดินสาย DC / AC / กราวด์ ในท่อตามแบบ",
                 "ติดตั้งอินเวอร์เตอร์และตู้ AC / DC ตาม SLD"]
        if job.needsExportLimiter == true { s.append("ติดตั้งและตั้งค่าอุปกรณ์กันไหลย้อน + CT") }
        s += ["ถ่ายรูป 9 หัวข้อและค่า Inverter Setting ในแอป", "ทดสอบก่อนเชื่อมต่อ เก็บกวาดหน้างาน"]
        return s
    }

    public var issues: [String] {
        var out: [String] = []
        if contractor.trimmingCharacters(in: .whitespaces).isEmpty { out.append("ยังไม่ระบุผู้รับเหมา") }
        if labor <= 0 { out.append("ยังไม่ระบุค่าแรงที่ตกลง") }
        if start == nil { out.append("ยังไม่ระบุวันเข้างาน") }
        if let s = start, let f = finish, f < s { out.append("วันเสร็จอยู่ก่อนวันเข้างาน") }
        return out
    }
}

/// Materials handed to the crew, counted against the BOQ's cost sheet.
public struct HomeDelivery: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var description: String
        public var unit: String
        /// Quantity the BOQ calls for.
        public var planned: Double
        public var delivered: Double?
        public var returned: Double = 0
        /// Serial numbers, for items that carry them (inverters, meters).
        public var serials: [String] = []
        public var needsSerials = false

        public init(id: String = UUID().uuidString, description: String, unit: String, planned: Double, needsSerials: Bool = false) {
            self.id = id; self.description = description; self.unit = unit; self.planned = planned; self.needsSerials = needsSerials
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
            planned = try c.decodeIfPresent(Double.self, forKey: .planned) ?? 0
            delivered = try c.decodeIfPresent(Double.self, forKey: .delivered)
            returned = try c.decodeIfPresent(Double.self, forKey: .returned) ?? 0
            serials = try c.decodeIfPresent([String].self, forKey: .serials) ?? []
            needsSerials = try c.decodeIfPresent(Bool.self, forKey: .needsSerials) ?? false
        }
        private enum CodingKeys: String, CodingKey { case id, description, unit, planned, delivered, returned, serials, needsSerials }

        public var short: Double { max(0, planned - (delivered ?? 0)) }
        /// Used on the roof: delivered less returned.
        public var used: Double { (delivered ?? 0) - returned }
    }

    public var items: [Item] = []
    public var deliveredOn: Date?
    public var received: HomeSignature?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        deliveredOn = try c.decodeIfPresent(Date.self, forKey: .deliveredOn)
        received = try c.decodeIfPresent(HomeSignature.self, forKey: .received)
    }
    private enum CodingKeys: String, CodingKey { case items, deliveredOn, received }

    /// Material lines of the BOQ (cost sheet): every priced or included line with a quantity, in the sections
    /// that are things, with the model note folded into the line above. Labour-only sections are left out.
    public static func from(_ boq: HomeBOQ) -> HomeDelivery {
        var d = HomeDelivery()
        let goods: Set<HomeBOQ.Section> = [.module, .inverter, .mounting, .cable, .conduit, .combiner]
        for l in boq.lines where goods.contains(l.section) {
            if l.isNote {
                if let last = d.items.indices.last { d.items[last].description += " · " + l.description }
                continue
            }
            let serial = l.section == .inverter && l.unit == "Pcs" || HomeBOQ.isExportControl(l.description)
            d.items.append(Item(description: l.description, unit: l.unit, planned: l.qty, needsSerials: serial))
        }
        return d
    }

    public var issues: [String] {
        var out: [String] = []
        for i in items where i.delivered != nil && i.short > 0 {
            out.append("ส่งไม่ครบ: \(i.description) ขาด \(HomeBOQ.kw(i.short)) \(i.unit)")
        }
        for i in items where i.needsSerials && (i.delivered ?? 0) > 0 {
            let filled = i.serials.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            if filled < Int(i.delivered ?? 0) { out.append("ยังไม่มี S/N ครบ: \(i.description)") }
        }
        if items.contains(where: { $0.returned > ($0.delivered ?? 0) }) { out.append("คืนของมากกว่าที่ส่ง") }
        return out
    }

    public var isComplete: Bool { !items.isEmpty && items.allSatisfy { $0.delivered != nil } && issues.isEmpty && received != nil }
}

/// A change the crew or the team asks for when the site differs from the drawings.
public struct HomeChange: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case pending, approved, rejected
        public var title: String {
            switch self {
            case .pending: "รออนุมัติ"
            case .approved: "อนุมัติ"
            case .rejected: "ไม่อนุมัติ"
            }
        }
    }

    public var id: String
    public var number: Int
    public var title: String
    public var reason = ""
    public var raisedBy = ""
    public var raised: Date
    public var photos: [String] = []
    /// Labour added (or taken off, negative) for the crew, baht.
    public var laborDelta: Double = 0
    /// Price change for the customer, baht before VAT.
    public var priceDelta: Double = 0
    /// New system sizes, when the change touches them.
    public var newPVKWp: Double?
    public var newInverterKW: Double?
    public var status: Status = .pending
    public var decidedBy = ""
    public var decided: Date?

    public init(id: String = UUID().uuidString, number: Int, title: String, raised: Date = Date()) {
        self.id = id; self.number = number; self.title = title; self.raised = raised
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        raisedBy = try c.decodeIfPresent(String.self, forKey: .raisedBy) ?? ""
        raised = try c.decodeIfPresent(Date.self, forKey: .raised) ?? Date()
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
        laborDelta = try c.decodeIfPresent(Double.self, forKey: .laborDelta) ?? 0
        priceDelta = try c.decodeIfPresent(Double.self, forKey: .priceDelta) ?? 0
        newPVKWp = try c.decodeIfPresent(Double.self, forKey: .newPVKWp)
        newInverterKW = try c.decodeIfPresent(Double.self, forKey: .newInverterKW)
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .pending
        decidedBy = try c.decodeIfPresent(String.self, forKey: .decidedBy) ?? ""
        decided = try c.decodeIfPresent(Date.self, forKey: .decided)
    }
    private enum CodingKeys: String, CodingKey {
        case id, number, title, reason, raisedBy, raised, photos, laborDelta, priceDelta, newPVKWp, newInverterKW, status, decidedBy, decided
    }

    public var changesSize: Bool { newPVKWp != nil || newInverterKW != nil }

    /// Why the change can't be approved as is; empty when it can.
    public func blockers(for job: HomeJob) -> [String] {
        var out: [String] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty { out.append("ยังไม่มีหัวข้อ") }
        if job.mode == .sell, let offer = job.offer {
            if let pv = newPVKWp, let filed = offer.pvKWp, pv > filed + 0.0001 {
                out.append("แผง \(HomeBOQ.kw(pv)) kWp เกินที่ยื่นขอขายไฟ \(HomeBOQ.kw(filed)) kWp")
            }
            if let inv = newInverterKW, let filed = offer.inverterKW, inv > filed + 0.0001 {
                out.append("อินเวอร์เตอร์ \(HomeBOQ.kw(inv)) kW เกินที่ยื่นขอขายไฟ \(HomeBOQ.kw(filed)) kW")
            }
        }
        return out
    }
}

/// One defect found at inspection, closed with an after photo.
public struct HomePunch: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var location = ""
    public var before: [String] = []
    public var after: [String] = []
    public var due: Date?
    public var closed: Date?
    /// When it was found; nil on a punch made before this was kept. Dates its post in the project feed.
    public var raised: Date?

    public init(id: String = UUID().uuidString, title: String, raised: Date? = nil) { self.id = id; self.title = title; self.raised = raised }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        before = try c.decodeIfPresent([String].self, forKey: .before) ?? []
        after = try c.decodeIfPresent([String].self, forKey: .after) ?? []
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        closed = try c.decodeIfPresent(Date.self, forKey: .closed)
        raised = try c.decodeIfPresent(Date.self, forKey: .raised)
    }
    private enum CodingKeys: String, CodingKey { case id, title, location, before, after, due, closed, raised }

    public var isOpen: Bool { closed == nil }
    /// Closing needs a photo of the fix.
    public var canClose: Bool { !after.isEmpty }
    public func isLate(on date: Date = Date()) -> Bool {
        guard isOpen, let due else { return false }
        return Calendar(identifier: .gregorian).startOfDay(for: due) < Calendar(identifier: .gregorian).startOfDay(for: date)
    }
}

/// Everything between the team and the crew on one job.
public struct HomeSite: Codable, Equatable, Sendable {
    public var workOrder = HomeWorkOrder()
    public var delivery = HomeDelivery()
    public var changes: [HomeChange] = []
    public var punches: [HomePunch] = []
    /// Deducted from the crew's payment (damage, missing items), baht.
    public var deductions: Double = 0
    public var deductionNote = ""
    public var accepted: HomeSignature?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workOrder = try c.decodeIfPresent(HomeWorkOrder.self, forKey: .workOrder) ?? HomeWorkOrder()
        delivery = try c.decodeIfPresent(HomeDelivery.self, forKey: .delivery) ?? HomeDelivery()
        changes = try c.decodeIfPresent([HomeChange].self, forKey: .changes) ?? []
        punches = try c.decodeIfPresent([HomePunch].self, forKey: .punches) ?? []
        deductions = try c.decodeIfPresent(Double.self, forKey: .deductions) ?? 0
        deductionNote = try c.decodeIfPresent(String.self, forKey: .deductionNote) ?? ""
        accepted = try c.decodeIfPresent(HomeSignature.self, forKey: .accepted)
    }
    private enum CodingKeys: String, CodingKey { case workOrder, delivery, changes, punches, deductions, deductionNote, accepted }

    public var nextChangeNumber: Int { (changes.map(\.number).max() ?? 0) + 1 }
    public var pendingChanges: [HomeChange] { changes.filter { $0.status == .pending } }
    public var approvedLaborDelta: Double { changes.filter { $0.status == .approved }.reduce(0) { $0 + $1.laborDelta } }
    public var approvedPriceDelta: Double { changes.filter { $0.status == .approved }.reduce(0) { $0 + $1.priceDelta } }
    public var openPunches: [HomePunch] { punches.filter(\.isOpen) }

    /// Labour owed to the crew: agreed, plus approved changes, less deductions.
    public var laborPayable: Double { workOrder.labor + approvedLaborDelta - deductions }

    /// What stands between the crew and their payment; empty when the job can be accepted.
    public var acceptanceBlockers: [String] {
        var out: [String] = []
        if workOrder.accepted == nil { out.append("ผู้รับเหมายังไม่เซ็นรับใบสั่งงาน") }
        if delivery.received == nil { out.append("ยังไม่มีลายเซ็นรับของ") }
        if !pendingChanges.isEmpty { out.append("มีใบขอเปลี่ยนแปลงรออนุมัติ \(pendingChanges.count) ใบ") }
        if !openPunches.isEmpty { out.append("Punch list ยังเปิดอยู่ \(openPunches.count) รายการ") }
        if laborPayable < 0 { out.append("ยอดหักมากกว่าค่าแรง") }
        return out
    }

    /// Approves a change; a change of size goes into the job (its BOQ is redrafted by the screen). Returns the
    /// blockers instead when it can't be approved.
    @discardableResult
    public mutating func approve(_ id: String, by name: String, job: inout HomeJob, on date: Date = Date()) -> [String] {
        guard let i = changes.firstIndex(where: { $0.id == id }) else { return ["ไม่พบใบขอเปลี่ยนแปลง"] }
        let blockers = changes[i].blockers(for: job)
        guard blockers.isEmpty else { return blockers }
        changes[i].status = .approved
        changes[i].decidedBy = name
        changes[i].decided = date
        if let pv = changes[i].newPVKWp { job.pvKWp = HomeBOQ.kw(pv) }
        if let inv = changes[i].newInverterKW { job.inverterKW = HomeBOQ.kw(inv) }
        if changes[i].changesSize { workOrder.revision += 1 }
        return []
    }

    public mutating func reject(_ id: String, by name: String, on date: Date = Date()) {
        guard let i = changes.firstIndex(where: { $0.id == id }) else { return }
        changes[i].status = .rejected
        changes[i].decidedBy = name
        changes[i].decided = date
    }
}
