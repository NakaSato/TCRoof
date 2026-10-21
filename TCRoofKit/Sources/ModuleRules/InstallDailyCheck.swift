import Foundation

/// The installation daily report's module checklist (docs/specs/module-install-rules.md §7.3): the readings the rules
/// check (torques, washer, clamps, gap, clearance, bend radius, crew, frame) and the evidence ticks that raise no rule
/// (PPE, dry weather, drain holes, cell colour, cable routing, grounding hardware), the serials, the engineer's reasons
/// for warns, and the versions it was signed under.
public struct InstallDailyCheck: Codable, Sendable, Equatable {
    public var method: MountingMethod?
    /// nil: the report's own crew count.
    public var crewCount: Int?
    public var ppe: Bool?, noJewelry: Bool?
    public var weatherDry: Bool?, modulesDry: Bool?
    public var rejectedSerials: [String] = []
    /// Bolt torques sampled today, N·m.
    public var boltTorquesNm: [Double] = []
    public var washerThicknessMm: Double?, washerOdMm: Double?
    public var clampsPerModule: Int?
    public var clampOverlapMm: Double?
    public var gapMm: Double?, rearClearanceMm: Double?
    public var drainHolesClear: Bool?, frameModified: Bool?, sameColour: Bool?
    public var noLoops: Bool?, outOfSun: Bool?, inConduit: Bool?
    public var bendRadiusMm: Double?
    public var groundWireMm2: Double?
    public var m4StarWasher: Bool?
    public var groundTorquesNm: [Double] = []
    public var installedSerials: [String] = []
    public var reasons: [String: String] = [:]
    public var ruleSetVersion: String?
    public var catalogVersion: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case method, crewCount, ppe, noJewelry, weatherDry, modulesDry, rejectedSerials, boltTorquesNm, washerThicknessMm, washerOdMm,
             clampsPerModule, clampOverlapMm, gapMm, rearClearanceMm, drainHolesClear, frameModified, sameColour, noLoops, outOfSun,
             inConduit, bendRadiusMm, groundWireMm2, m4StarWasher, groundTorquesNm, installedSerials, reasons, ruleSetVersion, catalogVersion
    }

    /// Every field optional, so a report saved by an older version still opens.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil }
        method = d(.method); crewCount = d(.crewCount); ppe = d(.ppe); noJewelry = d(.noJewelry); weatherDry = d(.weatherDry)
        modulesDry = d(.modulesDry); rejectedSerials = d(.rejectedSerials) ?? []; boltTorquesNm = d(.boltTorquesNm) ?? []
        washerThicknessMm = d(.washerThicknessMm); washerOdMm = d(.washerOdMm); clampsPerModule = d(.clampsPerModule)
        clampOverlapMm = d(.clampOverlapMm); gapMm = d(.gapMm); rearClearanceMm = d(.rearClearanceMm)
        drainHolesClear = d(.drainHolesClear); frameModified = d(.frameModified); sameColour = d(.sameColour); noLoops = d(.noLoops)
        outOfSun = d(.outOfSun); inConduit = d(.inConduit); bendRadiusMm = d(.bendRadiusMm); groundWireMm2 = d(.groundWireMm2)
        m4StarWasher = d(.m4StarWasher); groundTorquesNm = d(.groundTorquesNm) ?? []; installedSerials = d(.installedSerials) ?? []
        reasons = d(.reasons) ?? [:]; ruleSetVersion = d(.ruleSetVersion); catalogVersion = d(.catalogVersion)
    }

    /// The engine's input; `crew` is the report's own count, used when the checklist has none.
    public func input(crew: Int?) -> InstallInput {
        var i = InstallInput(method: method ?? .clamp)
        i.boltTorquesNm = boltTorquesNm
        i.washerThicknessMm = washerThicknessMm; i.washerOdMm = washerOdMm
        i.clampOverlapMm = clampOverlapMm; i.clampsPerModule = clampsPerModule
        i.groundTorquesNm = groundTorquesNm
        i.bendRadiusMm = bendRadiusMm
        i.crewCount = crewCount ?? crew
        i.frameModified = frameModified
        i.gapMm = gapMm; i.rearClearanceMm = rearClearanceMm
        return i
    }

    public func validation(crew: Int?) -> Validation { RuleEngine.check(input(crew: crew)) }

    /// Sign-off: no block, and a reason for every warn.
    public func canSign(crew: Int?) -> Bool { validation(crew: crew).canSubmit(reasons: reasons) }

    /// The evidence ticks still not confirmed (they raise no rule but the warranty wants them), Thai.
    public var openTicks: [String] {
        let ticks: [(Bool?, String)] = [
            (ppe, "อุปกรณ์ป้องกันครบ (ZN-54)"), (noJewelry, "ไม่สวมเครื่องประดับ"), (weatherDry, "อากาศแห้ง ไม่มีฝน (ZN-56)"),
            (modulesDry, "แผงและขั้วต่อแห้ง (ZN-57)"), (drainHolesClear, "รูระบายน้ำไม่อุดตัน (ZN-92)"),
            (sameColour, "แผงสีเซลล์เดียวกันอยู่ด้วยกัน (ZN-89)"), (noLoops, "สายไม่วนเป็นห่วง (ZN-100)"),
            (outOfSun, "สายไม่โดนแดดโดยตรง (ZN-65)"), (inConduit, "สายเดินในท่อ (ZN-116)"), (m4StarWasher, "สายดิน M4 + แหวนจักร (ZN-120)"),
        ]
        return ticks.filter { $0.0 != true }.map(\.1)
    }

    /// Readings typed as "18, 19.5 20": every number in the text.
    public static func readings(_ text: String) -> [Double] {
        text.split(whereSeparator: { ", ;\n".contains($0) }).compactMap { Double($0) }
    }
    public static func text(_ readings: [Double]) -> String {
        readings.map { $0 == $0.rounded() ? String(Int($0)) : String($0) }.joined(separator: ", ")
    }

    public static func decode(_ json: String) -> InstallDailyCheck? {
        guard !json.isEmpty, let d = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(InstallDailyCheck.self, from: d)
    }
    public var json: String {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
