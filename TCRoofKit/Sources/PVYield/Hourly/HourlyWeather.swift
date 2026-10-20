import Foundation

/// A year of hourly weather: the engine's only climate input (docs/specs/energy-yield). The reference engine and
/// its golden data use a PVGIS-ERA5 TMY (`pvgisTMY`); any source that gives hour-start UTC times, GHI, DNI, DHI,
/// air temperature and wind can be fed in the same way. Nothing here fetches data.
public struct HourlyWeather: Sendable, Equatable {
    /// Start of each hour, UTC seconds. GHI and DHI are means over the hour that starts here (PVGIS convention).
    public var unix: [Int]
    /// W/m².
    public var ghi: [Double], dni: [Double], dhi: [Double]
    /// °C and m/s at 10 m.
    public var tempAir: [Double], windSpeed: [Double]
    /// Where the data was taken, when known.
    public var latitude: Double?, longitude: Double?
    /// e.g. "PVGIS-ERA5 TMY".
    public var source: String

    public init(unix: [Int], ghi: [Double], dni: [Double], dhi: [Double], tempAir: [Double], windSpeed: [Double],
                latitude: Double? = nil, longitude: Double? = nil, source: String) {
        self.unix = unix; self.ghi = ghi; self.dni = dni; self.dhi = dhi; self.tempAir = tempAir; self.windSpeed = windSpeed
        self.latitude = latitude; self.longitude = longitude; self.source = source
    }

    public var count: Int { unix.count }

    /// Σ GHI over the year, kWh/m².
    public var annualGHI: Double { ghi.reduce(0, +) / 1000 }

    /// The reference's resource scaling (`load_meteo` with `ghi_target_kwh_m2`): GHI, DNI and DHI times one factor so
    /// the year's GHI is `target` kWh/m² (e.g. Global Solar Atlas / Solargis).
    public func scaled(toAnnualGHI target: Double) -> HourlyWeather {
        let k = target / annualGHI
        var w = self
        w.ghi = ghi.map { $0 * k }; w.dni = dni.map { $0 * k }; w.dhi = dhi.map { $0 * k }
        w.source = source + String(format: " × %.4f", k)
        return w
    }

    public enum ParseError: Error, Equatable {
        case missingColumn(String)
        case badRow(Int)
    }

    /// The PVGIS TMY as `tools/yield-reference` caches it: `time(UTC),ghi,dni,dhi,temp_air,wind_speed,…` with times
    /// like `1990-01-01 00:00:00+00:00`.
    public static func pvgisTMY(csv text: String, latitude: Double? = nil, longitude: Double? = nil,
                                source: String = "PVGIS-ERA5 TMY") throws -> HourlyWeather {
        var lines = text.split(whereSeparator: \.isNewline).makeIterator()
        guard let header = lines.next() else { throw ParseError.missingColumn("time(UTC)") }
        let cols = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        func col(_ name: String) throws -> Int {
            guard let i = cols.firstIndex(of: name) else { throw ParseError.missingColumn(name) }
            return i
        }
        let it = try col(cols.first ?? "time(UTC)"), ig = try col("ghi"), ib = try col("dni"), id = try col("dhi")
        let ia = try col("temp_air"), iw = try col("wind_speed")
        var w = HourlyWeather(unix: [], ghi: [], dni: [], dhi: [], tempAir: [], windSpeed: [],
                              latitude: latitude, longitude: longitude, source: source)
        var row = 1
        while let line = lines.next() {
            row += 1
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count > max(it, ig, ib, id, ia, iw), let t = unixTime(f[it]),
                  let g = Double(f[ig]), let b = Double(f[ib]), let d = Double(f[id]),
                  let a = Double(f[ia]), let v = Double(f[iw]) else { throw ParseError.badRow(row) }
            w.unix.append(t); w.ghi.append(g); w.dni.append(b); w.dhi.append(d); w.tempAir.append(a); w.windSpeed.append(v)
        }
        return w
    }

    /// `YYYY-MM-DD HH:MM:SS[+HH:MM]` (or `T` between), offset applied, as UTC seconds.
    static func unixTime(_ s: Substring) -> Int? {
        let c = Array(s.utf8)
        guard c.count >= 19 else { return nil }
        func num(_ a: Int, _ n: Int) -> Int? {
            var v = 0
            for k in a..<(a + n) {
                let d = Int(c[k]) - 48
                guard d >= 0 && d <= 9 else { return nil }
                v = v * 10 + d
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2), let h = num(11, 2), let mi = num(14, 2),
              let se = num(17, 2) else { return nil }
        var offset = 0
        if c.count >= 25, c[19] == 43 || c[19] == 45, let oh = num(20, 2), let om = num(23, 2) {
            offset = (oh * 3600 + om * 60) * (c[19] == 45 ? -1 : 1)
        }
        return daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60 + se - offset
    }

    /// Days since 1970-01-01 (H. Hinnant's algorithm).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// (month 1…12, day of year 1…366) of a UTC time shifted by `offset` seconds.
    static func calendar(_ unix: Int, offset: Int = 0) -> (month: Int, dayOfYear: Int) {
        let z0 = Int((Double(unix + offset) / 86400).rounded(.down))
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let m = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return (m, z0 - daysFromCivil(year, 1, 1) + 1)
    }
}
