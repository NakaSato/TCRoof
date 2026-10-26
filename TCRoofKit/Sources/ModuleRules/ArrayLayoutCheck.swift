import Foundation

/// The layout's installation checks as a job keeps them (docs/specs/module-install-rules.md §7.2): what the drawn layout
/// doesn't hold (module model, mounting method, clamp size, rear clearance, the string builder, cable, grounding), the
/// engineer's reasons for warns, and the versions it was checked under. The rest (tilt, orientation, clamp side and
/// offsets, gap, rails) comes from the layout itself (`LayoutGeometry`).
public struct ArrayLayoutCheck: Codable, Sendable, Equatable {
    public var moduleID: String?
    public var method: MountingMethod?
    public var clampLengthMm: Double?, clampThicknessMm: Double?
    public var clampsPerModule: Int?
    public var rearClearanceMm: Double?
    /// String builder: modules per string, the inverter's max DC input, the lowest site ambient.
    public var modulesPerString: Int?
    public var inverterMaxDcV: Double?
    public var tMinC: Double?
    /// A string runs over two roof faces (different tilt or azimuth, ZN-79).
    public var stringAcrossFaces: Bool?
    public var cableMm2: Double?
    public var cableAmpacityA: Double?
    public var parallelCount: Int?
    public var groundingParallel: Int?, groundingSeries: Int?
    public var reasons: [String: String] = [:]
    public var ruleSetVersion: String?
    public var catalogVersion: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case moduleID, method, clampLengthMm, clampThicknessMm, clampsPerModule, rearClearanceMm, modulesPerString, inverterMaxDcV,
             tMinC, stringAcrossFaces, cableMm2, cableAmpacityA, parallelCount, groundingParallel, groundingSeries, reasons,
             ruleSetVersion, catalogVersion
    }

    /// Every field optional, so a record saved by an older version still opens.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil }
        moduleID = d(.moduleID); method = d(.method); clampLengthMm = d(.clampLengthMm); clampThicknessMm = d(.clampThicknessMm)
        clampsPerModule = d(.clampsPerModule); rearClearanceMm = d(.rearClearanceMm); modulesPerString = d(.modulesPerString)
        inverterMaxDcV = d(.inverterMaxDcV); tMinC = d(.tMinC); stringAcrossFaces = d(.stringAcrossFaces); cableMm2 = d(.cableMm2)
        cableAmpacityA = d(.cableAmpacityA); parallelCount = d(.parallelCount); groundingParallel = d(.groundingParallel)
        groundingSeries = d(.groundingSeries); reasons = d(.reasons) ?? [:]; ruleSetVersion = d(.ruleSetVersion)
        catalogVersion = d(.catalogVersion)
    }

    public var module: ModuleModel? { moduleID.flatMap(ModuleCatalog.model) }

    /// What the drawn layout gives: the modules' tilt and orientation, the clamp offsets it uses, the gap and the rails.
    public struct LayoutGeometry: Sendable, Equatable {
        public var tiltDeg: Double?
        public var latitude: Double?
        public var landscape: Bool
        /// The side the clamps hold: rails across the long side → long.
        public var clampSide: ClampSide
        /// Every offset A (module edge → rail, mm) the layout uses, both ends.
        public var clampOffsetsMm: [Double]
        public var gapMm: Double
        public var railsPerModule: Int
        public var tiltsByFace: [Double]
        public var azimuthsByFace: [Double]
        public init(tiltDeg: Double?, latitude: Double?, landscape: Bool, clampSide: ClampSide, clampOffsetsMm: [Double],
                    gapMm: Double, railsPerModule: Int = 2, tiltsByFace: [Double] = [], azimuthsByFace: [Double] = []) {
            self.tiltDeg = tiltDeg; self.latitude = latitude; self.landscape = landscape; self.clampSide = clampSide
            self.clampOffsetsMm = clampOffsetsMm; self.gapMm = gapMm; self.railsPerModule = railsPerModule
            self.tiltsByFace = tiltsByFace; self.azimuthsByFace = azimuthsByFace
        }
    }

    /// The offset the zone check looks at: the first one outside the module's zone, else the first.
    public func checkedOffset(_ g: LayoutGeometry) -> Double? {
        guard let m = module, let zone = ModuleRules.clampZone(module: m, side: g.clampSide) else { return g.clampOffsetsMm.first }
        return g.clampOffsetsMm.first { !zone.contains($0) } ?? g.clampOffsetsMm.first
    }

    /// The engine's input: this record and the layout.
    public func input(_ g: LayoutGeometry) -> LayoutInput {
        var l = LayoutInput(module: module)
        l.landscape = g.landscape
        l.clampSide = g.clampSide
        l.clampOffsetMm = checkedOffset(g)
        l.gapMm = g.gapMm
        l.railsPerModule = g.railsPerModule
        l.tiltDeg = g.tiltDeg
        l.latitude = g.latitude
        l.rearClearanceMm = rearClearanceMm
        l.clampLengthMm = clampLengthMm; l.clampThicknessMm = clampThicknessMm
        l.clampsPerModule = clampsPerModule
        l.tMinC = tMinC
        l.inverterMaxDcV = inverterMaxDcV
        l.cableMm2 = cableMm2; l.cableAmpacityA = cableAmpacityA
        l.parallelCount = max(1, parallelCount ?? 1)
        l.groundingParallel = groundingParallel; l.groundingSeries = groundingSeries
        if let n = modulesPerString, n > 0, let id = moduleID {
            // one string, across two faces when asked: the faces' tilt and azimuth both appear in it
            let across = stringAcrossFaces == true && g.tiltsByFace.count > 1
            let tilts = across ? Array(g.tiltsByFace.prefix(2)) : [g.tiltDeg ?? 0]
            let azimuths = across ? Array(g.azimuthsByFace.prefix(2)) : [g.azimuthsByFace.first ?? 0]
            var plan = StringPlan.uniform(id: "S1", model: id, count: n, tilt: tilts[0], azimuth: azimuths[0])
            if across { plan.tiltsDeg[n - 1] = tilts[1]; plan.azimuthsDeg[n - 1] = azimuths[1] }
            l.strings = [plan]
        }
        return l
    }

    public func validation(_ g: LayoutGeometry) -> Validation { RuleEngine.check(input(g)) }

    /// The most modules a string can take with this record's module, T_min and inverter, and its cold Voc; nil until
    /// all three are known (or without β).
    public var stringLimit: (nmax: Int, coldVoc: Double, limitV: Double)? {
        guard let m = module, let t = tMinC, let n = ModuleRules.maxModulesInSeries(module: m, tMinC: t, inverterMaxDcV: inverterMaxDcV),
              let v = ModuleRules.coldVoc(module: m, tMinC: t) else { return nil }
        return (n, v, ModuleRules.voltageLimit(module: m, inverterMaxDcV: inverterMaxDcV))
    }

    /// The catalog model matching a module's power and size (± 10 mm), for a layout that only knows those.
    public static func match(wp: Double, lengthMm: Double, widthMm: Double) -> ModuleModel? {
        ModuleCatalog.models.first { abs($0.pmaxW - wp) < 0.5 && abs($0.lengthMm - lengthMm) <= 10 && abs($0.widthMm - widthMm) <= 10 }
    }

    public static func decode(_ json: String) -> ArrayLayoutCheck {
        guard !json.isEmpty, let d = json.data(using: .utf8), let c = try? JSONDecoder().decode(ArrayLayoutCheck.self, from: d) else { return ArrayLayoutCheck() }
        return c
    }
    public var json: String {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
