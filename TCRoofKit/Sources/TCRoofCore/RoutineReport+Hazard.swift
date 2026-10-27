import Foundation

/// R1's 5 × 5 risk assessment (docs/ui/weekly-request-ipad-map §4.5): the band a score falls in, the hazard list a
/// line's hazards come from, and scoring a risk.
public extension RoutineReport {
    /// The band of a likelihood × severity score, for the screen: 1–4 `ต่ำ`, 5–9 `ปานกลาง`, 10–16 `สูง`, 20–25 `สูงมาก`.
    enum RiskBand: Int, CaseIterable, Sendable {
        case low, medium, high, veryHigh

        public init(score: Int) {
            self = score <= 4 ? .low : score <= 9 ? .medium : score <= 16 ? .high : .veryHigh
        }

        public var title: String {
            switch self {
            case .low: "ต่ำ"
            case .medium: "ปานกลาง"
            case .high: "สูง"
            case .veryHigh: "สูงมาก"
            }
        }

        /// The band key's range, `1–4` … `20–25`.
        public var range: String {
            switch self {
            case .low: "1–4"
            case .medium: "5–9"
            case .high: "10–16"
            case .veryHigh: "20–25"
            }
        }
    }

    /// The level the PDF and older devices read for a score: ≤ 4 low, ≤ 9 medium, else high.
    static func level(score: Int) -> RiskLevel { score <= 4 ? .low : score <= 9 ? .medium : .high }

    /// The likelihood titles 1…5 and the severity titles 1…5 of the grid.
    static let likelihoodTitles = ["แทบไม่เกิด", "ไม่น่าเกิด", "อาจเกิด", "น่าจะเกิด", "เกิดแน่นอน"]
    static let severityTitles = ["เล็กน้อย", "ปฐมพยาบาล", "ต้องรักษา", "บาดเจ็บสาหัส", "เสียชีวิต"]

    /// A hazard of the list: its controls, the default score a new draft starts with, and the lines it applies to.
    struct Hazard: Hashable, Identifiable, Sendable {
        public enum Rule: Sendable { case height, electrical, droppedObjects, byHand }

        public let name: String
        public let controls: [String]
        public let likelihood: Int
        public let severity: Int
        public let rule: Rule
        public var id: String { name }

        public init(name: String, controls: [String], likelihood: Int, severity: Int, rule: Rule) {
            self.name = name; self.controls = controls; self.likelihood = likelihood; self.severity = severity; self.rule = rule
        }

        /// A roof or tank place for height, cables / a cabinet / the inverter for electrical, modules or trays on a roof
        /// for dropped objects; the others are added by hand.
        public func applies(to line: PlanLine) -> Bool {
            let place = line.location, work = line.description + " " + (line.task?.title ?? "")
            let roof = place.contains("หลังคา")
            switch rule {
            case .height: return roof || place.contains("ถัง")
            case .electrical: return ["สายไฟ", "ตู้", "อินเวอร์เตอร์"].contains { work.contains($0) }
            case .droppedObjects: return roof && ["แผง", "ราง"].contains { work.contains($0) }
            case .byHand: return false
            }
        }

        /// The controls as one line, for the R1 PDF's `แนวทางป้องกัน`.
        public var prevention: String { controls.joined(separator: " | ") }
    }

    /// The board's hazard list (docs/ui/weekly-request-ipad-map `sample-data.json`), to be reviewed by the safety officer.
    static let hazards: [Hazard] = [
        Hazard(name: "การทำงานบนที่สูง (Working at height)",
               controls: ["ติดตั้ง Lifeline / ราวกันตกก่อนขึ้นหลังคา", "ใบอนุญาตทำงานบนที่สูงและผู้เฝ้าระวัง",
                          "Full Body Harness + Double lanyard เกี่ยวตลอดเวลา (100% tie-off)"],
               likelihood: 3, severity: 5, rule: .height),
        Hazard(name: "ไฟฟ้าช็อต / อาร์กแฟลช (Electric shock / Arc flash)",
               controls: ["ตัดแยกแหล่งจ่ายและทำ LOTO", "วัดยืนยันไม่มีแรงดันก่อนสัมผัส (Test before touch)",
                          "ด้าน DC เปิด DC isolator และห้ามปลดขั้วต่อขณะมีกระแส", "ถุงมือฉนวนและชุด Arc-rated ตามระดับแรงดัน"],
               likelihood: 2, severity: 5, rule: .electrical),
        Hazard(name: "วัตถุตกหล่น (Dropped objects)",
               controls: ["กั้นเขตอันตรายด้านล่าง (Exclusion zone) และติดป้าย", "Toe board และผูกเครื่องมือ (Tool lanyard)",
                          "หมวกนิรภัยมีสายรัดคาง"],
               likelihood: 3, severity: 3, rule: .droppedObjects),
        Hazard(name: "ความเครียดจากความร้อน (Heat stress)",
               controls: ["ประเมินดัชนี WBGT ทุกวัน", "จัดรอบพักตามค่าความร้อน", "น้ำดื่มและที่พักในร่ม"],
               likelihood: 3, severity: 2, rule: .byHand),
        Hazard(name: "ฟ้าผ่า (Lightning)",
               controls: ["หยุดงานบนหลังคาและงานไฟฟ้ากลางแจ้งตามกฎ 30/30", "กลับมาทำต่อเมื่อพ้น 30 นาทีหลังฟ้าร้องครั้งสุดท้าย"],
               likelihood: 2, severity: 5, rule: .byHand),
    ]
}

public extension RoutineReport.Risk {
    /// The score, when both parts are set.
    var score: Int? { likelihood.flatMap { l in severity.map { l * $0 } } }

    /// The band of the score, when scored.
    var band: RoutineReport.RiskBand? { score.map(RoutineReport.RiskBand.init(score:)) }

    /// Scores it (1–5 each) and writes `level` from the score.
    mutating func assess(likelihood l: Int, severity s: Int) {
        likelihood = min(max(l, 1), 5); severity = min(max(s, 1), 5)
        level = RoutineReport.level(score: likelihood! * severity!)
    }
}

public extension RoutineReport.WeeklyRequest {
    /// The hazards of the list that apply to a line.
    func hazards(of line: RoutineReport.PlanLine) -> [RoutineReport.Hazard] {
        RoutineReport.hazards.filter { $0.applies(to: line) }
    }

    /// The week's assessment of a hazard (one per week, keyed by its name).
    func risk(for hazard: RoutineReport.Hazard) -> RoutineReport.Risk? { risks.first { $0.description == hazard.name } }

    /// Scores a hazard for the week (adding its risk with the controls when it has none).
    mutating func assess(_ hazard: RoutineReport.Hazard, likelihood l: Int, severity s: Int) {
        if let i = risks.firstIndex(where: { $0.description == hazard.name }) {
            risks[i].assess(likelihood: l, severity: s)
        } else {
            var r = RoutineReport.Risk(description: hazard.name, prevention: hazard.prevention)
            r.assess(likelihood: l, severity: s)
            risks.append(r)
        }
    }

    /// `ไม่ใช้กับงานนี้`: takes the hazard's assessment out.
    mutating func removeAssessment(_ hazard: RoutineReport.Hazard) { risks.removeAll { $0.description == hazard.name } }

    /// A new draft's start: every hazard that applies to its lines, assessed at the list's default score.
    mutating func assessDefaults() {
        for h in RoutineReport.hazards where risk(for: h) == nil && work.contains(where: { h.applies(to: $0) }) {
            assess(h, likelihood: h.likelihood, severity: h.severity)
        }
    }

    /// The first line (index) with a hazard not yet assessed, if any.
    var firstUnassessedLine: Int? {
        work.firstIndex { line in hazards(of: line).contains { risk(for: $0) == nil } }
    }
}
