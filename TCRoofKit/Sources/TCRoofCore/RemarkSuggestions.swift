import Foundation

/// One line E1 offers to add to `remarks` (docs/ui/survey-e1): the text, the page it comes from ("D1", "A4") and where
/// that page is.
public struct RemarkSuggestion: Hashable, Sendable, Identifiable {
    public let text: String
    /// Section number of the page the data comes from ("D1", "A4", "A3", "B1").
    public let source: String
    public let target: MissingGroup.Target
    public var id: String { text }
    public init(text: String, source: String, target: MissingGroup.Target) { self.text = text; self.source = source; self.target = target }
}

/// E1's "ข้อเสนอแนะอัตโนมัติ" rows. Rule-based and deterministic: every number and name comes from the job, and a rule
/// whose data isn't there doesn't fire. Which ones are already added is read from the `remarks` text, never stored.
public enum RemarkSuggestions {
    public static func make(job: Job) -> [RemarkSuggestion] {
        shade(job) + [flood(job), electrical(job), zeroExport(job)].compactMap { $0 }
    }

    // MARK: rules

    /// D pages: something shades a tank. Trees can be trimmed; other shade is a warning for the panel layout.
    /// No page computes a shading percentage yet, so none is quoted.
    static func shade(_ job: Job) -> [RemarkSuggestion] {
        let sections = job.sectionsByCategory.flatMap(\.sections)
        return job.modules.filter { $0.type == .tank }.compactMap { m in
            let v = m.values
            guard Schema.shaded(v) else { return nil }
            let from = v.multi("shadeFrom").filter { $0 != "อื่นๆ" }
            guard !from.isEmpty || v.multi("shadeFrom").contains("อื่นๆ") else { return nil }
            let dirs = v.multi("shadeDir").compactMap { d in Schema.shadeDirs.firstIndex(of: d).map { Tank.directions[$0] } }
            let side = dirs.isEmpty ? "" : "ด้าน" + dirs.joined(separator: "/")
            let name = m.name.trimmingCharacters(in: .whitespaces)
            let title = m.spec.short + (name.isEmpty ? "" : " " + name)
            let text: String
            if from == ["ต้นไม้"] {
                text = "ตัดแต่งต้นไม้\(side) \(title) ก่อนติดตั้ง"
            } else {
                let what = from.isEmpty ? "สิ่งกีดขวาง" : from.joined(separator: "/")
                text = "ระวังเงาบังจาก\(what)\(side) \(title) ก่อนจัดแผง"
            }
            let number = sections.first { $0.id == m.id }?.number ?? m.type.code
            return RemarkSuggestion(text: text, source: number, target: .module(m.id))
        }
    }

    /// A4: a reported flood or a GISTDA estimate sets how high the SMDB-PV and the relay go (`Schema.recommendedEquipHeight`).
    static func flood(_ job: Job) -> RemarkSuggestion? {
        let v = job.values
        guard let h = Schema.recommendedEquipHeight(v) else { return nil }
        let level = Int(FloodCheck.level(v).rounded())
        let why: String
        switch FloodCheck.state(v) {
        case .flooded: why = " (\(job.mainBoardName) เคยน้ำท่วม \(level) ซม.)"
        case .unknownFetched: why = " (ระดับน้ำประเมิน GISTDA \(level) ซม.)"
        default: why = ""
        }
        return RemarkSuggestion(text: "ยก SMDB-PV และรีเลย์กันย้อนสูง ≥ \(h) ซม.\(why)", source: "A4", target: .flood)
    }

    /// A3: the breakers on the PV connection bus with no IC, and transformers with no %Z — the same gaps the SLD lists.
    static func electrical(_ job: Job) -> RemarkSuggestion? {
        guard !job.values.transformers("trafos").isEmpty else { return nil }
        let sl = SingleLine.build(job)
        let ic = sl.checks.filter { $0.icKA == nil }.map(\.name)
        let z = sl.transformers.filter { $0.zPercent == nil && !$0.boards.isEmpty }.map { "TX\($0.index + 1)" }
        guard !ic.isEmpty || !z.isEmpty else { return nil }
        func list(_ names: [String]) -> String {
            names.count > 3 ? names.prefix(3).joined(separator: ", ") + " และอีก \(names.count - 3) ตัว" : names.joined(separator: ", ")
        }
        let parts = (ic.isEmpty ? [] : ["IC ของ " + list(ic)]) + (z.isEmpty ? [] : ["%Z ของ " + list(z)])
        return RemarkSuggestion(text: "ขอค่า " + parts.joined(separator: " และ ") + " ก่อนออกแบบ", source: "A3", target: .electrical)
    }

    /// B1: the daytime load B1 already sums is below the PV size (`BuildingPanels.daytimeNote`).
    static func zeroExport(_ job: Job) -> RemarkSuggestion? {
        guard let note = BuildingPanels.daytimeNote(job), note.needsZeroExport, let pv = note.pv,
              let first = job.modules.first(where: { $0.type == .panel }) else { return nil }
        let number = job.sectionsByCategory.flatMap(\.sections).first { $0.id == first.id }?.number ?? "B1"
        return RemarkSuggestion(text: "ต้องมีระบบกันย้อน (โหลดกลางวัน \(SingleLine.fmt(note.load)) kW < PV \(SingleLine.fmt(pv)) kW)",
                                source: number.split(separator: ".").first.map(String.init) ?? number, target: .module(first.id))
    }

    // MARK: remarks text

    /// A line without its "1." / "2)" number.
    static func stripNumber(_ line: Substring) -> String {
        var s = line.drop { $0 == " " || $0 == "\t" }
        let digits = s.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, let mark = s.dropFirst(digits.count).first, mark == "." || mark == ")" {
            s = s.dropFirst(digits.count + 1)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Already in `remarks`: some line, without its number, holds the text. Editing or deleting that line offers it again.
    public static func isAdded(_ s: RemarkSuggestion, in remarks: String) -> Bool {
        remarks.split(whereSeparator: \.isNewline).contains { stripNumber($0).contains(s.text) }
    }

    /// The suggestions not yet in `remarks`.
    public static func pending(_ all: [RemarkSuggestion], remarks: String) -> [RemarkSuggestion] {
        all.filter { !isAdded($0, in: remarks) }
    }

    /// `remarks` with "<n>. <text>" on a new line, numbered after the highest numbered line already there.
    public static func appending(_ list: [RemarkSuggestion], to remarks: String) -> String {
        var out = remarks
        var n = remarks.split(whereSeparator: \.isNewline).compactMap { line -> Int? in
            let s = line.drop { $0 == " " || $0 == "\t" }
            let digits = s.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, let mark = s.dropFirst(digits.count).first, mark == "." || mark == ")" else { return nil }
            return Int(digits)
        }.max() ?? 0
        for s in list {
            n += 1
            if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
            out += "\(n). \(s.text)"
        }
        return out
    }
}

/// E1's bottom-bar status (docs/ui/survey-e1). Completion stays `Schema.final.completion`; the remarks warning only shows.
public enum FinalSummary {
    static let short = ["verdict": "ผลการประเมิน", "surveyorSign": "ลายเซ็นวิศวกรผู้สำรวจ", "customerSign": "ลายเซ็นผู้ประสานงาน",
                        "customerName": "ชื่อผู้ประสานงาน"]

    /// Owner rule shown on the page, not enforced: "with conditions" and "not recommended" should say why.
    public static func remarksWanted(_ v: Values) -> Bool {
        guard let verdict = v.choice("verdict"), verdict != Options.verdict[0] else { return false }
        return v.text("remarks").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// This page's required gaps in short words, then the remarks warning.
    public static func pageGaps(_ v: Values) -> [String] {
        Schema.final.missing(v).map { short[$0.id] ?? $0.plainLabel } + (remarksWanted(v) ? ["ความเห็น / เงื่อนไข"] : [])
    }

    /// Pages other than E1 with gaps.
    public static func otherPages(_ job: Job) -> [MissingGroup] { job.missingGroups.filter { $0.target != .final } }

    /// "A2" from "A2 ภาพสถานที่ติดตั้ง".
    public static func code(_ g: MissingGroup) -> String { g.title.split(separator: " ").first.map(String.init) ?? g.title }

    public static func isComplete(_ job: Job) -> Bool { pageGaps(job.values).isEmpty && otherPages(job).isEmpty }

    public static func statusLine(_ job: Job) -> String {
        let here = pageGaps(job.values), others = otherPages(job)
        if !here.isEmpty { return "ยังขาดในหน้านี้: " + here.joined(separator: ", ") + (others.isEmpty ? "" : " · และอีก \(others.count) หน้า") }
        if !others.isEmpty { return "หน้านี้ครบแล้ว · ยังขาดอีก \(others.count) หน้า (\(others.map(code).joined(separator: ", ")))" }
        return "ครบทุกหน้าแล้ว · พร้อมส่งออก"
    }
}
