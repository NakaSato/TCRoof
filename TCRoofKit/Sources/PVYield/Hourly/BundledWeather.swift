import Foundation

/// The hourly weather years shipped with the package, and the sun tracks worked out from them. Only the Bangkok
/// PVGIS-ERA5 TMY of tools/yield-reference/data is bundled today; a site farther than `maxDistanceKm` from every
/// dataset gets none, and the caller falls back to its own estimate. Nothing is downloaded.
public enum BundledWeather {
    public struct Dataset: Sendable, Equatable, Identifiable {
        public var id: String
        /// Thai place name for the source line.
        public var place: String
        public var latitude: Double, longitude: Double
        public var file: String
        public var source: String
        public var attribution: String
    }

    public static let datasets: [Dataset] = [
        Dataset(id: "pvgis-era5-bangkok", place: "กรุงเทพฯ", latitude: 13.75, longitude: 100.50,
                file: "pvgis-tmy-era5-bangkok-13.75-100.50.csv", source: "PVGIS-ERA5 TMY",
                attribution: "PVGIS © European Union"),
    ]

    /// How far a site may be from a dataset's point and still use it. The central plain around Bangkok is one
    /// climate; farther sites (north, Isan, the south) differ by several per cent in GHI.
    public static let maxDistanceKm = 100.0

    /// The nearest dataset within `maxDistanceKm`, and the distance.
    public static func nearest(latitude: Double, longitude: Double, maxDistanceKm: Double = maxDistanceKm)
        -> (dataset: Dataset, distanceKm: Double)? {
        datasets.map { ($0, distanceKm(latitude, longitude, $0.latitude, $0.longitude)) }
            .filter { $0.1 <= maxDistanceKm }.min { $0.1 < $1.1 }
    }

    public static func load(_ d: Dataset) throws -> HourlyWeather {
        guard let url = Bundle.module.url(forResource: "weather/\(d.file)", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try HourlyWeather.pvgisTMY(csv: String(contentsOf: url, encoding: .utf8), latitude: d.latitude,
                                          longitude: d.longitude, source: d.source)
    }

    /// The sun track of a dataset's weather at a site, kept for later runs (the track takes ~0.1 s; one face then
    /// takes ~0.03 s). Sites are rounded to 0.01° (~1 km) for the cache.
    public static func track(_ d: Dataset, latitude: Double, longitude: Double) throws -> SunTrack {
        let key = "\(d.id) \((latitude * 100).rounded()) \((longitude * 100).rounded())"
        if let t = cache.get(key) { return t }
        let t = SunTrack(weather: try load(d), site: .init(latitude: (latitude * 100).rounded() / 100,
                                                           longitude: (longitude * 100).rounded() / 100))
        cache.set(key, t)
        return t
    }

    /// Great-circle distance, km.
    public static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = Double.pi / 180, dLat = (lat2 - lat1) * r, dLon = (lon2 - lon1) * r
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * r) * cos(lat2 * r) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    final class Cache: @unchecked Sendable {
        private var items: [String: SunTrack] = [:]
        private var order: [String] = []
        private let lock = NSLock()
        func get(_ k: String) -> SunTrack? { lock.lock(); defer { lock.unlock() }; return items[k] }
        func set(_ k: String, _ t: SunTrack) {
            lock.lock(); defer { lock.unlock() }
            if items[k] == nil { order.append(k) }
            items[k] = t
            while order.count > 4 { items[order.removeFirst()] = nil }
        }
    }
    static let cache = Cache()
}
