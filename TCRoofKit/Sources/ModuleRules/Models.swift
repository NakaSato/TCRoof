import Foundation

/// Module installation rules (docs/specs/module-install-rules.md): ZNSHINE's installation manual, Section 5, as a
/// module catalog, mounting profiles, a versioned rule set and a rule engine. Foundation only, no UI.

/// Big: 72 / 78 / 144 / 156 cells; small: 60 / 66 / 120 / 132 (source §5.1).
public enum SizeClass: String, Codable, Sendable {
    case big, small
    public init(cellCount: Int) { self = [60, 66, 120, 132].contains(cellCount) ? .small : .big }
}

/// The four approved methods (source §5.5).
public enum MountingMethod: String, Codable, Sendable, CaseIterable {
    case bolt, tracker1P, tracker2V, clamp
}

public enum ClampSide: String, Codable, Sendable { case long, short }

/// block stops submit; warn needs a written reason; info only shows a hint.
public enum Severity: String, Codable, Sendable, Comparable {
    case info, warn, block
    public static func < (a: Severity, b: Severity) -> Bool {
        let order: [Severity] = [.info, .warn, .block]
        return order.firstIndex(of: a)! < order.firstIndex(of: b)!
    }
}

/// Where a rule is checked.
public enum Stage: String, Codable, Sendable { case survey, layout, install, commission }

public struct ModuleModel: Codable, Sendable, Identifiable, Equatable {
    public var id: String                 // "ZXM7-UHLDD144-570"
    public var manufacturer: String       // "ZNSHINE"
    public var series: String
    public var technology: String         // "mono" | "poly"
    public var cellCount: Int
    public var pmaxW: Double, vmpV: Double, impA: Double, vocV: Double, iscA: Double
    public var stcTolerancePct: Double
    public var lengthMm: Double, widthMm: Double, thicknessMm: Double, weightKg: Double
    public var maxSystemVoltageV: Double
    public var maxSeriesFuseA: Double
    /// From the datasheet; nil blocks string sizing (ZN-106b).
    public var betaVocPctPerC: Double?
    public var gammaPmaxPctPerC: Double?
    public var bifacial: Bool
    public var doubleGlass: Bool
    // From the module's datasheet, when the catalog has it (all optional, so a catalog without them still loads).
    /// Max static load, front and rear, Pa (the module's own test; the mounting method's rating is `MountingProfile`).
    public var frontLoadPa: Double?, rearLoadPa: Double?
    public var nmotC: Double?
    public var alphaIscPctPerC: Double?
    public var bifacialFactor: Double?
    public var cable: String?, connector: String?, junctionBox: String?
    /// The datasheet version these values come from.
    public var datasheet: String?

    public var sizeClass: SizeClass { SizeClass(cellCount: cellCount) }

    /// One line of the datasheet values, Thai, for the pickers.
    public var datasheetLine: String? {
        var parts: [String] = []
        if let f = frontLoadPa, let r = rearLoadPa { parts.append(String(format: "รับแรงหน้า %.0f / หลัง %.0f Pa", f, r)) }
        if let b = betaVocPctPerC { parts.append(String(format: "Voc %.2f %%/°C", b)) }
        if let n = nmotC { parts.append(String(format: "NMOT %.0f °C", n)) }
        if let c = cable { parts.append("สาย " + c) }
        if let c = connector { parts.append(c) }
        guard !parts.isEmpty else { return nil }
        return (datasheet.map { "datasheet " + $0 + ": " } ?? "") + parts.joined(separator: " | ")
    }

    public init(id: String, manufacturer: String = "ZNSHINE", series: String = "", technology: String = "mono", cellCount: Int,
                pmaxW: Double, vmpV: Double, impA: Double, vocV: Double, iscA: Double, stcTolerancePct: Double = 3,
                lengthMm: Double, widthMm: Double, thicknessMm: Double = 30, weightKg: Double = 0,
                maxSystemVoltageV: Double = 1500, maxSeriesFuseA: Double = 25, betaVocPctPerC: Double? = nil,
                gammaPmaxPctPerC: Double? = nil, bifacial: Bool = false, doubleGlass: Bool = false) {
        self.id = id; self.manufacturer = manufacturer; self.series = series; self.technology = technology
        self.cellCount = cellCount; self.pmaxW = pmaxW; self.vmpV = vmpV; self.impA = impA; self.vocV = vocV; self.iscA = iscA
        self.stcTolerancePct = stcTolerancePct; self.lengthMm = lengthMm; self.widthMm = widthMm
        self.thicknessMm = thicknessMm; self.weightKg = weightKg; self.maxSystemVoltageV = maxSystemVoltageV
        self.maxSeriesFuseA = maxSeriesFuseA; self.betaVocPctPerC = betaVocPctPerC; self.gammaPmaxPctPerC = gammaPmaxPctPerC
        self.bifacial = bifacial; self.doubleGlass = doubleGlass
    }
}

/// A rated load for a group of modules under one method.
public struct LoadRating: Codable, Sendable, Equatable {
    public var cellCounts: [Int]
    public var clampSide: ClampSide?
    /// Positive (push) and negative (pull) loads, Pa.
    public var pushPa: Double, pullPa: Double
    public var note: String?
}

/// An approved mounting method: holes, bolt, torque, washer and the load ratings.
public struct MountingProfile: Codable, Sendable, Equatable {
    public var method: MountingMethod
    public var holeSpec: String
    public var bolt: String
    public var torqueNm: ClosedRange<Double>
    public var washerMinThicknessMm: Double
    public var washerOdMm: ClosedRange<Double>
    public var loads: [LoadRating]

    /// The rating for a module, clamped on `side` (clamp method), nil when the method isn't rated for it.
    public func load(cellCount: Int, side: ClampSide? = nil) -> LoadRating? {
        loads.first { $0.cellCounts.contains(cellCount) && (method != .clamp || $0.clampSide == (side ?? .long)) }
    }

    enum CodingKeys: String, CodingKey { case method, holeSpec, bolt, torqueNm, washerMinThicknessMm, washerOdMm, loads }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        method = try c.decode(MountingMethod.self, forKey: .method)
        holeSpec = try c.decode(String.self, forKey: .holeSpec)
        bolt = try c.decode(String.self, forKey: .bolt)
        let t = try c.decode([Double].self, forKey: .torqueNm), o = try c.decode([Double].self, forKey: .washerOdMm)
        torqueNm = t[0]...t[1]
        washerMinThicknessMm = try c.decode(Double.self, forKey: .washerMinThicknessMm)
        washerOdMm = o[0]...o[1]
        loads = try c.decode([LoadRating].self, forKey: .loads)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(method, forKey: .method); try c.encode(holeSpec, forKey: .holeSpec); try c.encode(bolt, forKey: .bolt)
        try c.encode([torqueNm.lowerBound, torqueNm.upperBound], forKey: .torqueNm)
        try c.encode(washerMinThicknessMm, forKey: .washerMinThicknessMm)
        try c.encode([washerOdMm.lowerBound, washerOdMm.upperBound], forKey: .washerOdMm)
        try c.encode(loads, forKey: .loads)
    }
}

/// One rule of the rule set: what the engine reports when its condition holds.
public struct RuleSpec: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var stages: [Stage]
    public var severity: Severity
    /// The form field the badge goes on.
    public var field: String
    public var message_en: String
    public var message_th: String
}

/// A rule that fired, with its message filled in.
public struct RuleResult: Sendable, Identifiable, Equatable {
    public let id: String
    public let severity: Severity
    public let field: String
    public let messageTH: String
    public let messageEN: String
}
