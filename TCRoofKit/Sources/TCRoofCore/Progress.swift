import Foundation

public struct Completion: Hashable, Sendable {
    public var filled: Int
    public var total: Int
    public init(filled: Int = 0, total: Int = 0) { self.filled = filled; self.total = total }
    public var fraction: Double { total == 0 ? 0 : Double(filled) / Double(total) }
    public var percent: Int { Int((fraction * 100).rounded()) }
    public var isComplete: Bool { total > 0 && filled >= total }
    public static func + (a: Completion, b: Completion) -> Completion { Completion(filled: a.filled + b.filled, total: a.total + b.total) }
}

public extension GroupSpec {
    func completion(_ v: Values) -> Completion {
        fields.reduce(into: Completion()) { c, f in
            guard f.isRequired(v) else { return }
            c.total += 1
            if f.isFilled(v) { c.filled += 1 }
        }
    }
    /// Required fields that are still empty (shown as "ยังไม่กรอก").
    func missing(_ v: Values) -> [FieldSpec] { fields.filter { $0.isRequired(v) && !$0.isFilled(v) } }
}

public extension ModuleSpec {
    func completion(_ v: Values) -> Completion { groups.reduce(Completion()) { $0 + $1.completion(v) } }
}

public extension SurveyModule {
    var spec: ModuleSpec { Schema.spec(type) }
    /// B4 also counts `photoDetail`, which the schema leaves optional for old jobs (`ZeroExport`).
    var completion: Completion { spec.completion(values) + (type == .backfeed ? ZeroExport.extraCompletion(values) : Completion()) }
    /// "ตู้ไฟฟ้า โรงสูบน้ำ"
    var title: String { name.isEmpty ? spec.short : spec.short + " · " + name }
}

public extension Job {
    var coverCompletion: Completion { [Schema.info, Schema.site, Schema.electrical, Schema.flood].reduce(Completion()) { $0 + $1.completion(values) } }
    var finalCompletion: Completion { Schema.final.completion(values) }
    var completion: Completion { modules.reduce(coverCompletion + finalCompletion) { $0 + $1.completion } }
    var photoCount: Int { allPhotos.count }
    /// Everything still to fill or fix, as "page: item" lines — the same list the export sheet shows.
    var missingItems: [String] { missingGroups.flatMap { g in g.items.map { g.title + ": " + $0 } } }
    /// Key facts of a section in one line, for the one-page summary.
    func facts(_ m: SurveyModule) -> String {
        let d = m.values
        func o(_ id: String) -> String { d.choice(id) == "อื่นๆ" ? (d.other(id).isEmpty ? "อื่นๆ" : d.other(id)) : (d.choice(id) ?? "") }
        func t(_ id: String) -> String { d.text(id).trimmingCharacters(in: .whitespaces) }
        func j(_ parts: String?...) -> String { parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
        func span(_ id: String) -> Double { parseSpans(d.text(id)).reduce(0, +) }
        let size: String? = span("spansX") > 0 && span("spansY") > 0 ? "\(fmt(span("spansX"))) x \(fmt(span("spansY"))) ม." : nil
        switch m.type {
        case .panel: return j(t("breakerAT").isEmpty ? nil : "เบรกเกอร์เมน \(t("breakerAT")) AT", t("loadKW").isEmpty ? nil : "โหลด \(t("loadKW")) kW" + (t("loadTime").isEmpty ? "" : " @" + t("loadTime")))
        case .inverter where InverterStation.isDesigned(d):
            let s = InverterStation(d)
            return j(s.sizesAssumed ? "\(s.sizes.count) เครื่อง" : s.sizesText, t("sizeLWH").isEmpty ? nil : "พื้นที่ " + t("sizeLWH"), s.minimumText, s.fits ? nil : "พื้นที่ไม่พอ")
        case .inverter:
            let n = d.number("inverterCount")
            return j(n.map { "\(fmt($0)) เครื่อง" }, t("sizeLWH").isEmpty ? nil : "พื้นที่ " + t("sizeLWH"), n.map { "ต้องการ \(String(format: "%.2f", 1.5 * $0 + 1.5)) x 2.00 ม." })
        case .water: return o("waterMode")
        case .backfeed: return j(o("level"), o("pole"))
        case .fts: return j(d.photo("photoEmg") != nil ? "มีภาพปุ่ม Emergency" : nil, t("emgPlace").isEmpty ? nil : t("emgPlace"),
                            d.photo("photoFTS") != nil ? "มีภาพตู้ FTS" : nil)
        case .roof: return j(o("roofShape"), o("roofMaterial"), o("roofStructure"), t("panelsBefore").isEmpty ? nil : "แผง \(t("panelsBefore"))" + (t("panelsCut").isEmpty ? "" : " (ตัด \(t("panelsCut")))"), size)
        case .tank: return j(Schema.tankKind(d), t("tankHeight").isEmpty ? nil : "สูง \(t("tankHeight")) ม.", t("surface"), size, d.obstacles("obst").isEmpty ? nil : "สิ่งกีดขวาง \(d.obstacles("obst").count) จุด", Schema.shadeText(d))
        case .sed: return j(t("distA").isEmpty || t("distB").isEmpty ? nil : "บ่อ \(t("distA")) x \(t("distB")) ซม.")
        case .house: return j(o("buildingType"), o("roofShape"), o("roofMaterial"), t("mainBreaker").isEmpty ? nil : "เมน \(t("mainBreaker")) A", o("facing").isEmpty ? nil : "หันทิศ" + o("facing"))
        case .roofForm: return j(o("roofShape"), o("roofMaterial"), o("facing").isEmpty ? nil : "หันทิศ" + o("facing"),
                                 t("panelAreaWidth").isEmpty || t("panelAreaLength").isEmpty ? nil : "พื้นที่ \(t("panelAreaWidth")) x \(t("panelAreaLength")) ซม.")
        }
    }
    /// "TR1: ด้านหลัง, ป้ายพิกัด (Nameplate)" for each transformer still missing required photos or its downstream MDB.
    var transformerGaps: [String] {
        values.transformers("trafos").indices.compactMap { i in
            guard Schema.transformerPresent(values, i) else { return nil }
            var miss = Schema.transformerAngles.filter { values.photo("tr\(i)_\($0.key)") == nil }.map(\.label)
            if values.text("tr\(i)_feed").trimmingCharacters(in: .whitespaces).isEmpty { miss.append("ตู้ MDB ปลายสาย") }
            if values.photo("tr\(i)_mdbSpace") == nil { miss.append("ที่ว่างติดตั้ง CB โซลาร์") }
            return miss.isEmpty ? nil : "TR\(i + 1): " + miss.joined(separator: ", ")
        }
    }

    /// Index of the n-th section of a type (1-based), used for names like "R1", "ตู้ไฟฟ้า 2".
    func ordinal(of module: SurveyModule) -> Int {
        (modules.filter { $0.type == module.type }.firstIndex { $0.id == module.id } ?? 0) + 1
    }
    /// Sections grouped by workbook sheet, in the order the sheets appear in the workbook.
    var modulesBySheet: [SheetGroup] {
        let order = ["ระบบไฟฟ้า", "ระบบไฟฟ้า 2", "หลังคาทั่วไป", "บ่อตกตะกอน", "หลังคาทั่วไป R", "บ่อน้ำใส"]
        return order.compactMap { s in
            let m = modules.filter { $0.spec.sheet == s }
            return m.isEmpty ? nil : SheetGroup(sheet: s, modules: m)
        }
    }
    /// Sections grouped by category (B, C, D) in code order, numbered "C1.1", "C1.2" when a type repeats.
    var sectionsByCategory: [SectionGroup] {
        SectionCategory.allCases.compactMap { cat in
            var items: [NumberedSection] = []
            for t in ModuleType.byCode where t.category == cat {
                let list = modules.filter { $0.type == t }
                for (i, m) in list.enumerated() {
                    items.append(NumberedSection(number: list.count > 1 ? "\(t.code).\(i + 1)" : t.code, module: m))
                }
            }
            return items.isEmpty ? nil : SectionGroup(category: cat, sections: items)
        }
    }
    /// Warn when a station sheet copy will be added because there are more sections than slots.
    var stationOverflow: [ModuleType: Int] {
        var r: [ModuleType: Int] = [:]
        for (t, slots) in Schema.stationSlots {
            let n = modules.filter { $0.type == t }.count
            if n > slots { r[t] = n }
        }
        return r
    }
}

/// One page of the editor in workbook order (A1–A4, each added section, E1) — the home card's step bar.
public struct SurveyStep: Identifiable, Hashable, Sendable {
    public enum Status: Sendable { case complete, current, missing, notStarted }
    public let page: MissingGroup.Target
    /// "A1", "C1.2"
    public let code: String
    public let title: String
    public let category: SectionCategory
    public let completion: Completion
    public var id: MissingGroup.Target { page }
}

public extension Job {
    var steps: [SurveyStep] {
        func cover(_ p: MissingGroup.Target, _ code: String, _ title: String, _ g: GroupSpec) -> SurveyStep {
            SurveyStep(page: p, code: code, title: title, category: .general, completion: g.completion(values))
        }
        return [cover(.info, "A1", "ข้อมูลโครงการ", Schema.info), cover(.site, "A2", "ภาพสถานที่ติดตั้ง", Schema.site),
                cover(.electrical, "A3", "มิเตอร์ หม้อแปลง และตู้ MDB", Schema.electrical), cover(.flood, "A4", "ประวัติน้ำท่วม", Schema.flood)]
            + sectionsByCategory.flatMap { g in
                g.sections.map { SurveyStep(page: .module($0.id), code: $0.number, title: $0.module.title, category: g.category, completion: $0.module.completion) }
            }
            + [SurveyStep(page: .final, code: "E1", title: "สรุปผลและลงนาม", category: .summary, completion: finalCompletion)]
    }
    /// First step with required fields still empty — where "continue" opens the editor.
    var nextStep: SurveyStep? { steps.first { $0.completion.total > 0 && !$0.completion.isComplete } }
    /// Each step with its colour on the step bar: done, the next one to fill, started but short, or untouched.
    var stepStatuses: [(step: SurveyStep, status: SurveyStep.Status)] {
        let next = nextStep?.page
        return steps.map { s in
            let c = s.completion
            let status: SurveyStep.Status = s.page == next ? .current
                : c.total == 0 || c.isComplete ? .complete : c.filled > 0 ? .missing : .notStarted
            return (s, status)
        }
    }
    /// Never saved to Drive, or answers edited since the last save there.
    /// Background photo uploads don't count as a save — the report files in Drive are still the old ones.
    var needsDriveSave: Bool {
        guard drive?.folderID != nil, let saved = drive?.lastSaved else { return true }
        return updated > saved
    }
}

public struct NumberedSection: Identifiable, Sendable {
    public let number: String
    public let module: SurveyModule
    public var id: UUID { module.id }
    /// "C1.2 หลังคา · 2 โรงสูบ"
    public var title: String { number + " " + module.title }
}
public struct SectionGroup: Identifiable, Sendable {
    public let category: SectionCategory
    public let sections: [NumberedSection]
    public var id: String { category.rawValue }
}

/// Sections that fill the same workbook sheet.
public struct SheetGroup: Identifiable, Sendable {
    public let sheet: String
    public let modules: [SurveyModule]
    public var id: String { sheet }
}

public extension FieldSpec {
    /// Short text for summaries and the PDF answer column.
    func displayText(_ v: Values) -> String {
        guard let val = v[id] else { return "" }
        switch val {
        case .text(let s):
            if case .number(let u) = kind, !s.isEmpty { return "\(s) \(u)" }
            return s
        case .choice(let s, let o): return s == "อื่นๆ" ? "อื่นๆ: \(o)" : s
        case .multi(let a): return a.joined(separator: ", ")
        case .photo: if case .signature = kind { return "ลงนามแล้ว" }; return "แนบภาพแล้ว"
        case .photos(let a): return a.isEmpty ? "" : "\(a.count) ภาพ"
        case .obstacles(let a):
            return a.map { "\($0.label.isEmpty ? "สิ่งกีดขวาง" : $0.label) (\($0.w.isEmpty ? "?" : $0.w)x\($0.h.isEmpty ? "?" : $0.h) ม. @\($0.x.isEmpty ? "0" : $0.x),\($0.y.isEmpty ? "0" : $0.y))" }.joined(separator: "; ")
        case .transformers(let a):
            return a.enumerated().map { i, t in
                "TR\(i + 1) \(t.kva.isEmpty ? "-" : t.kva)kVA: " + t.mdb.enumerated().compactMap { $1.isEmpty ? nil : "MDB\($0 + 1)=\($1)A" }.joined(separator: " ")
            }.joined(separator: " | ")
        case .marks(let a):
            return SiteMarks.labels(a).values.sorted().joined(separator: ", ")
        case .shapes(let a): return a.isEmpty ? "" : "\(a.count) รูปวาด"
        }
    }
}

/// "1.5,4,4" → [1.5, 4, 4]; "4ม., ๔" and "4 m" read too.
public func parseSpans(_ s: String) -> [Double] {
    s.split { ",/ \t".contains($0) }.compactMap { NumberInput.value(String($0)) }.filter { $0 > 0 }
}

/// Number formatting as on the forms: no trailing ".0".
public func fmt(_ x: Double, digits: Int = 2) -> String {
    if x == x.rounded() { return String(Int(x)) }
    var s = String(format: "%.\(digits)f", x)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}
