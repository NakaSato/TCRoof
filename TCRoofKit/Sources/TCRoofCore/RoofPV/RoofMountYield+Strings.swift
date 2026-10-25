import Foundation
import PVYield

/// The roof's strings for C1's `สตริง` tile: modules per string from the module on B2's inverter (`StringSizing`),
/// computed, never stored.
public extension RoofMountYield {
    struct StringPlan: Equatable, Sendable {
        /// Modules in one string, and how many full strings the roof's modules make.
        public var perString: Int
        public var strings: Int
        /// Modules left over that make no full string.
        public var leftover: Int
        /// The string lengths the module allows on the inverter.
        public var range: ClosedRange<Int>
        /// The strings the inverters take (MPPT × inputs per MPPT × inverters).
        public var inputs: Int
        /// e.g. `Growatt MAX 60KTL3 LV`.
        public var inverter: String
        /// What was assumed (no inverter picked in B2, or a size the engine has no model for).
        public var assumed: String?
        public var fits: Bool { strings + (leftover > 0 ? 1 : 0) <= inputs }
    }

    /// Lowest cell temperature for the string's Voc: the PVYield default for Thailand's lowlands.
    static let stringConditions = StringSizing.Conditions()

    /// The string length in the allowed range that leaves the fewest modules over (the longer one on a tie, so fewer
    /// strings); nil without modules, a module or inverter the engine has a model for, or any allowed length.
    static func stringPlan(_ i: Inputs) -> StringPlan? {
        guard i.modules > 0, let cat = catalogModule(wp: i.moduleWp, length: i.moduleLength, width: i.moduleWidth),
              let module = moduleSpec(catalogID: cat.id), let inv = inverters(i) else { return nil }
        let lim = StringSizing.limits(module: module, inverter: inv.spec, conditions: stringConditions)
        guard lim.min >= 1, lim.min <= lim.max else { return nil }
        return plan(modules: i.modules, range: lim.min...lim.max, inputs: inv.spec.mpptCount * inv.spec.stringsPerMppt * inv.count,
                    inverter: "\(inv.spec.manufacturer) \(inv.spec.model)", assumed: inv.assumed)
    }

    /// The choice itself, apart from the engine.
    static func plan(modules: Int, range: ClosedRange<Int>, inputs: Int, inverter: String, assumed: String?) -> StringPlan? {
        guard modules >= range.lowerBound else { return nil }
        let n = range.reversed().min { modules % $0 < modules % $1 } ?? range.upperBound
        return StringPlan(perString: n, strings: modules / n, leftover: modules % n, range: range, inputs: inputs,
                          inverter: inverter, assumed: assumed)
    }
}
