import Foundation
import PVYield

/// Yearly kWh per kWp of an unshaded plane at a site: the hourly engine (`PVYield`) on the bundled weather when the
/// site has a longitude and a dataset near it, else `SolarModel`'s clear-sky estimate. The roof layout's face choice
/// and face yields, the tank's energy, its energy search and its true-south comparison all read it, so the screens,
/// the PDF and the Excel give the same figure.
///
/// The hourly figure is a reference system's specific yield (`reference`): Znshine 570 W modules on one Growatt
/// MAX 60 at DC/AC about 1.05, with PVYield's default losses and no near shading (the tank's shade simulation and the
/// roof's obstacles handle shade). C1's energy card runs the full engine on the job's own inverters
/// (`RoofMountYield`), so it can differ slightly through clipping.
public enum PlaneYield {
    public enum Source: Equatable, Sendable {
        case hourly(dataset: String, place: String, distanceKm: Double)
        case clearSky
    }

    /// kWh/kWp a year at `latitude`, `longitude`, on a plane tilted `tilt`° facing `azimuthFromSouth`° from south
    /// (+ west). Without a longitude, or far from every bundled dataset, `SolarModel`. Kept per site and plane; the
    /// first call at a site works out its sun track (about 0.1 s), later planes about 0.03 s each (release).
    public static func kWhPerKWp(latitude: Double, longitude: Double?, tilt: Double, azimuthFromSouth: Double) -> Double {
        guard let lon = longitude, let near = BundledWeather.nearest(latitude: latitude, longitude: lon) else {
            return SolarModel.yield(lat: latitude, tilt: tilt, azimuthFromSouth: azimuthFromSouth)
        }
        let key = Key(lat: (latitude * 100).rounded(), lon: (lon * 100).rounded(), tilt: (tilt * 10).rounded(),
                      azimuth: (normalized(azimuthFromSouth) * 10).rounded())
        if let hit = cache.get(key) { return hit }
        guard let y = hourly(near.dataset, latitude: latitude, longitude: lon, tilt: tilt, azimuthFromSouth: azimuthFromSouth) else {
            return SolarModel.yield(lat: latitude, tilt: tilt, azimuthFromSouth: azimuthFromSouth)
        }
        cache.set(key, y)
        return y
    }

    /// Which model `kWhPerKWp` uses at a site.
    public static func source(latitude: Double, longitude: Double?) -> Source {
        guard let lon = longitude, let near = BundledWeather.nearest(latitude: latitude, longitude: lon),
              reference != nil else { return .clearSky }
        return .hourly(dataset: near.dataset.source, place: near.dataset.place, distanceKm: near.distanceKm)
    }

    /// The reference system's module, inverter and module count.
    static let reference: (module: PVYield.PVModuleSpec, inverter: InverterSpec, modules: Int)? = {
        guard let m = RoofMountYield.znshine570, let inv = RoofMountYield.inverterSpec(kw: 60) else { return nil }
        return (m, inv, 110)
    }()

    static func hourly(_ d: BundledWeather.Dataset, latitude: Double, longitude: Double, tilt: Double,
                       azimuthFromSouth: Double) -> Double? {
        guard let ref = reference, let track = try? BundledWeather.track(d, latitude: latitude, longitude: longitude) else { return nil }
        let azN = (normalized(azimuthFromSouth) + 180 + 360).truncatingRemainder(dividingBy: 360)
        let face = ArrayFace(id: "plane", moduleCount: ref.modules, tiltDeg: max(0, tilt), azimuthDegTrueN: azN)
        let r = YieldEngine.run(YieldSystem(module: ref.module, inverter: ref.inverter, faces: [face]), track: track)
        return r.specificYield > 0 ? r.specificYield : nil
    }

    /// An azimuth from south folded into -180…180.
    static func normalized(_ a: Double) -> Double {
        let x = (a + 180).truncatingRemainder(dividingBy: 360)
        return (x < 0 ? x + 360 : x) - 180
    }

    struct Key: Hashable { let lat, lon, tilt, azimuth: Double }

    final class Cache: @unchecked Sendable {
        private var items: [Key: Double] = [:]
        private let lock = NSLock()
        func get(_ k: Key) -> Double? { lock.lock(); defer { lock.unlock() }; return items[k] }
        func set(_ k: Key, _ v: Double) {
            lock.lock(); defer { lock.unlock() }
            if items.count > 512 { items.removeAll() }
            items[k] = v
        }
    }
    static let cache = Cache()
}
