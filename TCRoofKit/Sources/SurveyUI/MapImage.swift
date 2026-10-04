#if canImport(UIKit)
import UIKit
import MapKit
import CoreLocation
import TCRoofCore

/// Satellite picture of the site for "ภาพสถานที่ติดตั้ง". Mapbox satellite comes first; Google Maps Static API and then
/// Apple Maps imagery (no key needed) are used when a source has no key or doesn't answer. Same centre, zoom and framing
/// from every source.
enum MapImage {
    /// Keys for the sources that need one; an empty key skips that source.
    struct Keys: Equatable {
        var mapbox = ""
        var google = ""
    }

    enum Source: String, CaseIterable {
        case mapbox = "m", google = "g", apple = "a"
    }
    enum Failure: Error, LocalizedError {
        case noGPS, badResponse(String)
        var errorDescription: String? {
            switch self {
            case .noGPS: return "ยังไม่มีพิกัด GPS — กรอกที่ ข้อมูลโครงการ › พิกัดดาวเทียม Google Map (เช่น 17.0062, 99.8235 หรือวางลิงก์ Google Maps)"
            case .badResponse(let s): return "ดึงภาพแผนที่ไม่สำเร็จ: \(s)"
            }
        }
    }

    /// Frame of the site photo on the sheet is landscape; 640 px is the Static API's free-tier maximum width.
    static let size = CGSize(width: 640, height: 400)

    /// "17.0062, 99.8235", "17.0062 99.8235", or a Google Maps link containing "@lat,lng" or "q=lat,lng".
    static func coordinate(from text: String) -> CLLocationCoordinate2D? {
        let t = text.removingPercentEncoding ?? text
        let patterns = ["@(-?\\d+\\.\\d+),\\s*(-?\\d+\\.\\d+)", "[?&](?:q|query|ll|center)=(-?\\d+\\.\\d+),\\s*(-?\\d+\\.\\d+)", "(-?\\d{1,2}\\.\\d+)\\s*[, ]\\s*(-?\\d{1,3}\\.\\d+)"]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let r1 = Range(m.range(at: 1), in: t), let r2 = Range(m.range(at: 2), in: t),
                  let lat = Double(t[r1]), let lng = Double(t[r2]),
                  abs(lat) <= 90, abs(lng) <= 180 else { continue }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return nil
    }

    /// Ground width in metres shown by a Web-Mercator map `px` pixels wide at `zoom`.
    static func metersAcross(lat: Double, zoom: Int, px: Double = 640) -> Double {
        156_543.033_92 * cos(lat * .pi / 180) * px / pow(2, Double(zoom))
    }

    /// Sources in order of preference, each with its key: Mapbox, then Google, then Apple.
    static func sources(_ keys: Keys) -> [(Source, String)] {
        let mapbox = keys.mapbox.trimmingCharacters(in: .whitespacesAndNewlines)
        let google = keys.google.trimmingCharacters(in: .whitespacesAndNewlines)
        return [(.mapbox, mapbox), (.google, google), (.apple, "")].filter { $0.0 == .apple || !$0.1.isEmpty }
    }

    /// The picture from the first source that has it cached or answers; the last source's error when none does.
    static func fetch(gps: String, zoom: Int, keys: Keys) async throws -> UIImage {
        guard let c = coordinate(from: gps) else { throw Failure.noGPS }
        var failure: Error = Failure.badResponse("")
        for (source, key) in sources(keys) {
            let name = Cache.name(c, zoom: zoom, source: source)
            if let img = Cache.image(name) { return img }
            do {
                let img: UIImage
                switch source {
                case .mapbox: img = try await mapbox(c, zoom: zoom, token: key)
                case .google: img = try await google(c, zoom: zoom, key: key)
                case .apple: img = try await apple(c, zoom: zoom)
                }
                Cache.store(img, name)
                return img
            } catch {
                if Task.isCancelled { throw error }
                failure = error
            }
        }
        throw failure
    }

    /// The part of `img` inside the A1 report frame; the whole picture when there is no frame or it can't be cut.
    static func crop(_ img: UIImage, to crop: MapCrop?) -> UIImage {
        guard let crop, crop != .full, let cg = img.cgImage,
              let part = cg.cropping(to: crop.pixelRect(width: cg.width, height: cg.height)) else { return img }
        return UIImage(cgImage: part, scale: img.scale, orientation: img.imageOrientation)
    }

    /// Pictures already fetched, in memory and in Caches/MapImages, so reopening A1 or switching back to a zoom
    /// level doesn't download again. Satellite imagery rarely changes; a picture is fetched anew after 30 days.
    enum Cache {
        static let maxAge: TimeInterval = 30 * 24 * 3600
        static let maxFiles = 300
        private static let memory = NSCache<NSString, UIImage>()
        private static let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MapImages", isDirectory: true)

        /// Same centre (to ~1 cm), zoom and source → same picture.
        static func name(_ c: CLLocationCoordinate2D, zoom: Int, source: Source) -> String {
            String(format: "%@_%.7f_%.7f_z%d.jpg", source.rawValue, c.latitude, c.longitude, zoom)
        }

        static func image(_ name: String) -> UIImage? {
            if let img = memory.object(forKey: name as NSString) { return img }
            let url = folder.appendingPathComponent(name)
            guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  Date().timeIntervalSince(date) < maxAge,
                  let data = try? Data(contentsOf: url), let img = UIImage(data: data, scale: 2) else { return nil }
            memory.setObject(img, forKey: name as NSString)
            return img
        }

        static func store(_ img: UIImage, _ name: String) {
            memory.setObject(img, forKey: name as NSString)
            guard let data = img.jpegData(compressionQuality: 0.85) else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
            prune()
        }

        /// Keeps the newest `maxFiles` pictures.
        private static func prune() {
            let keys: Set<URLResourceKey> = [.contentModificationDateKey]
            guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys)),
                  files.count > maxFiles else { return }
            let dated = files.map { ($0, (try? $0.resourceValues(forKeys: keys))?.contentModificationDate ?? .distantPast) }
            for (url, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(maxFiles) { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Mapbox Static Images API, `satellite-v9` style. Mapbox zooms count 512-px tiles, one level less than Google's
    /// 256-px ones for the same ground width, so `zoom - 1` frames the same area as the other sources.
    static func mapbox(_ c: CLLocationCoordinate2D, zoom: Int, token: String) async throws -> UIImage {
        let center = String(format: "%.6f,%.6f", c.longitude, c.latitude)
        let path = "/styles/v1/mapbox/satellite-v9/static/pin-s+e53935(\(center))/\(center),\(zoom - 1),0/\(Int(size.width))x\(Int(size.height))@2x"
        var u = URLComponents(string: "https://api.mapbox.com")!
        u.path = path
        u.queryItems = [.init(name: "access_token", value: token)]
        let (data, resp) = try await URLSession.shared.data(from: u.url!)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let img = UIImage(data: data, scale: 2) else {
            let msg = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw Failure.badResponse("Mapbox HTTP \(status) \(msg)".trimmingCharacters(in: .whitespaces))
        }
        return img
    }

    static func google(_ c: CLLocationCoordinate2D, zoom: Int, key: String) async throws -> UIImage {
        var u = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")!
        let center = String(format: "%.6f,%.6f", c.latitude, c.longitude)
        u.queryItems = [.init(name: "center", value: center), .init(name: "zoom", value: String(zoom)),
                        .init(name: "size", value: "\(Int(size.width))x\(Int(size.height))"), .init(name: "scale", value: "2"),
                        .init(name: "maptype", value: "satellite"), .init(name: "markers", value: "color:red|\(center)"),
                        .init(name: "key", value: key)]
        let (data, resp) = try await URLSession.shared.data(from: u.url!)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let img = UIImage(data: data) else {
            let msg = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw Failure.badResponse("Google Maps HTTP \(status) \(msg)".trimmingCharacters(in: .whitespaces))
        }
        return img
    }

    static func apple(_ c: CLLocationCoordinate2D, zoom: Int) async throws -> UIImage {
        let w = metersAcross(lat: c.latitude, zoom: zoom), h = w * Double(size.height / size.width)
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: c, latitudinalMeters: h, longitudinalMeters: w)
        o.size = size
        o.scale = 2
        o.preferredConfiguration = MKImageryMapConfiguration()
        let shot = try await MKMapSnapshotter(options: o).start()
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            shot.image.draw(at: .zero)
            let p = shot.point(for: c)
            let pin = UIBezierPath(ovalIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            UIColor.systemRed.setFill(); pin.fill()
            UIColor.white.setStroke(); pin.lineWidth = 2.5; pin.stroke()
        }
    }
}
#endif
