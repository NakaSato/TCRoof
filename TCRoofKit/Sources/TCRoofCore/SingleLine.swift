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
    public var target: SLTarget { SLTarget(.electrical, trafo: index) }
}

/// A value the diagram cannot draw yet. Blocking ones stop the PV design.
public struct SLMissing: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var blocking: Bool
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
    /// "50 kA" / "25 kA · เผื่อน้อย" / "20 kA · ไม่พอ" / "ยังไม่รู้"
    public var value: String {
        let ic = icKA.map { SingleLine.fmt($0) + " kA" } ?? ""
        switch state {
        case .ok: return ic
        case .marginal: return ic + " · เผื่อน้อย"
        case .insufficient: return ic + " · ไม่พอ"
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
    /// Breaker rating over inverter current.
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

// MARK: - build

public extension SingleLine {
    /// - Parameter hvOverride: previews the other zero-export side without touching B4.
    static func build(_ job: Job, hvOverride: Bool? = nil) -> SingleLine {
        var b = Builder(job: job, hvOverride: hvOverride)
        return b.build()
    }
}

private func num(_ s: String) -> Double? { NumberInput.value(s) }
private func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }
private func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }

private struct Builder {
    let job: Job
    let hvOverride: Bool?
    var v: Values { job.values }
    var missing: [SLMissing] = []
    var assumptions: [SLAssumption] = []

    init(job: Job, hvOverride: Bool?) { self.job = job; self.hvOverride = hvOverride }

    mutating func miss(_ id: String, _ label: String, blocking: Bool, _ target: SLTarget) {
        missing.append(SLMissing(id: id, label: label, blocking: blocking, target: target))
    }

    func value(_ s: String, _ unit: String = "") -> SLText { blank(s) ? SLText("?", .missing) : SLText(t(s) + unit) }

    // MARK: breakers and boards

    /// Shows `?` in place of each empty part; `lead` is the breaker type with poles ("MCCB,3P").
    func breaker(type: String, poles: String, at: String, af: String, ic: String, brand: String, condition: String, note: String,
                 id: UUID, trafo: Int, board: Int, isMain: Bool, number: Int, name: String) -> SLBreaker {
        let kind = blank(type) ? "MCCB" : t(type)
        let p = blank(poles) ? "3P" : t(poles)
        let typeText = SLText(kind + "," + p, blank(type) ? .assumed : .known)
        let cond = SLCondition(condition)
        var br = SLBreaker(
            id: id, trafo: trafo, board: board,
            type: typeText,
            at: blank(at) ? SLText("?AT", .missing) : SLText(t(at) + "AT"),
            af: blank(af) ? SLText("?AF", .missing) : SLText(t(af) + "AF"),
            ic: blank(ic) ? SLText("IC ? kA", .missing) : SLText("IC " + t(ic) + " kA"),
            brand: blank(brand) ? SLText("ยี่ห้อ ?", .missing) : SLText(t(brand)))
        br.number = number; br.isMain = isMain; br.name = name
        br.atAmps = num(at); br.icKA = num(ic)
        if let cond { br.condition = SLText("สภาพ: " + t(condition), .condition(cond), bold: true) }
        if !blank(note) { br.note = SLText(t(note), cond.map { .condition($0) } ?? .known) }
        return br
    }

    func loadText(for target: String) -> [SLText] {
        let sections = job.sectionsByCategory.flatMap(\.sections).filter { $0.module.type == .panel }
        let trimmed = t(target)
        var name = trimmed.replacingOccurrences(of: "ตู้ไฟฟ้า", with: "").replacingOccurrences(of: "(B1)", with: "").trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "" }
        let match = sections.first { s in
            let n = t(s.module.name)
            return (!n.isEmpty && trimmed.contains(n)) || (!trimmed.isEmpty && trimmed.contains("(\(s.number))"))
        }
        var out = [SLText("ตู้ไฟฟ้า", bold: true)]
        out.append(name.isEmpty ? SLText("?", .missing, bold: true) : SLText(name, bold: true))
        if let m = match?.module {
            let kw = t(m.values.text("loadKW")), time = t(m.values.text("loadTime"))
            out.append(kw.isEmpty ? SLText("โหลด ? (B1)", .missing) : SLText("โหลด \(kw) kW" + (time.isEmpty ? "" : " @\(time)")))
        } else {
            out.append(SLText("โหลด ? (B1)", .missing))
        }
        return out
    }

    // MARK: build

    mutating func build() -> SingleLine {
        let trafos = v.transformers("trafos")
        let b4 = job.sectionsByCategory.flatMap(\.sections).first { $0.module.type == .backfeed }?.module
        let hv = hvOverride ?? (b4?.values.choice("level") == "กันย้อนที่แรงสูง")
        let pole = b4?.values.choice("pole") ?? "เสาใหม่"

        // connection point
        let connT = min(max(Int(v.text("sldTransformer")) ?? 0, 0), max(trafos.count - 1, 0))
        let connBoards = trafos[safe: connT]?.resolvedBoards ?? []
        let connB = connBoards.firstIndex { $0.id.uuidString == v.text("sldBoard") } ?? 0

        // transformers
        var sl: [SLTransformer] = []
        for (i, tr) in trafos.enumerated() { sl.append(transformer(tr, i, connection: (connT, connB))) }

        // short circuit at the connection bus
        let ct = sl[safe: connT]
        var zAssumed = false
        var isc: Double?
        if let ct, let kva = ct.kva {
            var z = ct.zPercent
            if z == nil { z = SLConstants.defaultZPercent; zAssumed = true }
            isc = SingleLine.shortCircuit(kva: kva, zPercent: z!)
        }
        if zAssumed { assumptions.append(SLAssumption(id: "z", text: "%Z ของ TX\(connT + 1) ไม่มีข้อมูล ใช้ \(SingleLine.fmt(SLConstants.defaultZPercent)) % คำนวณกระแสลัดวงจร")) }
        if isc != nil { assumptions.append(SLAssumption(id: "isc", text: "Isc = S / (√3 × 400 V × Z) · แหล่งจ่ายแรงสูงไม่จำกัด ไม่นับอิมพีแดนซ์สาย")) }

        // PV side
        let pv = pvBranch(isc: isc, connT: connT)

        // missing items of the boards
        collectBoardMissing(sl, connection: (connT, connB))

        // breaker check on the connection bus
        var checks: [SLCheck] = []
        if let board = sl[safe: connT]?.boards[safe: connB] {
            let bn = board.name
            checks.append(SLCheck(id: board.main.id.uuidString, name: "\(bn) \(board.main.type.text.split(separator: ",").first ?? "") เมน",
                                  icKA: board.main.icKA, state: SingleLine.classify(ic: board.main.icKA, isc: isc), target: board.main.target))
            for br in board.breakers {
                checks.append(SLCheck(id: br.id.uuidString, name: "CB\(br.number) \(br.name)".trimmingCharacters(in: .whitespaces),
                                      icKA: br.icKA, state: SingleLine.classify(ic: br.icKA, isc: isc), target: br.target))
            }
        }

        // flood
        var flood: SLFlood?
        let fr = job.floodCheck
        if fr.state == .flooded || fr.state == .unknownFetched {
            let year = t(v.text("floodYear"))
            let when = fr.state == .flooded ? (year.isEmpty ? "" : " (ปี \(year))") : " (ประเมิน GISTDA)"
            flood = SLFlood(text: "\(fr.mdbName) น้ำเคยเข้า \(Int(fr.level)) ซม.\(when) · ตู้ SMDB-PV และรีเลย์กันย้อนต้องสูง ≥ \(fr.minCm) ซม.",
                            minCm: fr.minCm, levelCm: Int(fr.level))
        }

        // conditions
        var bad = 0, fair = 0
        func count(_ c: String) { switch SLCondition(c) { case .bad?: bad += 1; case .fair?: fair += 1; default: break } }
        for tr in trafos { count(tr.condition); for bd in tr.resolvedBoards { count(bd.condition); for br in bd.breakers { count(br.condition) } } }

        // source
        let kv = t(v.choice("meterKV") ?? v.text("meterKV"))
        let phase = t(v.choice("meterPhase") ?? v.text("meterPhase"))
        let kvText = kv.isEmpty ? "?" : kv
        let sourceLabel = "ระบบจำหน่าย กฟภ. \(kvText) kV, 3Ø 3W, 50 Hz"
        let meterNo = t(v.text("meterNo")), ca = t(v.text("meterCA")), rate = t(v.text("meterRate")), ctv = t(v.text("meterCT"))
        let meter = [
            SLText("PEA METER " + (meterNo.isEmpty ? "?" : meterNo), meterNo.isEmpty ? .missing : .known, bold: true),
            SLText("CA \(ca.isEmpty ? "?" : ca) · อัตรา \(rate.isEmpty ? "?" : rate)", ca.isEmpty || rate.isEmpty ? .missing : .known),
            SLText("รับไฟ \(kvText) kV \(phase.isEmpty ? "?" : phase) · CT \(ctv.isEmpty ? "?" : ctv) A", kv.isEmpty || phase.isEmpty || ctv.isEmpty ? .missing : .known),
        ]
        if meterNo.isEmpty { miss("meter", "มิเตอร์: หมายเลข", blocking: false, SLTarget(.electrical)) }
        let protections = Set(trafos.map { t($0.hvProtection) }.filter { !$0.isEmpty })
        let protection = protections.count == 1 ? SLText(protections.first!) : SLText("Drop Out Fuse / Disconnecting Switch")

        let pn = t(v.text("projectName")), doc = t(v.text("docNo"))
        return SingleLine(sourceLabel: sourceLabel, meter: meter, protection: protection, zeroExportHV: hv, hasB4: b4 != nil, pole: pole,
                          transformers: sl, connection: (connT, connB), pv: pv, isc: isc, iscAssumedZ: zAssumed, checks: checks,
                          missing: missing, assumptions: assumptions, flood: flood, conditionCounts: (bad, fair),
                          projectLine: [pn, doc.isEmpty ? nil : "NO.\(doc)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
    }

    // MARK: transformer

    mutating func transformer(_ tr: Transformer, _ i: Int, connection: (Int, Int)) -> SLTransformer {
        let n = i + 1
        let kind = tr.type == "oil" ? " OIL IMMERSED" : tr.type == "dry" ? " DRY TYPE" : ""
        let fields = [tr.type, tr.voltage, tr.vectorGroup, tr.impedance, tr.brand, tr.serial, tr.year]
        let missingCount = fields.filter(blank).count
        let collapsed = missingCount * 2 > fields.count
        var lines = [SLText("TX\(n)" + kind, bold: true)]
        let kva = num(tr.kva)
        if collapsed {
            lines.append(blank(tr.kva) ? SLText("? kVA", .missing) : SLText(t(tr.kva) + " kVA"))
            lines.append(SLText("ป้ายพิกัดยังไม่ครบ", .missing))
        } else {
            lines.append(blank(tr.voltage) ? SLText("? V", .missing) : SLText(t(tr.voltage) + " V"))
            let vec = blank(tr.vectorGroup) ? "Vector ?" : t(tr.vectorGroup)
            let z = blank(tr.impedance) ? "?" : t(tr.impedance)
            lines.append(SLText("\(vec), Z=\(z)%", blank(tr.vectorGroup) || blank(tr.impedance) ? .missing : .known))
            lines.append(blank(tr.kva) ? SLText("? kVA", .missing) : SLText(t(tr.kva) + " kVA"))
            let id = "\(blank(tr.brand) ? "" : t(tr.brand) + " · ")SN \(blank(tr.serial) ? "?" : t(tr.serial)) · ปี \(blank(tr.year) ? "?" : t(tr.year))"
            lines.append(SLText(id, blank(tr.serial) || blank(tr.year) ? .missing : .known))
            if let c = SLCondition(tr.condition) {
                lines.append(SLText("สภาพ: " + t(tr.condition) + (blank(tr.conditionNote) ? "" : " — " + t(tr.conditionNote)), .condition(c), bold: true))
            } else {
                lines.append(SLText("สภาพ: ?", .missing, bold: true))
            }
        }

        // boards
        var boards: [SLBoard] = []
        // PV connects to a board even when none is filled in yet, so an empty transformer gets a placeholder main board
        var raw = tr.resolvedBoards
        if raw.isEmpty { var b = Board(isMain: true); b.id = tr.id; raw = [b] }
        for (k, bd) in raw.enumerated() {
            let feed = t(v.text("tr\(i)_feed")), feedLoc = t(v.text("tr\(i)_feedLoc"))
            var name = t(bd.name)
            if name.isEmpty && k == 0 { name = feed }
            if name.isEmpty { name = "MDB\(k + 1)" }
            var loc = t(bd.location)
            if loc.isEmpty && k == 0 { loc = feedLoc }
            let main = breaker(type: bd.mainType, poles: bd.poles, at: bd.at, af: bd.af, ic: bd.icu, brand: bd.brand, condition: bd.condition,
                               note: bd.conditionNote, id: bd.id, trafo: i, board: k, isMain: true, number: 0, name: name)
            var outs: [SLBreaker] = []
            for (j, br) in bd.breakers.enumerated() {
                var o = breaker(type: "MCCB", poles: br.poles, at: br.at, af: br.af, ic: br.ic, brand: br.brand, condition: br.condition,
                                note: "", id: br.id, trafo: i, board: k, isMain: false, number: j + 1,
                                name: t(br.target).replacingOccurrences(of: "ตู้ไฟฟ้า", with: "").replacingOccurrences(of: "(B1)", with: "").trimmingCharacters(in: .whitespaces))
                o.destination = (i == connection.0 && k == connection.1) ? loadText(for: br.target) : []
                outs.append(o)
            }
            boards.append(SLBoard(id: bd.id, trafo: i, index: k, name: name, location: loc, isMain: k == 0, main: main, breakers: outs))
        }
        let z = num(tr.impedance)
        // nameplate gaps: %Z is blocking (handled with the boards), the rest are not
        return SLTransformer(id: tr.id, index: i, lines: lines, collapsed: collapsed, hasLA: tr.hasLA, cable: SLText("สาย ? (A3)", .missing),
                             boards: boards, kva: kva, zPercent: z)
    }

    mutating func collectBoardMissing(_ trafos: [SLTransformer], connection: (Int, Int)) {
        let raw = v.transformers("trafos")
        for tx in trafos {
            let n = tx.index + 1
            let r = raw[tx.index]
            // %Z is needed wherever boards are drawn
            if !tx.boards.isEmpty && blank(r.impedance) {
                miss("z\(tx.index)", "TX\(n): %Z (ดวงจรฝั่ง \(tx.boards.first?.name ?? "MDB"))", blocking: true, tx.target)
            }
            var other: [String] = []
            if blank(r.kva) { other.append("kVA") }
            if blank(r.type) { other.append("ชนิด") }
            if blank(r.voltage) { other.append("แรงดัน") }
            if blank(r.vectorGroup) { other.append("Vector") }
            if blank(r.brand) { other.append("ยี่ห้อ") }
            if blank(r.serial) { other.append("SN") }
            if blank(r.year) { other.append("ปี") }
            if SLCondition(r.condition) == nil { other.append("สภาพ") }
            if r.hasLA == nil { other.append("LA") }
            if !other.isEmpty { miss("tx\(tx.index)", "TX\(n): " + other.joined(separator: ", "), blocking: false, tx.target) }

            for bd in tx.boards {
                let onConn = tx.index == connection.0 && bd.index == connection.1
                var mainGaps: [String] = []
                if bd.main.at.isMissing { mainGaps.append("AT") }
                if bd.main.icKA == nil { mainGaps.append("IC kA") }
                if !mainGaps.isEmpty {
                    miss("m\(bd.id)", "\(bd.name) เมนเบรกเกอร์: " + mainGaps.joined(separator: ", "), blocking: onConn, bd.main.target)
                }
                for br in bd.breakers {
                    var gaps: [String] = []
                    if br.ic.isMissing { gaps.append("IC kA") }
                    if br.af.isMissing { gaps.append("AF") }
                    if br.brand.isMissing { gaps.append("ยี่ห้อ") }
                    if !gaps.isEmpty { miss("b\(br.id)", "\(bd.name) CB\(br.number): " + gaps.joined(separator: ", "), blocking: onConn, br.target) }
                    if onConn, br.destination.contains(where: { $0.isMissing && $0.text.contains("B1") }) {
                        miss("l\(br.id)", "โหลด CB\(br.number) \(br.name) (B1)", blocking: false, SLTarget(.module(.panel)))
                    }
                }
            }
        }
    }

    // MARK: PV

    mutating func pvBranch(isc: Double?, connT: Int) -> SLPV {
        var pv = SLPV()
        let sections = job.sectionsByCategory.flatMap(\.sections)
        let cap = v.number("capacity")
        pv.capacityKWp = (cap ?? 0) > 0 ? cap : nil
        let invSections = sections.filter { $0.module.type == .inverter }
        let count = invSections.reduce(0) { $0 + Int($1.module.values.number("inverterCount") ?? 0) }
        pv.inverterCount = count > 0 ? count : nil

        if pv.capacityKWp == nil { miss("capacity", "A1 กำลังผลิตติดตั้ง (kWp)", blocking: true, .info) }
        if pv.inverterCount == nil { miss("invCount", "B2 จำนวนอินเวอร์เตอร์", blocking: true, .module(.inverter)) }

        let capT = pv.capacityKWp.map { SLText(SingleLine.fmt($0) + " kWp", .new) } ?? SLText("?", .missing)
        var rows: [SLRow] = [SLRow(label: "PV", value: capT)]
        // B2 sizes (every B2 section with inverters must have them): catalog Imax, B2 breakers and the B2 feeder
        let stations = invSections.filter { ($0.module.values.number("inverterCount") ?? 0) > 0 }.map { InverterStation($0.module.values) }
        let picked = !stations.isEmpty && stations.allSatisfy { !$0.sizesAssumed } ? stations.flatMap(\.sizes) : []
        if let n = pv.inverterCount, !picked.isEmpty, picked.count == n {
            let all = InverterStation(sizes: picked), fd = all.feeder
            let ats = picked.map { all.breaker(kw: $0).at }
            pv.inverterSizes = picked
            pv.inverterKW = Set(picked).count == 1 ? Double(picked[0]) : nil
            pv.inverterAT = ats.max()
            pv.totalAT = fd.at
            pv.inverterCable = Set(ats).count == 1 ? InverterStation.cable(at: ats[0]).label : ats.reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.map { InverterStation.cable(at: $0).label }.joined(separator: " / ")
            pv.mainCable = fd.label
            pv.busbar = SingleLine.busbar(forAT: fd.at)
            pv.cableRuns = n + 1
            pv.totalCableM = pv.cableRuns * SLConstants.cableRunM
            if let isc { pv.requiredIC = SingleLine.requiredIC(isc: isc) }
            assumptions.append(SLAssumption(id: "length", text: "ระยะสาย AC \(SLConstants.cableRunM) ม./เส้น × \(pv.cableRuns) เส้น = \(pv.totalCableM) ม. (ไม่มีข้อมูลระยะจริง)"))
            let icText = pv.requiredIC.map { " · IC ≥ \($0) kA" } ?? " · IC ≥ ? kA"
            rows += [SLRow(label: "อินเวอร์เตอร์", value: SLText(pv.inverterSummary, .new)),
                     SLRow(label: "เบรกเกอร์อินเวอร์เตอร์", value: SLText(all.breakerSummary, .new)),
                     SLRow(label: "เบรกเกอร์ PV รวม", value: SLText("\(fd.at) AT" + icText, pv.requiredIC == nil ? .missing : .new)),
                     SLRow(label: "ราง AC (SMDB-PV)", value: SLText("ทองแดง \(pv.busbar!) มม.", .new)),
                     SLRow(label: "สาย AC อินเวอร์เตอร์", value: SLText(pv.inverterCable! + " มม²", .new)),
                     SLRow(label: "สาย AC → \(job.mainBoardName)", value: SLText(fd.label + " มม²", .new))]
        } else if let kwp = pv.capacityKWp, let n = pv.inverterCount {
            let kw = SingleLine.standardInverter(kwp / Double(n))
            pv.inverterKW = kw
            let at = SingleLine.breakerAT(kw: kw), total = SingleLine.breakerAT(kw: kw * Double(n))
            pv.inverterAT = at; pv.totalAT = total
            pv.inverterCable = SingleLine.cable(forAT: at)
            pv.mainCable = SingleLine.cable(forAT: total)
            pv.busbar = SingleLine.busbar(forAT: total)
            pv.cableRuns = n + 1
            pv.totalCableM = pv.cableRuns * SLConstants.cableRunM
            if let isc { pv.requiredIC = SingleLine.requiredIC(isc: isc) }
            assumptions.append(SLAssumption(id: "invKW", text: "กำลังอินเวอร์เตอร์ \(SingleLine.fmt(kw)) kW/เครื่อง = A1 ÷ B2 ปัดเป็นขนาดมาตรฐาน (B2 ยังไม่มีช่อง kW)"))
            assumptions.append(SLAssumption(id: "sizes", text: "เบรกเกอร์ = I × 1.25 ปัดเป็นเฟรมมาตรฐาน · สาย/ราง ตามตาราง CV 0.6/1 kV ร้อยท่อ"))
            assumptions.append(SLAssumption(id: "length", text: "ระยะสาย AC \(SLConstants.cableRunM) ม./เส้น × \(pv.cableRuns) เส้น = \(pv.totalCableM) ม. (ไม่มีข้อมูลระยะจริง)"))
            let icText = pv.requiredIC.map { " · IC ≥ \($0) kA" } ?? " · IC ≥ ? kA"
            rows += [SLRow(label: "อินเวอร์เตอร์", value: SLText("\(n) × \(SingleLine.fmt(kw)) kW", .new)),
                     SLRow(label: "เบรกเกอร์อินเวอร์เตอร์", value: SLText("\(at) AT × \(n)", .new)),
                     SLRow(label: "เบรกเกอร์ PV รวม", value: SLText("\(total) AT" + icText, pv.requiredIC == nil ? .missing : .new)),
                     SLRow(label: "ราง AC (SMDB-PV)", value: SLText("ทองแดง \(pv.busbar!) มม.", .new)),
                     SLRow(label: "สาย AC อินเวอร์เตอร์", value: SLText(pv.inverterCable! + " มม²", .new)),
                     SLRow(label: "สาย AC → \(job.mainBoardName)", value: SLText(pv.mainCable! + " มม²", .new))]
        } else {
            for l in ["อินเวอร์เตอร์", "เบรกเกอร์อินเวอร์เตอร์", "เบรกเกอร์ PV รวม", "ราง AC (SMDB-PV)", "สาย AC อินเวอร์เตอร์", "สาย AC → \(job.mainBoardName)"] {
                rows.append(SLRow(label: l, value: SLText("?", .missing)))
            }
        }
        pv.rows = rows
        return pv
    }
}
