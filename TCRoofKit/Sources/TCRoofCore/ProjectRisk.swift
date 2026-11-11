import Foundation

/// One risk of the Master Plan's project risk register (`ทะเบียนความเสี่ยง`, R01–R13; CHA-81, PMBOK 5th §11.2.3.1 and
/// §11.3). The team's Google Sheet copies the register into `config/risks` on each pull (`tools/master-plan-sheet`,
/// `Core.riskRegister`); the app reads it, read only, team only.
public struct ProjectRisk: Codable, Equatable, Identifiable, Sendable {
    /// `R03`.
    public var id: String
    /// ความเสี่ยง (เหตุการณ์).
    public var title: String
    /// หมวด: `กฟภ.`, `ผรม.`, `เอกสาร` …
    public var category: String
    /// สาเหตุ / สัญญาณเตือน.
    public var cause: String
    /// ขอบเขต as typed: `ทั้งเฟส`, `ผรม. S`, `สถานี > 200 kVA` …; `jobs` is what the sheet made of it.
    public var scope: String
    /// WBS ที่กระทบ.
    public var wbs: String
    /// ตัวชี้วัด (KRI), its current value and threshold (เกณฑ์เตือน); `warn` once the value reaches the threshold.
    public var kri: String
    public var kriValue: Double?
    public var kriThreshold: Double?
    public var warn: Bool
    /// โอกาส and ผลกระทบ 1–5, their product, and the level from it (`สูง` ≥ 15, `กลาง` ≥ 8, `ต่ำ`).
    public var probability: Int?
    public var impact: Int?
    public var score: Int?
    public var level: String
    /// Days it would move COD if it happened, and the schedule reserve held for it.
    public var impactDays: Double?
    public var reserveDays: Double?
    /// กลยุทธ์ (PMBOK), วิธีรับมือ, ผู้รับผิดชอบ.
    public var strategy: String
    public var response: String
    public var owner: String
    /// `เปิด`, `เฝ้าระวัง`, `เกิดแล้ว` or `ปิด`.
    public var status: String
    /// ทบทวนล่าสุด, `yyyy-MM-dd`.
    public var reviewed: String?
    /// The app jobs (Firestore ids) of the stations it touches; nil for every station.
    public var jobs: [String]?

    public init(id: String, title: String, category: String = "", cause: String = "", scope: String = "", wbs: String = "",
                kri: String = "", kriValue: Double? = nil, kriThreshold: Double? = nil, warn: Bool = false,
                probability: Int? = nil, impact: Int? = nil, score: Int? = nil, level: String = "",
                impactDays: Double? = nil, reserveDays: Double? = nil, strategy: String = "", response: String = "",
                owner: String = "", status: String = "เปิด", reviewed: String? = nil, jobs: [String]? = nil) {
        self.id = id; self.title = title; self.category = category; self.cause = cause; self.scope = scope; self.wbs = wbs
        self.kri = kri; self.kriValue = kriValue; self.kriThreshold = kriThreshold; self.warn = warn
        self.probability = probability; self.impact = impact; self.score = score; self.level = level
        self.impactDays = impactDays; self.reserveDays = reserveDays; self.strategy = strategy; self.response = response
        self.owner = owner; self.status = status; self.reviewed = reviewed; self.jobs = jobs
    }

    enum CodingKeys: String, CodingKey {
        case id, title, category, cause, scope, wbs, kri, kriValue, kriThreshold, warn, probability, impact, score, level
        case impactDays, reserveDays, strategy, response, owner, status, reviewed, jobs
    }

    /// Every field but the id may be missing: a sheet edited by hand leaves cells blank.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
        func d(_ k: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil }
        func i(_ k: CodingKeys) -> Int? { d(k).map { Int($0.rounded()) } }
        id = try c.decode(String.self, forKey: .id)
        title = s(.title); category = s(.category); cause = s(.cause); scope = s(.scope); wbs = s(.wbs); kri = s(.kri)
        kriValue = d(.kriValue); kriThreshold = d(.kriThreshold)
        warn = ((try? c.decodeIfPresent(Bool.self, forKey: .warn)) ?? nil) ?? false
        probability = i(.probability); impact = i(.impact); score = i(.score); level = s(.level)
        impactDays = d(.impactDays); reserveDays = d(.reserveDays)
        strategy = s(.strategy); response = s(.response); owner = s(.owner); status = s(.status)
        reviewed = (try? c.decodeIfPresent(String.self, forKey: .reviewed)) ?? nil
        jobs = (try? c.decodeIfPresent([String].self, forKey: .jobs)) ?? nil
    }

    /// Not `ปิด`; a row with no status yet counts as open.
    public var isOpen: Bool { status.trimmingCharacters(in: .whitespaces) != "ปิด" }

    /// `สูง`, or a score of 15 and over when the level cell is blank.
    public var isHigh: Bool {
        let l = level.trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? (score ?? 0) >= 15 : l == "สูง"
    }

    public func touches(job id: String) -> Bool { jobs.map { $0.contains(id) } ?? true }

    /// `R03 ผรม. S กำลังติดตั้งไม่พอ`.
    public var label: String { id + " " + title }
}

public struct RiskRegister: Codable, Equatable, Sendable {
    public var risks: [ProjectRisk]
    /// When the sheet last wrote it.
    public var updatedAt: Date?

    public init(risks: [ProjectRisk], updatedAt: Date? = nil) { self.risks = risks; self.updatedAt = updatedAt }

    /// `config/risks`' `json` (`{ "risks": [...] }`); nil when it doesn't read.
    public static func decode(_ json: String) -> RiskRegister? {
        guard let data = json.data(using: .utf8),
              let r = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        return RiskRegister(risks: r.risks.compactMap(\.value))
    }

    /// A row that doesn't read (no id) is skipped, not the whole register.
    private struct Wire: Decodable { var risks: [Lenient] }
    private struct Lenient: Decodable {
        var value: ProjectRisk?
        init(from decoder: Decoder) throws { value = try? ProjectRisk(from: decoder) }
    }

    /// The open risks that touch a station, high ones first, then by score; `highOnly` keeps only the high ones.
    public func open(for jobID: String, highOnly: Bool = false) -> [ProjectRisk] {
        risks.filter { $0.isOpen && $0.touches(job: jobID) && (!highOnly || $0.isHigh) }
            .sorted { ($0.isHigh ? 1 : 0, $0.score ?? 0) > ($1.isHigh ? 1 : 0, $1.score ?? 0) }
    }
}

public extension ProjectRisk {
    /// One risk as the assistant's tools give it.
    struct Brief: Codable, Equatable, Sendable {
        public var id: String
        public var risk: String
        public var level: String
        public var score: Int?
        public var status: String
        public var kri: String?
        /// The KRI has reached its threshold (เตือน ⚠).
        public var kriWarning: Bool
        public var response: String
        public var owner: String
        public var impactDays: Double?

        public init(_ r: ProjectRisk) {
            id = r.id; risk = r.title; level = r.level.isEmpty ? (r.isHigh ? "สูง" : "") : r.level; score = r.score
            status = r.status; kri = r.kri.isEmpty ? nil : r.kri; kriWarning = r.warn; response = r.response
            owner = r.owner; impactDays = r.impactDays
        }
    }
}
