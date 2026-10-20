import Foundation

/// Datasheet entries for modules TCRoof uses, ready for `DatasheetFitter`.
/// Source: ZNSHINE ZXM7-UHLDD144 Series datasheet, version 2301.E (© ZNSHINE SOLAR 2022).
public enum ZnshineZXM7UHLDD144 {
    /// STC values per power class (datasheet "Electrical characteristics | STC").
    public static let stc: [Int: STCRatings] = [
        565: STCRatings(pNomW: 565, vmpV: 42.20, impA: 13.39, vocV: 50.90, iscA: 14.17, toleranceMinusPercent: 3, tolerancePlusPercent: 3),
        570: STCRatings(pNomW: 570, vmpV: 42.40, impA: 13.45, vocV: 51.10, iscA: 14.23, toleranceMinusPercent: 3, tolerancePlusPercent: 3),
        575: STCRatings(pNomW: 575, vmpV: 42.60, impA: 13.50, vocV: 51.30, iscA: 14.29, toleranceMinusPercent: 3, tolerancePlusPercent: 3),
        580: STCRatings(pNomW: 580, vmpV: 42.80, impA: 13.56, vocV: 51.50, iscA: 14.35, toleranceMinusPercent: 3, tolerancePlusPercent: 3),
        585: STCRatings(pNomW: 585, vmpV: 43.00, impA: 13.61, vocV: 51.70, iscA: 14.41, toleranceMinusPercent: 3, tolerancePlusPercent: 3),
        590: STCRatings(pNomW: 590, vmpV: 43.20, impA: 13.66, vocV: 51.90, iscA: 14.46, toleranceMinusPercent: 3, tolerancePlusPercent: 3),
        595: STCRatings(pNomW: 595, vmpV: 43.40, impA: 13.71, vocV: 52.10, iscA: 14.51, toleranceMinusPercent: 3, tolerancePlusPercent: 3),
    ]

    /// NMOT values (800 W/m², 20 °C ambient, 1 m/s; NMOT 44 °C) — used only to check a fit.
    public static let nmotPmaxW: [Int: Double] = [
        565: 426.40, 570: 430.30, 575: 433.90, 580: 437.80, 585: 441.40, 590: 447.10, 595: 450.80,
    ]
    public static let nmotCellTempC = 44.0

    /// Pmax −0.30 %/K, Voc −0.25 %/K, Isc +0.046 %/K (converted to absolute per class).
    public static func temperatureCoefficients(_ s: STCRatings) -> TemperatureCoefficients {
        TemperatureCoefficients(muIscAPerK: 0.00046 * s.iscA, muVocVPerK: -0.0025 * s.vocV, muPmpPercentPerK: -0.30)
    }

    /// 144 half-cells (6 × 24) → 72 in series × 2 parallel, 3 bypass diodes.
    public static let cells = CellLayout(cellsInSeries: 72, cellsInParallel: 2, bypassDiodes: 3)
    public static let dimensions = Dimensions(widthM: 1.134, heightM: 2.278, depthM: 0.030)
    public static let bifaciality = 0.80
    /// Linear power warranty: 1 % first year, 0.40 %/yr after, 87.40 % at year 30.
    public static let firstYearDegradationPercent = 1.0
    public static let annualDegradationPercent = 0.40

    public static func fit(_ watts: Int, assumptions: DatasheetFitter.Assumptions = .init()) throws -> DatasheetFitter.Result {
        guard let s = stc[watts] else { throw DatasheetFitter.FitError.noSolution("No \(watts) W class in datasheet") }
        var r = try DatasheetFitter.fit(
            id: "znshine-zxm7-uhldd144-\(watts)", manufacturer: "ZNSHINE SOLAR",
            model: "ZXM7-UHLDD144-\(watts)", technology: .monoSi,
            stc: s, temperatureCoefficients: temperatureCoefficients(s), cells: cells,
            dimensions: dimensions, assumptions: assumptions)
        r.spec.bifaciality = bifaciality
        r.spec.maxSystemVoltageV = 1500
        return r
    }
}
