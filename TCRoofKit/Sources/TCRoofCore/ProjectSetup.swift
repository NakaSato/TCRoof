import Foundation

/// A station's project facts as its plan file states them (the 102 PWA stations' `แผนโครงการ … (นำเข้า TCRoof).xlsx`,
/// sheet `แผนโครงการ`): the title line `แผนโครงการ P3-001 – <station> 163.02 kWp`, the set-up line
/// `กปภ.สาขาชัยบาดาล, ภาคเหนือ-กลาง, กฟภ. เขต น.3, Inverter 160 kW (ไม่ต้อง พค.2), Zero export HV, คำขอ PPIM…,
/// วิศวกร เปรม, Admin บีม, ผรม. B`, the installation points table and the Inverter station's type.
///
/// Every part is optional: an older `Master Plan Weekly` file has none of the lines, and a part the file leaves out
/// stays nil. Parts are told apart by their own words, not their place in the line.
public struct ProjectSetup: Equatable, Sendable {
    /// One row of the file's installation points table (`จุดติดตั้งของสถานีนี้`), a site type with any points.
    public struct Point: Equatable, Sendable {
        public var type: String
        public var count: Int
        public var modules: Int
        public var kWp: Double

        public init(type: String, count: Int, modules: Int = 0, kWp: Double = 0) {
            self.type = type; self.count = count; self.modules = modules; self.kWp = kWp
        }
    }

    /// The station's code in the 102-station list (`P3-001`).
    public var code: String?
    public var stationName: String?
    public var kWp: Double?
    /// The PWA branch as written (`กปภ.สาขาชัยบาดาล`).
    public var branch: String?
    /// `ภาคเหนือ-กลาง`, `ภาคอีสาน`, `ภาคใต้`.
    public var area: String?
    /// The PEA office the station connects through (`กฟภ. เขต น.3`).
    public var peaZone: String?
    public var inverterKW: Double?
    /// The line's `(ต้องยื่น พค.2)` / `(ไม่ต้อง พค.2)`.
    public var needsPK2: Bool?
    /// `HV` or `LV`.
    public var zeroExport: String?
    /// The PPIM request number (`PPIM1A5072BC`).
    public var ppimRequest: String?
    /// The team's engineer, the admin and the subcontractor's short name, as the file names them (not accounts).
    public var engineer: String?
    public var admin: String?
    public var contractor: String?
    /// The file's `OWNER` line (`การประปาส่วนภูมิภาค`).
    public var owner: String?
    public var points: [Point] = []
    /// The Inverter station's type (`สร้างใหม่ (E09)`) and its detail (`80+80 kW, โรงเรือน 9.00 × 2.50 ม., …`).
    public var inverterStation: String?
    public var inverterStationDetail: String?
    /// The file is one of the install cases (`แผนโครงการ P9-001 – แม่แบบ หลังคาลอนคู่, กันย้อน HV, …`), not a station's:
    /// its figures are examples, so the reader gives none of them.
    public var isTemplate = false

    public init() {}

    /// Nothing the app could take.
    public var isEmpty: Bool { self == ProjectSetup() }

    // MARK: reading the lines

    /// The title line and the set-up line of the `แผนโครงการ` sheet (A1, A2).
    public static func parse(title: String?, line: String?) -> ProjectSetup {
        var s = ProjectSetup()
        if let title { s.readTitle(title) }
        if let line { s.readLine(line) }
        return s
    }

    /// `แผนโครงการ P3-001 – <station> 163.02 kWp`.
    mutating func readTitle(_ title: String) {
        let t = Self.clean(title)
        guard t.hasPrefix("แผนโครงการ ") else { return }
        var rest = String(t.dropFirst("แผนโครงการ ".count))
        if let dash = rest.range(of: " – ") ?? rest.range(of: " - ") {
            let head = Self.clean(String(rest[..<dash.lowerBound]))
            if !head.isEmpty, !head.contains(" ") { code = head }
            rest = String(rest[dash.upperBound...])
        }
        if let k = rest.range(of: #"\s*[\d,]+(\.\d+)?\s*kWp$"#, options: .regularExpression) {
            kWp = Self.number(String(rest[k]).replacingOccurrences(of: "kWp", with: ""))
            rest = String(rest[..<k.lowerBound])
        }
        let name = Self.clean(rest)
        // an install case: its title names the case, and its code and kWp are the example's
        if name.hasPrefix("แม่แบบ ") { isTemplate = true; code = nil; kWp = nil; return }
        if !name.isEmpty { stationName = name }
    }

    /// An example's value rather than a station's: `กปภ.สาขา (ตัวอย่าง)`, `ตัวอย่าง`, `กฟภ. เขต ตย.01`, `คำขอ -`, and the
    /// install cases' roles in place of people (`วิศวกร วศ.01`, `Admin Admin`, `ผรม. 01`).
    static func isPlaceholder(_ v: String) -> Bool {
        let t = clean(v)
        return t.isEmpty || t == "-" || t == "–" || t == "ตัวอย่าง" || t.contains("(ตัวอย่าง)") || t.contains("ตย.")
            || t == "Admin" || t.range(of: #"^(วศ\.?\s*)?\d+$"#, options: .regularExpression) != nil
    }

    /// The comma-separated set-up line; a part this doesn't know is skipped.
    mutating func readLine(_ line: String) {
        for raw in line.components(separatedBy: ",") {
            let p = Self.clean(raw)
            guard let kind = Part(p) else { continue }
            let value = kind.value(of: p)
            if kind != .inverter, Self.isPlaceholder(value) { continue }
            switch kind {
            case .branch: branch = value
            case .area: area = value
            case .peaZone: peaZone = value
            case .inverter:
                if let m = p.range(of: #"[\d,]+(\.\d+)?(?=\s*kW)"#, options: .regularExpression) { inverterKW = Self.number(String(p[m])) }
                if p.contains("ต้องยื่น พค.2") { needsPK2 = true } else if p.contains("ไม่ต้อง") { needsPK2 = false }
            case .zeroExport: zeroExport = value
            case .ppim: ppimRequest = value
            case .engineer: engineer = value
            case .admin: admin = value
            case .contractor: contractor = value
            }
        }
    }

    /// The Weekly PLAN's `รหัส` line (`: P3-001, ผรม. B, วิศวกร เปรม, ข้อมูล ณ …`): fills the code, contractor and
    /// engineer where the set-up line didn't give them. `people` false takes only the code: a file with a set-up line
    /// names its people there, and one left out of it is no one, whatever the `รหัส` line still says.
    public mutating func readCodeLine(_ line: String, people: Bool = true) {
        for raw in line.components(separatedBy: ",") {
            var p = Self.clean(raw)
            if p.hasPrefix(":") { p = Self.clean(String(p.dropFirst())) }
            if code == nil, p.range(of: #"^P\d+-\d+$"#, options: .regularExpression) != nil { code = p; continue }
            guard people, let kind = Part(p), !Self.isPlaceholder(kind.value(of: p)) else { continue }
            if kind == .contractor, contractor == nil { contractor = kind.value(of: p) }
            if kind == .engineer, engineer == nil { engineer = kind.value(of: p) }
        }
    }

    /// A line with at least three parts of the set-up line: how the reader tells it from the sheet's other texts.
    public static func isSetupLine(_ line: String) -> Bool {
        line.components(separatedBy: ",").filter { Part(clean($0)) != nil }.count >= 3
    }

    /// The parts of the set-up line, by their own words.
    enum Part: CaseIterable {
        case branch, area, peaZone, inverter, zeroExport, ppim, engineer, admin, contractor

        init?(_ p: String) {
            if p.hasPrefix("กปภ.สาขา") || p.hasPrefix("การประปาส่วนภูมิภาคสาขา") { self = .branch }
            else if p.hasPrefix("ภาค") { self = .area }
            else if p.hasPrefix("กฟภ.") { self = .peaZone }
            else if p.hasPrefix("Inverter ") { self = .inverter }
            else if p.hasPrefix("Zero export ") { self = .zeroExport }
            else if p.hasPrefix("คำขอ ") { self = .ppim }
            else if p.hasPrefix("วิศวกร ") { self = .engineer }
            else if p.hasPrefix("Admin ") { self = .admin }
            else if p.hasPrefix("ผรม. ") || p.hasPrefix("ผรม ") { self = .contractor }
            else { return nil }
        }

        /// The word before the value, where the part has one.
        var prefix: String? {
            switch self {
            case .branch, .area, .peaZone, .inverter: nil
            case .zeroExport: "Zero export "
            case .ppim: "คำขอ "
            case .engineer: "วิศวกร "
            case .admin: "Admin "
            case .contractor: "ผรม. "
            }
        }

        func value(of p: String) -> String {
            guard let prefix else { return p }
            if self == .contractor, p.hasPrefix("ผรม "), !p.hasPrefix(prefix) { return ProjectSetup.clean(String(p.dropFirst(4))) }
            return ProjectSetup.clean(String(p.dropFirst(prefix.count)))
        }
    }

    // MARK: writing the lines back

    /// The set-up line with each part this has a value for put in, in the line's own order; parts it has no value for,
    /// and parts this doesn't know, are kept as they were. `dropPeople`: the engineer, admin and subcontractor this has
    /// none for are taken out instead, as a job's people are its own (a template's are another station's).
    public func rewrite(line: String, dropPeople: Bool = false) -> String {
        line.components(separatedBy: ",").compactMap { raw -> String? in
            let p = Self.clean(raw)
            guard let kind = Part(p) else { return p }
            if let new = part(kind, was: p) { return new }
            return dropPeople && [.engineer, .admin, .contractor].contains(kind) ? nil : p
        }.joined(separator: ", ")
    }

    /// The title line with this one's code, station and kWp where it has them.
    public func rewrite(title: String) -> String {
        var old = ProjectSetup()
        old.readTitle(title)
        guard Self.clean(title).hasPrefix("แผนโครงการ ") else { return title }
        // a case's title becomes the station's only with the station's name; its example code stays out
        if old.isTemplate {
            guard stationName != nil else { return title }
            old.code = nil
        }
        let c = code ?? old.code, n = stationName ?? old.stationName, k = kWp ?? old.kWp
        // the same facts keep the title as written (`182.40 kWp` stays, not `182.4`)
        let sameKWp = switch (k, old.kWp) { case let (a?, b?): abs(a - b) < 0.005; case (nil, nil): true; default: false }
        if c == old.code, n == old.stationName, sameKWp { return title }
        var t = "แผนโครงการ"
        if let c { t += " " + c + " –" }
        if let n { t += " " + n }
        if let k { t += " " + Self.format(k) + " kWp" }
        return t
    }

    /// One part written from this setup's value; nil when it has none.
    func part(_ kind: Part, was old: String) -> String? {
        switch kind {
        case .branch: return branch
        case .area: return area
        case .peaZone: return peaZone
        case .inverter:
            guard inverterKW != nil || needsPK2 != nil else { return nil }
            var current = ProjectSetup()
            current.readLine(old)
            let kw = inverterKW ?? current.inverterKW
            // a new size without the file's word on พค.2: the size decides it
            let pk2 = needsPK2 ?? (inverterKW != nil ? (kw ?? 0) >= 200 : current.needsPK2 ?? false)
            return "Inverter " + (kw.map(Self.format) ?? "") + " kW (" + (pk2 ? "ต้องยื่น พค.2" : "ไม่ต้อง พค.2") + ")"
        case .zeroExport: return zeroExport.map { "Zero export " + $0 }
        case .ppim: return ppimRequest.map { "คำขอ " + $0 }
        case .engineer: return engineer.map { "วิศวกร " + $0 }
        case .admin: return admin.map { "Admin " + $0 }
        case .contractor: return contractor.map { "ผรม. " + $0 }
        }
    }

    // MARK: helpers

    static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// `163.02`, `160`: no trailing zeros.
    public static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    /// The branch's own name, whichever way it is written: `กปภ.สาขาชัยบาดาล`, `การประปาส่วนภูมิภาคสาขาชัยบาดาล` and
    /// `สาขาชัยบาดาล` all give `ชัยบาดาล`.
    public static func branchName(_ s: String) -> String {
        var t = clean(s)
        for word in ["การประปาส่วนภูมิภาค", "กปภ.", "กปภ", "สาขา"] { t = t.replacingOccurrences(of: word, with: "") }
        return clean(t)
    }

    /// The daily reports' locations for the points: `<type> 1…n` per type with any.
    public var locations: [String] {
        points.flatMap { p in (1...max(1, p.count)).map { "\(p.type) \($0)" } }
    }
}
