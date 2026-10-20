import Foundation

/// Builds one-diode parameters from a datasheet when no PVsyst .PAN file exists.
///
/// Targets, in order:
///  1. γ so the model reproduces Pmp = Vmp·Imp at STC (for a given Rs).
///  2. Rs so the relative efficiency at 200 W/m², 25 °C matches the datasheet's low-light
///     figure (or a typical c-Si default). Low-light behaviour is what Rs mostly controls,
///     and it drives annual yield far more than the exact Vmp does.
///  3. μγ so the model's dPmp/dT matches the datasheet μPmp.
/// Rsh comes from assumptions (it barely affects STC power).
///
/// Matching Vmp exactly instead of low light gives an unphysical γ and up to −7 % error at
/// 200 W/m², so Vmp is reported as a check, not a target. Prefer the manufacturer's PAN file
/// whenever it exists: a fitted module will not match PVsyst as closely.
public enum DatasheetFitter {
    public struct Assumptions: Sendable {
        /// Rsh at 1000 W/m². `nil` → 300 Ω × (Ns / 72), typical of modern c-Si PAN files.
        public var rShuntRefOhm: Double?
        public var rShunt0Factor: Double = 4
        public var rShuntExp: Double = 5.5
        /// η(200 W/m²) / η(1000 W/m²) at 25 °C. Use the datasheet's low-irradiance figure
        /// when given; `nil` → 0.975, typical of modern mono c-Si PAN models.
        public var relativeEfficiencyAt200: Double?
        public init(rShuntRefOhm: Double? = nil, relativeEfficiencyAt200: Double? = nil) {
            self.rShuntRefOhm = rShuntRefOhm
            self.relativeEfficiencyAt200 = relativeEfficiencyAt200
        }
    }

    public enum FitError: Error, Equatable {
        case invalidDatasheet([String])
        case noSolution(String)
    }

    public struct Result: Sendable {
        public var spec: PVModuleSpec
        /// Model vs datasheet at STC, for display in the component library.
        public var pmpErrorPercent: Double
        public var vmpErrorPercent: Double
        public var muPmpErrorPercentPerK: Double
        public var relativeEfficiencyAt200: Double
    }

    public static func fit(
        id: String, manufacturer: String, model: String, technology: CellTechnology,
        stc: STCRatings, temperatureCoefficients tc: TemperatureCoefficients, cells: CellLayout,
        dimensions: Dimensions? = nil, assumptions: Assumptions = Assumptions()
    ) throws -> Result {
        let rsh = assumptions.rShuntRefOhm ?? 300 * Double(cells.cellsInSeries) / 72
        let lowLightTarget = assumptions.relativeEfficiencyAt200 ?? 0.975
        func makeSpec(rs: Double, gamma: Double, muGamma: Double) -> PVModuleSpec {
            PVModuleSpec(
                id: id, manufacturer: manufacturer, model: model, technology: technology,
                source: .datasheetFit, stc: stc, temperatureCoefficients: tc, cells: cells,
                oneDiode: OneDiodeParameters(rSeriesOhm: rs, rShuntRefOhm: rsh,
                                             rShunt0Ohm: assumptions.rShunt0Factor * rsh,
                                             rShuntExp: assumptions.rShuntExp,
                                             gammaRef: gamma, muGammaPerK: muGamma),
                dimensions: dimensions)
        }
        let pre = makeSpec(rs: 0.1, gamma: 1.0, muGamma: 0).validate()
        if !pre.isEmpty { throw FitError.invalidDatasheet(pre) }

        let pTarget = stc.vmpV * stc.impA

        // 1. For a given Rs, γ such that Pmp(STC) = target. Pmp falls monotonically with γ.
        func gammaFor(rs: Double) -> Double? {
            func pmp(_ g: Double) -> Double {
                PVsystSingleDiodeModel(spec: makeSpec(rs: rs, gamma: g, muGamma: 0))
                    .maxPowerPoint(effectiveIrradiance: 1000, cellTempC: 25).p
            }
            var lo = 0.5, hi = 2.5
            guard pmp(lo) >= pTarget, pmp(hi) <= pTarget else { return nil }
            for _ in 0..<70 {
                let mid = 0.5 * (lo + hi)
                if pmp(mid) > pTarget { lo = mid } else { hi = mid }
            }
            return 0.5 * (lo + hi)
        }
        func relEff200(rs: Double, gamma: Double) -> Double {
            let m = PVsystSingleDiodeModel(spec: makeSpec(rs: rs, gamma: gamma, muGamma: 0))
            let p1000 = m.maxPowerPoint(effectiveIrradiance: 1000, cellTempC: 25).p
            let p200 = m.maxPowerPoint(effectiveIrradiance: 200, cellTempC: 25).p
            return (p200 / 200) / (p1000 / 1000)
        }

        // 2. Scan Rs, then bisect on the sign change of (η200_model − target).
        let rsMax = 0.5 * stc.vocV / stc.iscA
        var samples: [(rs: Double, g: Double, err: Double)] = []
        for k in 0...40 {
            let rs = rsMax * Double(k) / 40
            if let g = gammaFor(rs: rs) { samples.append((rs, g, relEff200(rs: rs, gamma: g) - lowLightTarget)) }
        }
        guard !samples.isEmpty else { throw FitError.noSolution("No (Rs, γ) reproduces Pmp at STC") }
        var best = samples.min { abs($0.err) < abs($1.err) }!
        for (s0, s1) in zip(samples, samples.dropFirst()) where s0.err.sign != s1.err.sign {
            var lo = s0, hi = s1
            for _ in 0..<50 {
                let rm = 0.5 * (lo.rs + hi.rs)
                guard let g = gammaFor(rs: rm) else { break }
                let mid = (rs: rm, g: g, err: relEff200(rs: rm, gamma: g) - lowLightTarget)
                if mid.err.sign == lo.err.sign { lo = mid } else { hi = mid }
            }
            best = abs(lo.err) < abs(hi.err) ? lo : hi
            break
        }

        // μγ so that the model's Pmp temperature coefficient (25 → 50 °C at 1000 W/m²) matches μPmp.
        func modelMuPmp(_ muGamma: Double) -> Double {
            let m = PVsystSingleDiodeModel(spec: makeSpec(rs: best.rs, gamma: best.g, muGamma: muGamma))
            let p25 = m.maxPowerPoint(effectiveIrradiance: 1000, cellTempC: 25).p
            let p50 = m.maxPowerPoint(effectiveIrradiance: 1000, cellTempC: 50).p
            return (p50 / p25 - 1) / 25 * 100
        }
        var mlo = -0.01, mhi = 0.01
        let target = tc.muPmpPercentPerK
        let flo = modelMuPmp(mlo) - target, fhi = modelMuPmp(mhi) - target
        var muGamma = 0.0
        if flo.sign != fhi.sign {
            var fl = flo
            for _ in 0..<60 {
                let mid = 0.5 * (mlo + mhi)
                let fm = modelMuPmp(mid) - target
                if fm.sign == fl.sign { mlo = mid; fl = fm } else { mhi = mid }
            }
            muGamma = 0.5 * (mlo + mhi)
        } else {
            muGamma = abs(flo) < abs(fhi) ? mlo : mhi
        }

        let spec = makeSpec(rs: best.rs, gamma: best.g, muGamma: muGamma)
        let m = PVsystSingleDiodeModel(spec: spec)
        let mpp = m.maxPowerPoint(effectiveIrradiance: 1000, cellTempC: 25)
        return Result(
            spec: spec,
            pmpErrorPercent: (mpp.p / pTarget - 1) * 100,
            vmpErrorPercent: (mpp.v / stc.vmpV - 1) * 100,
            muPmpErrorPercentPerK: modelMuPmp(muGamma) - target,
            relativeEfficiencyAt200: relEff200(rs: best.rs, gamma: best.g))
    }
}
