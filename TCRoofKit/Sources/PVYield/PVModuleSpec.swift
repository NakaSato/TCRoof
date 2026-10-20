import Foundation

/// Portable PV module specification.
///
/// One JSON document per module model. It carries the datasheet ratings plus the
/// PVsyst one-diode parameters, so the same file drives both the TCRoof yield engine
/// and anything else that reads JSON. All values are SI units at STC
/// (1000 W/m², 25 °C cell, AM1.5) unless the property name says otherwise.
public struct PVModuleSpec: Codable, Sendable, Identifiable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Stable ID used by the TCRoof component library, e.g. "znshine-zxm8-tph144-580".
    public var id: String
    public var manufacturer: String
    public var model: String
    public var technology: CellTechnology
    /// Where `oneDiode` came from. `.pan` reproduces PVsyst most closely.
    public var source: ModelSource

    public var stc: STCRatings
    public var temperatureCoefficients: TemperatureCoefficients
    public var cells: CellLayout
    public var oneDiode: OneDiodeParameters

    public var dimensions: Dimensions?
    /// Bifaciality factor (0…1) when the module is bifacial.
    public var bifaciality: Double?
    /// Light-induced degradation, % (PVsyst "LIDLoss").
    public var lidPercent: Double?
    /// User-defined IAM profile from the PAN file, if any.
    public var iamProfile: [IAMPoint]?
    public var maxSystemVoltageV: Double?

    public init(
        id: String, manufacturer: String, model: String, technology: CellTechnology,
        source: ModelSource, stc: STCRatings, temperatureCoefficients: TemperatureCoefficients,
        cells: CellLayout, oneDiode: OneDiodeParameters, dimensions: Dimensions? = nil,
        bifaciality: Double? = nil, lidPercent: Double? = nil, iamProfile: [IAMPoint]? = nil,
        maxSystemVoltageV: Double? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.manufacturer = manufacturer
        self.model = model
        self.technology = technology
        self.source = source
        self.stc = stc
        self.temperatureCoefficients = temperatureCoefficients
        self.cells = cells
        self.oneDiode = oneDiode
        self.dimensions = dimensions
        self.bifaciality = bifaciality
        self.lidPercent = lidPercent
        self.iamProfile = iamProfile
        self.maxSystemVoltageV = maxSystemVoltageV
    }
}

public enum CellTechnology: String, Codable, Sendable {
    case monoSi, polySi, hit, cdTe, cigs, aSi, other
}

public enum ModelSource: String, Codable, Sendable {
    /// Parameters read from a PVsyst .PAN file.
    case pan
    /// Rs, γ and μγ fitted from datasheet values (see `DatasheetFitter`).
    case datasheetFit
}

public struct STCRatings: Codable, Sendable, Equatable {
    public var pNomW: Double
    public var vmpV: Double
    public var impA: Double
    public var vocV: Double
    public var iscA: Double
    /// Power tolerance, % (e.g. 0 / +3).
    public var toleranceMinusPercent: Double?
    public var tolerancePlusPercent: Double?

    public init(pNomW: Double, vmpV: Double, impA: Double, vocV: Double, iscA: Double,
                toleranceMinusPercent: Double? = nil, tolerancePlusPercent: Double? = nil) {
        self.pNomW = pNomW; self.vmpV = vmpV; self.impA = impA
        self.vocV = vocV; self.iscA = iscA
        self.toleranceMinusPercent = toleranceMinusPercent
        self.tolerancePlusPercent = tolerancePlusPercent
    }
}

public struct TemperatureCoefficients: Codable, Sendable, Equatable {
    /// dIsc/dT in A/K (PAN `muISC` is mA/K).
    public var muIscAPerK: Double
    /// dVoc/dT in V/K (PAN `muVocSpec` is mV/K). Reference only; the one-diode model produces its own.
    public var muVocVPerK: Double
    /// dPmp/dT in %/K (PAN `muPmpReq`). Used to fit μγ.
    public var muPmpPercentPerK: Double

    public init(muIscAPerK: Double, muVocVPerK: Double, muPmpPercentPerK: Double) {
        self.muIscAPerK = muIscAPerK; self.muVocVPerK = muVocVPerK
        self.muPmpPercentPerK = muPmpPercentPerK
    }
}

public struct CellLayout: Codable, Sendable, Equatable {
    /// Cells in series per module (PAN `NCelS`). Half-cut 144-cell modules are usually 72.
    public var cellsInSeries: Int
    /// Parallel cell strings (PAN `NCelP`). Half-cut modules are usually 2.
    public var cellsInParallel: Int
    public var bypassDiodes: Int?

    public init(cellsInSeries: Int, cellsInParallel: Int = 1, bypassDiodes: Int? = nil) {
        self.cellsInSeries = cellsInSeries
        self.cellsInParallel = cellsInParallel
        self.bypassDiodes = bypassDiodes
    }
}

/// PVsyst one-diode parameters at reference conditions.
public struct OneDiodeParameters: Codable, Sendable, Equatable {
    public var rSeriesOhm: Double
    /// Rsh at 1000 W/m² (PAN `RShunt`).
    public var rShuntRefOhm: Double
    /// Rsh at 0 W/m² (PAN `Rp_0`). PVsyst default is 4 × `rShuntRefOhm`.
    public var rShunt0Ohm: Double
    /// Exponent of the Rsh(G) law (PAN `Rp_Exp`), default 5.5.
    public var rShuntExp: Double
    /// Diode ideality factor at reference (PAN `Gamma`).
    public var gammaRef: Double
    /// dγ/dT in 1/K (PAN `muGamma`).
    public var muGammaPerK: Double

    public init(rSeriesOhm: Double, rShuntRefOhm: Double, rShunt0Ohm: Double? = nil,
                rShuntExp: Double = 5.5, gammaRef: Double, muGammaPerK: Double) {
        self.rSeriesOhm = rSeriesOhm
        self.rShuntRefOhm = rShuntRefOhm
        self.rShunt0Ohm = rShunt0Ohm ?? 4 * rShuntRefOhm
        self.rShuntExp = rShuntExp
        self.gammaRef = gammaRef
        self.muGammaPerK = muGammaPerK
    }
}

public struct Dimensions: Codable, Sendable, Equatable {
    public var widthM: Double
    public var heightM: Double
    public var depthM: Double?
    public var areaM2: Double { widthM * heightM }

    public init(widthM: Double, heightM: Double, depthM: Double? = nil) {
        self.widthM = widthM; self.heightM = heightM; self.depthM = depthM
    }
}

public struct IAMPoint: Codable, Sendable, Equatable {
    public var angleDeg: Double
    public var factor: Double
    public init(angleDeg: Double, factor: Double) { self.angleDeg = angleDeg; self.factor = factor }
}

// MARK: - Validation and JSON

public extension PVModuleSpec {
    /// Sanity checks before the spec is accepted into the component library.
    /// Returns human-readable problems; an empty array means the spec is usable.
    func validate() -> [String] {
        var issues: [String] = []
        let s = stc
        if s.pNomW <= 0 || s.vmpV <= 0 || s.impA <= 0 || s.vocV <= 0 || s.iscA <= 0 {
            issues.append("STC values must be positive")
        }
        if s.vmpV >= s.vocV { issues.append("Vmp must be below Voc") }
        if s.impA >= s.iscA { issues.append("Imp must be below Isc") }
        let vi = s.vmpV * s.impA
        if s.pNomW > 0, abs(vi - s.pNomW) / s.pNomW > 0.02 {
            issues.append(String(format: "Vmp × Imp = %.1f W differs from Pnom %.1f W by more than 2%%", vi, s.pNomW))
        }
        if cells.cellsInSeries <= 0 { issues.append("cellsInSeries must be positive") }
        if temperatureCoefficients.muPmpPercentPerK >= 0 { issues.append("muPmp should be negative") }
        let d = oneDiode
        if d.rSeriesOhm < 0 || d.rShuntRefOhm <= 0 || d.rShunt0Ohm <= 0 {
            issues.append("One-diode resistances out of range")
        }
        if d.gammaRef < 0.5 || d.gammaRef > 2.5 { issues.append("gammaRef outside 0.5…2.5") }
        if let b = bifaciality, b < 0 || b > 1 { issues.append("bifaciality must be within 0…1") }
        return issues
    }

    func jsonData(pretty: Bool = true) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try enc.encode(self)
    }

    static func from(json data: Data) throws -> PVModuleSpec {
        try JSONDecoder().decode(PVModuleSpec.self, from: data)
    }
}
