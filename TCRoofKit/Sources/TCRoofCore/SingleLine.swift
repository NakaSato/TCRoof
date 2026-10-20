import Foundation

// Single line diagram (SLD) generated from the survey: A1 capacity, A3 meter / transformers / boards / breakers,
// A4 flood check, B1 loads, B2 inverters, B4 zero export, B5 FTS. Pure value types — `SingleLineLayout` draws them
// for both the screen and the A3 PDF. Nothing here is stored in the job except three optional answers
// (`sldAttach`, `sldTransformer`, `sldBoard`).

/// How sure a piece of text in the diagram is.
public enum SLStatus: Hashable, Sendable {
    /// Read from the survey.
    case known
    /// Not entered yet — drawn as a red `?`.
    case missing
    /// Not survey data: a default or a calculation result (counted under "ค่าสมมติ").
    case assumed
    /// Equipment the project adds (PV side, zero-export CT / relay).
    case new
    case condition(SLCondition)
}

public enum SLCondition: String, Hashable, Sendable {
    case good, fair, bad
    public init?(_ text: String) {
        switch text.trimmingCharacters(in: .whitespaces) {
        case "ดี": self = .good
        case "พอใช้": self = .fair
        case "ชำรุด": self = .bad
        default: return nil
        }
    }
}

/// Where a tap on a diagram item goes.
public struct SLTarget: Hashable, Sendable {
    public enum Page: Hashable, Sendable { case info, electrical, flood, module(ModuleType) }
    public var page: Page
    /// Transformer index in A3.
    public var trafo: Int?
    /// Board index (position in the transformer's resolved boards).
    public var board: Int?
    public var breaker: UUID?
    public init(_ page: Page, trafo: Int? = nil, board: Int? = nil, breaker: UUID? = nil) {
        self.page = page; self.trafo = trafo; self.board = board; self.breaker = breaker
    }
    public static let info = SLTarget(.info)
    public static func module(_ t: ModuleType) -> SLTarget { SLTarget(.module(t)) }
    /// "A3 →" / "B2 →" for the link in the side panel.
    public var linkLabel: String {
        switch page {
        case .info: return "A1 →"
        case .electrical: return "A3 →"
        case .flood: return "A4 →"
        case .module(let t): return t.code + " →"
        }
    }
}

public struct SLText: Hashable, Sendable {
    public var text: String
    public var status: SLStatus
    public var bold = false
    public init(_ text: String, _ status: SLStatus = .known, bold: Bool = false) { self.text = text; self.status = status; self.bold = bold }
    public var isMissing: Bool { status == .missing }
}

public struct SLBreaker: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var trafo: Int
    public var board: Int
    /// Position on the bus, 1…n; 0 for a main breaker.
    public var number = 0
    public var isMain = false
    public var isNew = false
    /// "MCCB,3P"
    public var type: SLText
    /// "400AT" (drawn with a line under it) and "400AF"
    public var at: SLText
    public var af: SLText
    public var ic: SLText
    public var brand: SLText
    public var condition: SLText?
    public var note: SLText?
    public var atAmps: Double?
    public var icKA: Double?
    /// Short name for the breaker check list ("ระบบสูบน้ำ").
    public var name = ""
    /// Load block under an outgoing breaker of the connection board.
    public var destination: [SLText] = []
    /// Level 2: feeder cable and conduit, drawn rotated left of the feeder ("4x50,1x10-IEC01, ø50mm. UPVC"); "" when not entered.
    public var feeder = ""
    /// Level 2: a spare breaker, drawn with `SPARE` and no cable or load.
    public var spare = false
    public var target: SLTarget { SLTarget(.electrical, trafo: trafo, board: board, breaker: id) }
    /// Text lines, in drawing order.
    public var lines: [SLText] { [type, at, af, ic, brand] + [condition, note].compactMap { $0 } }
}

public struct SLBoard: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var trafo: Int
    public var index: Int
    public var name: String
    public var location: String
    public var isMain: Bool
    public var main: SLBreaker
    public var breakers: [SLBreaker]
    /// Level 2: label above the bus; "" when not entered.
    public var busbar = ""
    /// Level 2: ground conductor; the N/G bar and ground rod are drawn when it is given.
    public var ground = ""
    public var target: SLTarget { SLTarget(.electrical, trafo: trafo, board: index) }
}

public struct SLTransformer: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var index: Int
    /// First line is the bold title ("TX1 OIL IMMERSED").
    public var lines: [SLText]
    /// Most of the nameplate is missing, so `lines` is just the kVA and a red note.
    public var collapsed: Bool
    /// nil = not answered (drawn as `LA ?`)
    public var hasLA: Bool?
    public var cable: SLText
    public var boards: [SLBoard]
    public var kva: Double?
    public var zPercent: Double?
    /// A3's HV protection: `DO fuse`, `DS`, `VCB` or "" (drawn as its own symbol).
    public var protection = ""
    public var target: SLTarget { SLTarget(.electrical, trafo: index) }
}

/// A value the diagram cannot draw yet. Blocking ones stop the PV design.
public struct SLMissing: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var blocking: Bool
    public var target: SLTarget
}

/// A level 2 check printed under the diagram ("ค่าที่คำนวณจากข้อมูลสำรวจ"). Never an error: `flagged` only colours it.
public struct SLNote: Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String
    /// Outside its usual range (main AT against the full-load current, AT over AF, PV over the transformer).
    public var flagged = false
    public var target: SLTarget
}

public struct SLAssumption: Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String
}

public enum SLCheckState: Hashable, Sendable { case ok, marginal, insufficient, unknown }

public struct SLCheck: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var icKA: Double?
    public var state: SLCheckState
    public var target: SLTarget
    /// "50 kA" / "25 kA | เผื่อน้อย" / "20 kA | ไม่พอ" / "ยังไม่รู้"
    public var value: String {
        let ic = icKA.map { SingleLine.fmt($0) + " kA" } ?? ""
        switch state {
        case .ok: return ic
        case .marginal: return ic + " | เผื่อน้อย"
        case .insufficient: return ic + " | ไม่พอ"
        case .unknown: return "ยังไม่รู้"
        }
    }
}

public struct SLFlood: Hashable, Sendable {
    public var text: String
    public var minCm: Int
    public var levelCm: Int
}

/// The PV branch: A1 capacity → B2 inverters → SMDB-PV → connection board.
public struct SLPV: Hashable, Sendable {
    public var capacityKWp: Double?
    public var inverterCount: Int?
    public var inverterKW: Double?
    /// Per-inverter kW picked on B2 (all B2 sections); nil when B2 has no sizes and the kW is derived from A1.
    public var inverterSizes: [Int]?
    public var inverterAT: Int?
    public var totalAT: Int?
    public var requiredIC: Int?
    public var busbar: String?
    public var inverterCable: String?
    public var mainCable: String?
    public var cableRuns = 0
    public var totalCableM = 0
    /// Rows of the navy "ข้อมูลฝั่ง PV" card.
    public var rows: [SLRow] = []
    /// "2 × 60 kW" or "60 + 60 + 80 kW"; "?" parts when unknown.
    public var inverterSummary: String {
        if let s = inverterSizes, Set(s).count > 1 { return s.map(String.init).joined(separator: " + ") + " kW" }
        return "\(inverterCount.map(String.init) ?? "?") × \(inverterKW.map { SingleLine.fmt($0) } ?? "?") kW"
    }
}

public struct SLRow: Hashable, Sendable {
    public var label: String
    public var value: SLText
}

public struct SingleLine: Sendable {
    // source
    public var sourceLabel: String
    public var meter: [SLText]
    public var protection: SLText
    /// The one HV protection every transformer has (its symbol on the tap), "" when they differ or none is answered.
    public var protectionKind = ""
    /// The job has a B5 section: the FTS cut and the emergency button are drawn (decided 2026-10-19).
    public var hasB5 = true
    /// B4 "กันย้อนที่แรงสูง"
    public var zeroExportHV: Bool
    /// The job has a B4 section, so the toggle edits it; otherwise it only previews.
    public var hasB4: Bool
    public var pole: String
    public var transformers: [SLTransformer]
    /// The transformer / board the PV connects to.
    public var connection: (trafo: Int, board: Int)
    public var pv: SLPV
    public var isc: Double?
    public var iscAssumedZ: Bool
    public var checks: [SLCheck]
    public var missing: [SLMissing]
    public var assumptions: [SLAssumption]
    /// Level 2 checks on the connection board and its transformer, printed under the diagram.
    public var notes: [SLNote] = []
    public var flood: SLFlood?
    public var conditionCounts: (bad: Int, fair: Int)
    public var projectLine: String

    public var blocking: [SLMissing] { missing.filter(\.blocking) }
    public var others: [SLMissing] { missing.filter { !$0.blocking } }
    public var connectionBoard: SLBoard? { transformers[safe: connection.trafo]?.boards[safe: connection.board] }
}

// MARK: - constants

/// Every figure that is not survey data. All of them are counted under "ค่าสมมติ" when used.
public enum SLConstants {
    /// Line voltage of the LV side (V).
    public static let lineVoltage = 400.0
    /// Breaker rating over inverter current: the team's rule (confirmed 2026-10-19), not an assumption.
    public static let breakerFactor = 1.25
    /// IC must be at least this much above the prospective Isc to count as enough.
    public static let icMargin = 1.25
    /// %Z used when the nameplate value is missing.
    public static let defaultZPercent = 4.0
    /// Length of one AC cable run (m) — the survey has no cable lengths.
    public static let cableRunM = 20
    /// Standard inverter sizes (kW).
    public static let inverterSizes: [Double] = [5, 10, 15, 20, 25, 30, 36, 40, 50, 60, 75, 100, 110]
    /// Standard breaker frames (A).
    public static let frames: [Int] = [16, 20, 25, 32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 320, 400, 500, 630, 800]
    /// Standard breaking capacities (kA).
    public static let icSizes: [Int] = [10, 15, 25, 36, 50, 65, 85]
    /// Copper CV 0.6/1 kV in conduit by breaker AT: (up to AT, cable). Design values for 125 A and 250 A.
    public static let cables: [(at: Int, cable: String)] = [
        (20, "CV 4×4 + G4"), (32, "CV 4×10 + G10"), (50, "CV 4×16 + G16"), (63, "CV 4×25 + G16"), (100, "CV 4×35 + G16"), (125, "CV 4×35 + G16"),
        (160, "CV 4×70 + G35"), (200, "CV 4×95 + G50"), (250, "CV 4×120 + G25"), (320, "CV 4×185 + G95"), (400, "CV 4×240 + G120"),
        (500, "CV 4×300 + G150"), (630, "CV 2×(4×185) + G95"), (800, "CV 2×(4×240) + G120")]
    /// Copper busbar by AT.
    public static let busbars: [(at: Int, bar: String)] = [(100, "15 × 3"), (160, "20 × 5"), (250, "25 × 5"), (400, "30 × 5"), (630, "40 × 5"), (800, "50 × 5")]
}

// MARK: - calculations

public extension SingleLine {
    static func fmt(_ x: Double) -> String {
        x == x.rounded() && x < 1000 ? String(Int(x)) : String(format: "%.1f", x)
    }

    /// Smallest inverter size at or above `kw`; the largest when `kw` is bigger than all.
    static func standardInverter(_ kw: Double) -> Double { SLConstants.inverterSizes.first { $0 >= kw } ?? SLConstants.inverterSizes.last! }

    /// Breaker trip for `kw` of inverter output: I = P / (√3 × 400), × 1.25, rounded up to a standard frame.
    static func breakerAT(kw: Double) -> Int {
        let amps = kw * 1000 / (3.0.squareRoot() * SLConstants.lineVoltage) * SLConstants.breakerFactor
        return SLConstants.frames.first { Double($0) >= amps } ?? SLConstants.frames.last!
    }
    /// AF: the next frame at or above AT.
    static func breakerAF(at: Int) -> Int { SLConstants.frames.first { $0 >= at } ?? at }

    /// Prospective short-circuit current (kA) on the LV bus: S / (√3 × 400 × Z), infinite HV source.
    static func shortCircuit(kva: Double, zPercent: Double) -> Double? {
        guard kva > 0, zPercent > 0 else { return nil }
        return kva * 1000 / (3.0.squareRoot() * SLConstants.lineVoltage * zPercent / 100) / 1000
    }
    /// Smallest standard IC (kA) at or above `isc`.
    static func requiredIC(isc: Double) -> Int { SLConstants.icSizes.first { Double($0) >= isc } ?? SLConstants.icSizes.last! }

    static func classify(ic: Double?, isc: Double?) -> SLCheckState {
        guard let ic, ic > 0, let isc else { return .unknown }
        if ic >= SLConstants.icMargin * isc { return .ok }
        return ic >= isc ? .marginal : .insufficient
    }
    static func cable(forAT at: Int) -> String { (SLConstants.cables.first { $0.at >= at } ?? SLConstants.cables.last!).cable }
    static func busbar(forAT at: Int) -> String { (SLConstants.busbars.first { $0.at >= at } ?? SLConstants.busbars.last!).bar }
}
