import Foundation

// Papers that belong to the company or to a product model, not to one house: the engineer's ID, license and council
// certificate, and datasheets. Kept once in a library and attached to each job, so a job only collects what is its own.

public struct HomeLibrary: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case engineer, pvSpec, inverterSpec, equipment

        public var title: String {
            switch self {
            case .engineer: "เอกสารวิศวกรไฟฟ้า"
            case .pvSpec: "Datasheet แผง"
            case .inverterSpec: "Datasheet อินเวอร์เตอร์"
            case .equipment: "ชุด datasheet อุปกรณ์เชื่อมต่อ"
            }
        }

        /// What the item is named by.
        public var nameLabel: String {
            switch self {
            case .engineer: "ชื่อวิศวกร"
            case .pvSpec, .inverterSpec: "รุ่น (ตรงกับที่กรอก PPIM)"
            case .equipment: "ชื่อชุด เช่น Huawei 1 เฟส"
            }
        }

        /// The job document it stands in for.
        public var docID: String {
            switch self {
            case .engineer: "engineerDocs"
            case .pvSpec: "pvSpec"
            case .inverterSpec: "inverterSpec"
            case .equipment: "equipment"
            }
        }

        public init?(docID: String) {
            guard let k = Kind.allCases.first(where: { $0.docID == docID }) else { return nil }
            self = k
        }
    }

    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var kind: Kind
        public var name: String
        /// File names in the library folder, in file order.
        public var files: [String] = []
        /// Engineer: date of หนังสือรับรองสภาวิศวกร (valid 120 days).
        public var issued: Date?
        /// Used when nothing else picks one (engineer, equipment set).
        public var isDefault = false

        public init(id: String = UUID().uuidString, kind: Kind, name: String) {
            self.id = id; self.kind = kind; self.name = name
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            kind = try c.decode(Kind.self, forKey: .kind)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
            issued = try c.decodeIfPresent(Date.self, forKey: .issued)
            isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        }
        private enum CodingKeys: String, CodingKey { case id, kind, name, files, issued, isDefault }
    }

    public var items: [Item] = []
    /// BOQ unit prices remembered from earlier jobs (`HomeBOQ.priceBook`).
    public var prices: [String: HomeBOQPrice] = [:]
    /// The letterhead printed on the BOQ.
    public var company = HomeCompany()
    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        prices = try c.decodeIfPresent([String: HomeBOQPrice].self, forKey: .prices) ?? [:]
        company = try c.decodeIfPresent(HomeCompany.self, forKey: .company) ?? HomeCompany()
    }
    private enum CodingKeys: String, CodingKey { case items, prices, company }

    public func items(_ kind: Kind) -> [Item] { items.filter { $0.kind == kind } }
    public func item(_ id: String?) -> Item? { id.flatMap { id in items.first { $0.id == id } } }

    /// Lower case without spaces, dashes, dots or slashes, so "ZXM7-UHLD144 Series" finds "zxm7 uhld144".
    public static func normalize(_ s: String) -> String {
        s.lowercased().filter { !" -_./".contains($0) }
    }

    /// The item that fits the job's document: datasheets by the model typed for PPIM, otherwise the default (or the
    /// only one). Items without files never count.
    public func suggestion(for docID: String, job: HomeJob) -> Item? {
        guard let kind = Kind(docID: docID) else { return nil }
        let ready = items(kind).filter { !$0.files.isEmpty }
        switch kind {
        case .pvSpec: return match(ready, job.ppim.panels.map(\.model))
        case .inverterSpec: return match(ready, job.ppim.inverters.map(\.model))
        case .engineer, .equipment: return ready.first(where: \.isDefault) ?? (ready.count == 1 ? ready[0] : nil)
        }
    }

    private func match(_ ready: [Item], _ models: [String]) -> Item? {
        let wanted = models.map(Self.normalize).filter { !$0.isEmpty }
        return ready.first { item in
            let n = Self.normalize(item.name)
            return !n.isEmpty && wanted.contains { $0.contains(n) || n.contains($0) }
        }
    }

    /// Days the engineer's council certificate has left; nil without a date.
    public static func daysLeft(issued: Date?, on date: Date = Date()) -> Int? {
        guard let issued else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: issued), to: cal.startOfDay(for: date)).day ?? 0
        return HomeJob.coeCertValidDays - days
    }
}

/// Letterhead of the company's documents.
public struct HomeCompany: Codable, Equatable, Sendable {
    public var nameTH = ""
    public var nameEN = ""
    public var address = ""
    public var phone = ""
    public var taxID = ""
    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nameTH = try c.decodeIfPresent(String.self, forKey: .nameTH) ?? ""
        nameEN = try c.decodeIfPresent(String.self, forKey: .nameEN) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        taxID = try c.decodeIfPresent(String.self, forKey: .taxID) ?? ""
    }
    private enum CodingKeys: String, CodingKey { case nameTH, nameEN, address, phone, taxID }

    public var isEmpty: Bool { nameTH.isEmpty && nameEN.isEmpty }
}

// MARK: - What to do next

/// One line of the job's "ต้องทำต่อ" card.
public struct HomeAction: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case overdue, issue, deadline, document }
    public let id: String
    public let kind: Kind
    public let title: String
    public var detail: String?
    /// The document row it opens, if any.
    public var docID: String?
}

extension HomeJob {
    /// The few things that need the team now, most urgent first: missed deadlines, problems with the job's answers,
    /// deadlines within a week, then the documents the current stage still lacks.
    public func nextActions(on date: Date = Date(), limit: Int = 5) -> [HomeAction] {
        var out: [HomeAction] = []
        let deadlines = sellDeadlines.filter { !$0.done }
        for d in deadlines where d.daysLeft(on: date) < 0 {
            out.append(HomeAction(id: "late-" + d.id, kind: .overdue, title: d.title, detail: "เลยกำหนด \(-d.daysLeft(on: date)) วัน"))
        }
        for issue in issues(on: date) where !issue.hasPrefix("เลยกำหนด") {
            out.append(HomeAction(id: "issue-" + issue, kind: .issue, title: issue))
        }
        for d in deadlines where (0...7).contains(d.daysLeft(on: date)) {
            let left = d.daysLeft(on: date)
            out.append(HomeAction(id: "due-" + d.id, kind: .deadline, title: d.title, detail: left == 0 ? "ครบกำหนดวันนี้" : "เหลือ \(left) วัน"))
        }
        if let stage = currentStage {
            for spec in missing(in: stage) {
                out.append(HomeAction(id: "doc-" + spec.id, kind: .document, title: spec.title,
                                      detail: stage.title + " | " + spec.provider.title, docID: spec.id))
            }
        }
        return Array(out.prefix(limit))
    }

    /// Fills library-backed documents that are still empty with the library's suggestion; drops picks whose item is
    /// gone. Returns the documents it picked for.
    @discardableResult
    public mutating func applyLibrary(_ library: HomeLibrary) -> [String] {
        var picked: [String] = []
        // "" = the team chose not to use the library for that document; keep it so it isn't picked again
        for (doc, id) in libraryPicks where !id.isEmpty && library.item(id) == nil { libraryPicks[doc] = nil }
        for spec in checklist {
            guard HomeLibrary.Kind(docID: spec.id) != nil, libraryPicks[spec.id] == nil,
                  document(spec.id).files.isEmpty, let item = library.suggestion(for: spec.id, job: self) else { continue }
            libraryPicks[spec.id] = item.id
            picked.append(spec.id)
        }
        for (doc, id) in libraryPicks where !document(doc).status.isDone {
            guard library.item(id) != nil else { continue }
            var d = document(doc)
            d.status = .received
            d.updatedAt = Date()
            documents[doc] = d
        }
        if let engineer = library.item(libraryPicks["engineerDocs"]), let issued = engineer.issued { coeCertIssued = issued }
        return picked
    }
}
