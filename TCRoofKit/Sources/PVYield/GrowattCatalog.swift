import Foundation

/// Growatt MAX inverters used on TCRoof projects.
/// Sources: "MAX50~80KTL3LV" datasheet (2023-05) and "MAX 100-125KTL3-X LV" datasheet (2026-05 update).
public enum GrowattCatalog {
    public static func max60KTL3LV() throws -> InverterSpec {
        try make(id: "growatt-max-60ktl3-lv", model: "MAX 60KTL3 LV",
                 startV: 250, nominalDCV: 585, mpptMin: 200, mppts: 6,
                 maxInA: 26, maxIscA: 32, maxPV: 90_000,
                 acW: 60_000, acVA: 66_600, etaMax: 0.988, etaEuro: 0.984)
    }

    public static func max80KTL3LV() throws -> InverterSpec {
        try make(id: "growatt-max-80ktl3-lv", model: "MAX 80KTL3 LV",
                 startV: 250, nominalDCV: 600, mpptMin: 200, mppts: 7,
                 maxInA: 26, maxIscA: 32, maxPV: 120_000,
                 acW: 80_000, acVA: 88_800, etaMax: 0.990, etaEuro: 0.985)
    }

    public static func max125KTL3XLV() throws -> InverterSpec {
        try make(id: "growatt-max-125ktl3-x-lv", model: "MAX 125KTL3-X LV",
                 startV: 195, nominalDCV: 600, mpptMin: 180, mppts: 10,
                 maxInA: 32, maxIscA: 40, maxPV: nil,
                 acW: 125_000, acVA: 137_500, etaMax: 0.988, etaEuro: 0.985)
    }

    public static func all() throws -> [InverterSpec] {
        [try max60KTL3LV(), try max80KTL3LV(), try max125KTL3XLV()]
    }

    private static func make(id: String, model: String, startV: Double, nominalDCV: Double,
                             mpptMin: Double, mppts: Int, maxInA: Double, maxIscA: Double,
                             maxPV: Double?, acW: Double, acVA: Double,
                             etaMax: Double, etaEuro: Double) throws -> InverterSpec {
        let loss = try InverterEfficiencyModel.fit(maxEfficiency: etaMax, euroEfficiency: etaEuro,
                                                   acNominalPowerW: acW)
        return InverterSpec(
            id: id, manufacturer: "Growatt", model: model, source: .datasheetFit,
            maxDCVoltageV: 1100, startVoltageV: startV, nominalDCVoltageV: nominalDCV,
            mpptMinV: mpptMin, mpptMaxV: 1000, mpptCount: mppts, stringsPerMppt: 2,
            maxInputCurrentPerMpptA: maxInA, maxShortCircuitCurrentPerMpptA: maxIscA,
            maxRecommendedPVPowerW: maxPV, acNominalPowerW: acW, acMaxApparentPowerVA: acVA,
            nominalACVoltageV: 400, maxEfficiency: etaMax, euroEfficiency: etaEuro,
            mpptEfficiency: 0.999, lossModel: loss, nightConsumptionW: 1)
    }
}
