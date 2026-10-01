import Foundation

/// PV module metadata as stored in `pv-modules/*.json` (schema `tcroof.pv-module/1`).
/// One file per series; each electrical rating is a `Variant`.
public struct PVModuleSpec: Codable, Sendable, Identifiable {
    public var schema: String
    public var id: String
    public var manufacturer: String
    public var series: String
    public var description: String
    public var technology: String
    public var cell: Cell
    public var bifacial: Bool
    public var bifacialFactor: Tolerance?
    public var glass: String?
    public var source: Source
    public var mechanical: Mechanical
    public var limits: Limits
    public var temperature: Temperature
    public var warranty: Warranty
    public var packaging: Packaging?
    public var certifications: [String]
    public var defaultVariant: String
    public var variants: [Variant]

    public struct Cell: Codable, Sendable { public var type: String; public var count: Int; public var layout: String; public var waferMm: Int? }
    public struct Tolerance: Codable, Sendable { public var value: Double; public var tolerance: Double }
    public struct Source: Codable, Sendable { public var datasheet: String; public var version: String; public var date: String; public var note: String? }
    public struct Mechanical: Codable, Sendable {
        public var lengthMm: Double, widthMm: Double, thicknessMm: Double, toleranceMm: Double?
        public var weightKg: Double, weightToleranceKg: Double?, areaM2: Double
        public var frame: Frame?
        public var mountingHoles: [Holes]
        public var groundingHoles: Holes2?
        public var drainageHoles: Holes2?
        public var junctionBox: JunctionBox?
        public var cable: Cable?
        public var connector: String?
        public struct Frame: Codable, Sendable { public var heightMm: Double; public var flangeMm: Double }
        public struct Holes: Codable, Sendable { public var count: Int; public var slotMm: [Double]; public var pitchAlongLengthMm: Double; public var pitchAcrossWidthMm: Double }
        public struct Holes2: Codable, Sendable { public var count: Int; public var diameterMm: Double?; public var slotMm: [Double]? }
        public struct JunctionBox: Codable, Sendable { public var ip: String; public var bypassDiodes: Int }
        public struct Cable: Codable, Sendable { public var crossSectionMm2: Double; public var lengthMm: Double }
    }
    public struct Limits: Codable, Sendable {
        public var maxSystemVoltageV: Double, maxSeriesFuseA: Double
        public var operatingTempC: Range
        public var frontStaticLoadPa: Double, rearStaticLoadPa: Double
        public var fireRating: String?
        public struct Range: Codable, Sendable { public var min: Double; public var max: Double }
    }
    public struct Temperature: Codable, Sendable {
        public var nmotC: Double, nmotToleranceC: Double?
        public var pmaxPctPerC: Double, pmaxCoeffTolerance: Double?, vocPctPerC: Double, iscPctPerC: Double
    }
    public struct Warranty: Codable, Sendable { public var productYears: Int; public var outputYears: Int; public var annualDegradationPct: Double }
    public struct Packaging: Codable, Sendable { public var piecesPerBox: Int; public var piecesPer40HQ: Int }

    public struct Variant: Codable, Sendable, Identifiable {
        public var id: String
        public var pmaxW: Double
        public var stc: Point
        public var nmot: PointP
        public var rearGain25: PointP?
        public struct Point: Codable, Sendable { public var vmpV: Double, impA: Double, vocV: Double, iscA: Double, efficiencyPct: Double }
        public struct PointP: Codable, Sendable { public var pmaxW: Double, vmpV: Double, impA: Double, vocV: Double, iscA: Double }
    }

    public var defaultRating: Variant? { variants.first { $0.id == defaultVariant } ?? variants.first }

    /// Voc at the coldest cell temperature, for string sizing against the inverter max DC voltage.
    public func vocAt(cellC: Double, variant v: Variant) -> Double { v.stc.vocV * (1 + temperature.vocPctPerC / 100 * (cellC - 25)) }

    /// Most modules per string that keeps cold Voc under the module and inverter limits.
    public func maxModulesPerString(inverterMaxVdc: Double, minCellC: Double = 10, variant v: Variant) -> Int {
        let limit = min(inverterMaxVdc, limits.maxSystemVoltageV)
        return Int((limit / vocAt(cellC: minCellC, variant: v)).rounded(.down))
    }
}

/// PV module series bundled with the app (`Resources/pv-modules/*.json`).
public enum PVModuleCatalog {
    /// Every bundled series, sorted by manufacturer then series.
    public static let all: [PVModuleSpec] = {
        guard let dir = Bundle.module.url(forResource: "pv-modules", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(PVModuleSpec.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.manufacturer, $0.series) < ($1.manufacturer, $1.series) }
    }()

    /// The rating chosen in settings by variant id, e.g. "zxm7-uhldd144-580".
    public static func variant(_ id: String) -> (spec: PVModuleSpec, variant: PVModuleSpec.Variant)? {
        for s in all { if let v = s.variants.first(where: { $0.id == id }) { return (s, v) } }
        return nil
    }

    /// Default rating for new installs: the first bundled series' default variant.
    public static var defaultVariantID: String { all.first?.defaultRating?.id ?? "" }

    /// kWp for a panel count at the given rating.
    public static func kWp(panels: Int, variantID: String) -> Double? {
        guard let w = variant(variantID)?.variant.pmaxW else { return nil }
        return Double(panels) * w / 1000
    }
}
