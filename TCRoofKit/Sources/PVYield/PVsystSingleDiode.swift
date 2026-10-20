import Foundation

/// PVsyst one-diode module model.
///
/// Same equations as PVsyst and pvlib `calcparams_pvsyst` + `singlediode`:
///
///     IL   = (G/Gref) · [IL_ref + μIsc·(Tc − Tref)]
///     γ    = γref + μγ·(Tc − Tref)
///     I0   = I0_ref · (Tc/Tref)³ · exp[ q·Eg/(k·γ) · (1/Tref − 1/Tc) ]      (kelvin)
///     a    = γ · Ns · k·Tc / q
///     Rsh  = Rsh_base + (Rsh_0 − Rsh_base)·exp(−Rsh_exp·G/Gref)
///     I    = IL − I0·[exp((V + I·Rs)/a) − 1] − (V + I·Rs)/Rsh
///
/// IL_ref and I0_ref are derived from Isc and Voc at STC (closed form).
public struct PVsystSingleDiodeModel: Sendable {
    public static let boltzmann = 1.380649e-23      // J/K
    public static let elementaryCharge = 1.602176634e-19  // C
    public static let bandgapEV = 1.121              // eV, crystalline Si (PVsyst / pvlib default)
    public static let gRef = 1000.0                  // W/m²
    public static let tRefC = 25.0                   // °C

    public let spec: PVModuleSpec
    public let iLRef: Double
    public let i0Ref: Double

    public init(spec: PVModuleSpec) {
        self.spec = spec
        let tRefK = Self.tRefC + 273.15
        let a = Self.modifiedIdealityVoltage(gamma: spec.oneDiode.gammaRef,
                                             cellsInSeries: spec.cells.cellsInSeries, cellTempK: tRefK)
        let refs = Self.referenceCurrents(isc: spec.stc.iscA, voc: spec.stc.vocV,
                                          rs: spec.oneDiode.rSeriesOhm,
                                          rsh: spec.oneDiode.rShuntRefOhm, a: a)
        self.iLRef = refs.iL
        self.i0Ref = refs.i0
    }

    /// Diode parameters at a given effective irradiance (W/m²) and cell temperature (°C).
    public func parameters(effectiveIrradiance g: Double, cellTempC: Double) -> OperatingParameters {
        let d = spec.oneDiode
        let tRefK = Self.tRefC + 273.15
        let tK = cellTempC + 273.15
        let dT = cellTempC - Self.tRefC
        let gamma = d.gammaRef + d.muGammaPerK * dT
        let a = Self.modifiedIdealityVoltage(gamma: gamma, cellsInSeries: spec.cells.cellsInSeries, cellTempK: tK)
        let iL = (g / Self.gRef) * (iLRef + spec.temperatureCoefficients.muIscAPerK * dT)
        let egJ = Self.bandgapEV * Self.elementaryCharge
        let i0 = i0Ref * pow(tK / tRefK, 3) * exp(egJ / (Self.boltzmann * gamma) * (1 / tRefK - 1 / tK))
        let e = exp(-d.rShuntExp)
        let rshBase = max((d.rShuntRefOhm - d.rShunt0Ohm * e) / (1 - e), 0)
        let rsh = rshBase + (d.rShunt0Ohm - rshBase) * exp(-d.rShuntExp * g / Self.gRef)
        return OperatingParameters(iL: iL, i0: i0, rs: d.rSeriesOhm, rsh: rsh, a: a)
    }

    /// Maximum power point for one module.
    public func maxPowerPoint(effectiveIrradiance g: Double, cellTempC: Double) -> PowerPoint {
        guard g > 0 else { return PowerPoint(v: 0, i: 0, p: 0) }
        return Self.maxPowerPoint(parameters(effectiveIrradiance: g, cellTempC: cellTempC))
    }

    public func openCircuitVoltage(effectiveIrradiance g: Double, cellTempC: Double) -> Double {
        guard g > 0 else { return 0 }
        return Self.openCircuitVoltage(parameters(effectiveIrradiance: g, cellTempC: cellTempC))
    }

    public func current(atVoltage v: Double, effectiveIrradiance g: Double, cellTempC: Double) -> Double {
        Self.current(atVoltage: v, parameters(effectiveIrradiance: g, cellTempC: cellTempC))
    }

    // MARK: - Core math (static, so it is easy to test)

    public static func modifiedIdealityVoltage(gamma: Double, cellsInSeries: Int, cellTempK: Double) -> Double {
        gamma * Double(cellsInSeries) * boltzmann * cellTempK / elementaryCharge
    }

    /// Solve IL and I0 from the short-circuit and open-circuit points:
    ///   Isc = IL − I0·(e^{Isc·Rs/a} − 1) − Isc·Rs/Rsh
    ///   0   = IL − I0·(e^{Voc/a} − 1) − Voc/Rsh
    public static func referenceCurrents(isc: Double, voc: Double, rs: Double, rsh: Double, a: Double)
        -> (iL: Double, i0: Double) {
        let i0 = (isc * (1 + rs / rsh) - voc / rsh) / (exp(voc / a) - exp(isc * rs / a))
        let iL = i0 * (exp(voc / a) - 1) + voc / rsh
        return (iL, i0)
    }

    /// I(V) by guarded Newton on the implicit diode equation (monotonic in I).
    public static func current(atVoltage v: Double, _ p: OperatingParameters) -> Double {
        func f(_ i: Double) -> Double {
            let x = (v + i * p.rs)
            return p.iL - p.i0 * (exp(x / p.a) - 1) - x / p.rsh - i
        }
        func df(_ i: Double) -> Double {
            -p.i0 * p.rs / p.a * exp((v + i * p.rs) / p.a) - p.rs / p.rsh - 1
        }
        var hi = p.iL + 1e-9                  // f(hi) ≤ 0 for v ≥ 0
        var lo = -max(p.iL, 1)                // extend until f(lo) > 0
        var guard_ = 0
        while f(lo) <= 0 && guard_ < 60 { lo *= 2; guard_ += 1 }
        var i = min(max(p.iL - v / p.rsh, lo), hi)
        for _ in 0..<100 {
            let fi = f(i)
            if abs(fi) < 1e-12 { break }
            if fi > 0 { lo = i } else { hi = i }
            var next = i - fi / df(i)
            if !(next > lo && next < hi) { next = 0.5 * (lo + hi) }
            if abs(next - i) < 1e-13 { i = next; break }
            i = next
        }
        return i
    }

    public static func openCircuitVoltage(_ p: OperatingParameters) -> Double {
        func g(_ v: Double) -> Double { p.iL - p.i0 * (exp(v / p.a) - 1) - v / p.rsh }
        var lo = 0.0
        var hi = p.a * log(p.iL / p.i0 + 1) + 1
        while g(hi) > 0 { hi *= 1.5 }
        var v = 0.5 * (lo + hi)
        for _ in 0..<100 {
            let gv = g(v)
            if abs(gv) < 1e-12 { break }
            if gv > 0 { lo = v } else { hi = v }
            let dg = -p.i0 / p.a * exp(v / p.a) - 1 / p.rsh
            var next = v - gv / dg
            if !(next > lo && next < hi) { next = 0.5 * (lo + hi) }
            if abs(next - v) < 1e-12 { v = next; break }
            v = next
        }
        return v
    }

    /// Golden-section search for max V·I(V) on [0, Voc]; P(V) is unimodal.
    public static func maxPowerPoint(_ p: OperatingParameters) -> PowerPoint {
        let voc = openCircuitVoltage(p)
        guard voc > 0 else { return PowerPoint(v: 0, i: 0, p: 0) }
        let phi = (sqrt(5.0) - 1) / 2
        var a = 0.0, b = voc
        var c = b - phi * (b - a), d = a + phi * (b - a)
        var pc = c * current(atVoltage: c, p), pd = d * current(atVoltage: d, p)
        while (b - a) > 1e-9 * voc {
            if pc > pd { b = d; d = c; pd = pc; c = b - phi * (b - a); pc = c * current(atVoltage: c, p) }
            else { a = c; c = d; pc = pd; d = a + phi * (b - a); pd = d * current(atVoltage: d, p) }
        }
        let v = 0.5 * (a + b)
        let i = current(atVoltage: v, p)
        return PowerPoint(v: v, i: i, p: v * i)
    }
}

public struct OperatingParameters: Sendable, Equatable {
    public var iL: Double
    public var i0: Double
    public var rs: Double
    public var rsh: Double
    /// Modified ideality voltage a = γ·Ns·k·T/q (V).
    public var a: Double
}

public struct PowerPoint: Sendable, Equatable {
    public var v: Double
    public var i: Double
    public var p: Double
}
