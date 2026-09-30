import Foundation

/// GISTDA results kept on the device by area (about 100 m cells), so another job near the same site, or the same job after the
/// stored result was cleared, needs no 14 requests and works offline. A fresh entry is used instead of a request; an old one
/// (the flood history changes once a year) only when the service does not answer.
public struct FloodCache: Sendable {
    public static let freshDays = 30.0
    static let storeKey = "solarSurvey.floodCache"
    private let defaults: UserDefaultsBox

    /// `UserDefaults` is not Sendable; the box keeps the struct simple.
    struct UserDefaultsBox: @unchecked Sendable { let d: UserDefaults }
    public init(defaults: UserDefaults = .standard) { self.defaults = UserDefaultsBox(d: defaults) }

    /// "17.006,99.824,1000" — three decimals is about 110 m.
    static func key(lat: Double, lon: Double, radius: Int) -> String { String(format: "%.3f,%.3f,%d", lat, lon, radius) }

    private var all: [String: FloodGistda] {
        get {
            guard let d = defaults.d.data(forKey: Self.storeKey) else { return [:] }
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return (try? dec.decode([String: FloodGistda].self, from: d)) ?? [:]
        }
        nonmutating set {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            if let d = try? enc.encode(newValue) { defaults.d.set(d, forKey: Self.storeKey) }
        }
    }

    /// The stored result for the area; `fresh` limits it to `freshDays`. Estimates typed by the surveyor are never cached.
    public func lookup(lat: Double, lon: Double, radius: Int = 1000, fresh: Bool, now: Date = Date()) -> FloodGistda? {
        guard let g = all[Self.key(lat: lat, lon: lon, radius: radius)], g.manual != true else { return nil }
        return !fresh || now.timeIntervalSince(g.fetchedAt) < Self.freshDays * 86_400 ? g : nil
    }
    public func store(_ g: FloodGistda) {
        guard g.manual != true else { return }
        var a = all
        a[Self.key(lat: g.lat, lon: g.lon, radius: g.radiusMeters)] = g
        // keep the newest 200 areas
        if a.count > 200 { for k in a.sorted(by: { $0.value.fetchedAt < $1.value.fetchedAt }).prefix(a.count - 200).map(\.key) { a[k] = nil } }
        all = a
    }
}
