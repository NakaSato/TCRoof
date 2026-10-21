import Foundation

/// The four calculations of the installation rules (docs/specs/module-install-rules.md §6).
public enum ModuleRules {

    /// ZN-106 | Table 5-4: the most modules in one string so its Voc at `tMinC` stays under the lower of the module's
    /// max system voltage and the inverter's max DC input. Nil without β (rule ZN-106b blocks).
    public static func maxModulesInSeries(module: ModuleModel, tMinC: Double, inverterMaxDcV: Double?) -> Int? {
        guard let cold = coldVoc(module: module, tMinC: tMinC) else { return nil }
        return Int((voltageLimit(module: module, inverterMaxDcV: inverterMaxDcV) / cold).rounded(.down))
    }

    /// One module's Voc at `tMinC`; nil without β.
    public static func coldVoc(module: ModuleModel, tMinC: Double) -> Double? {
        guard let beta = module.betaVocPctPerC else { return nil }
        return module.vocV * (1 + (beta / 100) * (tMinC - 25))
    }

    /// The string voltage limit: the module's max system voltage, or the inverter's max DC input when lower.
    public static func voltageLimit(module: ModuleModel, inverterMaxDcV: Double?) -> Double {
        min(module.maxSystemVoltageV, inverterMaxDcV ?? .infinity)
    }

    /// ZN-112: I_cable,min = 1.25 × Isc × Np.
    public static func minCableAmpacity(module: ModuleModel, parallelCount np: Int) -> Double {
        1.25 * module.iscA * Double(np)
    }

    /// Table 5-2: the recommended fixed tilt from |latitude|. Exactly 15° takes the 15°–25° row (both give 15°).
    public static func recommendedTilt(latitude: Double) -> Double {
        let lat = abs(latitude)
        switch lat {
        case ..<15: return 15
        case ..<25: return lat
        case ..<30: return lat + 5
        case ..<35: return lat + 10
        case ..<40: return lat + 15
        default: return lat + 20
        }
    }

    /// ZN-132: the Voc a string of `modules` should read at `cellTempC`, from the datasheet's Voc and β; nil without β.
    public static func expectedVoc(module: ModuleModel, modules: Int, cellTempC: Double) -> Double? {
        coldVoc(module: module, tMinC: cellTempC).map { $0 * Double(modules) }
    }

    /// The module temperature estimated from the datasheet's NMOT (800 W/m², 20 °C air): T = T_air + (NMOT − 20) × G / 800.
    /// Nil without NMOT.
    public static func cellTemperature(module: ModuleModel, ambientC: Double, irradianceWm2: Double) -> Double? {
        guard let nmot = module.nmotC else { return nil }
        return ambientC + (nmot - 20) * irradianceWm2 / 800
    }

    /// §5.5.3: the allowed clamp offset A (module edge → clamp centre, mm): L/4 ± 50 on the long side, W/5 ± 50 on the
    /// short side for 60 / 66 / 120 / 132 cells only (nil: not rated).
    public static func clampZone(module: ModuleModel, side: ClampSide) -> ClosedRange<Double>? {
        switch side {
        case .long:
            let a = module.lengthMm / 4
            return (a - 50)...(a + 50)
        case .short:
            guard [60, 66, 120, 132].contains(module.cellCount) else { return nil }
            let a = module.widthMm / 5
            return (a - 50)...(a + 50)
        }
    }
}
