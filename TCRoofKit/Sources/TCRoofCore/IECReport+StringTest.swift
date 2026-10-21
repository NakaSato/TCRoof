import Foundation
import ModuleRules

/// The module maker's string test on step 2 (docs/specs/module-install-rules.md §7.4, rules phase 5): each string's Voc
/// against the datasheet's Voc and β at the module temperature (ZN-132, a warn), and the two strings of an MPPT, which the
/// inverter parallels (ZN-110, a fail). Nothing is stored and the Excel sheet is unchanged.
public extension IECReport {
    /// The catalog model of the test's module (its brand and power), nil when the catalog has none.
    var catalogModule: ModuleModel? {
        module.powerW > 0 ? ModuleCatalog.model(brand: module.brand, powerW: module.powerW) : nil
    }

    /// The before phase's readings of one inverter, grouped by MPPT; ids are the 1-based slots.
    func stringTestInput(_ inv: Inverter) -> StringTestInput {
        StringTestInput(module: catalogModule, irradianceWm2: before.irradianceWm2, moduleTempC: before.moduleTempC,
                        ambientC: before.ambientC,
                        strings: inv.strings.map { .init(id: String($0.slot), group: String(Self.mppt(slot: $0.slot)), modules: $0.value.modules,
                                                         vocV: $0.value.vocV, polarityOK: $0.value.polarityOK) })
    }

    func stringTest(_ inv: Inverter) -> StringTestCheck { StringTestCheck(stringTestInput(inv)) }

    /// ZN-110: `MPPT 3 | Voc 2 สตริงต่างกัน 12.0 V (เกิน 10 V)`, for both strings of the MPPT; a reversed string says
    /// `ขั้วสายกลับ` itself.
    func parallelFailure(_ inv: Inverter, slot: Int) -> String? {
        let mppt = Self.mppt(slot: slot)
        guard let g = stringTest(inv).groups[String(mppt)], g.ids.contains(String(slot)), g.spreadV > StringTestCheck.parallelSpreadV else { return nil }
        return "MPPT \(mppt) | Voc \(g.ids.count) สตริงต่างกัน \(String(format: "%.1f", g.spreadV)) V (เกิน \(Int(StringTestCheck.parallelSpreadV)) V ก่อนต่อขนาน)"
    }

    /// ZN-132 for one string: what it should read, how far off it is, and whether it's flagged; nil without a catalog
    /// module, a module temperature or a reading.
    func manualVoc(_ inv: Inverter, slot: Int) -> (expectedV: Double, deviation: Double, flagged: Bool)? {
        let t = stringTest(inv)
        guard let r = t.strings[String(slot)], let d = r.deviation else { return nil }
        return (r.expectedV, d, t.flags(String(slot)))
    }

    /// The warn line: `Voc ต่างจากคู่มือแผง −6.2% (คาด 736.0 V | ตรวจจุดต่อสาย)`.
    func manualVocWarning(_ inv: Inverter, slot: Int) -> String? {
        guard let m = manualVoc(inv, slot: slot), m.flagged else { return nil }
        return "Voc ต่างจากคู่มือแผง \(Self.signedPercent(m.deviation)) (คาด \(String(format: "%.1f", m.expectedV)) V | ตรวจจุดต่อสาย)"
    }

    /// Where the expected Voc comes from: `แผง 65 °C (ประมาณจาก NMOT 44 °C)` / `แผง 58 °C (วัด)`; nil without one.
    var stringTestBasis: String? {
        let t = StringTestCheck(StringTestInput(module: catalogModule, irradianceWm2: before.irradianceWm2, moduleTempC: before.moduleTempC,
                                                ambientC: before.ambientC, strings: []))
        guard let tc = t.cellTempC else { return nil }
        let source = t.tempMeasured ? "วัด" : "ประมาณจาก NMOT " + String(format: "%.0f", catalogModule?.nmotC ?? 0) + " °C"
        return "แผง " + String(format: "%.0f", tc) + " °C (" + source + ")"
    }
}
