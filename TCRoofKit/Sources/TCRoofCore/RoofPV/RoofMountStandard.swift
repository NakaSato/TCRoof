import Foundation

/// The roof mounting standard (docs/specs/roof-pv-layout.md §3): module, clamping zone, L-foot spacing and setbacks.
/// One set per company, kept in the survey settings; a job may edit it. Lengths in metres.
public struct RoofMountStandard: Codable, Equatable, Sendable {
    /// Module, portrait: the long side runs up the slope.
    public var moduleLength = 2.28
    public var moduleWidth = 1.13
    public var moduleWp = 600.0
    /// Rail distance from the module's end, from the datasheet.
    public var clampMin = 0.34
    public var clampMax = 0.68
    /// L-foot spacing along a rail.
    public var footSpacing = 1.20
    /// Setbacks from the eave, the ridge, and the verges and hips (one value for both).
    public var setEave = 0.30
    public var setRidge = 0.40
    public var setVerge = 0.50

    // fixed values, not shown in the settings
    public var moduleGap = 0.02
    public var railOverhang = 0.05
    public var footCantilever = 0.40
    public var footMinBay = 0.30
    /// Rail length as bought, for the splices.
    public var railStock = 4.20
    /// A face below this share of the best face's yield is left empty.
    public var faceMinShare = 0.85

    public init() {}

    public static let standard = RoofMountStandard()

    public var moduleKW: Double { moduleWp / 1000 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RoofMountStandard()
        func v(_ k: CodingKeys, _ def: Double) -> Double { (try? c.decodeIfPresent(Double.self, forKey: k)).flatMap { $0 } ?? def }
        moduleLength = v(.moduleLength, d.moduleLength); moduleWidth = v(.moduleWidth, d.moduleWidth); moduleWp = v(.moduleWp, d.moduleWp)
        clampMin = v(.clampMin, d.clampMin); clampMax = v(.clampMax, d.clampMax); footSpacing = v(.footSpacing, d.footSpacing)
        setEave = v(.setEave, d.setEave); setRidge = v(.setRidge, d.setRidge); setVerge = v(.setVerge, d.setVerge)
        moduleGap = v(.moduleGap, d.moduleGap); railOverhang = v(.railOverhang, d.railOverhang)
        footCantilever = v(.footCantilever, d.footCantilever); footMinBay = v(.footMinBay, d.footMinBay)
        railStock = v(.railStock, d.railStock); faceMinShare = v(.faceMinShare, d.faceMinShare)
    }

    /// The setback of a face edge of this kind.
    func setback(_ edge: RoofFace.Edge) -> Double {
        switch edge {
        case .eave: setEave
        case .ridge: setRidge
        case .verge, .hip: setVerge
        }
    }
}

/// What stands on the roof, by kind: how far modules and L-feet keep from it, and its default height (§3.3).
public enum RoofObstacleKind: String, Codable, CaseIterable, Sendable {
    case skylight, turbine, stack, pipe, other

    public var title: String {
        switch self {
        case .skylight: "แผ่นโปร่งแสง"
        case .turbine: "ลูกหมุนระบายอากาศ"
        case .stack: "ปล่อง / ท่อไอเสีย"
        case .pipe: "ท่อระบาย"
        case .other: "สิ่งกีดขวางอื่น"
        }
    }

    /// Modules keep this far from it (m).
    public var moduleClearance: Double { self == .skylight ? 0.10 : 0.30 }
    /// L-feet keep this far from it (m): never fixed into a skylight or its lap.
    public var footClearance: Double { self == .skylight ? 0.50 : 0.30 }
    /// Height above the roof when the survey has none (m).
    public var defaultHeight: Double {
        switch self {
        case .turbine: 0.60
        case .stack: 2.00
        case .pipe: 0.50
        case .skylight, .other: 0
        }
    }
}
