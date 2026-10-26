import Foundation

/// The sun of every weather hour at one site, and the hour's DNI made consistent with it: the reference's
/// `sun_position` (tools/yield-reference/reference_engine.py).
///
/// PVGIS-ERA5 GHI and DHI are means over the hour that starts at the timestamp, but the file's DNI was derived with
/// the sun AT the timestamp, which pushes beam light into the morning. So, over twelve 5-minute samples of the hour:
/// - the effective zenith is the mean cos θz over the sunlit samples, the azimuth the middle sunlit sample's;
/// - DNI = (GHI − DHI) / mean cos θz over the whole hour (capped at the extraterrestrial value), expressed against
///   the effective zenith; hours with mean cos θz ≤ 0.02 keep all their light as diffuse.
///
/// Independent of the array, so one track serves every face and every rerun at the site.
public struct SunTrack: Sendable {
    public struct Hour: Sendable, Equatable {
        public var unix: Int
        /// Effective apparent zenith (95° when the sun is down the whole hour) and azimuth (°).
        public var zenith: Double, azimuth: Double
        public var ghi: Double, dni: Double, dhi: Double
        public var dniExtra: Double
        /// Kasten–Young airmass of `zenith`; nil when the sun is down.
        public var airmass: Double?
        public var tempAir: Double, windSpeed: Double
        /// Local calendar month 1…12 (the monthly table).
        public var month: Int
    }

    public var hours: [Hour]
    public var site: SolarPosition.Site
    public var weatherSource: String
    /// Local time of the monthly table and of the rows' design pitch (Thailand +7).
    public var utcOffsetHours: Double

    /// - Parameter utcOffsetHours: local time for the monthly table (Thailand +7).
    public init(weather w: HourlyWeather, site: SolarPosition.Site, utcOffsetHours: Double = 7) {
        self.site = site
        self.utcOffsetHours = utcOffsetHours
        weatherSource = w.source
        let n = w.count, offset = Int(utcOffsetHours * 3600)
        var out = [Hour](repeating: Hour(unix: 0, zenith: 95, azimuth: 0, ghi: 0, dni: 0, dhi: 0, dniExtra: 0, airmass: nil,
                                         tempAir: 0, windSpeed: 0, month: 1), count: n)
        // the slow SPA terms at each hour's start and end; consecutive hours share an end
        var cache: (Int, SolarPosition.Geocentric)?
        func geo(_ t: Int) -> SolarPosition.Geocentric {
            if let c = cache, c.0 == t { return c.1 }
            return SolarPosition.geocentric(unix: Double(t))
        }
        for k in 0..<n {
            let t0 = w.unix[k]
            let g0 = geo(t0), g1 = SolarPosition.geocentric(unix: Double(t0 + 3600))
            cache = (t0 + 3600, g1)
            var cosSum = 0.0, up = 0, first = -1, last = -1
            var az = [Double](repeating: 0, count: 12)
            for m in 0..<12 {
                let p = SolarPosition.topocentric(unix: Double(t0 + m * 300), g0.lerp(g1, Double(m) / 12), site: site)
                let c = max(cos(p.apparentZenith * .pi / 180), 0)
                az[m] = p.azimuth
                if c > 0 { cosSum += c; up += 1; if first < 0 { first = m }; last = m }
            }
            let cosEff = up > 0 ? cosSum / Double(up) : 0
            let zen = up > 0 ? acos(min(1, max(0, cosEff))) * 180 / .pi : 95
            let azimuth = az[up > 0 ? (first + last) / 2 : 6]
            let cal = HourlyWeather.calendar(t0)
            let extra = Irradiance.extraterrestrial(dayOfYear: cal.dayOfYear)
            let cosHour = cosSum / 12
            let ok = cosHour > 0.02
            let bh = max(w.ghi[k] - w.dhi[k], 0)
            let dni0 = ok ? min(bh / cosHour, extra) : 0
            let dni = ok && cosEff > 0 ? dni0 * cosHour / cosEff : 0
            out[k] = Hour(unix: t0, zenith: zen, azimuth: azimuth, ghi: w.ghi[k], dni: dni, dhi: ok ? w.dhi[k] : w.ghi[k],
                          dniExtra: extra, airmass: Irradiance.relativeAirmass(apparentZenith: zen),
                          tempAir: w.tempAir[k], windSpeed: w.windSpeed[k], month: HourlyWeather.calendar(t0, offset: offset).month)
        }
        hours = out
    }
}
