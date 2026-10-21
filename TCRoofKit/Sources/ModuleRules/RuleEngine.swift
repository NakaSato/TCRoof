import Foundation

/// What each stage's form holds. A field left nil isn't checked: its rule waits for the answer.

public enum SeaDistance: String, Codable, Sendable { case under100m, to1km, over1km }

/// Survey → installation checks (§7.1).
public struct SiteInput: Codable, Sendable, Equatable {
    public var latitude: Double?
    public var altitudeM: Double?
    public var seaDistance: SeaDistance?
    public var humidityPct: Double?
    /// The site's monthly average minimum and maximum ambient, °C.
    public var monthlyMinC: Double?, monthlyMaxC: Double?
    public var roofFireproof: Bool?
    public var plannedTiltDeg: Double?
    /// Room behind the modules the roof allows, mm (ZN-90).
    public var rearClearanceMm: Double?
    public init(latitude: Double? = nil, altitudeM: Double? = nil, seaDistance: SeaDistance? = nil, humidityPct: Double? = nil,
                monthlyMinC: Double? = nil, monthlyMaxC: Double? = nil, roofFireproof: Bool? = nil, plannedTiltDeg: Double? = nil,
                rearClearanceMm: Double? = nil) {
        self.latitude = latitude; self.altitudeM = altitudeM; self.seaDistance = seaDistance; self.humidityPct = humidityPct
        self.monthlyMinC = monthlyMinC; self.monthlyMaxC = monthlyMaxC; self.roofFireproof = roofFireproof; self.plannedTiltDeg = plannedTiltDeg
        self.rearClearanceMm = rearClearanceMm
    }
}

/// The survey's installation checks as a job keeps them (§7.1): the answers, the site notes that raise no rule, the
/// engineer's reason for each warn, and the rule set and catalog the survey was saved under.
public struct SiteInstallCheck: Codable, Sendable, Equatable {
    public var altitudeM: Double?
    public var seaDistance: SeaDistance?
    /// Farms and meadows: fine per IEC 62716 (ZN-74), noted only.
    public var ammonia: Bool?
    /// Strong wind or many lightning strikes: notes ZN-75 / ZN-76.
    public var highWind: Bool?
    public var lightning: Bool?
    public var monthlyMinC: Double?, monthlyMaxC: Double?
    /// The lowest site ambient, °C, for string sizing.
    public var tMinC: Double?
    public var humidityPct: Double?
    public var roofFireproof: Bool?
    public var rearClearanceMm: Double?
    /// Roof edge to array edge, m (ZN-77).
    public var edgeSafeZoneM: Double?
    public var shadingSources: [String] = []
    /// The modules' planned tilt, not the roof's slope.
    public var plannedTiltDeg: Double?
    /// Rule id → the engineer's reason for passing a warn.
    public var reasons: [String: String] = [:]
    /// The versions the survey was last saved under; nil until then.
    public var ruleSetVersion: String?
    public var catalogVersion: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case altitudeM, seaDistance, ammonia, highWind, lightning, monthlyMinC, monthlyMaxC, tMinC, humidityPct, roofFireproof,
             rearClearanceMm, edgeSafeZoneM, shadingSources, plannedTiltDeg, reasons, ruleSetVersion, catalogVersion
    }

    /// Every field optional, so a record saved by an older version still opens.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil }
        altitudeM = d(.altitudeM); seaDistance = d(.seaDistance); ammonia = d(.ammonia); highWind = d(.highWind)
        lightning = d(.lightning); monthlyMinC = d(.monthlyMinC); monthlyMaxC = d(.monthlyMaxC); tMinC = d(.tMinC)
        humidityPct = d(.humidityPct); roofFireproof = d(.roofFireproof); rearClearanceMm = d(.rearClearanceMm)
        edgeSafeZoneM = d(.edgeSafeZoneM); shadingSources = d(.shadingSources) ?? []; plannedTiltDeg = d(.plannedTiltDeg)
        reasons = d(.reasons) ?? [:]; ruleSetVersion = d(.ruleSetVersion); catalogVersion = d(.catalogVersion)
    }

    /// The engine's input, with the survey's latitude.
    public func input(latitude: Double?) -> SiteInput {
        SiteInput(latitude: latitude, altitudeM: altitudeM, seaDistance: seaDistance, humidityPct: humidityPct,
                  monthlyMinC: monthlyMinC, monthlyMaxC: monthlyMaxC, roofFireproof: roofFireproof, plannedTiltDeg: plannedTiltDeg,
                  rearClearanceMm: rearClearanceMm)
    }

    public func validation(latitude: Double?) -> Validation { RuleEngine.check(input(latitude: latitude)) }

    /// Nothing answered yet.
    public var isEmpty: Bool {
        var blank = SiteInstallCheck(); blank.reasons = reasons; blank.ruleSetVersion = ruleSetVersion; blank.catalogVersion = catalogVersion
        return self == blank
    }

    /// Notes for the site that raise no rule (ZN-74 / 75 / 76), Thai.
    public var notes: [String] {
        var out: [String] = []
        if ammonia == true { out.append("ZN-74 พื้นที่มีแอมโมเนีย (ฟาร์ม ทุ่งหญ้า) ติดตั้งได้ตาม IEC 62716") }
        if highWind == true { out.append("ZN-75 พื้นที่ลมแรง ต้องมีแนวกันลมหรือวิธีป้องกันลม") }
        if lightning == true { out.append("ZN-76 พื้นที่ฟ้าผ่าบ่อย ระบบต้องมีการป้องกันฟ้าผ่า") }
        return out
    }

    public static func decode(_ json: String) -> SiteInstallCheck {
        guard !json.isEmpty, let d = json.data(using: .utf8), let c = try? JSONDecoder().decode(SiteInstallCheck.self, from: d) else { return SiteInstallCheck() }
        return c
    }
    public var json: String {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

/// One series string: each module's model, tilt and azimuth.
public struct StringPlan: Codable, Sendable, Equatable {
    public var id: String
    public var modelIDs: [String]
    public var tiltsDeg: [Double]
    public var azimuthsDeg: [Double]
    public var count: Int { modelIDs.count }
    public init(id: String, modelIDs: [String], tiltsDeg: [Double] = [], azimuthsDeg: [Double] = []) {
        self.id = id; self.modelIDs = modelIDs; self.tiltsDeg = tiltsDeg; self.azimuthsDeg = azimuthsDeg
    }
    /// `count` modules of one model at one tilt and azimuth.
    public static func uniform(id: String, model: String, count: Int, tilt: Double, azimuth: Double) -> StringPlan {
        StringPlan(id: id, modelIDs: Array(repeating: model, count: count), tiltsDeg: Array(repeating: tilt, count: count),
                   azimuthsDeg: Array(repeating: azimuth, count: count))
    }
}

/// Layout → module and mounting (§7.2).
public struct LayoutInput: Sendable, Equatable {
    public var module: ModuleModel?
    public var landscape = false
    public var clampSide: ClampSide?
    /// Offset A, module edge to clamp centre, mm.
    public var clampOffsetMm: Double?
    /// Two landscape modules share one horizontal rail along their long frame.
    public var sharesLongRail = false
    public var bifacialHeightM: Double?
    public var rearClearanceMm: Double?
    public var gapMm: Double?
    public var clampLengthMm: Double?, clampThicknessMm: Double?
    public var clampsPerModule: Int?
    public var railsPerModule: Int?
    public var tiltDeg: Double?
    public var latitude: Double?
    public var strings: [StringPlan] = []
    public var tMinC: Double?
    public var inverterMaxDcV: Double?
    public var cableMm2: Double?
    public var cableAmpacityA: Double?
    public var parallelCount = 1
    public var groundingParallel: Int?, groundingSeries: Int?
    public init(module: ModuleModel? = nil) { self.module = module }
}

/// Installation daily report → the module install checklist (§7.3).
public struct InstallInput: Codable, Sendable, Equatable {
    public var method: MountingMethod?
    public var boltTorquesNm: [Double] = []
    public var washerThicknessMm: Double?, washerOdMm: Double?
    public var clampOverlapMm: Double?
    public var clampsPerModule: Int?
    public var groundTorquesNm: [Double] = []
    public var bendRadiusMm: Double?
    public var crewCount: Int?
    public var frameModified: Bool?
    public var gapMm: Double?
    public var rearClearanceMm: Double?
    public init(method: MountingMethod? = nil) { self.method = method }
}

/// Commissioning: strings to be paralleled (§7.4).
public struct StringReading: Codable, Sendable, Equatable {
    public var id: String
    public var vocV: Double
    public var polarityOK: Bool
    public init(id: String, vocV: Double, polarityOK: Bool) { self.id = id; self.vocV = vocV; self.polarityOK = polarityOK }
}

/// A form's check: the rules that fired, against the rule set and catalog versions it was made with.
public struct Validation: Sendable, Equatable {
    public var results: [RuleResult]
    public var ruleSetVersion: String
    public var catalogVersion: String

    public var blocks: [RuleResult] { results.filter { $0.severity == .block } }
    public var warns: [RuleResult] { results.filter { $0.severity == .warn } }
    /// Submit: no block, and a written reason for every warn (by rule id).
    public func canSubmit(reasons: [String: String]) -> Bool {
        blocks.isEmpty && warns.allSatisfy { !(reasons[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    /// The TC engineer signs only a report with no open block.
    public var canSign: Bool { blocks.isEmpty }
}

/// Runs the rule set on a stage's input (§5). The rule set (JSON) gives each rule its severity, field and messages; the
/// conditions are here. A rule whose input is missing doesn't fire.
public enum RuleEngine {
    /// The ids the engine has a condition for; `RuleEngineTests` keeps them and the rule set the same.
    public static let conditions: Set<String> = [
        "ZN-70", "ZN-73a", "ZN-73b", "ZN-69", "T5-1", "ZN-77", "ZN-81", "ZN-82",
        "ZN-79", "ZN-52", "ZN-53", "ZN-85", "ZN-90", "ZN-91", "ZN-95", "ZN-97", "S553-zone", "S553-short", "ZN-88",
        "ZN-105", "ZN-106", "ZN-106b", "ZN-112", "ZN-107", "ZN-122",
        "S551-torque", "S551-washer", "S553-overlap", "ZN-121", "ZN-108", "ZN-61", "ZN-63", "ZN-110",
    ]

    static func fire(_ id: String, _ values: [String: String] = [:], rules: [RuleSpec]) -> RuleResult? {
        guard let r = rules.first(where: { $0.id == id }) else { return nil }
        func fill(_ s: String) -> String { values.reduce(s) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) } }
        return RuleResult(id: r.id, severity: r.severity, field: r.field, messageTH: fill(r.message_th), messageEN: fill(r.message_en))
    }

    static func validation(_ fired: [RuleResult?]) -> Validation {
        Validation(results: fired.compactMap { $0 }.sorted { $0.severity > $1.severity },
                   ruleSetVersion: ModuleCatalog.ruleSetVersion, catalogVersion: ModuleCatalog.version)
    }

    static func number(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
    }

    // MARK: survey

    public static func check(_ s: SiteInput, rules: [RuleSpec] = ModuleCatalog.rules) -> Validation {
        var out: [RuleResult?] = []
        if let a = s.altitudeM, a > 2000 { out.append(fire("ZN-70", rules: rules)) }
        switch s.seaDistance {
        case .under100m?: out.append(fire("ZN-73a", rules: rules))
        case .to1km?: out.append(fire("ZN-73b", rules: rules))
        default: break
        }
        if let h = s.humidityPct, h > 85 { out.append(fire("ZN-69", rules: rules)) }
        if let lo = s.monthlyMinC, lo < -20 { out.append(fire("T5-1", rules: rules)) }
        else if let hi = s.monthlyMaxC, hi > 47 { out.append(fire("T5-1", rules: rules)) }
        if s.roofFireproof == false { out.append(fire("ZN-77", rules: rules)) }
        if let c = s.rearClearanceMm, c < 115 { out.append(fire("ZN-90", rules: rules)) }
        out += tilt(s.plannedTiltDeg, latitude: s.latitude, rules: rules)
        return validation(out)
    }

    /// ZN-81 and ZN-82, on the survey's planned tilt and the layout's tilt.
    static func tilt(_ tilt: Double?, latitude: Double?, rules: [RuleSpec]) -> [RuleResult?] {
        guard let t = tilt else { return [] }
        var out: [RuleResult?] = []
        if t < 10 { out.append(fire("ZN-81", rules: rules)) }
        if let lat = latitude {
            let rec = ModuleRules.recommendedTilt(latitude: lat)
            if abs(t - rec) >= 0.5 { out.append(fire("ZN-82", ["tilt": number((rec * 10).rounded() / 10)], rules: rules)) }
        }
        return out
    }

    // MARK: layout

    public static func check(_ l: LayoutInput, rules: [RuleSpec] = ModuleCatalog.rules) -> Validation {
        var out: [RuleResult?] = tilt(l.tiltDeg, latitude: l.latitude, rules: rules)
        if let m = l.module {
            if m.sizeClass == .big && l.landscape && l.clampSide == .short { out.append(fire("ZN-52", rules: rules)) }
            if m.sizeClass == .small && l.landscape && l.sharesLongRail { out.append(fire("ZN-53", rules: rules)) }
            if m.bifacial, let h = l.bifacialHeightM, !(0.5...2).contains(h) { out.append(fire("ZN-85", rules: rules)) }
            if let side = l.clampSide {
                if let zone = ModuleRules.clampZone(module: m, side: side) {
                    if let a = l.clampOffsetMm, !zone.contains(a) { out.append(fire("S553-zone", rules: rules)) }
                } else {
                    out.append(fire("S553-short", rules: rules))
                }
            }
            // string sizing needs β
            if !l.strings.isEmpty && m.betaVocPctPerC == nil { out.append(fire("ZN-106b", rules: rules)) }
            if let t = l.tMinC, let nmax = ModuleRules.maxModulesInSeries(module: m, tMinC: t, inverterMaxDcV: l.inverterMaxDcV),
               l.strings.contains(where: { $0.count > nmax }) {
                out.append(fire("ZN-106", ["nmax": String(nmax)], rules: rules))
            }
            let need = ModuleRules.minCableAmpacity(module: m, parallelCount: l.parallelCount)
            if let a = l.cableAmpacityA, a < need { out.append(fire("ZN-112", ["amps": String(format: "%.2f", need)], rules: rules)) }
        }
        if let c = l.rearClearanceMm, c < 115 { out.append(fire("ZN-90", rules: rules)) }
        if let g = l.gapMm, g < 10 { out.append(fire("ZN-91", rules: rules)) }
        if (l.clampLengthMm.map { $0 < 60 } ?? false) || (l.clampThicknessMm.map { $0 < 3 } ?? false) { out.append(fire("ZN-95", rules: rules)) }
        if let n = l.clampsPerModule, n < 4 { out.append(fire("ZN-97", rules: rules)) }
        if let n = l.railsPerModule, n < 2 { out.append(fire("ZN-88", rules: rules)) }
        if l.strings.contains(where: { s in Set(s.tiltsDeg).count > 1 || Set(s.azimuthsDeg).count > 1 }) { out.append(fire("ZN-79", rules: rules)) }
        if l.strings.contains(where: { Set($0.modelIDs).count > 1 }) { out.append(fire("ZN-105", rules: rules)) }
        if let s = l.cableMm2, s < 4 { out.append(fire("ZN-107", rules: rules)) }
        if (l.groundingParallel.map { $0 > 4 } ?? false) || (l.groundingSeries.map { $0 > 8 } ?? false) { out.append(fire("ZN-122", rules: rules)) }
        return validation(out)
    }

    // MARK: installation

    public static func check(_ i: InstallInput, rules: [RuleSpec] = ModuleCatalog.rules) -> Validation {
        var out: [RuleResult?] = []
        let profile = i.method.flatMap(ModuleCatalog.profile) ?? ModuleCatalog.profile(.bolt)!
        if i.boltTorquesNm.contains(where: { !profile.torqueNm.contains($0) }) { out.append(fire("S551-torque", rules: rules)) }
        // the clamp method has no washer spec
        if profile.washerMinThicknessMm > 0 {
            let thin = i.washerThicknessMm.map { $0 < profile.washerMinThicknessMm } ?? false
            let od = i.washerOdMm.map { !profile.washerOdMm.contains($0) } ?? false
            if thin || od { out.append(fire("S551-washer", rules: rules)) }
        }
        if let o = i.clampOverlapMm, !(7...10).contains(o) { out.append(fire("S553-overlap", rules: rules)) }
        if let n = i.clampsPerModule, n < 4 { out.append(fire("ZN-97", rules: rules)) }
        if i.groundTorquesNm.contains(where: { !(4...8).contains($0) }) { out.append(fire("ZN-121", rules: rules)) }
        if let r = i.bendRadiusMm, r < 43 { out.append(fire("ZN-108", rules: rules)) }
        if let n = i.crewCount, n < 2 { out.append(fire("ZN-61", rules: rules)) }
        if i.frameModified == true { out.append(fire("ZN-63", rules: rules)) }
        if let g = i.gapMm, g < 10 { out.append(fire("ZN-91", rules: rules)) }
        if let c = i.rearClearanceMm, c < 115 { out.append(fire("ZN-90", rules: rules)) }
        return validation(out)
    }

    // MARK: commissioning

    /// ZN-110: strings about to be paralleled — any reversed polarity, or Voc differing by more than 10 V.
    public static func check(parallel strings: [StringReading], rules: [RuleSpec] = ModuleCatalog.rules) -> Validation {
        let v = strings.map(\.vocV)
        let spread = (v.max() ?? 0) - (v.min() ?? 0)
        return validation([strings.contains { !$0.polarityOK } || spread > 10 ? fire("ZN-110", rules: rules) : nil])
    }
}
