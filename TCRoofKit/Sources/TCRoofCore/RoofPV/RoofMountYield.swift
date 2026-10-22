import Foundation
import PVYield

/// The yearly energy of C1's roof PV layout from the hourly engine (`PVYield`, docs/specs/energy-yield), with
/// `SolarModel` as the fallback when an input is missing: no hourly weather near the site (only the Bangkok TMY
/// ships), no GPS, or a module the engine has no model for. Computed, never stored.
///
/// - Faces: the layout's faces in use, their tilt (`Roof.slope` through `RoofFaces`) and compass azimuth (the plan's
///   bearing), and their module counts.
/// - Module: the standard's module matched to the equipment catalog (size and watts); the catalog's `p570` is the
///   Znshine ZXM7-UHLDD144-570 fit.
/// - Inverters: B2's picked sizes (Growatt MAX 60 / 80 / 125). With one roof section in the job the roof takes all of
///   them; otherwise, or with none picked, as many of the size as keep DC/AC at 1.3 or less (ค่าสมมติ).
public enum RoofMountYield {
    /// Everything the estimate depends on, so the page reruns it only when one of these changes.
    public struct Inputs: Hashable, Sendable {
        public struct Face: Hashable, Sendable {
            public var id: String
            public var modules: Int
            public var tiltDeg: Double, azimuthDeg: Double
            /// SolarModel's kWh/kWp (the fallback; the layout's own face yield is `PlaneYield`'s).
            public var clearSkyYield: Double
        }
        public var faces: [Face]
        public var moduleWp: Double, moduleLength: Double, moduleWidth: Double
        /// B2's picked inverter sizes over the job (kW); empty when none is picked.
        public var inverterSizes: [Int]
        /// Roof (C1) sections in the job.
        public var roofSections: Int
        public var latitude: Double?, longitude: Double?

        public var modules: Int { faces.reduce(0) { $0 + $1.modules } }
        public var kWp: Double { Double(modules) * moduleWp / 1000 }
    }

    public enum Source: Equatable, Sendable {
        /// The hourly engine, on a dataset this far from the site.
        case hourly(dataset: String, place: String, distanceKm: Double, attribution: String)
        /// SolarModel, and why the hourly engine couldn't run.
        case clearSky(reason: String)
    }

    public struct FaceYield: Equatable, Sendable, Identifiable {
        public var id: String
        public var modules: Int
        public var kWp: Double
        /// MWh per year (P50, year 1), and per kWp.
        public var mwh: Double, kWhPerKWp: Double
    }

    public struct Estimate: Equatable, Sendable {
        public var faces: [FaceYield]
        public var kWp: Double
        /// P50, year 1 (MWh).
        public var mwh: Double
        /// P90 of one year (MWh); nil from SolarModel.
        public var p90MWh: Double?
        public var kWhPerKWp: Double
        /// On the plane's irradiation; nil from SolarModel (a fixed 80 %).
        public var performanceRatio: Double?
        /// e.g. `Growatt MAX 60KTL3 LV × 2 | DC/AC 1.25`.
        public var inverterLine: String?
        public var source: Source
        /// What was assumed (ค่าสมมติ).
        public var assumptions: [String]

        public var isHourly: Bool { if case .hourly = source { return true }; return false }

        /// `คำนวณรายชั่วโมง | PVGIS-ERA5 TMY กรุงเทพฯ (ห่าง 12 กม.)` or `ประมาณแบบท้องฟ้าใส | …`.
        public var sourceLine: String {
            switch source {
            case .hourly(let d, let place, let km, _):
                return "คำนวณรายชั่วโมง | \(d) \(place)" + (km >= 1 ? String(format: " (ห่าง %.0f กม.)", km) : "")
            case .clearSky(let why):
                return "ประมาณแบบท้องฟ้าใส PR 80% | \(why)"
            }
        }
    }

    // MARK: - Inputs

    public static func inputs(_ layout: RoofMountLayout, job: Job) -> Inputs {
        let used = layout.faces.filter { $0.used && $0.modules > 0 }
        let s = layout.standard
        let gps = GPS.parse(job.values.text("gps"))
        var sizes: [Int] = []
        for m in job.modules where m.type == .inverter {
            let st = InverterStation(m.values)
            if !st.sizesAssumed { sizes += st.sizes }
        }
        return Inputs(faces: used.map { f in
                          let tilt = f.face.tilt * 180 / .pi
                          let fromSouth = (f.face.azimuth - 180 + 540).truncatingRemainder(dividingBy: 360) - 180
                          return Inputs.Face(id: f.face.id, modules: f.modules, tiltDeg: tilt, azimuthDeg: f.face.azimuth,
                                             clearSkyYield: SolarModel.yield(lat: layout.latitude, tilt: tilt, azimuthFromSouth: fromSouth))
                      },
                      moduleWp: s.moduleWp, moduleLength: s.moduleLength, moduleWidth: s.moduleWidth,
                      inverterSizes: sizes, roofSections: max(1, job.modules.filter { $0.type == .roof }.count),
                      latitude: gps?.lat, longitude: gps?.lon)
    }

    // MARK: - Equipment

    /// The catalog module of this size and power, if any.
    public static func catalogModule(wp: Double, length: Double, width: Double, catalog: EquipmentCatalog = .bundled) -> EquipmentCatalog.PVModule? {
        catalog.pv.first { Double($0.w) == wp.rounded() && abs(Double($0.l) / 1000 - length) < 0.01 && abs(Double($0.wd) / 1000 - width) < 0.01 }
    }

    /// The engine's model of a catalog module: only `p570` (the Znshine ZXM7-UHLDD144-570 datasheet fit) so far.
    public static func moduleSpec(catalogID: String) -> PVYield.PVModuleSpec? {
        catalogID == "p570" ? znshine570 : nil
    }
    static let znshine570: PVYield.PVModuleSpec? = try? ZnshineZXM7UHLDD144.fit(570).spec

    /// The engine's model of a catalog inverter size (kW): Growatt MAX 60 / 80 / 125.
    public static func inverterSpec(kw: Int) -> InverterSpec? { growatt[kw] }
    static let growatt: [Int: InverterSpec] = {
        var out: [Int: InverterSpec] = [:]
        out[60] = try? GrowattCatalog.max60KTL3LV()
        out[80] = try? GrowattCatalog.max80KTL3LV()
        out[125] = try? GrowattCatalog.max125KTL3XLV()
        return out
    }()

    /// DC/AC the assumed inverter count keeps under.
    public static let assumedDCAC = 1.3

    /// The inverter model and count for the roof, and what was assumed.
    static func inverters(_ i: Inputs) -> (spec: InverterSpec, count: Int, assumed: String?)? {
        let known = i.inverterSizes.filter { inverterSpec(kw: $0) != nil }
        // the most common picked size (the larger on a tie)
        let size = Dictionary(grouping: known, by: { $0 }).max { a, b in (a.value.count, a.key) < (b.value.count, b.key) }?.key
        let kw = size ?? 60
        guard let spec = inverterSpec(kw: kw) else { return nil }
        let fit = max(1, Int((i.kWp / (Double(kw) * assumedDCAC)).rounded(.up)))
        if let size, i.roofSections == 1 {
            let ac = i.inverterSizes.reduce(0, +)
            return (spec, max(1, Int((Double(ac) / Double(size)).rounded())), nil)
        }
        if size != nil { return (spec, fit, "อินเวอร์เตอร์ \(kw) kW × \(fit) ตามสัดส่วนหลังคานี้") }
        let why = i.inverterSizes.isEmpty ? "ยังไม่เลือกอินเวอร์เตอร์ (B2)" : "ไม่มีแบบจำลองอินเวอร์เตอร์ \(i.inverterSizes.map(String.init).joined(separator: ", ")) kW"
        return (spec, fit, "\(why) | คิด Growatt \(kw) kW × \(fit)")
    }

    // MARK: - Estimate

    /// The hourly engine when it can run, else SolarModel. Slow on the first call at a site (the sun track):
    /// call it off the main thread.
    public static func estimate(_ i: Inputs) -> Estimate {
        guard i.modules > 0 else { return clearSky(i, reason: "ยังไม่มีแผง") }
        guard let lat = i.latitude, let lon = i.longitude else { return clearSky(i, reason: "ยังไม่มีพิกัด A1") }
        guard let near = BundledWeather.nearest(latitude: lat, longitude: lon) else {
            return clearSky(i, reason: "ยังไม่มีข้อมูลอากาศรายชั่วโมงของพื้นที่นี้")
        }
        guard let cat = catalogModule(wp: i.moduleWp, length: i.moduleLength, width: i.moduleWidth),
              let module = moduleSpec(catalogID: cat.id) else {
            return clearSky(i, reason: String(format: "ยังไม่มีแบบจำลองแผง %.0f W", i.moduleWp))
        }
        guard let inv = inverters(i), let track = try? BundledWeather.track(near.dataset, latitude: lat, longitude: lon) else {
            return clearSky(i, reason: "อ่านข้อมูลอากาศไม่ได้")
        }
        let faces = i.faces.map { ArrayFace(id: $0.id, moduleCount: $0.modules, tiltDeg: $0.tiltDeg, azimuthDegTrueN: $0.azimuthDeg) }
        let system = YieldSystem(module: module, inverter: inv.spec, inverterCount: inv.count, faces: faces)
        let r = YieldEngine.run(system, track: track)
        let dcTotal = r.faces.reduce(0) { $0 + $1.eDCIn }
        let kWp = r.dcKWp
        let out = r.faces.map { f -> FaceYield in
            let fk = Double(f.modules) * module.stc.pNomW / 1000
            let mwh = dcTotal > 0 ? r.energies.eGrid * f.eDCIn / dcTotal / 1000 : 0
            return FaceYield(id: f.id, modules: f.modules, kWp: fk, mwh: mwh, kWhPerKWp: fk > 0 ? mwh * 1000 / fk : 0)
        }
        var assumptions = ["ไม่คิดเงาบังใกล้ แผงสองหน้า และกระแส MPPT", "ค่าสูญเสียตามค่าเริ่มต้นของ PVYield"]
        if let a = inv.assumed { assumptions.insert(a, at: 0) }
        if module.stc.pNomW != i.moduleWp { assumptions.append(String(format: "แผง %.0f W", module.stc.pNomW)) }
        let d = near.dataset
        return Estimate(faces: out, kWp: kWp, mwh: r.energies.eGrid / 1000, p90MWh: r.probability.p90OneYear / 1000,
                        kWhPerKWp: r.specificYield, performanceRatio: r.performanceRatio,
                        inverterLine: "\(inv.spec.manufacturer) \(inv.spec.model) × \(inv.count) | " + String(format: "DC/AC %.2f", r.dcAcRatio),
                        source: .hourly(dataset: d.source, place: d.place, distanceKm: near.distanceKm, attribution: d.attribution),
                        assumptions: assumptions)
    }

    /// SolarModel's estimate (what `RoofMountQuantities.energy` adds up).
    static func clearSky(_ i: Inputs, reason: String) -> Estimate {
        let kw = i.moduleWp / 1000
        let faces = i.faces.map { f in
            FaceYield(id: f.id, modules: f.modules, kWp: Double(f.modules) * kw, mwh: Double(f.modules) * kw * f.clearSkyYield / 1000,
                      kWhPerKWp: f.clearSkyYield)
        }
        let mwh = faces.reduce(0) { $0 + $1.mwh }, kWp = i.kWp
        return Estimate(faces: faces, kWp: kWp, mwh: mwh, p90MWh: nil, kWhPerKWp: kWp > 0 ? mwh * 1000 / kWp : 0,
                        performanceRatio: nil, inverterLine: nil, source: .clearSky(reason: reason), assumptions: [])
    }
}

extension RoofMount {
    /// A1's GPS as the layouts' site: its latitude (nil without GPS, the callers then take `defaultLatitude`) and its
    /// longitude (nil without a latitude, so a default latitude is never paired with a real longitude).
    public static func site(_ job: Job) -> (latitude: Double?, longitude: Double?) {
        let gps = job.values.text("gps")
        guard let lat = latitude(gps: gps) else { return (nil, nil) }
        return (lat, longitude(gps: gps))
    }

    /// The roof's layout as the job keeps it, at the job's site, and its energy as C1's card works it out
    /// (`RoofMountYield.estimate`), for the report and the workbook. Slow on the first call at a site: not on the
    /// main thread.
    public static func printed(_ v: Values, job: Job) -> (layout: RoofMountLayout, energy: RoofMountYield.Estimate) {
        let s = site(job)
        let m = layout(v, latitude: s.latitude, longitude: s.longitude).layout
        return (m, RoofMountYield.estimate(RoofMountYield.inputs(m, job: job)))
    }
}
