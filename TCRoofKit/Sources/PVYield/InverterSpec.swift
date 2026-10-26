import Foundation

/// Portable grid-tied inverter specification (datasheet level), plus an efficiency model.
public struct InverterSpec: Codable, Sendable, Identifiable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var manufacturer: String
    public var model: String
    public var source: InverterModelSource

    // DC input
    public var maxDCVoltageV: Double
    public var startVoltageV: Double
    public var nominalDCVoltageV: Double
    public var mpptMinV: Double
    public var mpptMaxV: Double
    public var mpptCount: Int
    public var stringsPerMppt: Int
    /// Max operating input current per MPPT (A). Above this the inverter limits current.
    public var maxInputCurrentPerMpptA: Double
    /// Max short-circuit current per MPPT (A). A hard safety limit for string design.
    public var maxShortCircuitCurrentPerMpptA: Double
    /// Manufacturer's max recommended PV power at STC (W), if given.
    public var maxRecommendedPVPowerW: Double?

    // AC output
    public var acNominalPowerW: Double
    public var acMaxApparentPowerVA: Double
    public var nominalACVoltageV: Double

    // Efficiency
    public var maxEfficiency: Double
    public var euroEfficiency: Double
    public var mpptEfficiency: Double?
    /// Fitted loss model (see `InverterEfficiencyModel`).
    public var lossModel: InverterLossModel
    public var nightConsumptionW: Double

    public init(id: String, manufacturer: String, model: String, source: InverterModelSource,
                maxDCVoltageV: Double, startVoltageV: Double, nominalDCVoltageV: Double,
                mpptMinV: Double, mpptMaxV: Double, mpptCount: Int, stringsPerMppt: Int,
                maxInputCurrentPerMpptA: Double, maxShortCircuitCurrentPerMpptA: Double,
                maxRecommendedPVPowerW: Double?, acNominalPowerW: Double, acMaxApparentPowerVA: Double,
                nominalACVoltageV: Double, maxEfficiency: Double, euroEfficiency: Double,
                mpptEfficiency: Double?, lossModel: InverterLossModel, nightConsumptionW: Double) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id; self.manufacturer = manufacturer; self.model = model; self.source = source
        self.maxDCVoltageV = maxDCVoltageV; self.startVoltageV = startVoltageV
        self.nominalDCVoltageV = nominalDCVoltageV; self.mpptMinV = mpptMinV; self.mpptMaxV = mpptMaxV
        self.mpptCount = mpptCount; self.stringsPerMppt = stringsPerMppt
        self.maxInputCurrentPerMpptA = maxInputCurrentPerMpptA
        self.maxShortCircuitCurrentPerMpptA = maxShortCircuitCurrentPerMpptA
        self.maxRecommendedPVPowerW = maxRecommendedPVPowerW
        self.acNominalPowerW = acNominalPowerW; self.acMaxApparentPowerVA = acMaxApparentPowerVA
        self.nominalACVoltageV = nominalACVoltageV
        self.maxEfficiency = maxEfficiency; self.euroEfficiency = euroEfficiency
        self.mpptEfficiency = mpptEfficiency; self.lossModel = lossModel
        self.nightConsumptionW = nightConsumptionW
    }
}

public enum InverterModelSource: String, Codable, Sendable {
    /// Efficiency curve read from a PVsyst .OND file (not implemented yet).
    case ond
    /// Loss model fitted from datasheet max and European efficiency.
    case datasheetFit
}

/// Schmidt–Sauer three-term loss model, in per-unit of `pDC0` (DC power at AC nominal):
///     p_loss = l0 + l1·p + l2·p²,   P_AC = P_DC − p_loss·pDC0
/// l0 = no-load (switching, control) loss, l1 = voltage-drop loss, l2 = ohmic loss.
public struct InverterLossModel: Codable, Sendable, Equatable {
    public var l0: Double
    public var l1: Double
    public var l2: Double
    /// DC input power that gives AC nominal power (W).
    public var pDC0W: Double
}

public enum InverterEfficiencyModel {
    /// EN 50530 European efficiency weights at 5, 10, 20, 30, 50, 100 % load.
    public static let euroPoints: [(load: Double, weight: Double)] =
        [(0.05, 0.03), (0.10, 0.06), (0.20, 0.13), (0.30, 0.10), (0.50, 0.48), (1.00, 0.20)]

    /// Efficiency at DC per-unit load p = P_DC / pDC0.
    public static func efficiency(atLoad p: Double, _ m: InverterLossModel) -> Double {
        guard p > 0 else { return 0 }
        return max(0, (p - (m.l0 + m.l1 * p + m.l2 * p * p)) / p)
    }

    public static func euroEfficiency(_ m: InverterLossModel) -> Double {
        euroPoints.reduce(0) { $0 + $1.weight * efficiency(atLoad: $1.load, m) }
    }

    /// Maximum of η(p) over 0 < p ≤ 1.2.
    public static func peakEfficiency(_ m: InverterLossModel) -> Double {
        var best = 0.0
        var p = 0.01
        while p <= 1.2 { best = max(best, efficiency(atLoad: p, m)); p += 0.0005 }
        return best
    }

    /// Fit (l0, l1, l2) to the datasheet max and European efficiencies.
    ///
    /// Two datasheet numbers cannot fix three parameters, so the load at which efficiency
    /// peaks is assumed (`peakLoad`, default 0.4 — typical of string inverters; most
    /// datasheet efficiency curves peak at 30–50 % load). With p* fixed:
    ///     k = (1 − η_max − l1)/2,  l0 = k·p*,  l2 = k/p*
    /// and l1 is solved so the European weighting reproduces η_euro (η_euro rises
    /// monotonically with l1 at fixed η_max and p*). l1 may come out slightly negative;
    /// that is a fitting artefact, not a physical gain.
    public static func fit(maxEfficiency: Double, euroEfficiency: Double, acNominalPowerW: Double,
                           peakLoad: Double = 0.4) throws -> InverterLossModel {
        guard euroEfficiency < maxEfficiency, maxEfficiency < 1, peakLoad > 0, peakLoad < 1 else {
            throw DatasheetFitter.FitError.invalidDatasheet(["Need euro < max < 1 and 0 < peakLoad < 1"])
        }
        func model(_ l1: Double) -> InverterLossModel {
            let k = (1 - maxEfficiency - l1) / 2
            let l0 = k * peakLoad, l2 = k / peakLoad
            let eta1 = 1 - (l0 + l1 + l2)
            return InverterLossModel(l0: l0, l1: l1, l2: l2, pDC0W: acNominalPowerW / eta1)
        }
        let span = 1 - maxEfficiency
        var lo = -span, hi = span * 0.999                // keep k > 0
        func f(_ l1: Double) -> Double { InverterEfficiencyModel.euroEfficiency(model(l1)) - euroEfficiency }
        guard f(lo) < 0, f(hi) > 0 else {
            throw DatasheetFitter.FitError.noSolution("Euro efficiency not reachable with the given max efficiency")
        }
        for _ in 0..<100 {
            let mid = 0.5 * (lo + hi)
            if f(mid) < 0 { lo = mid } else { hi = mid }
        }
        return model(0.5 * (lo + hi))
    }

    public enum ACLimit: Sendable { case nominalPower, maxApparentPower }

    /// AC output for a DC input (W): efficiency curve, then clipping at the AC limit.
    /// Returns (acW, clippedW) where clippedW is the DC power the inverter could not use.
    public static func acPower(dcW: Double, spec: InverterSpec, limit: ACLimit = .nominalPower)
        -> (acW: Double, clippedDCW: Double) {
        guard dcW > 0 else { return (-spec.nightConsumptionW, 0) }
        let m = spec.lossModel
        let pAC = dcW * efficiency(atLoad: dcW / m.pDC0W, m)
        let cap = limit == .nominalPower ? spec.acNominalPowerW : spec.acMaxApparentPowerVA
        if pAC <= cap { return (pAC, 0) }
        // Inverter moves off MPP until AC = cap; DC used = cap / η(at that DC).
        var lo = 0.0, hi = dcW
        for _ in 0..<60 {
            let mid = 0.5 * (lo + hi)
            if mid * efficiency(atLoad: mid / m.pDC0W, m) > cap { hi = mid } else { lo = mid }
        }
        return (cap, dcW - lo)
    }
}

public extension InverterSpec {
    func validate() -> [String] {
        var issues: [String] = []
        if !(mpptMinV < mpptMaxV && mpptMaxV <= maxDCVoltageV) { issues.append("MPPT range must sit below max DC voltage") }
        if !(euroEfficiency < maxEfficiency && maxEfficiency < 1) { issues.append("Need euro < max < 1") }
        if mpptCount <= 0 || stringsPerMppt <= 0 { issues.append("MPPT and string counts must be positive") }
        if acMaxApparentPowerVA < acNominalPowerW { issues.append("Max apparent power below nominal") }
        return issues
    }

    func jsonData(pretty: Bool = true) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try enc.encode(self)
    }

    static func from(json data: Data) throws -> InverterSpec {
        try JSONDecoder().decode(InverterSpec.self, from: data)
    }
}
