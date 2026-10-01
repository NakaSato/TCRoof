import Foundation

/// Inverters, PV modules, cabinets and breaker rules: the one source for B2, the SLD and C1
/// (the canvas `TCR_SPECS`). Shipped as `Resources/equipment-catalog.json`.
public struct EquipmentCatalog: Codable, Hashable, Sendable {
    public struct Inverter: Codable, Hashable, Sendable {
        public var kw: Int
        public var brand: String
        public var model: String
        /// Maximum AC output current (A).
        public var imax: Double
        /// Rated AC output (kVA).
        public var sac: Double
        public var mppt: Int
        public var vdc: Int
        /// Size in mm.
        public var w: Int, h: Int, d: Int
        public var kg: Double
        public var ip: String
        public init(kw: Int, brand: String, model: String, imax: Double, sac: Double, mppt: Int, vdc: Int, w: Int, h: Int, d: Int, kg: Double, ip: String) {
            self.kw = kw; self.brand = brand; self.model = model; self.imax = imax; self.sac = sac; self.mppt = mppt; self.vdc = vdc
            self.w = w; self.h = h; self.d = d; self.kg = kg; self.ip = ip
        }
    }
    public struct PVModule: Codable, Hashable, Sendable {
        public var id: String
        /// Rated power (W).
        public var w: Int
        public var model: String
        /// Length, width and thickness in mm.
        public var l: Int, wd: Int, t: Int
        public var kg: Double, voc: Double, isc: Double, vmp: Double, imp: Double
        /// The default module.
        public var def: Bool?
    }
    public struct ACCabinet: Codable, Hashable, Sendable {
        /// Largest number of inverters this cabinet takes.
        public var upTo: Int
        public var w: Int, h: Int, d: Int
        public var busbar: String
    }
    public struct DCCabinet: Codable, Hashable, Sendable {
        /// Largest MPPT count this cabinet takes.
        public var mpptUpTo: Int
        public var w: Int, h: Int, d: Int
        public var strings: Int
    }
    public struct Box: Codable, Hashable, Sendable { public var w: Int, h: Int, d: Int }
    public struct Cabinets: Codable, Hashable, Sendable {
        public var ac: [ACCabinet]
        public var dc: [DCCabinet]
        public var meter: Box
        public var sem: Box
    }
    public struct Rules: Codable, Hashable, Sendable {
        /// Breaker AT ≥ current × this factor.
        public var cbFactor: Double
        /// Standard breaker frame sizes (AT), ascending.
        public var cbStd: [Int]
    }

    public var version: String
    public var inverters: [Inverter]
    public var pv: [PVModule]
    public var cabinets: Cabinets
    public var rules: Rules

    /// The catalog shipped with the app.
    public static let bundled: EquipmentCatalog = {
        guard let url = Bundle.module.url(forResource: "equipment-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(EquipmentCatalog.self, from: data) else {
            fatalError("equipment-catalog.json missing from TCRoofCore resources")
        }
        return c
    }()

    /// Catalog sizes (kW), ascending.
    public var inverterSizes: [Int] { inverters.map(\.kw).sorted() }

    /// The catalog inverter of this size, or a generic one: Imax from kW at 400 V 3-phase, 870 × 580 × 290 mm, 6 MPPT.
    public func inverter(kw: Int) -> Inverter {
        if let r = inverters.first(where: { $0.kw == kw }) { return r }
        return Inverter(kw: kw, brand: "", model: "\(kw) kW", imax: Double(kw) * 1000 / (3.0.squareRoot() * 400), sac: Double(kw),
                        mppt: 6, vdc: 1100, w: 870, h: 580, d: 290, kg: 0, ip: "")
    }
    /// AC cabinet for this many inverters (the largest when there are more).
    public func acCabinet(inverters n: Int) -> ACCabinet { cabinets.ac.first { n <= $0.upTo } ?? cabinets.ac[cabinets.ac.count - 1] }
    /// DC cabinet for an inverter with this many MPPTs (the largest when there are more).
    public func dcCabinet(mppt: Int) -> DCCabinet { cabinets.dc.first { mppt <= $0.mpptUpTo } ?? cabinets.dc[cabinets.dc.count - 1] }
}
