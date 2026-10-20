import Foundation

/// String design checks for one module type on one inverter.
///
/// Voltages use the datasheet Voc coefficient at the coldest cell temperature (standard
/// practice) and the one-diode model's Vmp at the hottest. Currents include an optional
/// bifacial rear-side gain on Isc/Imp.
public enum StringSizing {
    public struct Conditions: Sendable {
        /// Coldest expected cell temperature at sunrise (°C). Thailand lowlands rarely go below
        /// 15 °C; northern highlands can reach ~5 °C — set per site.
        public var minCellTempC: Double = 10
        /// Hottest expected cell temperature at full sun (°C). Roof-mounted in Thailand: ~70 °C.
        public var maxCellTempC: Double = 70
        /// Extra current from the rear side for bifacial modules, e.g. 0.10 = +10 %.
        public var bifacialCurrentGain: Double = 0
        public init(minCellTempC: Double = 10, maxCellTempC: Double = 70, bifacialCurrentGain: Double = 0) {
            self.minCellTempC = minCellTempC; self.maxCellTempC = maxCellTempC
            self.bifacialCurrentGain = bifacialCurrentGain
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

    /// Allowed string length range for this module on this inverter.
    public static func limits(module: PVModuleSpec, inverter: InverterSpec, conditions c: Conditions = .init())
        -> (min: Int, max: Int, vocCold: Double, vmpHot: Double, vmpCold: Double) {
        let vocCold = module.stc.vocV + module.temperatureCoefficients.muVocVPerK * (c.minCellTempC - 25)
        let m = PVsystSingleDiodeModel(spec: module)
        let vmpHot = m.maxPowerPoint(effectiveIrradiance: 1000, cellTempC: c.maxCellTempC).v
        let vmpCold = m.maxPowerPoint(effectiveIrradiance: 1000, cellTempC: c.minCellTempC).v
        let maxN = Int(floor(min(inverter.maxDCVoltageV / vocCold, inverter.mpptMaxV / vmpCold)))
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
        add("Max DC voltage", vocString <= inverter.maxDCVoltageV ? .ok : .error,
            String(format: "Voc at %.0f °C = %.0f V (limit %.0f V)", c.minCellTempC, vocString, inverter.maxDCVoltageV))

        let vmpHot = Double(n) * lim.vmpHot
        let vmpCold = Double(n) * lim.vmpCold
        add("MPPT window, hot", vmpHot >= inverter.mpptMinV ? .ok : .error,
            String(format: "Vmp at %.0f °C = %.0f V (min %.0f V)", c.maxCellTempC, vmpHot, inverter.mpptMinV))
        add("MPPT window, cold", vmpCold <= inverter.mpptMaxV ? .ok : .warning,
            String(format: "Vmp at %.0f °C = %.0f V (max %.0f V)", c.minCellTempC, vmpCold, inverter.mpptMaxV))
        add("Start voltage", vmpHot >= inverter.startVoltageV ? .ok : .warning,
            String(format: "Vmp hot %.0f V vs start %.0f V", vmpHot, inverter.startVoltageV))

        if s > inverter.stringsPerMppt {
            add("Strings per MPPT", .error, "\(s) strings > \(inverter.stringsPerMppt) inputs per MPPT")
        }
        let g = 1 + c.bifacialCurrentGain
        let isc = Double(s) * module.stc.iscA * g
        add("Short-circuit current per MPPT", isc <= inverter.maxShortCircuitCurrentPerMpptA ? .ok : .error,
            String(format: "%d × Isc%@ = %.1f A (limit %.0f A)", s, c.bifacialCurrentGain > 0 ? " incl. bifacial" : "", isc, inverter.maxShortCircuitCurrentPerMpptA))
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
