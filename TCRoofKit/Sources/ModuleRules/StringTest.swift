import Foundation

/// Commissioning → the string test (docs/specs/module-install-rules.md §7.4): each string's open-circuit voltage against
/// the datasheet's (ZN-132), and the strings about to be paralleled (ZN-110).
public struct StringTestInput: Sendable, Equatable {
    public struct Reading: Sendable, Equatable {
        public var id: String
        /// The strings of one group are paralleled (one MPPT input).
        public var group: String
        public var modules: Int
        public var vocV: Double?
        public var polarityOK: Bool?
        public init(id: String, group: String, modules: Int, vocV: Double?, polarityOK: Bool?) {
            self.id = id; self.group = group; self.modules = modules; self.vocV = vocV; self.polarityOK = polarityOK
        }
    }

    /// Nil when the catalog has no such model: only ZN-110 is checked.
    public var module: ModuleModel?
    public var irradianceWm2: Double?
    /// Measured on the module's back; without it the temperature comes from the air and the datasheet's NMOT.
    public var moduleTempC: Double?
    public var ambientC: Double?
    public var strings: [Reading]

    public init(module: ModuleModel?, irradianceWm2: Double?, moduleTempC: Double?, ambientC: Double?, strings: [Reading]) {
        self.module = module; self.irradianceWm2 = irradianceWm2; self.moduleTempC = moduleTempC; self.ambientC = ambientC
        self.strings = strings
    }
}

/// The string test worked out: the temperature used, each string's expected Voc, and each group's spread.
public struct StringTestCheck: Sendable, Equatable {
    /// ZN-132: a string more than 5 % off its expected Voc, at 200 W/m² or more.
    public static let vocTolerance = 0.05
    public static let minIrradianceWm2 = 200.0
    /// ZN-110: strings paralleled may differ by up to 10 V.
    public static let parallelSpreadV = 10.0

    public struct StringResult: Sendable, Equatable {
        public var expectedV: Double
        /// Signed fraction, nil without a reading.
        public var deviation: Double?
        public var flagged: Bool { deviation.map { abs($0) > StringTestCheck.vocTolerance } ?? false }
    }

    public struct GroupResult: Sendable, Equatable {
        public var ids: [String]
        public var spreadV: Double
        public var reversed: Bool
        public var fails: Bool { reversed || spreadV > StringTestCheck.parallelSpreadV }
    }

    /// The module temperature the expected Voc uses; nil when there is neither a reading nor air + light + NMOT.
    public var cellTempC: Double?
    /// The temperature was measured, not estimated from NMOT.
    public var tempMeasured: Bool
    /// Below 200 W/m² (or no reading) the manual's comparison doesn't apply.
    public var enoughLight: Bool
    /// By string id; empty without a catalog module, a temperature or β.
    public var strings: [String: StringResult]
    /// By group, only groups of two or more strings with a Voc.
    public var groups: [String: GroupResult]
    public var validation: Validation

    public init(_ t: StringTestInput, rules: [RuleSpec] = ModuleCatalog.rules) {
        let m = t.module
        if let measured = t.moduleTempC {
            cellTempC = measured; tempMeasured = true
        } else if let m, let a = t.ambientC, let g = t.irradianceWm2 {
            cellTempC = ModuleRules.cellTemperature(module: m, ambientC: a, irradianceWm2: g); tempMeasured = false
        } else {
            cellTempC = nil; tempMeasured = false
        }
        enoughLight = (t.irradianceWm2 ?? 0) >= Self.minIrradianceWm2

        var strings: [String: StringResult] = [:]
        if let m, let tc = cellTempC {
            for s in t.strings {
                guard let e = ModuleRules.expectedVoc(module: m, modules: s.modules, cellTempC: tc), e > 0 else { continue }
                strings[s.id] = StringResult(expectedV: e, deviation: s.vocV.map { ($0 - e) / e })
            }
        }
        self.strings = strings

        var groups: [String: GroupResult] = [:]
        for key in Set(t.strings.map(\.group)) {
            let read = t.strings.filter { $0.group == key && $0.vocV != nil }
            guard read.count > 1 else { continue }
            let v = read.compactMap(\.vocV)
            groups[key] = GroupResult(ids: read.map(\.id), spreadV: (v.max() ?? 0) - (v.min() ?? 0),
                                      reversed: read.contains { $0.polarityOK == false })
        }
        self.groups = groups

        let off = enoughLight ? t.strings.map(\.id).filter { strings[$0]?.flagged == true } : []
        validation = RuleEngine.validation([
            off.isEmpty ? nil : RuleEngine.fire("ZN-132", ["strings": off.joined(separator: ", ")], rules: rules),
            groups.values.contains { $0.fails } ? RuleEngine.fire("ZN-110", rules: rules) : nil,
        ])
    }

    /// The string is flagged by ZN-132 (enough light, more than 5 % off).
    public func flags(_ id: String) -> Bool { enoughLight && strings[id]?.flagged == true }
}

public extension RuleEngine {
    static func check(_ t: StringTestInput, rules: [RuleSpec] = ModuleCatalog.rules) -> Validation {
        StringTestCheck(t, rules: rules).validation
    }
}

public extension ModuleCatalog {
    /// The catalog model of a module named by brand and power (the IEC test's `Znshine` 570 W); an empty brand matches
    /// any maker.
    static func model(brand: String, powerW: Double) -> ModuleModel? {
        let b = brand.trimmingCharacters(in: .whitespaces).lowercased()
        return models.first { $0.pmaxW == powerW && (b.isEmpty || $0.manufacturer.lowercased() == b || b.contains($0.manufacturer.lowercased())) }
    }
}
