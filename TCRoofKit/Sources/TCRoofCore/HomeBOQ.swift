import Foundation

// BOQ (Bill of quantities) of a home job, made by the engineer from the design: the company's layout of nine
// sections, material and labour per line, totals with VAT. Two prints: the cost sheet (quantities and unit prices)
// and the customer sheet (each line as one lot, as the company sends it).

public struct HomeBOQ: Codable, Equatable, Sendable {
    public enum Section: Int, Codable, CaseIterable, Sendable {
        case module = 1, inverter, mounting, cable, conduit, combiner, testing, labor, management

        public var title: String {
            switch self {
            case .module: "PV Module"
            case .inverter: "Inverter & Accessories"
            case .mounting: "PV mounting Structure"
            case .cable: "Cable"
            case .conduit: "Conduit, Wireway"
            case .combiner: "DC/AC Combiner"
            case .testing: "Testing and Commission"
            case .labor: "Labors Cost"
            case .management: "Preliminaries and Project management"
            }
        }
    }

    public struct Line: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var section: Section
        public var description: String
        public var brand = ""
        public var unit = "Lot"
        /// 0 = a note under the line above (model, rating); it has no price.
        public var qty: Double = 1
        /// Unit prices, baht.
        public var material: Double = 0
        public var labor: Double = 0
        /// Priced inside another line (the sample's AC surge, DC CB and DC SPD inside the RCBO line): listed, no price.
        public var included = false

        public init(id: String = UUID().uuidString, section: Section, description: String, brand: String = "", unit: String = "Lot",
                    qty: Double = 1, material: Double = 0, labor: Double = 0, included: Bool = false) {
            self.id = id; self.section = section; self.description = description; self.brand = brand; self.unit = unit
            self.qty = qty; self.material = material; self.labor = labor; self.included = included
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            section = try c.decode(Section.self, forKey: .section)
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
            unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "Lot"
            qty = try c.decodeIfPresent(Double.self, forKey: .qty) ?? 1
            material = try c.decodeIfPresent(Double.self, forKey: .material) ?? 0
            labor = try c.decodeIfPresent(Double.self, forKey: .labor) ?? 0
            included = try c.decodeIfPresent(Bool.self, forKey: .included) ?? false
        }
        private enum CodingKeys: String, CodingKey { case id, section, description, brand, unit, qty, material, labor, included }

        public var isNote: Bool { qty == 0 }
        public var materialTotal: Double { included ? 0 : qty * material }
        public var laborTotal: Double { included ? 0 : qty * labor }
        public var amount: Double { materialTotal + laborTotal }
        /// Key of the price book: the description without spaces, dashes or case.
        public var priceKey: String { HomeLibrary.normalize(description) }
    }

    public var number = ""
    public var revision = 1
    public var issued: Date?
    public var validUntil: Date?
    public var customer = ""
    public var lines: [Line] = []
    public var overhead: Double = 0
    public var discount: Double = 0
    /// Cable runs the draft sizes PV and AC cable from, metres.
    public var dcRunM: Double = 20
    public var acRunM: Double = 20

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        issued = try c.decodeIfPresent(Date.self, forKey: .issued)
        validUntil = try c.decodeIfPresent(Date.self, forKey: .validUntil)
        customer = try c.decodeIfPresent(String.self, forKey: .customer) ?? ""
        lines = try c.decodeIfPresent([Line].self, forKey: .lines) ?? []
        overhead = try c.decodeIfPresent(Double.self, forKey: .overhead) ?? 0
        discount = try c.decodeIfPresent(Double.self, forKey: .discount) ?? 0
        dcRunM = try c.decodeIfPresent(Double.self, forKey: .dcRunM) ?? 20
        acRunM = try c.decodeIfPresent(Double.self, forKey: .acRunM) ?? 20
    }
    private enum CodingKeys: String, CodingKey {
        case number, revision, issued, validUntil, customer, lines, overhead, discount, dcRunM, acRunM
    }

    public static let vatRate = 0.07

    public var subtotal: Double { lines.reduce(0) { $0 + $1.amount } }
    public var total: Double { subtotal + overhead - discount }
    public var vat: Double { (total * Self.vatRate * 100).rounded() / 100 }
    public var grandTotal: Double { total + vat }

    /// Baht per Wp of the panels in the BOQ (before VAT); nil without panels.
    public var perWp: Double? { panelKWp.map { subtotal / ($0 * 1000) } }

    /// kWp of the module lines: the Wp in "… 575W" times the quantity.
    public var panelKWp: Double? {
        let rows = lines.filter { $0.section == .module && !$0.isNote && Self.watt(in: $0.description) != nil }
        guard !rows.isEmpty else { return nil }
        return rows.reduce(0) { $0 + Double(Self.watt(in: $1.description)!) * $1.qty } / 1000
    }

    /// "ZNSHINE SOLAR PANEL 575W" → 575.
    static func watt(in s: String) -> Int? {
        guard let r = s.range(of: #"(\d{3,4})\s*W(p)?\b"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Int(s[r].prefix { $0.isNumber })
    }

    public var projectTitle: String {
        "งานติดตั้งระบบไฟฟ้าจากพลังงานแสงอาทิตย์บนหลังคา (Solar Rooftop) ขนาด " + (panelKWp.map(Self.kw) ?? "…") + " kWp"
    }

    /// kWp with up to three decimals: 5.175, 5.13, 10.
    public static func kw(_ v: Double) -> String {
        var s = String(format: "%.3f", (v * 1000).rounded() / 1000)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    public func lines(_ section: Section) -> [Line] { lines.filter { $0.section == section } }

    // MARK: Checks

    public func issues(for job: HomeJob) -> [String] {
        var out: [String] = []
        if let kwp = panelKWp, let jobKWp = HomeJob.number(job.pvKWp), abs(kwp - jobKWp) > 0.005 {
            out.append("แผงใน BOQ \(Self.kw(kwp)) kWp ไม่ตรงกับงาน \(Self.kw(jobKWp)) kWp")
        }
        if panelKWp == nil { out.append("ยังไม่มีแผงในหมวด PV Module (ระบุวัตต์ เช่น 575W)") }
        if lines(.inverter).allSatisfy(\.isNote) { out.append("ยังไม่มีอินเวอร์เตอร์") }
        if job.needsExportLimiter == true,
           !lines(.inverter).contains(where: { Self.isExportControl($0.description) }) {
            out.append("ต้องมีอุปกรณ์กันไหลย้อน (smart meter / export limiter) ในหมวดอินเวอร์เตอร์")
        }
        let unpriced = lines.filter { !$0.isNote && !$0.included && $0.material == 0 && $0.labor == 0 }
        if !unpriced.isEmpty {
            out.append("ยังไม่มีราคา \(unpriced.count) รายการ: " + unpriced.prefix(3).map(\.description).joined(separator: ", ")
                       + (unpriced.count > 3 ? " …" : ""))
        }
        if let i = issued, let v = validUntil, v < i { out.append("วันที่สิ้นสุดอยู่ก่อนวันที่เสนอ") }
        return out
    }

    static func isExportControl(_ s: String) -> Bool {
        let n = s.lowercased()
        return ["smart meter", "smart energy", "power sensor", "export", "กันไหลย้อน", "zero"].contains { n.contains($0) }
    }

    // MARK: Draft from the design

    /// Lines from the job's PPIM tables and route, priced from the price book where it knows the line.
    public static func draft(job: HomeJob, prices: [String: HomeBOQPrice] = [:], dcRunM: Double = 20, acRunM: Double = 20) -> HomeBOQ {
        var b = HomeBOQ()
        b.dcRunM = dcRunM; b.acRunM = acRunM
        var l: [Line] = []
        for p in job.ppim.panels where !p.model.isEmpty || !p.watt.isEmpty {
            l.append(Line(section: .module, description: "\(p.brand.uppercased()) SOLAR PANEL \(p.watt)W".trimmingCharacters(in: .whitespaces),
                          brand: p.brand, unit: "Module", qty: HomeJob.number(p.count) ?? 0))
            if !p.model.isEmpty { l.append(Line(section: .module, description: "Model : \(p.model)", qty: 0)) }
        }
        l.append(Line(section: .module, description: "Fitting and accessories"))
        for i in job.ppim.inverters where !i.model.isEmpty {
            l.append(Line(section: .inverter, description: "\(i.brand) \(i.model)".trimmingCharacters(in: .whitespaces),
                          brand: i.brand, unit: "Pcs", qty: HomeJob.number(i.count) ?? 1))
        }
        if job.needsExportLimiter == true {
            l.append(Line(section: .inverter, description: "Smart meter / Export limiter (zero export) + CT", unit: "Set"))
        }
        l.append(Line(section: .inverter, description: "Fitting and accessories"))
        l.append(Line(section: .mounting, description: "Mounting", unit: "Job"))
        l.append(Line(section: .mounting, description: "Fitting and accessories"))
        let three = job.phase == .multi
        l.append(Line(section: .cable, description: "PV Cable 6 sq.mm. (Type H1Z2Z2-K)", unit: "m.", qty: dcRunM * 2))
        l.append(Line(section: .cable, description: three ? "AC Cable 4C (ขนาดตาม SLD) VCT-G" : "AC Cable 2C (ขนาดตาม SLD) VCT-G", unit: "m.", qty: acRunM))
        l.append(Line(section: .cable, description: "Ground Cable 1C THW (ขนาดตาม SLD)", unit: "m.", qty: acRunM / 2))
        l.append(Line(section: .cable, description: "Fitting and accessories"))
        l.append(Line(section: .conduit, description: "Conduit IMC (ขนาดตาม SLD)", unit: "m.", qty: acRunM))
        l.append(Line(section: .conduit, description: "Conduit fitting, Support and Accessories"))
        l.append(Line(section: .combiner, description: three ? "MCB AC / RCBO 4P (พิกัดตาม SLD)" : "MCB AC / RCBO 2P (พิกัดตาม SLD)", unit: "Pcs"))
        l.append(Line(section: .combiner, description: "AC Surge Type II", unit: "Pcs"))
        l.append(Line(section: .combiner, description: "DC CB (พิกัดตาม SLD)", unit: "Pcs"))
        l.append(Line(section: .combiner, description: "DC SPD Type II", unit: "Pcs"))
        l.append(Line(section: .combiner, description: "Fitting and accessories"))
        l.append(Line(section: .testing, description: "Testing and Commission", unit: "Job"))
        l.append(Line(section: .labor, description: "Labors Cost", unit: "Job"))
        l.append(Line(section: .management, description: "Preliminaries and Project management", unit: "Job"))
        b.lines = l.map { line in
            var x = line
            if !x.isNote, let p = prices[x.section.rawValue.description + ":" + x.priceKey] {
                x.material = p.material; x.labor = p.labor
            }
            return x
        }
        return b
    }

    /// Price-book entries for every priced line (keyed by section and description).
    public var priceBook: [String: HomeBOQPrice] {
        var out: [String: HomeBOQPrice] = [:]
        for l in lines where !l.isNote && !l.included && (l.material > 0 || l.labor > 0) {
            out[l.section.rawValue.description + ":" + l.priceKey] = HomeBOQPrice(material: l.material, labor: l.labor)
        }
        return out
    }

    // MARK: Customer sheet

    /// As sent to customers: each priced line one lot at its total (pieces keep their count), notes as they are.
    public var customerLines: [Line] {
        lines.map { l in
            guard !l.isNote, l.unit != "Pcs" else { return l }
            var x = l
            x.material = l.materialTotal; x.labor = l.laborTotal
            x.qty = 1; x.unit = "Lot"
            return x
        }
    }
}

/// Remembered unit prices of a BOQ line.
public struct HomeBOQPrice: Codable, Equatable, Sendable {
    public var material: Double
    public var labor: Double
    public init(material: Double, labor: Double) { self.material = material; self.labor = labor }
}
