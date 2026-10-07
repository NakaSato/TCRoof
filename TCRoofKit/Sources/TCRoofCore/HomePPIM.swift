import Foundation

// What a residential self-use request needs besides the uploads: the answers typed into PPIM part 3, and the photo
// pages of part 4 slot 4. Both follow a filed request (PPIM screens and the pages uploaded with it).

/// PPIM part 3 (ระบุข้อมูลเครื่องกำเนิดไฟฟ้า): the values the team types in, kept with the job.
public struct PPIMEntry: Codable, Equatable, Sendable {
    public struct Panel: Codable, Equatable, Sendable {
        public var type = "Mono"
        public var brand = ""
        public var model = ""
        /// Wp per panel.
        public var watt = ""
        public var count = ""
        public init() {}
        public var kWp: Double? {
            guard let w = HomeJob.number(watt), let n = HomeJob.number(count) else { return nil }
            return w * n / 1000
        }
    }

    public struct Inverter: Codable, Equatable, Sendable {
        public var brand = ""
        public var model = ""
        public var kW = ""
        public var count = "1"
        public init() {}
        public var total: Double? {
            guard let k = HomeJob.number(kW), let n = HomeJob.number(count) else { return nil }
            return k * n
        }
    }

    /// หมายเลขเครื่องวัด (PEA No.) on the meter.
    public var peaMeterNo = ""
    public var latitude = ""
    public var longitude = ""
    public var panels: [Panel] = [Panel()]
    public var inverters: [Inverter] = [Inverter()]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        peaMeterNo = try c.decodeIfPresent(String.self, forKey: .peaMeterNo) ?? ""
        latitude = try c.decodeIfPresent(String.self, forKey: .latitude) ?? ""
        longitude = try c.decodeIfPresent(String.self, forKey: .longitude) ?? ""
        panels = try c.decodeIfPresent([Panel].self, forKey: .panels) ?? [Panel()]
        inverters = try c.decodeIfPresent([Inverter].self, forKey: .inverters) ?? [Inverter()]
    }
    private enum CodingKeys: String, CodingKey { case peaMeterNo, latitude, longitude, panels, inverters }

    /// กำลังการผลิตทั้งหมด (kWp) of the panel table; nil while a row is incomplete.
    public var panelKWp: Double? {
        let rows = panels.map(\.kWp)
        guard !rows.isEmpty, !rows.contains(where: { $0 == nil }) else { return nil }
        return rows.compactMap { $0 }.reduce(0, +)
    }

    /// กำลังการผลิตทั้งหมด (kW) of the inverter table: PPIM's requested size.
    public var inverterKW: Double? {
        let rows = inverters.map(\.total)
        guard !rows.isEmpty, !rows.contains(where: { $0 == nil }) else { return nil }
        return rows.compactMap { $0 }.reduce(0, +)
    }

    /// Thailand's extent, for catching swapped or mistyped coordinates.
    public static let latRange = 5.5...20.5
    public static let longRange = 97.3...105.7

    public var coordinate: (lat: Double, long: Double)? {
        guard let la = HomeJob.number(latitude), let lo = HomeJob.number(longitude) else { return nil }
        return (la, lo)
    }

    public var issues: [String] {
        var out: [String] = []
        if let c = coordinate {
            if Self.latRange.contains(c.long) && Self.longRange.contains(c.lat) {
                out.append("ละติจูดกับลองจิจูดสลับกัน")
            } else if !Self.latRange.contains(c.lat) || !Self.longRange.contains(c.long) {
                out.append("พิกัดไม่อยู่ในประเทศไทย")
            }
        }
        if !peaMeterNo.isEmpty && !peaMeterNo.allSatisfy(\.isNumber) { out.append("หมายเลขเครื่องวัดเป็นตัวเลขเท่านั้น") }
        return out
    }

    /// The meter voltage PPIM lists for the job's phase (the 3-phase choice is as on the screen).
    public static func meterVoltage(_ phase: SelfCertification.Phase?) -> String? {
        switch phase {
        case .multi: "380 V (3 phase)"
        case .single: "230 V (1 phase)"
        case nil: nil
        }
    }

    /// Answers that are the same on every residential self-use request, as (question, answer).
    public static let fixedAnswers: [(String, String)] = [
        ("ประเภทการขอเชื่อมต่อ", "เชื่อมต่อใหม่"),
        ("เจ้าของเครื่องกำเนิดไฟฟ้า", "ผู้ใช้ไฟฟ้าเป็นเจ้าของเครื่องกำเนิดไฟฟ้า (IPU)"),
        ("ประเภทเชื้อเพลิง", "พลังงานแสงอาทิตย์"),
        ("รูปแบบการติดตั้ง", "ติดตั้งบนหลังคา (Solar PV Rooftop)"),
        ("ระบบป้องกันการจ่ายกระแสไฟฟ้าไหลย้อน", "Zero Export Controller"),
        ("ส่วนที่ 5 การรับรอง", "ติ๊กยอมรับครบทั้ง 9 ข้อ"),
    ]
}

/// Slot 4's photo pages: A4, a centred project header, then two titled sections a page, each with one or two photos.
public struct PhotoReport: Codable, Equatable, Sendable {
    public struct Section: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        /// File names in the job's permit folder, at most `PhotoReport.maxPhotos`.
        public var photos: [String] = []
        /// Standard sections must have a photo once the system is installed.
        public var required = true

        public init(id: String, title: String, required: Bool = true) {
            self.id = id; self.title = title; self.required = required
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
            required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? true
        }
        private enum CodingKeys: String, CodingKey { case id, title, photos, required }
    }

    public static let maxPhotos = 2

    /// The nine shots of an installed system, in page order, then optional ones.
    public static let standard: [Section] = [
        Section(id: "panels", title: "ภาพถ่ายแผงเซลล์แสงอาทิตย์"),
        Section(id: "inverter", title: "ภาพถ่ายเครื่องแปลงไฟฟ้า Inverter"),
        Section(id: "inverterSN", title: "ภาพถ่ายเครื่องแปลงไฟฟ้า Inverter (Serial No.)"),
        Section(id: "dcGround", title: "ภาพถ่ายกราวด์กระแสตรง"),
        Section(id: "acInside", title: "ภาพถ่ายตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสสลับ (ด้านใน)"),
        Section(id: "acOutside", title: "ภาพถ่ายตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสสลับ (ด้านนอก)"),
        Section(id: "dcInside", title: "ภาพถ่ายตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสตรง (ด้านใน)"),
        Section(id: "dcOutside", title: "ภาพถ่ายตู้ควบคุมและบริภัณฑ์ไฟฟ้ากระแสตรง (ด้านนอก)"),
        Section(id: "connection", title: "ภาพถ่ายจุดเชื่อมต่อระบบโซลาร์เซลล์"),
        Section(id: "meter", title: "ภาพถ่ายมิเตอร์กันไหลย้อน (Smart Power Sensor)", required: false),
        Section(id: "site", title: "ภาพถ่ายสถานที่ตั้งโครงการ", required: false),
    ]

    public static let defaultTitle = "โครงการติดตั้งระบบผลิตไฟฟ้าพลังงานแสงอาทิตย์บนหลังคา (Solar Rooftop Project)"

    public var projectTitle = PhotoReport.defaultTitle
    /// Second header line: the installation address as on the drawings.
    public var address = ""
    public var sections: [Section] = PhotoReport.standard

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectTitle = try c.decodeIfPresent(String.self, forKey: .projectTitle) ?? Self.defaultTitle
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        var saved = try c.decodeIfPresent([Section].self, forKey: .sections) ?? []
        // standard sections added later appear in their place
        for (i, s) in Self.standard.enumerated() where !saved.contains(where: { $0.id == s.id }) {
            saved.insert(s, at: min(i, saved.count))
        }
        sections = saved
    }
    private enum CodingKeys: String, CodingKey { case projectTitle, address, sections }

    /// Header lines, centred: project, address, size.
    public func header(kWp: Double?) -> [String] {
        var lines = [projectTitle]
        if !address.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(address) }
        if let kWp { lines.append("ขนาดกำลังการผลิตติดตั้ง \(Self.format(kWp)) กิโลวัตต์") }
        return lines
    }

    static func format(_ v: Double) -> String {
        let s = String(format: "%.2f", v)
        var t = s
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t
    }

    public var filled: [Section] { sections.filter { !$0.photos.isEmpty } }
    /// Required sections without a photo.
    public var missing: [Section] { sections.filter { $0.required && $0.photos.isEmpty } }
    public var photoCount: Int { sections.reduce(0) { $0 + $1.photos.count } }

    /// Sections with photos, two a page.
    public var pages: [[Section]] {
        let f = filled
        return stride(from: 0, to: f.count, by: 2).map { Array(f[$0..<min($0 + 2, f.count)]) }
    }

    public mutating func add(_ photo: String, to id: String) {
        guard let i = sections.firstIndex(where: { $0.id == id }), sections[i].photos.count < Self.maxPhotos else { return }
        sections[i].photos.append(photo)
    }

    public mutating func remove(_ photo: String) {
        for i in sections.indices { sections[i].photos.removeAll { $0 == photo } }
    }

    // MARK: Page geometry (PDF points, top-left origin), measured from the filed pages

    public static let pageSize: [Double] = [595.32, 841.92]
    public static let headerTop = 71.0
    public static let headerLineHeight = 21.0
    public static let titleFontSize = 13.0

    /// The section's title box and photo area, for slot 0 (upper) or 1 (lower) of a page.
    public static func frame(slot: Int) -> (title: [Double], area: [Double]) {
        slot == 0
            ? ([60, 158, 475.32, 22], [82, 190, 431.32, 246])
            : ([60, 452, 475.32, 22], [82, 488, 431.32, 246])
    }

    /// One photo fills the area; two landscape photos stack, otherwise they sit side by side.
    /// `aspects` are width / height of the photos, in order.
    public static func layout(aspects: [Double]) -> PhotoLayout {
        switch aspects.count {
        case ...1: .single
        default: aspects.prefix(2).allSatisfy { $0 >= 1.15 } ? .stack2 : .side2
        }
    }

    /// The largest rect of `aspect` inside `cell`, centred.
    public static func fit(aspect: Double, in cell: [Double]) -> [Double] {
        guard aspect > 0, cell[2] > 0, cell[3] > 0 else { return cell }
        var w = cell[2], h = w / aspect
        if h > cell[3] { h = cell[3]; w = h * aspect }
        return [cell[0] + (cell[2] - w) / 2, cell[1] + (cell[3] - h) / 2, w, h]
    }

    /// Photo rects of one section, aspect-fit in their cells.
    public static func photoRects(slot: Int, aspects: [Double], gap: Double = 6) -> [[Double]] {
        let area = frame(slot: slot).area
        let cells = layout(aspects: aspects).cells(in: area, count: min(aspects.count, maxPhotos), gap: gap)
        return zip(cells, aspects).map { fit(aspect: $1, in: $0) }
    }
}
