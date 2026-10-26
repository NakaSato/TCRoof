import Foundation

/// String design checks for one module type on one inverter.
///
/// Voltages use the datasheet Voc coefficient at the coldest cell temperature (standard
/// practice; the one-diode model's Voc there when the spec has no coefficient) and the model's
/// Vmp at the hottest. The voltage limit is the lower of the inverter's and the module's own
/// rating. The start voltage is compared with the hot Vmp, as a hard minimum in both `limits`
/// and `check`. Currents include an optional bifacial rear-side gain on Isc/Imp; Isc is an
/// error over the inverter's limit and a warning once the safety margin (1.25 × by default,
/// IEC 62548 practice) passes it.
public enum StringSizing {
    public struct Conditions: Sendable {
        /// Coldest expected cell temperature at sunrise (°C). Thailand lowlands rarely go below
        /// 15 °C; northern highlands can reach ~5 °C — set per site.
        public var minCellTempC: Double = 10
        /// Hottest expected cell temperature at full sun (°C). Roof-mounted in Thailand: ~70 °C.
        public var maxCellTempC: Double = 70
        /// Extra current from the rear side for bifacial modules, e.g. 0.10 = +10 %.
        public var bifacialCurrentGain: Double = 0
        /// Margin on Isc for irradiance above 1000 W/m² and heat (IEC 62548 uses 1.25). Isc above
        /// the inverter's limit is an error; Isc × this above it is a warning.
        public var iscSafetyFactor: Double = 1.25
        public init(minCellTempC: Double = 10, maxCellTempC: Double = 70, bifacialCurrentGain: Double = 0,
                    iscSafetyFactor: Double = 1.25) {
            self.minCellTempC = minCellTempC; self.maxCellTempC = maxCellTempC
            self.bifacialCurrentGain = bifacialCurrentGain; self.iscSafetyFactor = iscSafetyFactor
        }
    }

    public enum Level: String, Codable, Sendable { case ok, warning, error }

    public struct Check: Codable, Sendable, Equatable {
        public var name: String
        public var level: Level
        public var detail: String
    }

    public struct Report: Sendable {
        public var minModulesPerString: Int
        public var maxModulesPerString: Int
        public var vocColdPerModuleV: Double
        public var vmpHotPerModuleV: Double
        public var vmpColdPerModuleV: Double
        public var checks: [Check]
        public var worst: Level { checks.contains { $0.level == .error } ? .error : checks.contains { $0.level == .warning } ? .warning : .ok }
    }

    /// The string's voltage limit: the inverter's maximum DC input, or the module's own maximum
    /// system voltage when that is lower.
    public static func maxDCVoltage(module: PVModuleSpec, inverter: InverterSpec) -> Double {
        min(inverter.maxDCVoltageV, module.maxSystemVoltageV ?? .infinity)
    }

    /// Voc per module at the coldest cell temperature: from the datasheet coefficient, or from the
    /// one-diode model when the spec has none (a PAN without `muVocSpec`), never the STC Voc.
    public static func vocCold(module: PVModuleSpec, conditions c: Conditions = .init()) -> Double {
        let mu = module.temperatureCoefficients.muVocVPerK
        if mu != 0 { return module.stc.vocV + mu * (c.minCellTempC - 25) }
        return PVsystSingleDiodeModel(spec: module).openCircuitVoltage(effectiveIrradiance: 1000, cellTempC: c.minCellTempC)
    }

    /// Allowed string length range for this module on this inverter.
    public static func limits(module: PVModuleSpec, inverter: InverterSpec, conditions c: Conditions = .init())
        -> (min: Int, max: Int, vocCold: Double, vmpHot: Double, vmpCold: Double) {
        let vocCold = Self.vocCold(module: module, conditions: c)
        let m = PVsystSingleDiodeModel(spec: module)
        let vmpHot = m.maxPowerPoint(effectiveIrradiance: 1000, cellTempC: c.maxCellTempC).v
        let vmpCold = m.maxPowerPoint(effectiveIrradiance: 1000, cellTempC: c.minCellTempC).v
        let maxV = maxDCVoltage(module: module, inverter: inverter)
        let maxN = Int(floor(min(maxV / vocCold, inverter.mpptMaxV / vmpCold)))
        let minN = Int(ceil(max(inverter.mpptMinV, inverter.startVoltageV) / vmpHot))
        return (minN, maxN, vocCold, vmpHot, vmpCold)
    }

    public static func check(module: PVModuleSpec, inverter: InverterSpec, modulesPerString n: Int,
                             stringsPerMppt s: Int, totalModules: Int? = nil,
                             conditions c: Conditions = .init()) -> Report {
        let lim = limits(module: module, inverter: inverter, conditions: c)
        var checks: [Check] = []
        func add(_ name: String, _ level: Level, _ detail: String) { checks.append(Check(name: name, level: level, detail: detail)) }

        let vocString = Double(n) * lim.vocCold
        let maxV = maxDCVoltage(module: module, inverter: inverter)
        let byModule = maxV < inverter.maxDCVoltageV
        add("Max DC voltage", vocString <= maxV ? .ok : .error,
            String(format: "Voc at %.0f °C = %.0f V (limit %.0f V%@)", c.minCellTempC, vocString, maxV,
                   byModule ? ", module rating" : ""))

        let vmpHot = Double(n) * lim.vmpHot
        let vmpCold = Double(n) * lim.vmpCold
        add("MPPT window, hot", vmpHot >= inverter.mpptMinV ? .ok : .error,
            String(format: "Vmp at %.0f °C = %.0f V (min %.0f V)", c.maxCellTempC, vmpHot, inverter.mpptMinV))
        add("MPPT window, cold", vmpCold <= inverter.mpptMaxV ? .ok : .warning,
            String(format: "Vmp at %.0f °C = %.0f V (max %.0f V)", c.minCellTempC, vmpCold, inverter.mpptMaxV))
        // a hard minimum, as in `limits`: a string shorter than its `min` is an error here too
        add("Start voltage", vmpHot >= inverter.startVoltageV ? .ok : .error,
            String(format: "Vmp hot %.0f V vs start %.0f V", vmpHot, inverter.startVoltageV))

        if s > inverter.stringsPerMppt {
            add("Strings per MPPT", .error, "\(s) strings > \(inverter.stringsPerMppt) inputs per MPPT")
        }
        let g = 1 + c.bifacialCurrentGain
        let isc = Double(s) * module.stc.iscA * g
        let iscLimit = inverter.maxShortCircuitCurrentPerMpptA, iscMargin = isc * c.iscSafetyFactor
        let iscLevel: Level = isc > iscLimit ? .error : iscMargin > iscLimit ? .warning : .ok
        add("Short-circuit current per MPPT", iscLevel,
            String(format: "%d × Isc%@ = %.1f A, × %.2f = %.1f A (limit %.0f A)", s,
                   c.bifacialCurrentGain > 0 ? " incl. bifacial" : "", isc, c.iscSafetyFactor, iscMargin, iscLimit))
        let imp = Double(s) * module.stc.impA * g
        let impOK = imp <= inverter.maxInputCurrentPerMpptA
        let gThreshold = 1000 * inverter.maxInputCurrentPerMpptA / imp
        add("Operating current per MPPT", impOK ? .ok : .warning,
            String(format: "%d × Imp%@ = %.1f A (limit %.0f A)", s, c.bifacialCurrentGain > 0 ? " incl. bifacial" : "",
                   imp, inverter.maxInputCurrentPerMpptA)
            + (impOK ? "" : String(format: " — inverter caps current above ~%.0f W/m² on the module plane", gThreshold)))

        if let total = totalModules {
            let dcW = Double(total) * module.stc.pNomW
            let ratio = dcW / inverter.acNominalPowerW
            let fits = total <= n * s * inverter.mpptCount
            add("Inputs available", fits ? .ok : .error,
                "\(total) modules vs \(n * s * inverter.mpptCount) max (\(n)/string × \(s) × \(inverter.mpptCount) MPPT)")
            if let maxPV = inverter.maxRecommendedPVPowerW {
                add("Max recommended PV power", dcW <= maxPV ? .ok : .warning,
                    String(format: "%.1f kWp vs %.0f kWp", dcW / 1000, maxPV / 1000))
            }
            add("DC/AC ratio", ratio <= 1.3 ? .ok : .warning, String(format: "%.2f", ratio))
        }
        return Report(minModulesPerString: lim.min, maxModulesPerString: lim.max,
                      vocColdPerModuleV: lim.vocCold, vmpHotPerModuleV: lim.vmpHot,
                      vmpColdPerModuleV: lim.vmpCold, checks: checks)
    }
}
